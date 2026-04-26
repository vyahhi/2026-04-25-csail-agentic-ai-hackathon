# 2026-04-25-csail-agentic-ai-hackathon

Hermes deployment and operations repo for the remote MIT-focused Mac mini assistant.

This repo manages the Hermes setup only. It does not manage any separate remote OpenClaw installation.

## Repo Layout

```text
scripts/  deployment and configuration entrypoints
hermes/   files synced into ~/.hermes on the Mac mini
docs/     setup, integration, and operations detail
```

## Verified Target

```text
Tailscale DNS: nicolaws-mac-mini.tail3b0ac2.ts.net
SSH user: nicolaw
Hermes: v0.11.0
Provider: openai-codex
Default model: gpt-5.4
```

## Quick Start

```bash
cp .env.example .env
chmod 600 .env
```

Then run, in order:

```bash
scripts/install-mac-mini-deps.sh
scripts/deploy-hermes-mac-mini.sh
scripts/configure-hermes-openai-codex.sh
scripts/configure-hermes-telegram.sh
scripts/configure-hermes-canvas.sh
scripts/configure-hermes-mit-printers.sh
scripts/configure-mit-vpn-globalprotect.sh
scripts/configure-hermes-browser-cdp.sh
scripts/configure-hermes-integrations.sh
scripts/configure-hermes-cron.sh
scripts/configure-hermes-alerts.sh
```

## Common Commands

Telegram:

- queue by default while busy
- interrupt command: `/stop`
- MIT health command: `/mitstatus`

Remote checks:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.local/bin/hermes doctor'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-status.py --summary'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.local/bin/hermes cron list'
```

## Docs

- [Setup](docs/setup.md)
- [Integrations](docs/integrations.md)
- [Operations](docs/operations.md)

## Notes

- Local `.env` is intentionally untracked.
- Secrets stay out of git.
- Keep Markdown prompts, skills, and helper payloads under `hermes/`.
- Keep orchestration in `scripts/`.
