#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

SSH_USER="${MAC_MINI_SSH_USER:?MAC_MINI_SSH_USER is required}"
SSH_HOST="${MAC_MINI_TAILSCALE_DNS:-${MAC_MINI_TAILSCALE_HOST:?MAC_MINI_TAILSCALE_HOST is required}}"
SSH_PASSWORD="${MAC_MINI_SSH_PASSWORD:?MAC_MINI_SSH_PASSWORD is required}"

FILES=(
  "$REPO_ROOT/hermes/skills/email/himalaya/SKILL.md:.hermes/skills/email/himalaya/SKILL.md"
  "$REPO_ROOT/hermes/skills/email/himalaya/references/configuration.md:.hermes/skills/email/himalaya/references/configuration.md"
  "$REPO_ROOT/hermes/skills/email/himalaya/references/message-composition.md:.hermes/skills/email/himalaya/references/message-composition.md"
  "$REPO_ROOT/hermes/skills/domain/mit-email/SKILL.md:.hermes/skills/domain/mit-email/SKILL.md"
  "$REPO_ROOT/hermes/skills/domain/mit-directory/SKILL.md:.hermes/skills/domain/mit-directory/SKILL.md"
  "$REPO_ROOT/hermes/skills/domain/mit-status/SKILL.md:.hermes/skills/domain/mit-status/SKILL.md"
  "$REPO_ROOT/hermes/skills/domain/piazza/SKILL.md:.hermes/skills/domain/piazza/SKILL.md"
  "$REPO_ROOT/hermes/skills/creative/openai-image-gen-or-edit/SKILL.md:.hermes/skills/creative/openai-image-gen-or-edit/SKILL.md"
  "$REPO_ROOT/hermes/skills/productivity/simple-pdf-generation/SKILL.md:.hermes/skills/productivity/simple-pdf-generation/SKILL.md"
  "$REPO_ROOT/hermes/scripts/mit-email-applemail.py:.hermes/scripts/mit-email-applemail.py"
  "$REPO_ROOT/hermes/scripts/mit-email-browser.py:.hermes/scripts/mit-email-browser.py"
  "$REPO_ROOT/hermes/scripts/mit-status.py:.hermes/scripts/mit-status.py"
  "$REPO_ROOT/hermes/scripts/piazza.py:.hermes/scripts/piazza.py"
)

if ! command -v expect >/dev/null 2>&1; then
  echo "This script requires expect for password-based SSH automation." >&2
  exit 1
fi

for mapping in "${FILES[@]}"; do
  local_path="${mapping%%:*}"
  if [[ ! -f "$local_path" ]]; then
    echo "Missing required file: $local_path" >&2
    exit 1
  fi
done

b64() {
  printf '%s' "${1:-}" | base64 | tr -d '\n'
}

