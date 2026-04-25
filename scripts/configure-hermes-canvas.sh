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
CANVAS_API_TOKEN="${CANVAS_API_TOKEN:-}"
CANVAS_SKILL_FILE="$REPO_ROOT/hermes/skills/domain/mit-canvas-course/SKILL.md"
CANVAS_SNAPSHOT_FILE="$REPO_ROOT/hermes/scripts/canvas-course-snapshot.sh"
HERMES_MEMORY_FILE="$REPO_ROOT/hermes/memories/MEMORY.md"
HERMES_USER_FILE="$REPO_ROOT/hermes/memories/USER.md"

if ! command -v expect >/dev/null 2>&1; then
  echo "This script requires expect for password-based SSH automation." >&2
  exit 1
fi

for required_file in "$CANVAS_SKILL_FILE" "$CANVAS_SNAPSHOT_FILE" "$HERMES_MEMORY_FILE" "$HERMES_USER_FILE"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required file: $required_file" >&2
    exit 1
  fi
done

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

copy_remote() {
  local local_path="$1"
  local remote_path="$2"

  SSH_USER="$SSH_USER" SSH_HOST="$SSH_HOST" SSH_PASSWORD="$SSH_PASSWORD" LOCAL_PATH="$local_path" REMOTE_PATH="$remote_path" expect <<'EXPECT_EOF'
    log_user 0
    set timeout -1
    set sent_login 0
    spawn scp -q -o StrictHostKeyChecking=accept-new $env(LOCAL_PATH) $env(SSH_USER)@$env(SSH_HOST):$env(REMOTE_PATH)
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

mkdir -p ~/.hermes/scripts ~/.hermes/skills/domain/mit-canvas-course ~/.hermes/memories
touch ~/.hermes/.env
chmod 600 ~/.hermes/.env

python3 - <<'PY'
import os
from pathlib import Path

path = Path.home() / ".hermes" / ".env"
values = {
    "CANVAS_BASE_URL": os.environ["REMOTE_CANVAS_BASE_URL"],
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
        if key in {"CANVAS_COURSE_ID", "CANVAS_COURSE_URL"}:
            continue
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

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
echo "Configured Canvas values:"
python3 - <<'PY'
from pathlib import Path
for line in (Path.home() / ".hermes" / ".env").read_text().splitlines():
    if line.startswith(("CANVAS_BASE_URL=", "CANVAS_API_TOKEN=")):
        key = line.split("=", 1)[0]
        print(f"{key}=***REDACTED***" if key == "CANVAS_API_TOKEN" else line)
PY
REMOTE_SCRIPT

encoded_script="$(base64 <"$tmp_script" | tr -d '\n')"
remote_cmd="REMOTE_CANVAS_BASE_URL='${CANVAS_BASE_URL}' REMOTE_CANVAS_API_TOKEN='${CANVAS_API_TOKEN}' bash -lc 'printf %s ${encoded_script} | base64 -d | bash'"

echo "Configuring Hermes Canvas integration on $SSH_USER@$SSH_HOST"
run_remote "$remote_cmd"
copy_remote "$CANVAS_SKILL_FILE" ".hermes/skills/domain/mit-canvas-course/SKILL.md"
copy_remote "$CANVAS_SNAPSHOT_FILE" ".hermes/scripts/canvas-course-snapshot.sh"
copy_remote "$HERMES_MEMORY_FILE" ".hermes/memories/MEMORY.md"
copy_remote "$HERMES_USER_FILE" ".hermes/memories/USER.md"
run_remote "chmod +x ~/.hermes/scripts/canvas-course-snapshot.sh && ~/.hermes/scripts/canvas-course-snapshot.sh"
echo "Hermes Canvas integration configuration completed."
