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
JOB_NAME="${HERMES_MIT_BRIEFING_NAME:-mit-daily-briefing}"

if ! command -v expect >/dev/null 2>&1; then
  echo "This script requires expect for password-based SSH automation." >&2
  exit 1
fi

remote_cmd="$(cat <<'REMOTE_CMD'
python3 - <<'PY'
import os
import re
import subprocess
name = os.environ["JOB_NAME"]
hermes = os.path.expanduser("~/.local/bin/hermes")
listed = subprocess.run(f"{hermes} cron list", shell=True, check=True, capture_output=True, text=True).stdout
clean = re.sub(r'\x1b\[[0-9;]*m', '', listed)
job_id = None
for line in clean.splitlines():
    m = re.match(r"\s*([a-f0-9]{12})\s+\[active\]", line)
    if m:
        job_id = m.group(1)
        break
if not job_id:
    raise SystemExit(f"Could not find cron job named {name!r}")
print(job_id)
subprocess.run(f"{hermes} cron run --accept-hooks {job_id}", shell=True, check=True)
PY
sleep 20
tail -n 80 ~/.hermes/logs/gateway.log 2>/dev/null || true
REMOTE_CMD
)"

SSH_USER="$SSH_USER" SSH_HOST="$SSH_HOST" SSH_PASSWORD="$SSH_PASSWORD" JOB_NAME="$JOB_NAME" REMOTE_CMD="$remote_cmd" expect <<'EXPECT_EOF'
  log_user 1
  set timeout -1
  set sent_login 0
  spawn ssh -tt -o PubkeyAuthentication=no -o PreferredAuthentications=password -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 $env(SSH_USER)@$env(SSH_HOST) env JOB_NAME=$env(JOB_NAME) $env(REMOTE_CMD)
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
    eof {
      catch wait result
      exit [lindex $result 3]
    }
  }
EXPECT_EOF
