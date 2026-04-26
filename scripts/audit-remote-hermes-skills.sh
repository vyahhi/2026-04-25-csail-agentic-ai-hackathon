#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
REMOTE_SKILLS_DIR="${REMOTE_SKILLS_DIR:-.hermes/skills}"
IMPORT_REPO_OWNED=0
SHOW_DIFF=0
KEEP_SNAPSHOT=0
CODEX_AUTONOMOUS=0
CODEX_MODEL="${CODEX_MODEL:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/audit-remote-hermes-skills.sh [options]

Fetch and audit all skills from the remote Hermes Mac mini.

Default behavior is read-only:
  - fetches ~/.hermes/skills from the Mac mini
  - compares every repo-owned skill file under hermes/skills
  - lists remote-only SKILL.md files, usually Hermes hub/bundled skills
  - scans remote skills for private local identifiers derived from .env
  - does not edit, commit, push, or deploy anything

Options:
  --show-diff            Print unified diffs for repo-owned changed files.
  --import-repo-owned    Copy remote versions over matching local hermes/skills files.
                         Review with git diff before committing.
  --codex-autonomous     After fetching/auditing, run codex exec to autonomously
                         review, sanitize, commit, and push repo-worthy changes.
  --codex-model MODEL    Model passed to codex exec in autonomous mode.
  --keep-snapshot        Keep the fetched snapshot and print its path.
  -h, --help             Show this help.

Environment:
  ENV_FILE               Defaults to .env in the repo root.
  REMOTE_SKILLS_DIR      Defaults to .hermes/skills.

Required .env keys:
  MAC_MINI_SSH_USER
  MAC_MINI_SSH_PASSWORD
  MAC_MINI_TAILSCALE_DNS or MAC_MINI_TAILSCALE_HOST
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --show-diff)
      SHOW_DIFF=1
      shift
      ;;
    --import-repo-owned)
      IMPORT_REPO_OWNED=1
      shift
      ;;
    --codex-autonomous)
      CODEX_AUTONOMOUS=1
      KEEP_SNAPSHOT=1
      shift
      ;;
    --codex-model)
      CODEX_MODEL="${2:?--codex-model requires a model name}"
      shift 2
      ;;
    --keep-snapshot)
      KEEP_SNAPSHOT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

if ! command -v expect >/dev/null 2>&1; then
  echo "This script requires expect for password-based SSH automation." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

SSH_USER="${MAC_MINI_SSH_USER:?MAC_MINI_SSH_USER is required}"
SSH_HOST="${MAC_MINI_TAILSCALE_DNS:-${MAC_MINI_TAILSCALE_HOST:?MAC_MINI_TAILSCALE_HOST is required}}"
SSH_PASSWORD="${MAC_MINI_SSH_PASSWORD:?MAC_MINI_SSH_PASSWORD is required}"

TMPDIR="$(mktemp -d /tmp/hermes-remote-skills.XXXXXX)"
REMOTE_TGZ="/tmp/hermes-skills-audit.tgz"

