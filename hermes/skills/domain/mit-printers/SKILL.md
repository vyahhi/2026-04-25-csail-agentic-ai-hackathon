---
name: mit-printers
description: Find MIT printers near a fuzzy campus location and help print Telegram attachments or URLs using MIT Pharos/Athena Print Center or a configured local print queue.
---

# MIT Printers

Use this skill when the user asks to find a printer at MIT, print a document, print a Telegram attachment, print a URL, or locate a nearby Pharos printer.

## Operating Rules

- The configured Mac mini is not on the local MIT network. Do not assume it can reach MIT-only printers, MITnet-only KB pages, or department print queues directly.
- The local printer list is a cached dataset, not automatically live. If the user needs current availability, verify against MIT Printer Locations, CSAIL TIG printing docs, or live CUPS/status pages from an MIT/CSAIL network.
- Treat printing as a user-visible side effect. Confirm the document and destination before submitting to a local print queue unless the user has already explicitly said to print that exact file.
- Prefer MIT Pharos for general campus printing. MIT IS&T documents that users can install the Pharos client or use Athena Print Center/MobilePrint at `https://print.mit.edu` to upload documents and release jobs at Pharos printers.
- For Pharos, the selected nearby printer is normally where the user releases the job; the submitted queue may be a central queue such as `mitprint`.
- Do not claim a document was physically printed unless `lp` or another print command succeeded. Otherwise say it is ready to upload/release.
- If the local machine is off MITnet or has no MIT print queue configured, direct the user to Athena Print Center/MobilePrint and provide the nearest printer candidates.
- Use only documents or URLs the user supplied. Do not access private documents without explicit user intent.
- For public Pharos printing near CSAIL/Stata/Building 32, prefer Stata Lobby Pharos printers first.
- For CSAIL department printing, report the CSAIL queue name and required network: Building 32 printing requires CSAILPrivate wireless or wired CSAIL Ethernet.

## Find Nearby Printers

Use the fuzzy finder:

```bash
~/.hermes/scripts/mit-printer-find.py "stata"
~/.hermes/scripts/mit-printer-find.py "building 10"
~/.hermes/scripts/mit-printer-find.py "near E51"
```

The data file is:

```text
~/.hermes/data/mit-printers.json
```

## Print File Or URL

Use:

```bash
~/.hermes/scripts/mit-print-file.sh --file /path/to/document.pdf --location "building 10"
~/.hermes/scripts/mit-print-file.sh --url "https://example.edu/file.pdf" --location "stata"
```

Optional flags:

```text
--queue QUEUE     default: MIT_PRINT_QUEUE or mitprint
--copies N        default: 1
--duplex
--dry-run
```

If `lp`, MITnet, or the queue is unavailable, the helper prints MobilePrint instructions.

## Telegram Attachments

When a user asks from Telegram to print an attached file:

1. Locate the downloaded attachment path or URL in the current Telegram/Hermes message context.
2. If only a Telegram URL is available, download it to a temporary file.
3. Run `mit-print-file.sh --file ... --location ...` or `--url ...`.
4. If no queue is configured, tell the user to upload the file at `https://print.mit.edu` and release it at one of the nearby printer candidates.

## Sources Encoded In The Local Dataset

- MIT IS&T Printers and Printing service page.
- MIT Libraries printer location guide.
- MIT computing map public student printer list.
- MIT Tang Hall computing page.
- MIT Math Department printing page for department printers.
