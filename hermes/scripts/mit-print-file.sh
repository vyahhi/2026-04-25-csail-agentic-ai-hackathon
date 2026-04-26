#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  mit-print-file.sh --file PATH [--location QUERY] [--method auto|ipp|mobileprint|lp] [--open-mobileprint] [--queue QUEUE] [--copies N] [--duplex] [--dry-run]
  mit-print-file.sh --url URL  [--location QUERY] [--method auto|ipp|mobileprint|lp] [--open-mobileprint] [--queue QUEUE] [--copies N] [--duplex] [--dry-run]

Prints by one of three paths:
  1. local lp/CUPS queue if one is configured
  2. Athena Print Center/MobilePrint browser automation
  3. direct IPP to a reachable MIT printer over VPN/MITnet as an explicit advanced mode

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
printer_json=""

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
  auto|ipp|mobileprint|lp) ;;
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
  printer_json="$("$HOME/.hermes/scripts/mit-printer-find.py" "$location" --limit 1 --json 2>/dev/null || true)"
fi

resolve_printer_target() {
  local explicit="$1"
  local json_input="${2:-}"
  TARGET_QUEUE=""
  TARGET_HOST=""
  TARGET_URI=""

  if [[ -n "$explicit" && "$explicit" != "mitprint" ]]; then
    TARGET_QUEUE="${explicit%.mit.edu}"
    if [[ "$explicit" == *.* ]]; then
      TARGET_HOST="$explicit"
    else
      TARGET_HOST="${TARGET_QUEUE}.mit.edu"
    fi
  elif [[ -n "$json_input" ]]; then
    local resolved
    resolved="$(printf '%s' "$json_input" | python3 -c '
import json, sys
data = json.load(sys.stdin)
results = data.get("results") or []
if not results:
    raise SystemExit(0)
printer = results[0]
queue = (printer.get("queue") or "").strip()
hosts = (
    printer.get("bw_hostnames")
    or printer.get("hostnames")
    or []
)
host = (hosts[0] if hosts else "").strip()
if not queue and host.endswith(".mit.edu"):
    queue = host[:-8]
print(f"{queue}\t{host}")
')" || true
    TARGET_QUEUE="${resolved%%$'\t'*}"
    TARGET_HOST="${resolved#*$'\t'}"
  fi

  if [[ -n "$TARGET_QUEUE" && -n "$TARGET_HOST" ]]; then
    TARGET_URI="ipp://$TARGET_HOST/printers/$TARGET_QUEUE"
  fi
}

document_format() {
  local lower="${file##*/}"
  lower="$(printf '%s' "$lower" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.pdf) echo "application/pdf" ;;
    *.txt|*.text|*.md|*.csv|*.log) echo "text/plain" ;;
    *.jpg|*.jpeg) echo "image/jpeg" ;;
    *.png) echo "image/png" ;;
    *.ps) echo "application/postscript" ;;
    *) echo "application/octet-stream" ;;
  esac
}

ipp_printer_ready() {
  local uri="$1"
  command -v ipptool >/dev/null 2>&1 || return 1
  ipptool -tv "$uri" /usr/share/cups/ipptool/get-printer-attributes.test >/dev/null 2>&1
}

run_ipp_print() {
  resolve_printer_target "${queue_explicit:+$queue}" "$printer_json"
  if [[ -z "$TARGET_URI" ]]; then
    return 1
  fi
  if ! ipp_printer_ready "$TARGET_URI"; then
    return 1
  fi

  local fmt
  fmt="$(document_format)"
  echo
  echo "Direct IPP target:"
  echo "  queue: $TARGET_QUEUE"
  echo "  host:  $TARGET_HOST"
  echo "  uri:   $TARGET_URI"
  echo "  format:$fmt"

  if [[ "$dry_run" == true ]]; then
    echo "Dry run only; not submitting."
    return 0
  fi

  local cmd=(ipptool -tv -f "$file" -d "document-format=$fmt" -d "copies=$copies")
  if [[ "$duplex" == true ]]; then
    cmd+=(-d "sides=two-sided-long-edge")
  fi
  cmd+=("$TARGET_URI" /usr/share/cups/ipptool/print-job.test)

  echo
  echo "IPP command:"
  printf ' %q' "${cmd[@]}"
  echo

  local output
  if ! output="$("${cmd[@]}" 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  printf '%s\n' "$output"
  if ! grep -q "status-code = successful-ok" <<<"$output"; then
    echo "IPP submission did not return successful-ok." >&2
    return 1
  fi
  echo "Submitted directly over IPP to '$TARGET_QUEUE'."
}

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
  elif [[ -n "$printer_json" ]]; then
    browser_printer="$(printf '%s' "$printer_json" | python3 -c '
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

if [[ "$method" == "ipp" ]]; then
  if run_ipp_print; then
    exit 0
  fi
  echo "Direct IPP printing is not available for the requested printer from this machine." >&2
  exit 1
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
