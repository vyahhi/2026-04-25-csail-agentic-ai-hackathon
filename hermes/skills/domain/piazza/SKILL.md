---
name: piazza
description: Read-only Piazza access through the unofficial piazza-api package. Use when the user asks to inspect, search, list, or summarize Piazza posts.
---

# Piazza

Piazza has no official public API for this use case. This skill uses the unofficial `piazza-api` Python package and remains read-only in this repo.

## Rules

- Read-only only. Do not create posts, edit posts, answer, endorse, follow up, enroll users, or modify folders/tags.
- Do not expose Piazza credentials.
- If login fails because of SSO/MFA/captcha, ask the user to use browser export or provide a supported session/auth method.
- Use small limits first; Piazza has informal rate limits.
- Start with course discovery instead of assuming a single fixed class.

## Helper

```bash
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py profile
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py classes
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py list --limit 20
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py read POST_ID
```

If more than one course is available, use `classes` first and then pass `--network-id` to `list` or `read` when needed.

Required env:

```text
PIAZZA_EMAIL=...
PIAZZA_PASSWORD=...
```

Optional env:

```text
PIAZZA_NETWORK_ID=...
```

Install dependency:

```bash
~/.hermes/hermes-agent/venv/bin/python -m pip install piazza-api
```

`PIAZZA_NETWORK_ID` is now optional. If it is unset, the helper prefers the last active Piazza course or the only visible course in the account.
