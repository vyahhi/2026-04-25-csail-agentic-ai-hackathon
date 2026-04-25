---
name: mit-printers
description: Find MIT printers near a fuzzy campus location and help print Telegram attachments or URLs using MIT Pharos/Athena Print Center or a configured local print queue.
---

# MIT Printers

Use this skill when the user asks to find a printer at MIT, print a document, print a Telegram attachment, print a URL, or locate a nearby Pharos printer.

## Operating Rules

- The configured Mac mini is not on the local MIT network. Do not assume it can reach MIT-only printers, MITnet-only KB pages, or department print queues directly.
- Always use live source lookup through `mit-printer-find.py`. Do not use or create a local cached printer dataset.
- If a live source redirects to an access-restricted page from the off-campus Mac mini, report that source failure and use only the sources that were actually fetched.
- Treat printing as a user-visible side effect. Confirm the document and destination before submitting to a local print queue unless the user has already explicitly said to print that exact file.
- Prefer MIT Pharos for general campus printing. MIT IS&T documents that users can install the Pharos client or use Athena Print Center/MobilePrint at `https://print.mit.edu` to upload documents and release jobs at Pharos printers.
- For Pharos, the selected nearby printer is normally where the user releases the job; the submitted queue may be a central queue such as `mitprint`.
- Do not claim a document was physically printed unless `lp` or another print command succeeded. Otherwise say it is ready to upload/release.
- If the local machine is off MITnet or has no MIT print queue configured, use Athena Print Center/MobilePrint at `https://print.mit.edu` as the remote printing path and provide the nearest printer candidates.
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

The helper fetches remote sources on every run:

```text
https://kb.mit.edu/confluence/display/mitcontrib/MIT+Printer+Locations
https://tig.csail.mit.edu/print-copy-scan/macos-printing/
```

The MIT KB Pharos page may be access-restricted from outside MITnet; CSAIL TIG
printing pages are currently public.

## Print File Or URL

Use:

```bash
~/.hermes/scripts/mit-print-file.sh --file /path/to/document.pdf --location "building 10"
~/.hermes/scripts/mit-print-file.sh --url "https://example.edu/file.pdf" --location "stata"
~/.hermes/scripts/mit-print-file.sh --file /path/to/document.pdf --method mobileprint --open-mobileprint
```

Optional flags:

```text
--method auto|mobileprint|lp
--open-mobileprint
--queue QUEUE     default: MIT_PRINT_QUEUE or mitprint
--copies N        default: 1
--duplex
--dry-run
```

If `lp`, MITnet, or the queue is unavailable, the helper prints MobilePrint upload/release instructions. `--open-mobileprint` opens `https://print.mit.edu` on the Mac mini desktop.

## Telegram Attachments

When a user asks from Telegram to print an attached file:

1. Locate the downloaded attachment path or URL in the current Telegram/Hermes message context.
2. If only a Telegram URL is available, download it to a temporary file.
3. Run `mit-print-file.sh --file ... --location ...` or `--url ...`.
4. Prefer `--method mobileprint --open-mobileprint` for remote Pharos printing. Tell the user the document path and nearby printer candidates.

## Sources

- MIT IS&T Printers and Printing service page.
- MIT KB Pharos printer locations.
- MIT Libraries printer location guide.
- CSAIL TIG printing docs.
