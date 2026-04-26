---
name: mit-printers
description: Find MIT printers near a fuzzy campus location and help print Telegram attachments or URLs using documented MIT Pharos/Athena Print Center flows or a configured local print queue, with direct IPP kept as an explicit advanced option.
---

# MIT Printers

Use this skill when the user asks to find a printer at MIT, print a document, print a Telegram attachment, print a URL, or locate a nearby Pharos printer.

## Operating Rules

- The configured Mac mini is normally off local MIT network, but it can use MIT VPN. VPN helps with MIT-restricted docs and services, but do not treat specific-printer IPP as the default MIT public-printing path.
- Use `mit-printer-find.py`, which includes a bundled public MIT printer baseline and augments it with live source lookup when available. Do not create a separate local cached printer dataset.
- If a live source redirects to an access-restricted page from the off-campus Mac mini, report that source failure and use only the sources that were actually fetched.
- Treat printing as a user-visible side effect. Confirm the document and destination before submitting to a local print queue unless the user has already explicitly said to print that exact file.
- Prefer MIT Pharos for general campus printing. Use the documented MIT public-printing paths first: a configured Pharos/LPR queue if present, or Athena Print Center/MobilePrint at `https://print.mit.edu`.
- For Pharos, the selected nearby printer is normally where the user releases the job; the submitted queue may be a central queue such as `mitprint`.
- Hermes can submit and release MobilePrint jobs through the persistent Chrome session on the Mac mini when `print.mit.edu` is still authenticated. Hermes can also submit direct IPP jobs to reachable public MIT printers, but keep that as an explicit advanced mode because MIT’s public docs emphasize Pharos queue/client/MobilePrint flows, not specific-printer IPP accounting.
- Do not claim a document was physically printed unless `lp`, the MobilePrint browser helper, or an explicitly requested direct IPP submission succeeded. Otherwise say it is only prepared and why.
- If a local `lp` queue is unavailable, use Athena Print Center/MobilePrint at `https://print.mit.edu` as the remote printing path and provide the nearest printer candidates.
- The MIT KB Touchless Printing Release with MobilePrint page is the reference for remote release, but it may require MITnet or MIT VPN.
- Use only documents or URLs the user supplied. Do not access private documents without explicit user intent.
- For public MIT printer queries near CSAIL/Stata/Building 32, return only general MIT Pharos printers by default, not CSAIL department-local queues.
- Only include CSAIL department printers when the user explicitly asks for department/private/internal CSAIL queues or queue names.

## Find Nearby Printers

Use the fuzzy finder:

```bash
~/.hermes/scripts/mit-printer-find.py "stata"
~/.hermes/scripts/mit-printer-find.py "building 10"
~/.hermes/scripts/mit-printer-find.py "near E51"
~/.hermes/scripts/mit-printer-find.py "csail" --json
~/.hermes/scripts/mit-printer-find.py "csail private queue" --include-department
```

The helper uses a bundled public MIT printer list and also fetches remote sources on every run:

```text
bundled public MIT printer list in repo
https://kb.mit.edu/confluence/display/mitcontrib/MIT+Printer+Locations
https://tig.csail.mit.edu/print-copy-scan/macos-printing/
```

The MIT KB Pharos page may be access-restricted from outside MITnet; CSAIL TIG
printing pages are currently public. When MIT KB is blocked, the bundled public
MIT list remains available for general printer discovery.

## Print File Or URL

Use:

```bash
~/.hermes/scripts/mit-print-browser.py print --file /path/to/document.pdf --printer stata-p
~/.hermes/scripts/mit-print-file.sh --file /path/to/document.pdf --location "building 10"
~/.hermes/scripts/mit-print-file.sh --url "https://example.edu/file.pdf" --location "stata"
~/.hermes/scripts/mit-print-file.sh --file /path/to/document.pdf --method ipp --queue stata-p
~/.hermes/scripts/mit-print-file.sh --file /path/to/document.pdf --method mobileprint --open-mobileprint
```

Optional flags:

```text
--method auto|ipp|mobileprint|lp
--open-mobileprint
--queue QUEUE     default: MIT_PRINT_QUEUE or mitprint
--copies N        default: 1
--duplex
--dry-run
```

`mit-print-file.sh --method auto` should use the documented MIT path first: a configured local `lp` queue if present, otherwise the MobilePrint browser helper. Keep `--method ipp` as an explicit advanced option when you intentionally want direct browserless submission to a specific reachable printer over VPN. Run the browser helper from the Hermes repo venv, not system Python, because the working environment may only have the required websocket/browser dependencies there:

```bash
source ~/.hermes/hermes-agent/venv/bin/activate && python ~/.hermes/scripts/mit-print-browser.py print --file /absolute/path/to/file.pdf --printer stata-p
```

If the persistent browser session is not authenticated, it then prints MobilePrint upload/release instructions. `--open-mobileprint` opens `https://print.mit.edu` on the Mac mini desktop.

## Verified Direct IPP Path

On this Mac mini with MIT VPN connected, direct IPP submission has been verified against:

```text
ipp://stata-p.mit.edu/printers/stata-p
ipp://stata-color.mit.edu/printers/stata-color
```

So direct IPP is technically available as an advanced path, but not the default MIT public-printing path.

### CDP fallback when the browser helper stalls

The My Print Center automation can fail even after upload succeeds, commonly with messages like:
- `Could not reach the print confirmation dialog.`
- `Uploaded file ... did not become ready in My Print Center.`

When that happens, use the live persistent browser session plus `browser_cdp` as a recovery path instead of giving up:

1. Find the active `print.mit.edu` tab with `Target.getTargets`.
2. Inspect page state with `Runtime.evaluate` to read the title/body text, visible buttons, current quota, and whether the uploaded filename appears in the jobs table.
3. If needed, click `Refresh` or `OK` style controls in page DOM.
4. If the uploaded row is present but not selected, programmatically check/select its checkbox.
5. Click the page `Print` button via DOM script.
6. If a Pharos confirmation dialog appears, click `Confirm` via DOM script.
7. Verify success by re-reading page state. Strong success signals are:
   - the uploaded file row disappears
   - page shows `There is no data` / `No items to display`
   - `hasFile:false` in your DOM probe
   - print quota decreases by the document cost

Do not say the job printed successfully until one of the helper flows or the CDP fallback is actually verified.

## Telegram Attachments

When a user asks from Telegram to print an attached file:

1. Locate the downloaded attachment path or URL in the current Telegram/Hermes message context.
2. If only a Telegram URL is available, download it to a temporary file.
3. Run `mit-print-file.sh --file ... --location ...` or `--url ...`.
4. Prefer `--method auto` for normal MIT public printing. Use `--method ipp` only when you explicitly want the advanced direct-printer path.

## Sources

- MIT IS&T Printers and Printing service page.
- MIT KB Pharos printer locations.
- MIT Libraries printer location guide.
- CSAIL TIG printing docs.
