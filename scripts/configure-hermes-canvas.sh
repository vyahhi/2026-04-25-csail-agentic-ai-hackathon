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
CANVAS_BASE_URL="${CANVAS_BASE_URL:-https://canvas.mit.edu}"
CANVAS_COURSE_ID="${CANVAS_COURSE_ID:-37338}"
CANVAS_COURSE_URL="${CANVAS_COURSE_URL:-$CANVAS_BASE_URL/courses/$CANVAS_COURSE_ID}"
CANVAS_API_TOKEN="${CANVAS_API_TOKEN:-}"

if ! command -v expect >/dev/null 2>&1; then
  echo "This script requires expect for password-based SSH automation." >&2
  exit 1
fi

run_remote() {
  local remote_cmd="$1"

  SSH_USER="$SSH_USER" SSH_HOST="$SSH_HOST" SSH_PASSWORD="$SSH_PASSWORD" REMOTE_CMD="$remote_cmd" expect <<'EXPECT_EOF'
    log_user 0
    set timeout -1
    set sent_login 0
    spawn ssh -tt -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 $env(SSH_USER)@$env(SSH_HOST) $env(REMOTE_CMD)
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

tmp_script="$(mktemp)"
trap 'rm -f "$tmp_script"' EXIT

cat >"$tmp_script" <<'REMOTE_SCRIPT'
set -euo pipefail

mkdir -p ~/.hermes/scripts ~/.hermes/skills/domain/mit-canvas-course
touch ~/.hermes/.env
chmod 600 ~/.hermes/.env

python3 - <<'PY'
import os
from pathlib import Path

path = Path.home() / ".hermes" / ".env"
values = {
    "CANVAS_BASE_URL": os.environ["REMOTE_CANVAS_BASE_URL"],
    "CANVAS_COURSE_ID": os.environ["REMOTE_CANVAS_COURSE_ID"],
    "CANVAS_COURSE_URL": os.environ["REMOTE_CANVAS_COURSE_URL"],
}
token = os.environ.get("REMOTE_CANVAS_API_TOKEN", "").strip()
if token:
    values["CANVAS_API_TOKEN"] = token

lines = path.read_text().splitlines() if path.exists() else []
out = []
seen = set()
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        key = line.split("=", 1)[0]
        if key in values:
            out.append(f"{key}={values[key]}")
            seen.add(key)
        else:
            out.append(line)
    else:
        out.append(line)
for key, value in values.items():
    if key not in seen:
        out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n")
path.chmod(0o600)
PY

cat > ~/.hermes/skills/domain/mit-canvas-course/SKILL.md <<'SKILL'
---
name: mit-canvas-course
description: View-only access guidance for the configured MIT Canvas course. Use when the user asks about Canvas, MIT Canvas, course 37338, assignments, modules, syllabus, announcements, or course pages.
---

# MIT Canvas Course

This Hermes install is configured for a view-only Canvas target:

- `CANVAS_BASE_URL`
- `CANVAS_COURSE_ID`
- `CANVAS_COURSE_URL`
- optional `CANVAS_API_TOKEN`

Default course:

```text
https://canvas.mit.edu/courses/37338
```

## Rules

- Treat Canvas as read-only.
- Do not submit assignments, edit pages, post comments, change grades, enroll users, or perform any state-changing action.
- Use `GET` requests only for Canvas API access.
- If `CANVAS_API_TOKEN` is absent or an API endpoint returns `401`, explain that authenticated Canvas API access requires a token and fall back to public page reads.
- Prefer the Canvas REST API when `CANVAS_API_TOKEN` exists.
- For public page reads, use `curl -Ls "$CANVAS_COURSE_URL"` and extract visible text or Canvas `ENV` metadata.

## Useful Read-Only API Calls

```bash
curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID/tabs"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID/assignments?per_page=100"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID/modules?per_page=100"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/announcements?context_codes[]=course_$CANVAS_COURSE_ID"
```

## Helper

Run this on the Mac mini for a quick status snapshot:

```bash
~/.hermes/scripts/canvas-course-snapshot.sh
```
SKILL

cat > ~/.hermes/scripts/canvas-course-snapshot.sh <<'SNAPSHOT'
#!/usr/bin/env bash
set -euo pipefail

HERMES_ENV="$HOME/.hermes/.env"
if [[ -f "$HERMES_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$HERMES_ENV"
  set +a
fi

CANVAS_BASE_URL="${CANVAS_BASE_URL:-https://canvas.mit.edu}"
CANVAS_COURSE_ID="${CANVAS_COURSE_ID:-37338}"
CANVAS_COURSE_URL="${CANVAS_COURSE_URL:-$CANVAS_BASE_URL/courses/$CANVAS_COURSE_ID}"

echo "Canvas course URL: $CANVAS_COURSE_URL"
echo

echo "Public page:"
curl -Ls "$CANVAS_COURSE_URL" |
  python3 -c 'import re,sys,html
text=sys.stdin.read()
title=re.search(r"<title>(.*?)</title>", text, re.I|re.S)
ctx=re.search(r"context_asset_string\":\"(course_[0-9]+)", text)
login=bool(re.search(r"id=\"global_nav_login_link\"|/login", text))
print("  title:", html.unescape(title.group(1)).strip() if title else "unknown")
print("  context:", ctx.group(1) if ctx else "unknown")
print("  login_link_visible:", login)'

echo
echo "API:"
if [[ -n "${CANVAS_API_TOKEN:-}" ]]; then
  status="$(curl -sS -o /tmp/canvas-course-api.json -w "%{http_code}" -H "Authorization: Bearer $CANVAS_API_TOKEN" "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID" || true)"
else
  echo "  CANVAS_API_TOKEN not set; API may return 401."
  status="$(curl -sS -o /tmp/canvas-course-api.json -w "%{http_code}" "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID" || true)"
fi

echo "  course endpoint status: $status"
if [[ "$status" == "200" ]]; then
  python3 -m json.tool /tmp/canvas-course-api.json | sed -n '1,80p'
else
  sed -n '1,20p' /tmp/canvas-course-api.json 2>/dev/null || true
fi
SNAPSHOT
chmod +x ~/.hermes/scripts/canvas-course-snapshot.sh

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
echo "Configured Canvas values:"
python3 - <<'PY'
from pathlib import Path
for line in (Path.home() / ".hermes" / ".env").read_text().splitlines():
    if line.startswith(("CANVAS_BASE_URL=", "CANVAS_COURSE_ID=", "CANVAS_COURSE_URL=", "CANVAS_API_TOKEN=")):
        key = line.split("=", 1)[0]
        print(f"{key}=***REDACTED***" if key == "CANVAS_API_TOKEN" else line)
PY
echo
~/.hermes/scripts/canvas-course-snapshot.sh
REMOTE_SCRIPT

encoded_script="$(base64 <"$tmp_script" | tr -d '\n')"
remote_cmd="REMOTE_CANVAS_BASE_URL='${CANVAS_BASE_URL}' REMOTE_CANVAS_COURSE_ID='${CANVAS_COURSE_ID}' REMOTE_CANVAS_COURSE_URL='${CANVAS_COURSE_URL}' REMOTE_CANVAS_API_TOKEN='${CANVAS_API_TOKEN}' bash -lc 'printf %s ${encoded_script} | base64 -d | bash'"

echo "Configuring Hermes Canvas course on $SSH_USER@$SSH_HOST"
run_remote "$remote_cmd"
echo "Hermes Canvas course configuration completed."
