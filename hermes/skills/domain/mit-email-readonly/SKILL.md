---
name: mit-email-readonly
description: Read-only access guidance for the user's MIT Microsoft 365 mailbox. Prefer local Apple Mail data and fall back to a saved Outlook browser session only when needed.
---

# MIT Email Read-Only

MIT email is Microsoft 365/Outlook.

## Rules

- Read-only by default. Do not send, reply, forward, delete, archive, move, mark read/unread, or create rules.
- Prefer local mailbox data over browser access.
- On this Mac mini, prefer Apple Mail first when it is configured and readable.
- Use the Outlook browser-session helper only as fallback.
- Do not expose OAuth tokens.
- Summarize mail carefully; quote only short snippets when needed.

## Default workflow

1. Try Apple Mail local access:

```bash
~/.hermes/scripts/mit-email-applemail.py mailboxes
~/.hermes/scripts/mit-email-applemail.py list --limit 10
```

2. If Apple Mail direct SQLite access is blocked with an error like `sqlite3.DatabaseError: authorization denied`, use the updated helper anyway — it automatically falls back to read-only AppleScript queries against the Mail app:

```bash
~/.hermes/scripts/mit-email-applemail.py mailboxes
~/.hermes/scripts/mit-email-applemail.py list --limit 10
```

3. If Mail AppleScript calls begin failing with `AppleEvent timed out (-1712)`, relaunch Mail and retry:

```bash
pkill -x Mail || true
open -a Mail
~/.hermes/scripts/mit-email-applemail.py list --limit 10
```

4. Only if Apple Mail access fails at both the SQLite and AppleScript layers, fall back to the Outlook browser-session helper:

```bash
~/.hermes/scripts/mit-email-browser.py list --limit 3
```

## Notes

- Raw IMAP/SMTP support exists in Hermes, but Microsoft 365 commonly requires Modern Auth/OAuth2. Avoid storing MIT account passwords for mailbox access.
- `~/.hermes/scripts/mit-email-applemail.py` reads Apple Mail's local `Envelope Index` SQLite database. On macOS, this may fail with `authorization denied` if the current session lacks the required Mail/Full Disk Access permissions.
- The Apple Mail helper now has a practical read-only fallback path through AppleScript when direct SQLite access is blocked.
- Apple Mail is the intended primary path for this user's MIT mailbox on this Mac mini.
- Thunderbird and Microsoft Graph are intentionally omitted from the normal workflow for this user.
