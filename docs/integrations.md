# Integrations

## Telegram

Configure:

```bash
scripts/configure-hermes-telegram.sh
```

Behavior:

- busy messages queue by default
- interrupt command: `/stop`
- MIT health command: `/mitstatus`

## Canvas

Configure:

```bash
scripts/configure-hermes-canvas.sh
```

Required env:

```text
CANVAS_BASE_URL=https://canvas.mit.edu
CANVAS_API_TOKEN=...
```

Current design:

- dynamic course discovery
- view-only
- no pinned course ID or URL

Helper:

```bash
~/.hermes/scripts/canvas-course-snapshot.sh
```

## MIT Printers

Configure:

```bash
scripts/configure-hermes-mit-printers.sh
```

Installed pieces:

```text
hermes/skills/domain/mit-printers/SKILL.md
hermes/scripts/mit-printer-find.py
hermes/scripts/mit-print-file.sh
hermes/scripts/mit-print-browser.py
```

Current printing policy:

1. configured local `lp` / Pharos queue, if present
2. MIT MobilePrint at `https://print.mit.edu`
3. direct IPP only as an explicit advanced option

Important:

- public MIT printer lookup is dynamic
- CSAIL-private printers are excluded by default
- the documented quota-linked path is MobilePrint or Pharos queue/client

## MIT VPN

Configure:

```bash
scripts/configure-mit-vpn-globalprotect.sh
```

Portal:

```text
gpvpn.mit.edu
```

Current verified behavior:

- GlobalProtect installed
- MIT-only resources reachable when connected
- ordinary internet still works
- Tailscale remained connected during testing

Helpful commands:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-vpn-globalprotect.sh status'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-vpn-globalprotect.sh test'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-vpn-globalprotect.sh test-kb'
```

## Persistent Browser / MIT SSO

Configure:

```bash
scripts/configure-hermes-browser-cdp.sh
```

Helper:

```bash
~/.hermes/scripts/persistent-browser-cdp.sh
```

Purpose:

- reuse one Chrome profile for MIT SSO-backed browser tasks
- reduce repeated Touchstone / Duo prompts

Commands:

```bash
~/.hermes/scripts/persistent-browser-cdp.sh start
~/.hermes/scripts/persistent-browser-cdp.sh status
~/.hermes/scripts/persistent-browser-cdp.sh stop
```

## MIT Email and Piazza

Configure:

```bash
scripts/configure-hermes-integrations.sh
```

Installed pieces:

```text
hermes/skills/domain/mit-email/SKILL.md
hermes/skills/domain/mit-status/SKILL.md
hermes/skills/domain/piazza/SKILL.md
hermes/scripts/mit-email-applemail.py
hermes/scripts/mit-email-browser.py
hermes/scripts/mit-status.py
hermes/scripts/piazza.py
```

Current supported mail paths:

1. Apple Mail helper
2. Outlook browser-session fallback

Not part of the supported active path:

- raw IMAP password auth

Mail checks:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-applemail.py list --limit 3'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-browser.py list --limit 3'
```

Piazza checks:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py classes'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py list --limit 10'
```
