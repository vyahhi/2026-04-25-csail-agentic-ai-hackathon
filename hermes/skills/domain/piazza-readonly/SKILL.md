---
name: piazza-readonly
description: Read-only Piazza access through the unofficial piazza-api package. Use when the user asks to inspect, search, list, or summarize Piazza posts.
---

# Piazza Read-Only

Piazza has no official public API for this use case. This skill uses the unofficial `piazza-api` Python package and must remain read-only.

## Rules

- Read-only only. Do not create posts, edit posts, answer, endorse, follow up, enroll users, or modify folders/tags.
- Do not expose Piazza credentials.
- If login fails because of SSO/MFA/captcha, ask the user to use browser export or provide a supported session/auth method.
- Use small limits first; Piazza has informal rate limits.

## Helper

```bash
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza-readonly.py profile
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza-readonly.py list --limit 20
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza-readonly.py read POST_ID
```

Required env:

```text
PIAZZA_EMAIL=...
PIAZZA_PASSWORD=...
PIAZZA_NETWORK_ID=...
```

Install dependency:

```bash
~/.hermes/hermes-agent/venv/bin/python -m pip install piazza-api
```

`PIAZZA_NETWORK_ID` is the course/network identifier used by Piazza. The user may need to open the class in the browser and copy the network id from the URL or request metadata.
