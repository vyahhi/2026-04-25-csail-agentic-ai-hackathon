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
  "$REPO_ROOT/hermes/skills/domain/mit-printers/SKILL.md:.hermes/skills/domain/mit-printers/SKILL.md"
  "$REPO_ROOT/hermes/scripts/mit-printer-find.py:.hermes/scripts/mit-printer-find.py"
  "$REPO_ROOT/hermes/scripts/mit-print-browser.py:.hermes/scripts/mit-print-browser.py"
  "$REPO_ROOT/hermes/scripts/mit-print-file.sh:.hermes/scripts/mit-print-file.sh"
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

run_remote() {
  local remote_cmd="$1"

  SSH_USER="$SSH_USER" SSH_HOST="$SSH_HOST" SSH_PASSWORD="$SSH_PASSWORD" REMOTE_CMD="$remote_cmd" expect <<'EXPECT_EOF'
    log_user 0
    set timeout -1
    set sent_login 0
    spawn ssh -tt -o PubkeyAuthentication=no -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 $env(SSH_USER)@$env(SSH_HOST) $env(REMOTE_CMD)
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
    spawn scp -q -o PubkeyAuthentication=no -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 -o StrictHostKeyChecking=accept-new $env(LOCAL_PATH) $env(SSH_USER)@$env(SSH_HOST):$env(REMOTE_PATH)
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

echo "Configuring Hermes MIT printers skill on $SSH_USER@$SSH_HOST"
run_remote "mkdir -p ~/.hermes/skills/domain/mit-printers ~/.hermes/scripts && rm -f ~/.hermes/data/mit-printers.json"

for mapping in "${FILES[@]}"; do
  local_path="${mapping%%:*}"
  remote_path="${mapping#*:}"
  copy_remote "$local_path" "$remote_path"
done

run_remote "set -e; if [[ -x ~/.hermes/hermes-agent/venv/bin/python ]]; then ~/.hermes/hermes-agent/venv/bin/python -m pip install websocket-client >/dev/null; else python3 -m pip install --user websocket-client >/dev/null; fi"
run_remote "chmod +x ~/.hermes/scripts/mit-printer-find.py ~/.hermes/scripts/mit-print-browser.py ~/.hermes/scripts/mit-print-file.sh && ~/.hermes/scripts/mit-printer-find.py 'building 10' --limit 3 && if [[ -x ~/.hermes/hermes-agent/venv/bin/python ]]; then ~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/mit-print-browser.py --help >/dev/null; else ~/.hermes/scripts/mit-print-browser.py --help >/dev/null; fi && ~/.hermes/scripts/mit-print-file.sh --help >/dev/null"
echo "Hermes MIT printers skill configuration completed."
