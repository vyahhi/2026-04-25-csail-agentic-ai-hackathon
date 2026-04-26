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
ALERT_INTERVAL="${HERMES_MIT_ALERT_INTERVAL_SECONDS:-900}"
PLIST_LABEL="ai.hermes.mit-degraded-alert"

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
      eof {
        catch wait result
        exit [lindex $result 3]
      }
    }
EXPECT_EOF
}

tmp_script="$(mktemp)"
cat >"$tmp_script" <<REMOTE_SCRIPT
set -euo pipefail
install -m 755 /tmp/mit-degraded-alert.py ~/.hermes/scripts/mit-degraded-alert.py
mkdir -p ~/.hermes/logs ~/Library/LaunchAgents
python3 - <<'PY'
from pathlib import Path
home = Path.home()
plist = home / "Library" / "LaunchAgents" / "${PLIST_LABEL}.plist"
python_bin = home / ".hermes" / "hermes-agent" / "venv" / "bin" / "python"
if not python_bin.exists():
    python_bin = Path("/usr/bin/python3")
script = home / ".hermes" / "scripts" / "mit-degraded-alert.py"
stdout_log = home / ".hermes" / "logs" / "mit-degraded-alert.log"
stderr_log = home / ".hermes" / "logs" / "mit-degraded-alert.error.log"
plist.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>{python_bin}</string>
    <string>{script}</string>
    <string>--send</string>
  </array>
  <key>StartInterval</key>
  <integer>${ALERT_INTERVAL}</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>{stdout_log}</string>
  <key>StandardErrorPath</key>
  <string>{stderr_log}</string>
</dict>
</plist>
''')
PY
uid=\$(id -u)
launchctl bootout gui/\$uid ~/Library/LaunchAgents/${PLIST_LABEL}.plist >/dev/null 2>&1 || true
launchctl bootstrap gui/\$uid ~/Library/LaunchAgents/${PLIST_LABEL}.plist
launchctl kickstart -k gui/\$uid/${PLIST_LABEL}
launchctl print gui/\$uid/${PLIST_LABEL}
REMOTE_SCRIPT

echo "Configuring degraded MIT alerts on $SSH_USER@$SSH_HOST"
run_remote "mkdir -p ~/.hermes/scripts ~/.hermes/logs ~/Library/LaunchAgents"
copy_remote "$REPO_ROOT/hermes/scripts/mit-degraded-alert.py" "/tmp/mit-degraded-alert.py"
copy_remote "$tmp_script" "/tmp/setup-hermes-alerts.sh"
run_remote "bash /tmp/setup-hermes-alerts.sh"
rm -f "$tmp_script"
echo "Installed degraded alert service."
echo "Label: ${PLIST_LABEL}"
echo "Interval: ${ALERT_INTERVAL}s"
