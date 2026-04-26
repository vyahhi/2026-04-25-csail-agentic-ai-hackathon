# Setup

## First-Time Local Setup

```bash
cp .env.example .env
chmod 600 .env
```

Edit `.env` with at least:

```text
MAC_MINI_TAILSCALE_DNS=...
MAC_MINI_SSH_USER=...
MAC_MINI_SSH_PASSWORD=...
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USERS=...
TELEGRAM_HOME_CHANNEL=...
CANVAS_API_TOKEN=...
PIAZZA_EMAIL=...
PIAZZA_PASSWORD=...
```

`TELEGRAM_ALLOWED_USERS` and `TELEGRAM_HOME_CHANNEL` must be numeric Telegram IDs.

## Base Provisioning

Run:

```bash
scripts/install-mac-mini-deps.sh
scripts/deploy-hermes-mac-mini.sh
scripts/configure-hermes-openai-codex.sh
scripts/configure-hermes-telegram.sh
```

What that gives you:

- Homebrew, `rg`, and other base dependencies
- Hermes installed on the Mac mini
- Codex/OpenAI auth imported into Hermes
- Telegram wired to the gateway

## Persona and Synced Hermes Files

`scripts/deploy-hermes-mac-mini.sh` syncs:

```text
hermes/SOUL.md
hermes/memories/MEMORY.md
hermes/memories/USER.md
```

These define the MIT personal assistant persona and durable operating notes.

## Verified Remote State

As last audited:

```text
macOS: 26.3 (build 25D125)
Homebrew: /opt/homebrew/bin/brew
Hermes CLI: ~/.local/bin/hermes
Codex CLI: /opt/homebrew/bin/codex
ripgrep: /opt/homebrew/bin/rg
```

## Verify

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  'export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; hermes doctor'
```

Expected important checks:

```text
OpenAI Codex auth: logged in
codex CLI: installed
ripgrep (rg): installed
Default model: gpt-5.4
Provider: openai-codex
```
