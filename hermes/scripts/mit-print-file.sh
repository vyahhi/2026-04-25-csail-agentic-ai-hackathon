#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  mit-print-file.sh --file PATH [--location QUERY] [--method auto|mobileprint|lp] [--open-mobileprint] [--queue QUEUE] [--copies N] [--duplex] [--dry-run]
  mit-print-file.sh --url URL  [--location QUERY] [--method auto|mobileprint|lp] [--open-mobileprint] [--queue QUEUE] [--copies N] [--duplex] [--dry-run]

Prepares remote MIT Pharos printing through Athena Print Center/MobilePrint, or
submits to a local print queue if one is configured. For MIT Pharos, release the
job at a nearby Pharos device or through MobilePrint.

MobilePrint URL: https://print.mit.edu

The MIT KB Touchless Printing Release with MobilePrint page may be MITnet-only.
If that page is not reachable from the Mac mini, use the Athena Print Center URL.
USAGE
}

file=""
url=""
location=""
queue="${MIT_PRINT_QUEUE:-mitprint}"
queue_explicit=false
copies=1
duplex=false
dry_run=false
method="auto"
open_mobileprint=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) file="$2"; shift 2 ;;
    --url) url="$2"; shift 2 ;;
    --location) location="$2"; shift 2 ;;
    --method) method="$2"; shift 2 ;;
    --open-mobileprint) open_mobileprint=true; shift ;;
    --queue) queue="$2"; queue_explicit=true; shift 2 ;;
    --copies) copies="$2"; shift 2 ;;
    --duplex) duplex=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$file" && -z "$url" ]]; then
  echo "Provide --file or --url." >&2
  usage >&2
  exit 2
fi

if [[ -n "$file" && -n "$url" ]]; then
  echo "Use only one of --file or --url." >&2
  exit 2
fi

case "$method" in
  auto|mobileprint|lp) ;;
  *) echo "Unknown --method: $method" >&2; usage >&2; exit 2 ;;
esac

if [[ -n "$url" ]]; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  name="$(basename "${url%%\?*}")"
  [[ -n "$name" && "$name" != "/" ]] || name="downloaded-document"
  file="$tmpdir/$name"
  curl -fL "$url" -o "$file"
fi

if [[ ! -f "$file" ]]; then
  echo "File not found: $file" >&2
  exit 1
fi

echo "Document: $file"
if [[ -n "$location" && -x "$HOME/.hermes/scripts/mit-printer-find.py" ]]; then
  echo
  echo "Nearby printer candidates for: $location"
  "$HOME/.hermes/scripts/mit-printer-find.py" "$location" --limit 3 || true
fi

print_mobileprint_instructions() {
  echo
  echo "Remote MIT printing path: Athena Print Center/MobilePrint"
  echo "  1. Open https://print.mit.edu in an MIT-authenticated browser."
  echo "  2. Upload this document:"
  echo "     $file"
  echo "  3. Set copies/options in MobilePrint."
  echo "  4. Release the job remotely in Athena Print Center or at the selected Pharos printer."
  echo
  echo "MIT KB reference, may require MITnet or MIT VPN:"
  echo "  https://kb.mit.edu/confluence/display/istcontrib/Touchless+Printing+Release+with+MobilePrint"
}

run_mobileprint_browser() {
  local browser_script="$HOME/.hermes/scripts/mit-print-browser.py"
  local browser_runner=()
  if [[ ! -f "$browser_script" ]]; then
    print_mobileprint_instructions
    return 0
  fi
  if [[ -x "$HOME/.hermes/hermes-agent/venv/bin/python" ]]; then
    browser_runner=("$HOME/.hermes/hermes-agent/venv/bin/python" "$browser_script")
  else
    browser_runner=("$browser_script")
  fi

  local browser_printer=""
  if [[ "$queue_explicit" == true && -n "$queue" && "$queue" != "mitprint" ]]; then
    browser_printer="$queue"
  elif [[ -n "$location" && -x "$HOME/.hermes/scripts/mit-printer-find.py" ]]; then
    browser_printer="$("$HOME/.hermes/scripts/mit-printer-find.py" "$location" --limit 1 --json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
results = data.get("results") or []
if results:
    printer = results[0]
    candidates = (
        printer.get("bw_hostnames")
        or printer.get("hostnames")
        or ([printer.get("queue")] if printer.get("queue") else [])
        or ([printer.get("name")] if printer.get("name") else [])
    )
    if candidates:
        print(str(candidates[0]).replace(".mit.edu", ""))
')"
  fi

  local printer_arg=()
  if [[ -n "$browser_printer" ]]; then
    printer_arg=(--printer "$browser_printer")
  fi

  if ! "${browser_runner[@]}" print --file "$file" "${printer_arg[@]}"; then
    local status=$?
    print_mobileprint_instructions
    return "$status"
  fi
}

if [[ "$open_mobileprint" == true ]]; then
  if command -v open >/dev/null 2>&1; then
    open "https://print.mit.edu" || true
  else
    echo "Cannot open browser automatically; command 'open' is unavailable." >&2
  fi
fi

if [[ "$method" == "mobileprint" ]]; then
  run_mobileprint_browser
  exit $?
fi

if ! command -v lp >/dev/null 2>&1; then
  run_mobileprint_browser
  exit $?
fi

if ! lpstat -v "$queue" >/dev/null 2>&1; then
  if [[ "$method" == "lp" ]]; then
    echo "Print queue '$queue' is not configured on this machine." >&2
    exit 1
  fi
  run_mobileprint_browser
  exit $?
fi

cmd=(lp -d "$queue" -n "$copies")
if [[ "$duplex" == true ]]; then
  cmd+=(-o sides=two-sided-long-edge)
fi
cmd+=("$file")

echo
echo "Print command:"
printf ' %q' "${cmd[@]}"
echo

if [[ "$dry_run" == true ]]; then
  echo "Dry run only; not submitting."
  exit 0
fi

"${cmd[@]}"
echo "Submitted to queue '$queue'. For MIT Pharos, release the job at a nearby Pharos printer or via Athena Print Center."
