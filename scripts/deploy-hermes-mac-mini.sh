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
INSTALL_URL="${HERMES_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"

if ! command -v expect >/dev/null 2>&1; then
  echo "This script requires expect for password-based SSH automation." >&2
  exit 1
fi

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

echo "Deploying Hermes Agent to $SSH_USER@$SSH_HOST"

run_remote "hostname; whoami; sw_vers -productVersion"

run_remote "curl -fsSL '$INSTALL_URL' | bash -s -- --skip-setup"

run_remote "mkdir -p ~/.hermes/memories"
copy_remote "$REPO_ROOT/hermes/SOUL.md" ".hermes/SOUL.md"
copy_remote "$REPO_ROOT/hermes/memories/MEMORY.md" ".hermes/memories/MEMORY.md"
copy_remote "$REPO_ROOT/hermes/memories/USER.md" ".hermes/memories/USER.md"

run_remote "export PATH=\"\$HOME/.local/bin:\$PATH\"; command -v hermes; hermes --help >/dev/null; hermes doctor || true"

echo "Hermes deploy completed. Run setup interactively with:"
echo "  ssh $SSH_USER@$SSH_HOST 'export PATH=\"\$HOME/.local/bin:\$PATH\"; hermes setup'"
