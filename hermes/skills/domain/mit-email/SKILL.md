---
name: mit-email
description: Access the user's MIT Microsoft 365 mailbox on this Mac mini. Prefer Apple Mail locally; use the persistent Outlook browser session as fallback. Read and write actions are allowed when the user explicitly requests them.
---

# MIT Email

MIT email is Microsoft 365/Outlook.

## Rules

- Prefer local mailbox access over browser access.
- On this Mac mini, prefer Apple Mail first when it is configured and readable.
- Use the Outlook browser-session helper only as fallback.
- Do not expose OAuth tokens, passwords, or private account data.
- Default to read-only behavior unless the user explicitly asks for a state-changing action.
- When the user explicitly asks to send, reply, forward, draft, move, archive, delete, or otherwise modify mailbox state, those write actions are allowed.
- Summarize mail carefully; quote only short snippets when needed.
- For any outbound email or saved draft created by the agent, append the footer: `Sent by Nikolay's AI agent`.

## Default workflow

1. Try Apple Mail local access:

```bash
~/.hermes/scripts/mit-email-applemail.py mailboxes
~/.hermes/scripts/mit-email-applemail.py list --limit 10
```

2. If Apple Mail direct SQLite access fails for any local reason such as `authorization denied`, `unable to open database file`, or Mail database version drift, use the same helper anyway — it automatically falls back to read-only AppleScript queries against the Mail app:

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

4. If the user requested a write action and the local helper does not support it directly, use AppleScript against Mail or the persistent Outlook browser session, depending on which path is available and authenticated.

5. Only if Apple Mail access fails at both the SQLite and AppleScript layers, fall back to the Outlook browser-session helper:

```bash
~/.hermes/scripts/mit-email-browser.py list --limit 3
```

## Notes

- Raw IMAP/SMTP support exists in Hermes, but Microsoft 365 commonly requires Modern Auth/OAuth2. Avoid storing MIT account passwords for mailbox access.
- `~/.hermes/scripts/mit-email-applemail.py` reads Apple Mail's local `Envelope Index` SQLite database. On macOS, this may fail with `authorization denied` if the current session lacks the required Mail/Full Disk Access permissions.
- The Apple Mail helper currently provides the primary practical read path, with AppleScript as the fallback under the same helper.
- Apple Mail is the intended primary path for this user's MIT mailbox on this Mac mini.
