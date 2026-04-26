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
- Apple Mail draft editing has important quirks on this Mac mini: reading draft metadata/recipients via AppleScript works, but directly setting `content of m` on an existing draft can fail with `Mail got an error ... (-10006)`. Reliable workaround: inspect the existing draft to capture subject, recipients, and body, then create a fresh draft with the updated body and the same recipients. After creating the replacement draft, verify by re-reading drafts filtered by subject, because duplicate drafts can accumulate.
- Apple Mail also prepends a leading newline when creating a new outgoing message via AppleScript `content:` / `set content of ...`. In tests, drafts consistently began with ASCII 10 before the first visible character, even when the body string itself did not start with a newline. Treat this as a Mail quirk; do not add extra leading blank lines manually, and expect one empty line at the top when composing via this path.
- For replies/forwards, do not fake threading by creating a new message with a `Re:` or `Fwd:` subject. Use Mail's native `reply <message>` or `forward <message>` commands so `In-Reply-To` / thread metadata stays attached and the result groups correctly in both sent and recipient inboxes.
- Important verification rule for outbound mail: after creating or sending any draft/reply, re-read the resulting Drafts/Sent message and confirm the body still contains the intended opening text, any requested notes, and the footer `Sent by Nikolay's AI agent`. Do not assume Apple Mail preserved the composed body.
- Apple Mail reply/attachment automation can silently drop or mangle custom body text. For replies with attachments, or whenever exact content matters, prefer the Outlook browser compose path if Mail verification fails.
- Stronger failure mode discovered on this Mac mini: native Apple Mail `reply ...` messages can save or send with an effectively empty body after AppleScript body rewriting, even without attachments. Treat native reply-body rewriting as unreliable here.
- If a reply or forward must preserve exact wording, especially with attachments or multi-recipient follow-ups, do not send it through Apple Mail body-edit automation. Use the authenticated Outlook browser compose/reply path instead, or stop after drafting and explicitly verify before sending.
- This failure mode appears specific to Apple Mail native reply-body rewriting. A plain new outgoing Apple Mail message with a custom body plus attachment can still preserve the body correctly when verified in Sent Items. For single-recipient or non-threaded outbound mail, Apple Mail `make new outgoing message` remains viable on this Mac mini, but still verify Sent/Drafts afterward.
- If exact visual formatting matters more than local Mail automation quirks, consider the persistent Outlook browser session as a fallback compose path.
- For Drafts mailbox access in AppleScript, `mailbox "Drafts" of (first account whose name is "Exchange")` works more reliably than `drafts mailbox` when you need account-scoped reads.
