---
name: piazza
description: Piazza access through the unofficial piazza-api package. Use for inspecting, searching, listing, summarizing, and — when the user explicitly requests it — creating or editing Piazza content.
---

# Piazza

Piazza has no official public API for this use case. This skill uses the unofficial `piazza-api` Python package for both read operations and, when explicitly requested by the user, carefully scoped write operations.

## Rules

- Reading is allowed by default.
- State-changing Piazza actions are allowed only when the user explicitly asks for them or clearly authorizes them in the current task.
- For writes, prefer the smallest scoped action possible: reply instead of edit, edit instead of delete, single course instead of global.
- Before a write, confirm you are targeting the correct course and post.
- Do not expose Piazza credentials.
- If login fails because of SSO/MFA/captcha, ask the user to use browser export or provide a supported session/auth method.
- Use small limits first; Piazza has informal rate limits.
- After any write, verify by re-reading the affected post/feed.

## Helper

For discovery and read operations:

```bash
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py profile
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py classes
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py list --limit 20
~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py read POST_ID
```

Use `classes` first to discover what courses are visible in the current Piazza account. Normal workflow should start from account-wide discovery rather than manually managing internal Piazza identifiers.

For write operations, use the `piazza_api` package directly from the Hermes venv until dedicated helper subcommands are added.

Required env:

```text
PIAZZA_EMAIL=...
PIAZZA_PASSWORD=...
```

Install dependency:

```bash
~/.hermes/hermes-agent/venv/bin/python -m pip install piazza-api
```

The Piazza account may expose one or many courses. Start by discovering visible courses with `classes`, then inspect the relevant course through the helper.

## Common write patterns

Use the `piazza_api.network.Network` methods exposed by the installed package when the user explicitly requests a write. Confirm the target course and post first.

Available state-changing methods include:

- `create_post`
- `create_reply`
- `create_followup`
- `create_instructor_answer`
- `update_post`
- `delete_post`
- `pin_post`
- `resolve_post`
- `mark_as_duplicate`
- `add_feedback` / `remove_feedback`
- `add_students` / `remove_users`

Example: create a reply

```bash
~/.hermes/hermes-agent/venv/bin/python - <<'PY'
from piazza_api import Piazza
import os, shlex
from pathlib import Path

path = Path.home()/'.hermes'/'.env'
for line in path.read_text().splitlines():
    s = line.strip()
    if not s or s.startswith('#') or '=' not in s:
        continue
    k, v = s.split('=', 1)
    if k not in os.environ:
        try:
            parts = shlex.split(v, comments=False, posix=True)
            os.environ[k] = parts[0] if parts else ''
        except Exception:
            os.environ[k] = v

p = Piazza()
p.user_login(email=os.environ['PIAZZA_EMAIL'], password=os.environ['PIAZZA_PASSWORD'])
cls = p.network('SELECTED_COURSE_ID')
resp = cls.create_reply('POST_ID', 'Reply text here')
print(resp)
PY
```

Example: create a new post

```bash
~/.hermes/hermes-agent/venv/bin/python - <<'PY'
from piazza_api import Piazza
import os, shlex
from pathlib import Path

path = Path.home()/'.hermes'/'.env'
for line in path.read_text().splitlines():
    s = line.strip()
    if not s or s.startswith('#') or '=' not in s:
        continue
    k, v = s.split('=', 1)
    if k not in os.environ:
        try:
            parts = shlex.split(v, comments=False, posix=True)
            os.environ[k] = parts[0] if parts else ''
        except Exception:
            os.environ[k] = v

p = Piazza()
p.user_login(email=os.environ['PIAZZA_EMAIL'], password=os.environ['PIAZZA_PASSWORD'])
cls = p.network('SELECTED_COURSE_ID')
resp = cls.create_post(
    'Question title here',
    'Post body here',
    folders=['logistics'],
    type='question'
)
print(resp)
PY
```

Always re-read the affected feed/post after a write to verify the exact result.

## Troubleshooting course mismatches

If Canvas shows a Piazza tab for a course but `piazza.py classes` does not list that course, treat Canvas and Piazza as independently scoped systems. The current Piazza credentials/session may only expose a different class. In that case:

1. Verify visible Piazza courses with `classes` instead of assuming the Canvas course is available.
2. If needed, inspect the Canvas course tabs to confirm a Piazza external tool exists.
3. Do not invent a hidden Piazza course identifier from Canvas metadata alone unless the launch/session data exposes it clearly.
4. Report the mismatch explicitly and ask the user to provide or switch to a Piazza account/session that can see the desired class.
