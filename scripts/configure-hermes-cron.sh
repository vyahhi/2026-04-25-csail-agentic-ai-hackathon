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
SCHEDULE="${HERMES_MIT_BRIEFING_SCHEDULE:-0 8 * * *}"
DELIVER="${HERMES_MIT_BRIEFING_DELIVER:-telegram}"
WORKDIR="${HERMES_MIT_BRIEFING_WORKDIR:-$REPO_ROOT}"

PROMPT="$(cat <<'EOF'
Prepare Nikolay's daily MIT briefing. Keep it concise and operational.

Include:
1. important unread or recent MIT email items
2. new Piazza questions or comments across visible classes
3. today's and near-term Canvas deadlines or modules that need attention
4. MIT assistant health warnings only if something is degraded

Use the installed MIT integrations and skills. If a source is unavailable, say so briefly and continue.
Deliver a Telegram-friendly summary.
EOF
)"

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

b64() {
  printf '%s' "${1:-}" | base64 | tr -d '\n'
}

REMOTE_PROMPT_B64="$(b64 "$PROMPT")"
REMOTE_NAME_B64="$(b64 "$JOB_NAME")"
REMOTE_SCHEDULE_B64="$(b64 "$SCHEDULE")"
REMOTE_DELIVER_B64="$(b64 "$DELIVER")"
REMOTE_WORKDIR_B64="$(b64 "$WORKDIR")"

remote_cmd="$(cat <<REMOTE_CMD
JOB_NAME_B64='${REMOTE_NAME_B64}' \
SCHEDULE_B64='${REMOTE_SCHEDULE_B64}' \
DELIVER_B64='${REMOTE_DELIVER_B64}' \
WORKDIR_B64='${REMOTE_WORKDIR_B64}' \
PROMPT_B64='${REMOTE_PROMPT_B64}' \
python3 - <<'PY'
import base64
import os
import re
import shlex
import subprocess

def dec(key: str) -> str:
    return base64.b64decode(os.environ[key]).decode()

name = dec("JOB_NAME_B64")
schedule = dec("SCHEDULE_B64")
deliver = dec("DELIVER_B64")
workdir = dec("WORKDIR_B64")
prompt = dec("PROMPT_B64")
hermes = "$HOME/.local/bin/hermes"

def clean(text: str) -> str:
    return re.sub(r'\\x1b\\[[0-9;]*m', '', text)

listed = subprocess.run(
    f'{hermes} cron list',
    shell=True,
    check=True,
    capture_output=True,
    text=True,
).stdout
for line in clean(listed).splitlines():
    if name in line:
        job_id = line.strip().split()[0]
        subprocess.run(
            f'{hermes} cron remove {job_id}',
            shell=True,
            check=True,
        )

subprocess.run(
    " ".join([
        shlex.quote(hermes),
        "cron", "create",
        shlex.quote(schedule),
        shlex.quote(prompt),
        "--name", shlex.quote(name),
        "--deliver", shlex.quote(deliver),
        "--skill", "mit-email",
        "--skill", "piazza",
        "--skill", "mit-status",
        "--skill", "mit-canvas-course",
        "--workdir", shlex.quote(workdir),
    ]),
    shell=True,
    check=True,
)
subprocess.run(f'{hermes} cron list', shell=True, check=True)
PY
REMOTE_CMD
)"

echo "Configuring Hermes cron job '$JOB_NAME' on $SSH_USER@$SSH_HOST"
run_remote "$remote_cmd"
echo "Installed daily MIT briefing cron."
echo "Schedule: $SCHEDULE"
echo "Delivery: $DELIVER"
