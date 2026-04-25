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

echo "Installing Mac mini dependencies on $SSH_USER@$SSH_HOST"

run_remote "set -e
sudo -v

if ! command -v brew >/dev/null 2>&1; then
  NONINTERACTIVE=1 CI=1 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"
fi

if [ -x /opt/homebrew/bin/brew ]; then
  eval \"\$(/opt/homebrew/bin/brew shellenv)\"
elif [ -x /usr/local/bin/brew ]; then
  eval \"\$(/usr/local/bin/brew shellenv)\"
fi

brew update
brew install ripgrep ffmpeg

grep -q 'brew shellenv' ~/.zprofile 2>/dev/null || {
  echo 'eval \"\$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile
}

export PATH=\"/opt/homebrew/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH\"
command -v brew
command -v rg
command -v ffmpeg
brew --version | head -1
rg --version | head -1
ffmpeg -version | head -1"

echo "Mac mini dependency install completed."
