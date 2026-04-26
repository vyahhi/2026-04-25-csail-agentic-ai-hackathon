---
name: mit-status
description: Check the live health of the Mac mini MIT assistant stack: VPN, Telegram gateway, persistent browser, Canvas, MIT email, and Piazza.
---

# MIT Status

Use this skill when the user asks whether Hermes is working, what is broken, or wants a quick operational snapshot of the MIT assistant setup.

## Default command

```bash
~/.hermes/scripts/mit-status.py
```

## What it checks

- MIT VPN reachability through the KB access test
- persistent Chrome CDP status, with a restart attempt if it is down
- Hermes gateway status
- Telegram configuration and busy input mode
- Canvas API token reachability
- MIT email via Apple Mail helper, including AppleScript fallback when direct SQLite access fails
- MIT email via saved Outlook browser session
- Piazza course visibility

## Response style

- Lead with broken or degraded components first.
- Then list healthy components briefly.
- If one mail path fails but another works, say that clearly instead of calling email fully broken.
- If VPN is down, mention that MIT-only browser flows may fail even if cached sessions still work.
