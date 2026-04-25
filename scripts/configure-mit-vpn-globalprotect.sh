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
MIT_VPN_PORTAL="${MIT_VPN_PORTAL:-gpvpn.mit.edu}"

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

echo "Checking MIT GlobalProtect VPN on $SSH_USER@$SSH_HOST"
run_remote "set -e; \
  echo 'Portal: $MIT_VPN_PORTAL'; \
  if [[ -d /Applications/GlobalProtect.app ]]; then \
    echo 'GlobalProtect app: installed'; \
  else \
    echo 'GlobalProtect app: not installed'; \
  fi; \
  if pgrep -fl 'GlobalProtect|PanGPS|PanGPA' >/dev/null 2>&1; then \
    echo 'GlobalProtect process: running'; \
    pgrep -fl 'GlobalProtect|PanGPS|PanGPA' || true; \
  else \
    echo 'GlobalProtect process: not running'; \
  fi; \
  echo 'Opening https://$MIT_VPN_PORTAL on the Mac mini desktop for Kerberos/Duo login and installer download.'; \
  open 'https://$MIT_VPN_PORTAL'"

cat <<EOF

MIT VPN setup is interactive:
1. On the Mac mini desktop, log in at https://$MIT_VPN_PORTAL with MIT Kerberos and Duo.
2. Download the macOS GlobalProtect package and install it.
3. If macOS asks, allow Palo Alto Networks under System Settings.
4. In GlobalProtect, use portal address: $MIT_VPN_PORTAL
5. Connect and complete Kerberos/Duo.

After connecting, rerun this script or test MIT KB access from the Mac mini.
EOF