run_remote() {
  local remote_cmd="$1"

  SSH_USER="$SSH_USER" SSH_HOST="$SSH_HOST" SSH_PASSWORD="$SSH_PASSWORD" REMOTE_CMD="$remote_cmd" expect <<'EXPECT_EOF'
    log_user 0
    set timeout -1
    set sent_login 0
    spawn ssh -tt -o PubkeyAuthentication=no -o PreferredAuthentications=password -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 $env(SSH_USER)@$env(SSH_HOST) $env(REMOTE_CMD)
    log_user 1
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

copy_remote() {
  local local_path="$1"
  local remote_path="$2"

  SSH_USER="$SSH_USER" SSH_HOST="$SSH_HOST" SSH_PASSWORD="$SSH_PASSWORD" LOCAL_PATH="$local_path" REMOTE_PATH="$remote_path" expect <<'EXPECT_EOF'
    log_user 0
    set timeout -1
    set sent_login 0
    spawn scp -q -o PubkeyAuthentication=no -o PreferredAuthentications=password -o StrictHostKeyChecking=accept-new $env(LOCAL_PATH) $env(SSH_USER)@$env(SSH_HOST):$env(REMOTE_PATH)
    log_user 1
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

echo "Configuring Hermes integrations on $SSH_USER@$SSH_HOST"
run_remote "mkdir -p ~/.hermes/skills/email/himalaya/references ~/.hermes/skills/domain/mit-email ~/.hermes/skills/domain/mit-directory ~/.hermes/skills/domain/mit-status ~/.hermes/skills/domain/piazza ~/.hermes/skills/creative/openai-image-gen-or-edit ~/.hermes/skills/productivity/simple-pdf-generation ~/.hermes/scripts ~/.hermes/auth && touch ~/.hermes/.env && chmod 600 ~/.hermes/.env"

for mapping in "${FILES[@]}"; do
  local_path="${mapping%%:*}"
  remote_path="${mapping#*:}"
  copy_remote "$local_path" "$remote_path"
done

remote_env_cmd="$(
  cat <<REMOTE_CMD
PIAZZA_EMAIL_B64='$(b64 "${PIAZZA_EMAIL:-}")' \
PIAZZA_PASSWORD_B64='$(b64 "${PIAZZA_PASSWORD:-}")' \
python3 - <<'PY'
import base64
import os
import shlex
from pathlib import Path

path = Path.home() / ".hermes" / ".env"
values = {}
for key in [
    "PIAZZA_EMAIL",
    "PIAZZA_PASSWORD",
]:
    raw = os.environ.get(f"{key}_B64", "")
    value = base64.b64decode(raw).decode() if raw else ""
    if value:
        values[key] = value

lines = path.read_text().splitlines() if path.exists() else []
out = []
seen = set()
remove_keys = {
    "PIAZZA_NETWORK_ID",
    "MS_GRAPH_CLIENT_ID",
    "MS_GRAPH_TENANT",
    "MS_GRAPH_SCOPES",
}
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        key = line.split("=", 1)[0]
        if key in remove_keys and key not in values:
            continue
        if key in values:
            out.append(f"{key}={shlex.quote(values[key])}")
            seen.add(key)
        else:
            out.append(line)
    else:
        out.append(line)
for key, value in values.items():
    if key not in seen:
        out.append(f"{key}={shlex.quote(value)}")
path.write_text("\\n".join(out) + "\\n")
path.chmod(0o600)
PY
REMOTE_CMD
)"

run_remote "$remote_env_cmd"
run_remote "chmod +x ~/.hermes/scripts/mit-email-applemail.py ~/.hermes/scripts/mit-email-browser.py ~/.hermes/scripts/mit-status.py ~/.hermes/scripts/piazza.py && ~/.hermes/scripts/mit-email-applemail.py --help >/dev/null && ~/.hermes/scripts/mit-status.py >/dev/null && ~/.hermes/scripts/piazza.py --help >/dev/null"
run_remote "rm -rf ~/.hermes/skills/domain/mit-email-readonly ~/.hermes/skills/creative/openai-image-edit-via-codex && rm -f ~/.hermes/scripts/mit-email-thunderbird.py ~/.hermes/scripts/mit-email-graph.py"

run_remote "set -e; if [[ -x ~/.hermes/hermes-agent/venv/bin/python ]]; then ~/.hermes/hermes-agent/venv/bin/python -m ensurepip --upgrade >/dev/null; ~/.hermes/hermes-agent/venv/bin/python -m pip install websocket-client >/dev/null; ~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/mit-email-applemail.py mailboxes >/dev/null 2>&1 || true; ~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/mit-email-browser.py list --limit 1 >/dev/null 2>&1 || true; else python3 -m pip install --user websocket-client >/dev/null; python3 ~/.hermes/scripts/mit-email-applemail.py mailboxes >/dev/null 2>&1 || true; python3 ~/.hermes/scripts/mit-email-browser.py list --limit 1 >/dev/null 2>&1 || true; fi"

run_remote "set -e; if [[ -x ~/.hermes/hermes-agent/venv/bin/python ]]; then ~/.hermes/hermes-agent/venv/bin/python -m ensurepip --upgrade >/dev/null; ~/.hermes/hermes-agent/venv/bin/python -m pip install piazza-api >/dev/null; ~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py --help >/dev/null; else python3 -m pip install --user piazza-api >/dev/null; python3 ~/.hermes/scripts/piazza.py --help >/dev/null; fi"

run_remote "export PATH=\"/opt/homebrew/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH\"; hermes skills list | grep -E 'mit-email|mit-directory|mit-status|piazza|openai-image-gen-or-edit|simple-pdf-generation' || true"

echo "Hermes integrations installed."
echo "MIT email supported paths on this Mac mini are Apple Mail first and Outlook browser-session fallback second."
echo "Piazza auth requires PIAZZA_EMAIL and PIAZZA_PASSWORD. Course selection is dynamic; use classes first or pass --network-id explicitly when needed."
