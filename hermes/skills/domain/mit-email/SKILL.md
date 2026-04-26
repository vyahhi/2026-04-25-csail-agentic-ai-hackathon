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

2. On this Mac mini, treat that helper as the Apple Mail path. The supported live behavior is Mail-app-backed access:

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

5. Only if Apple Mail access fails, fall back to the Outlook browser-session helper:

```bash
~/.hermes/scripts/mit-email-browser.py list --limit 3
```

## Notes

- Raw IMAP/SMTP support exists in Hermes, but Microsoft 365 commonly requires Modern Auth/OAuth2. Avoid storing MIT account passwords for mailbox access.
- `~/.hermes/scripts/mit-email-applemail.py` is the Apple Mail helper for this Mac mini and uses the Mail app path directly.
- Apple Mail is the intended primary path for this user's MIT mailbox on this Mac mini.
- When you need a custom Apple Mail query that the helper does not expose, prefer `execute_code` with `subprocess.run(['osascript', '-e', SCRIPT], ...)` instead of a shell heredoc through `terminal()`. AppleScript uses `&` for string concatenation, and Hermes terminal safety may misread that as shell backgrounding.
