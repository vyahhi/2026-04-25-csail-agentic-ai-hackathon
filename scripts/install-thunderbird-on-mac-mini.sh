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

expect <<'EXPECT_EOF'
  log_user 1
  set timeout -1
  set sent_login 0
  spawn ssh -tt -o StrictHostKeyChecking=accept-new $env(SSH_USER)@$env(SSH_HOST) {export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; brew list --cask thunderbird >/dev/null 2>&1 || brew install --cask thunderbird; open -na /Applications/Thunderbird.app}
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
