# Operations

## MIT Status

Unified health helper:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-status.py'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-status.py --summary'
```

Checks:

- VPN
- persistent Chrome CDP
- gateway
- Telegram config
- Canvas
- MIT email
- Piazza

## Gateway

Install and start:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  'export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; hermes gateway install && hermes gateway start && hermes gateway status'
```

## Cron

Configure the daily MIT briefing:

```bash
scripts/configure-hermes-cron.sh
```

Current default job:

```text
name: mit-daily-briefing
schedule: 0 8 * * *
delivery: telegram
```

Optional `.env` overrides:

```text
HERMES_MIT_BRIEFING_NAME=mit-daily-briefing
HERMES_MIT_BRIEFING_SCHEDULE=0 8 * * *
HERMES_MIT_BRIEFING_DELIVER=telegram
HERMES_MIT_BRIEFING_WORKDIR=
```

Cron checks:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.local/bin/hermes cron status'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.local/bin/hermes cron list'
```

## Common Remote Commands

Doctor:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  'export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; hermes doctor'
```

Interactive Hermes:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  'export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; hermes'
```

Canvas snapshot:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/canvas-course-snapshot.sh'
```

Printer lookup:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-printer-find.py "building 10"'
```

## Notes

- MagicDNS hostnames are only reachable from devices in the Tailscale tailnet.
- Local `.env` stays untracked.
- Secrets do not get committed.