cleanup() {
  if [[ "$KEEP_SNAPSHOT" != "1" ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

run_remote() {
  local remote_cmd="$1"

  SSH_USER="$SSH_USER" SSH_HOST="$SSH_HOST" SSH_PASSWORD="$SSH_PASSWORD" REMOTE_CMD="$remote_cmd" expect <<'EXPECT_EOF'
    log_user 0
    set timeout -1
    set sent_login 0
    spawn ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 $env(SSH_USER)@$env(SSH_HOST) $env(REMOTE_CMD)
    expect {
      -glob "*Password:*" {
        if {$sent_login == 0} {
          send "$env(SSH_PASSWORD)\r"
          set sent_login 1
        }
        exp_continue
      }
      -glob "*password:*" {
        if {$sent_login == 0} {
          send "$env(SSH_PASSWORD)\r"
          set sent_login 1
        }
        exp_continue
      }
      -glob "*Permission denied*" {
        exit 13
      }
      eof {
        catch wait result
        exit [lindex $result 3]
      }
    }
EXPECT_EOF
}

copy_from_remote() {
  local remote_path="$1"
  local local_path="$2"

  SSH_USER="$SSH_USER" SSH_HOST="$SSH_HOST" SSH_PASSWORD="$SSH_PASSWORD" REMOTE_PATH="$remote_path" LOCAL_PATH="$local_path" expect <<'EXPECT_EOF'
    log_user 0
    set timeout -1
    set sent_login 0
    spawn scp -q -o PubkeyAuthentication=no -o PreferredAuthentications=password -o StrictHostKeyChecking=accept-new $env(SSH_USER)@$env(SSH_HOST):$env(REMOTE_PATH) $env(LOCAL_PATH)
    expect {
      -glob "*Password:*" {
        if {$sent_login == 0} {
          send "$env(SSH_PASSWORD)\r"
          set sent_login 1
        }
        exp_continue
      }
      -glob "*password:*" {
        if {$sent_login == 0} {
          send "$env(SSH_PASSWORD)\r"
          set sent_login 1
        }
        exp_continue
      }
      -glob "*Permission denied*" {
        exit 13
      }
      eof {
        catch wait result
        exit [lindex $result 3]
      }
    }
EXPECT_EOF
}

echo "Fetching remote Hermes skills from $SSH_USER@$SSH_HOST:$REMOTE_SKILLS_DIR"
run_remote "rm -f '$REMOTE_TGZ' && tar -czf '$REMOTE_TGZ' -C \"\$(dirname '$REMOTE_SKILLS_DIR')\" \"\$(basename '$REMOTE_SKILLS_DIR')\""
copy_from_remote "$REMOTE_TGZ" "$TMPDIR/hermes-skills.tgz"
tar -xzf "$TMPDIR/hermes-skills.tgz" -C "$TMPDIR"

REMOTE_ROOT="$TMPDIR/skills"
if [[ ! -d "$REMOTE_ROOT" ]]; then
  echo "Remote archive did not contain a skills directory." >&2
  exit 1
fi

echo
echo "Remote snapshot: $TMPDIR"
echo "Remote SKILL.md count: $(find "$REMOTE_ROOT" -name SKILL.md | wc -l | tr -d ' ')"
echo "Remote file count: $(find "$REMOTE_ROOT" -type f | wc -l | tr -d ' ')"

echo
echo "Repo-owned skill file differences:"
DIFF_FILES=()
while IFS= read -r rel_path; do
  remote_path="$REMOTE_ROOT/$rel_path"
  local_path="$REPO_ROOT/hermes/skills/$rel_path"
  if [[ ! -f "$remote_path" ]]; then
    echo "REMOTE_MISSING $rel_path"
    continue
  fi
  if ! cmp -s "$local_path" "$remote_path"; then
    DIFF_FILES+=("$rel_path")
    echo "DIFF $rel_path"
    if [[ "$SHOW_DIFF" == "1" ]]; then
      diff -u "$local_path" "$remote_path" || true
    fi
  fi
done < <(cd "$REPO_ROOT/hermes/skills" && find . -type f | sed 's#^\./##' | sort)

if [[ "${#DIFF_FILES[@]}" -eq 0 ]]; then
  echo "none"
fi

echo
echo "Remote-only top-level SKILL.md files:"
comm -13 \
  <(cd "$REPO_ROOT/hermes/skills" && find . -name SKILL.md | sed 's#^\./##' | sort) \
  <(cd "$REMOTE_ROOT" && find . -name SKILL.md | sed 's#^\./##' | sort) \
  | sed 's#^#REMOTE_ONLY #' || true

echo
echo "Remote-only non-skill metadata roots:"
comm -13 \
  <(cd "$REPO_ROOT/hermes/skills" && find . -maxdepth 2 -type f | sed 's#^\./##' | sort) \
  <(cd "$REMOTE_ROOT" && find . -maxdepth 2 -type f | sed 's#^\./##' | sort) \
  | sed -n '1,80p' \
  | sed 's#^#REMOTE_ONLY_FILE #' || true

echo
echo "Private-data scan over remote skills:"
SCAN_PATTERN="$(
  python3 - <<'PY'
import os
import re

keys = [
    "MAC_MINI_SSH_USER",
    "MAC_MINI_TAILSCALE_HOST",
    "MAC_MINI_TAILSCALE_NAME",
    "MAC_MINI_TAILSCALE_DNS",
    "MAC_MINI_SSH_PASSWORD",
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_ALLOWED_USERS",
    "TELEGRAM_HOME_CHANNEL",
    "CANVAS_API_TOKEN",
    "PIAZZA_EMAIL",
    "PIAZZA_PASSWORD",
]

patterns = []
for key in keys:
    value = os.environ.get(key, "")
    if not value or value in {"replace-me", "your-mac-mini", "your-mac-mini.example.ts.net", "100.x.y.z", "mac-user", "123456789"}:
        continue
    if len(value) < 4:
        continue
    patterns.append(re.escape(value))

extra = os.environ.get("HERMES_SKILL_AUDIT_EXTRA_PATTERNS", "")
for line in extra.splitlines():
    line = line.strip()
    if line:
        patterns.append(line)

# Generic course/thread leakage signals. Keep these generic; do not hardcode
# names, exact email addresses, tokens, hostnames, or user IDs in this repo.
patterns.extend([
    r"Quiz [0-9]+",
    r"\bfor (the|a|an) [^.\n]{3,80} thread\b",
    r"/Users/[^/[:space:]]+",
    r"[0-9]{6,}:AA[A-Za-z0-9_-]{20,}",
    r"[0-9]{4}~[A-Za-z0-9_-]{20,}",
])

print("|".join(dict.fromkeys(patterns)))
PY
)"
if [[ -n "$SCAN_PATTERN" ]] && rg -n "$SCAN_PATTERN" "$REMOTE_ROOT"; then
  echo
  echo "Private-data scan found matches above. Do not import those lines verbatim."
else
  echo "no known private/local identifiers found"
fi

if [[ "$IMPORT_REPO_OWNED" == "1" ]]; then
  echo
  echo "Importing remote versions of repo-owned changed files for local review."
  for rel_path in "${DIFF_FILES[@]}"; do
    mkdir -p "$REPO_ROOT/hermes/skills/$(dirname "$rel_path")"
    cp "$REMOTE_ROOT/$rel_path" "$REPO_ROOT/hermes/skills/$rel_path"
    echo "IMPORTED $rel_path"
  done
  echo
  echo "Review with:"
  echo "  git diff -- hermes/skills"
  echo
  echo "Commit/push only after removing secrets, private examples, and remote-specific stale choices."
else
  echo
  echo "No files were changed. To import repo-owned remote versions for review, rerun with --import-repo-owned."
fi

if [[ "$KEEP_SNAPSHOT" == "1" ]]; then
  echo
  echo "Kept snapshot at: $TMPDIR"
fi

if [[ "$CODEX_AUTONOMOUS" == "1" ]]; then
  if ! command -v codex >/dev/null 2>&1; then
    echo "codex CLI is required for --codex-autonomous." >&2
    exit 1
  fi

  echo
  echo "Starting autonomous Codex skill sync review."
  codex_args=(exec --cd "$REPO_ROOT" --full-auto)
  if [[ -n "$CODEX_MODEL" ]]; then
    codex_args+=(-m "$CODEX_MODEL")
  fi

  codex "${codex_args[@]}" - <<PROMPT
You are in the repo root: $REPO_ROOT

Task: fully handle remote Hermes skill updates from this fetched snapshot:
$TMPDIR/skills

Use this policy:
- Compare ALL remote skill files against repo files under hermes/skills.
- Repo-owned/project skills may be updated when the remote contains useful new operational guidance.
- Do not blindly import hub/bundled marketplace skills that are remote-only; mention them only if relevant.
- Preserve repo-local corrections when remote is stale, especially gpt-5.5 in OpenAI image skill examples.
- Do not commit private or overly specific facts from remote, including specific course/quiz/thread/person/account/host/token examples.
- Sanitize remote-specific examples into generalized reusable guidance.
- If changes are needed: edit files, run a focused validation, commit, and push to origin main.
- If no changes are needed: make no commit and report why.
- Do not rerun scripts/audit-remote-hermes-skills.sh with --codex-autonomous from inside this session.

Suggested checks:
- diff -qr hermes/skills "$TMPDIR/skills"
- inspect repo-owned diffs with diff -u
- scan candidate edits with rg for private identifiers before committing
- git status --short
PROMPT
fi
