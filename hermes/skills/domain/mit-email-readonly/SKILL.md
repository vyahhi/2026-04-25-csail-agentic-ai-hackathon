---
name: mit-email-readonly
description: Read-only access guidance for the user's MIT Microsoft 365 mailbox via Apple Mail, Microsoft Graph Mail.Read, or a saved Outlook session. Use when the user asks to inspect, search, summarize, or read MIT email.
---

# MIT Email Read-Only

MIT email is Microsoft 365/Outlook. Prefer Apple Mail local access when the mailbox is configured on the Mac. Otherwise prefer Microsoft Graph with delegated `Mail.Read` over IMAP password auth.

## Rules

- Read-only by default. Do not send, reply, forward, delete, archive, move, mark read/unread, or create rules.
- Use Apple Mail local access when the mailbox is configured on the Mac.
- Otherwise use Microsoft Graph `Mail.Read` helper when configured.
- If neither Apple Mail nor Graph is available, use the Outlook browser-session helper before telling the user email is unavailable.
- Do not expose OAuth tokens.
- Summarize mail content carefully; quote only short snippets when needed.
- Only ask the user to run Graph device-code login if both Graph and the persistent Outlook session are unavailable.

## Helper

```bash
~/.hermes/scripts/mit-email-applemail.py mailboxes
~/.hermes/scripts/mit-email-applemail.py list --limit 10
~/.hermes/scripts/mit-email-graph.py login
~/.hermes/scripts/mit-email-graph.py me
~/.hermes/scripts/mit-email-graph.py folders
~/.hermes/scripts/mit-email-graph.py list --limit 10
~/.hermes/scripts/mit-email-graph.py list --search "canvas" --limit 10
~/.hermes/scripts/mit-email-graph.py read MESSAGE_ID
~/.hermes/scripts/mit-email-browser.py list --limit 3
```

Required env:

```text
MS_GRAPH_CLIENT_ID=...
MS_GRAPH_TENANT=organizations
MS_GRAPH_SCOPES=offline_access User.Read Mail.Read
```

The Graph helper saves tokens to `~/.hermes/auth/ms-graph-token.json`.

## Notes

Raw IMAP/SMTP support exists in Hermes, but Microsoft 365 commonly requires Modern Auth/OAuth2. Avoid storing MIT account passwords for mailbox access.

If Apple Mail is configured on the Mac mini with the MIT Microsoft 365 account, use:

```bash
~/.hermes/scripts/mit-email-applemail.py list --limit 3
```

That is the preferred non-browser path because it reads the local Apple Mail index instead of depending on a live browser session.

If Microsoft Graph is not configured but the persistent Hermes Chrome profile is already authenticated to Outlook Web, use:

```bash
~/.hermes/scripts/mit-email-browser.py list --limit 3
```

That path is still read-only, but it depends on the saved Outlook browser session rather than native Graph OAuth.
