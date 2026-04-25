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

if ! command -v expect >/dev/null 2>&1; then
  echo "This script requires expect for password-based SSH automation." >&2
  exit 1
fi

run_remote() {
  local remote_cmd="$1"

  SSH_USER="$SSH_USER" SSH_HOST="$SSH_HOST" SSH_PASSWORD="$SSH_PASSWORD" REMOTE_CMD="$remote_cmd" expect <<'EXPECT_EOF'
    log_user 1
    set timeout -1
    spawn ssh -tt -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 $env(SSH_USER)@$env(SSH_HOST) $env(REMOTE_CMD)
    expect {
      -glob "*Password:*" {
        send "$env(SSH_PASSWORD)\r"
        exp_continue
      }
      -glob "*password:*" {
        send "$env(SSH_PASSWORD)\r"
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

echo "Installing persistent browser helper on $SSH_USER@$SSH_HOST"

helper_b64="$(base64 <"$REPO_ROOT/hermes/scripts/persistent-browser-cdp.sh" | tr -d '\n')"

run_remote "set -e
mkdir -p ~/.hermes/scripts ~/.hermes
printf '%s' '$helper_b64' | base64 -d > ~/.hermes/scripts/persistent-browser-cdp.sh
chmod +x ~/.hermes/scripts/persistent-browser-cdp.sh
python3 - <<'PY'
from pathlib import Path
path = Path.home() / '.hermes' / 'config.yaml'
text = path.read_text()
if 'browser:' not in text:
    text += '\n# Persistent browser configuration\nbrowser:\n  cdp_url: \"http://127.0.0.1:9222\"\n'
elif 'cdp_url:' not in text:
    lines = text.splitlines()
    out = []
    inserted = False
    for line in lines:
        out.append(line)
        if line.strip() == 'browser:':
            out.append('  cdp_url: \"http://127.0.0.1:9222\"')
            inserted = True
    text = '\n'.join(out) + '\n'
else:
    import re
    text = re.sub(r'(^\\s*cdp_url:\\s*\").*(\"\\s*$)', r'\\1http://127.0.0.1:9222\\2', text, flags=re.M)
path.write_text(text)
PY
~/.hermes/scripts/persistent-browser-cdp.sh start
export PATH=\"\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH\"
hermes dump 2>/dev/null | sed -n '1,40p'
~/.hermes/scripts/persistent-browser-cdp.sh status"

echo "Persistent browser CDP configured."
