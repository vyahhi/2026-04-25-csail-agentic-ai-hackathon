#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
LOCAL_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

if [[ ! -f "$LOCAL_CODEX_HOME/auth.json" ]]; then
  echo "Missing local Codex OAuth file: $LOCAL_CODEX_HOME/auth.json" >&2
  echo "Run 'codex login' locally first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

SSH_USER="${MAC_MINI_SSH_USER:?MAC_MINI_SSH_USER is required}"
SSH_HOST="${MAC_MINI_TAILSCALE_DNS:-${MAC_MINI_TAILSCALE_HOST:?MAC_MINI_TAILSCALE_HOST is required}}"
SSH_PASSWORD="${MAC_MINI_SSH_PASSWORD:?MAC_MINI_SSH_PASSWORD is required}"
HERMES_MODEL="${HERMES_MODEL:-gpt-5.4}"

if ! command -v expect >/dev/null 2>&1; then
  echo "This script requires expect for password-based SSH automation." >&2
  exit 1
fi

remote_expect() {
  local mode="$1"
  local payload="$2"

  SSH_USER="$SSH_USER" SSH_HOST="$SSH_HOST" SSH_PASSWORD="$SSH_PASSWORD" PAYLOAD="$payload" MODE="$mode" expect <<'EXPECT_EOF'
    log_user 1
    set timeout -1
    set sent_login 0
    if {$env(MODE) == "ssh"} {
      spawn ssh -tt -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 $env(SSH_USER)@$env(SSH_HOST) $env(PAYLOAD)
    } else {
      spawn sh -c $env(PAYLOAD)
    }
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
      -re {(?i)(use|import|continue|overwrite|select).*\[[Yy]/[Nn]\]} {
        send "y\r"
        exp_continue
      }
      -re {(?i)(use|import|continue|overwrite|select).*\[[Yy]\]} {
        send "\r"
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

echo "Installing Codex CLI cask on $SSH_USER@$SSH_HOST if needed"
remote_expect ssh "set -e
export PATH=\"/opt/homebrew/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH\"
if ! command -v brew >/dev/null 2>&1; then
  echo 'Homebrew is required. Run scripts/install-mac-mini-deps.sh first.' >&2
  exit 1
fi
if ! command -v codex >/dev/null 2>&1; then
  brew install --cask codex
fi
command -v codex
codex --version"

echo "Copying local Codex OAuth files to $SSH_USER@$SSH_HOST"
remote_expect ssh "mkdir -p ~/.codex && chmod 700 ~/.codex"
remote_expect scp "scp -q -o StrictHostKeyChecking=accept-new '$LOCAL_CODEX_HOME/auth.json' '$SSH_USER@$SSH_HOST:.codex/auth.json'"
if [[ -f "$LOCAL_CODEX_HOME/config.toml" ]]; then
  remote_expect scp "scp -q -o StrictHostKeyChecking=accept-new '$LOCAL_CODEX_HOME/config.toml' '$SSH_USER@$SSH_HOST:.codex/config.toml'"
fi
remote_expect ssh "chmod 600 ~/.codex/auth.json ~/.codex/config.toml 2>/dev/null || chmod 600 ~/.codex/auth.json"

echo "Importing Codex OAuth into Hermes and selecting $HERMES_MODEL"
remote_expect ssh "set -e
export PATH=\"/opt/homebrew/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH\"
hermes auth add openai-codex || hermes auth status openai-codex
python3 - <<'PY'
from pathlib import Path
path = Path.home() / '.hermes' / 'config.yaml'
text = path.read_text()
text = text.replace('default: \"anthropic/claude-opus-4.6\"', 'default: \"gpt-5.4\"')
text = text.replace('default: \"gpt-5.5\"', 'default: \"gpt-5.4\"')
text = text.replace('provider: \"auto\"', 'provider: \"openai-codex\"')
text = text.replace('base_url: \"https://openrouter.ai/api/v1\"', 'base_url: \"https://chatgpt.com/backend-api/codex\"')
path.write_text(text)
PY
hermes auth status openai-codex
hermes doctor"

echo "Hermes OpenAI Codex OAuth configuration completed."
