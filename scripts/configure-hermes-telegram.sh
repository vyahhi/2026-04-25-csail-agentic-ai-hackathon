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
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}"
TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS:-}"
TELEGRAM_HOME_CHANNEL="${TELEGRAM_HOME_CHANNEL:-$TELEGRAM_ALLOWED_USERS}"

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

echo "Configuring Hermes Telegram on $SSH_USER@$SSH_HOST"

tmp_script="$(mktemp)"
trap 'rm -f "$tmp_script"' EXIT

cat >"$tmp_script" <<'REMOTE_SCRIPT'
set -euo pipefail
mkdir -p ~/.hermes
touch ~/.hermes/.env
chmod 600 ~/.hermes/.env

python3 - <<'PY'
import os
from pathlib import Path

path = Path.home() / ".hermes" / ".env"
values = {
    "TELEGRAM_BOT_TOKEN": os.environ["REMOTE_TELEGRAM_BOT_TOKEN"],
}
allowed = os.environ.get("REMOTE_TELEGRAM_ALLOWED_USERS", "").strip()
home = os.environ.get("REMOTE_TELEGRAM_HOME_CHANNEL", "").strip()
if allowed:
    values["TELEGRAM_ALLOWED_USERS"] = allowed
if home:
    values["TELEGRAM_HOME_CHANNEL"] = home

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

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
python3 - <<'PY'
from pathlib import Path
for line in (Path.home() / ".hermes" / ".env").read_text().splitlines():
    if line.startswith(("TELEGRAM_BOT_TOKEN=", "TELEGRAM_ALLOWED_USERS=", "TELEGRAM_HOME_CHANNEL=")):
        key = line.split("=", 1)[0]
        print(f"{key}=***REDACTED***" if key == "TELEGRAM_BOT_TOKEN" else line)
PY

python3 - <<'PY'
from pathlib import Path
import re

path = Path.home() / ".hermes" / "config.yaml"
text = path.read_text() if path.exists() else ""

if "display:" not in text:
    text += "\n# Messaging interaction defaults\ndisplay:\n  busy_input_mode: queue\n"
elif "busy_input_mode:" not in text:
    lines = text.splitlines()
    out = []
    inserted = False
    for line in lines:
        out.append(line)
        if line.strip() == "display:":
            out.append("  busy_input_mode: queue")
            inserted = True
    text = "\n".join(out) + ("\n" if out else "")
else:
    import re
    text = re.sub(r'(^\s*busy_input_mode:\s*).*$',
                  r'\1queue',
                  text,
                  flags=re.M)

path.write_text(text)
PY

python3 - <<'PY'
from pathlib import Path
import re

path = Path.home() / ".hermes" / "config.yaml"
text = path.read_text() if path.exists() else ""
block = (
    "quick_commands:\n"
    "  mitstatus:\n"
    "    type: exec\n"
    "    command: ~/.hermes/scripts/mit-status.py --summary\n"
    "  mit_status:\n"
    "    type: exec\n"
    "    command: ~/.hermes/scripts/mit-status.py --summary\n"
)

if "quick_commands:" not in text:
    text = text.rstrip() + "\n\n" + block
else:
    pattern = re.compile(
        r"(^quick_commands:\n(?:^[^\S\r\n].*\n)*)",
        re.M,
    )
    match = pattern.search(text)
    if match:
        section = match.group(1)
        if re.search(r"^\s{2}mitstatus:\n(?:^\s{4}.*\n)*", section, re.M):
            section = re.sub(
                r"^\s{2}mitstatus:\n(?:^\s{4}.*\n)*",
                "  mitstatus:\n    type: exec\n    command: ~/.hermes/scripts/mit-status.py --summary\n",
                section,
                flags=re.M,
            )
        else:
            section = section + "  mitstatus:\n    type: exec\n    command: ~/.hermes/scripts/mit-status.py --summary\n"
        if re.search(r"^\s{2}mit_status:\n(?:^\s{4}.*\n)*", section, re.M):
            section = re.sub(
                r"^\s{2}mit_status:\n(?:^\s{4}.*\n)*",
                "  mit_status:\n    type: exec\n    command: ~/.hermes/scripts/mit-status.py --summary\n",
                section,
                flags=re.M,
            )
        else:
            section = section + "  mit_status:\n    type: exec\n    command: ~/.hermes/scripts/mit-status.py --summary\n"
        text = text[:match.start(1)] + section + text[match.end(1):]

path.write_text(text)
PY

echo "Configured display.busy_input_mode=queue in ~/.hermes/config.yaml"
hermes gateway status || true
REMOTE_SCRIPT

encoded_script="$(base64 <"$tmp_script" | tr -d '\n')"
remote_cmd="REMOTE_TELEGRAM_BOT_TOKEN='${TELEGRAM_BOT_TOKEN}' REMOTE_TELEGRAM_ALLOWED_USERS='${TELEGRAM_ALLOWED_USERS}' REMOTE_TELEGRAM_HOME_CHANNEL='${TELEGRAM_HOME_CHANNEL}' bash -lc 'printf %s ${encoded_script} | base64 -d | bash'"
run_remote "$remote_cmd"

if [[ -z "$TELEGRAM_ALLOWED_USERS" || -z "$TELEGRAM_HOME_CHANNEL" ]]; then
  echo "Telegram token is configured, but allowed/home user IDs are not set."
  echo "Send /start to the bot, then run scripts/resolve-telegram-chat.sh or set TELEGRAM_ALLOWED_USERS and TELEGRAM_HOME_CHANNEL in .env."
else
echo "Telegram token, allowlist, and home channel are configured."
fi
echo "Default busy-message mode is queue. Use /stop in Telegram to interrupt the current task."
echo "Quick commands /mitstatus and /mit_status run ~/.hermes/scripts/mit-status.py --summary."
