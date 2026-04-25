#!/usr/bin/env bash
set -euo pipefail

portal="${MIT_VPN_PORTAL:-gpvpn.mit.edu}"
action="${1:-status}"

usage() {
  cat <<'USAGE'
Usage:
  mit-vpn-globalprotect.sh status
  mit-vpn-globalprotect.sh open-portal
  mit-vpn-globalprotect.sh open-app
  mit-vpn-globalprotect.sh connect
  mit-vpn-globalprotect.sh test-kb

MIT VPN uses GlobalProtect / Prisma Access. Login requires interactive MIT
Kerberos and Duo approval, so this helper opens the Mac desktop UI and reports
status rather than trying to bypass the interactive flow.
USAGE
}

globalprotect_cli() {
  for candidate in \
    "/Applications/GlobalProtect.app/Contents/MacOS/GlobalProtect" \
    "/Applications/GlobalProtect.app/Contents/Resources/globalprotect" \
    "/usr/local/bin/globalprotect" \
    "/opt/homebrew/bin/globalprotect"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

status() {
  echo "Portal: $portal"
  if [[ -d /Applications/GlobalProtect.app ]]; then
    echo "GlobalProtect app: installed"
  else
    echo "GlobalProtect app: not installed"
  fi

  if cli="$(globalprotect_cli)"; then
    echo "GlobalProtect CLI: $cli"
    "$cli" show --status 2>/dev/null || true
  else
    echo "GlobalProtect CLI: not found"
  fi

  if pgrep -fl 'GlobalProtect|PanGPS|PanGPA' >/dev/null 2>&1; then
    echo "GlobalProtect process: running"
    pgrep -fl 'GlobalProtect|PanGPS|PanGPA' || true
  else
    echo "GlobalProtect process: not running"
  fi
}

open_portal() {
  echo "Opening https://$portal on the Mac mini desktop."
  open "https://$portal"
}

open_app() {
  if [[ -d /Applications/GlobalProtect.app ]]; then
    echo "Opening GlobalProtect.app."
    open -a GlobalProtect
  else
    echo "GlobalProtect.app is not installed. Opening portal for installer download."
    open_portal
  fi
}

connect_vpn() {
  if cli="$(globalprotect_cli)"; then
    echo "Starting GlobalProtect connection to $portal."
    "$cli" connect --portal "$portal" || true
  else
    open_app
  fi
  echo "Complete MIT Kerberos and Duo approval in the GlobalProtect UI."
}

test_kb() {
  final_url="$(
    python3 - <<'PY'
import urllib.request
url = "https://kb.mit.edu/confluence/display/istcontrib/Touchless+Printing+Release+with+MobilePrint"
req = urllib.request.Request(url, headers={"User-Agent": "Hermes MIT VPN check/1.0"})
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        print(resp.geturl())
except Exception as exc:
    print(f"ERROR: {exc}")
PY
  )"
  echo "MIT KB final URL: $final_url"
  if [[ "$final_url" == *accessrestricted* ]]; then
    echo "MIT KB is still access-restricted from this Mac. VPN is not connected or not routing MIT KB."
    return 1
  fi
}

case "$action" in
  status) status ;;
  open-portal) open_portal ;;
  open-app) open_app ;;
  connect) connect_vpn ;;
  test-kb) test_kb ;;
  -h|--help|help) usage ;;
  *) echo "Unknown action: $action" >&2; usage >&2; exit 2 ;;
esac
