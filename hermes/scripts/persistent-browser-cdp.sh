#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  persistent-browser-cdp.sh start
  persistent-browser-cdp.sh stop
  persistent-browser-cdp.sh status

Starts a persistent Google Chrome instance with a dedicated user-data-dir and
Chrome DevTools Protocol enabled on 127.0.0.1:9222. Hermes can then reuse this
browser profile via browser.cdp_url in ~/.hermes/config.yaml, preserving cookies
and MIT SSO state across browser tasks.
USAGE
}

action="${1:-status}"
cdp_port="${HERMES_BROWSER_CDP_PORT:-9222}"
profile_dir="${HERMES_BROWSER_PROFILE_DIR:-$HOME/.hermes/chrome-cdp-profile}"
pid_file="${HERMES_BROWSER_PID_FILE:-$HOME/.hermes/chrome-cdp.pid}"
chrome_app="${HERMES_BROWSER_APP:-/Applications/Google Chrome.app}"
chrome_bin="$chrome_app/Contents/MacOS/Google Chrome"

is_running() {
  if [[ ! -f "$pid_file" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

wait_for_port() {
  python3 - "$cdp_port" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
deadline = time.time() + 15
while time.time() < deadline:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(1)
    try:
        sock.connect(("127.0.0.1", port))
    except OSError:
        time.sleep(0.5)
    else:
        sock.close()
        print(f"listening:{port}")
        sys.exit(0)
sys.exit(1)
PY
}

case "$action" in
  start)
    if [[ ! -x "$chrome_bin" ]]; then
      echo "Chrome binary not found: $chrome_bin" >&2
      exit 1
    fi
    mkdir -p "$profile_dir"
    chmod 700 "$profile_dir"
    if is_running; then
      echo "Persistent Chrome already running with PID $(cat "$pid_file")."
      exit 0
    fi
    nohup "$chrome_bin" \
      --remote-debugging-address=127.0.0.1 \
      --remote-debugging-port="$cdp_port" \
      --user-data-dir="$profile_dir" \
      --no-first-run \
      --no-default-browser-check \
      >/tmp/hermes-chrome-cdp.log 2>&1 &
    echo "$!" >"$pid_file"
    chmod 600 "$pid_file"
    wait_for_port
    echo "Started persistent Chrome on http://127.0.0.1:$cdp_port with profile $profile_dir"
    ;;
  stop)
    if is_running; then
      kill "$(cat "$pid_file")"
      rm -f "$pid_file"
      echo "Stopped persistent Chrome."
    else
      echo "Persistent Chrome is not running."
    fi
    ;;
  status)
    if is_running; then
      echo "running pid=$(cat "$pid_file") port=$cdp_port profile=$profile_dir"
    else
      echo "stopped port=$cdp_port profile=$profile_dir"
    fi
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown action: $action" >&2
    usage >&2
    exit 2
    ;;
esac
