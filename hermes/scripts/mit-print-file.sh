#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  mit-print-file.sh --file PATH [--location QUERY] [--queue QUEUE] [--copies N] [--duplex] [--dry-run]
  mit-print-file.sh --url URL  [--location QUERY] [--queue QUEUE] [--copies N] [--duplex] [--dry-run]

Submits a document to a local print queue if one is configured. For MIT Pharos,
the normal queue is often "mitprint"; release the job at a nearby Pharos device.

If no local queue is available, the script prints instructions for Athena Print
Center/MobilePrint: https://print.mit.edu

This Mac mini may be off MITnet. In that case, do not expect direct MIT print
queues to work; use Athena Print Center/MobilePrint from an MIT-authenticated
browser/session instead.
USAGE
}

file=""
url=""
location=""
queue="${MIT_PRINT_QUEUE:-mitprint}"
copies=1
duplex=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) file="$2"; shift 2 ;;
    --url) url="$2"; shift 2 ;;
    --location) location="$2"; shift 2 ;;
    --queue) queue="$2"; shift 2 ;;
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

if ! command -v lp >/dev/null 2>&1; then
  echo
  echo "Local lp command not found. Upload manually to Athena Print Center:"
  echo "  https://print.mit.edu"
  exit 0
fi

if ! lpstat -v "$queue" >/dev/null 2>&1; then
  echo
  echo "Print queue '$queue' is not configured on this machine."
  echo "Upload manually to Athena Print Center/MobilePrint:"
  echo "  https://print.mit.edu"
  echo
  echo "MIT IS&T says Athena Print Center can upload documents and release jobs to Pharos printers."
  echo "This is expected when running from a machine that is not on MITnet."
  exit 0
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
