# 2026-04-25-csail-agentic-ai-hackathon
https://www.csail.mit.edu/event/agentic-ai-hackathon

## Mac Mini Hermes Runbook

This repo contains scripts to provision Hermes Agent on the remote Mac mini over
Tailscale SSH. Connection settings live in local `.env`, which is intentionally
not tracked by git. Use `.env.example` as the template.

Current verified target:

```text
Tailscale DNS: nicolaws-mac-mini.tail3b0ac2.ts.net
SSH user: nicolaw
Hermes: v0.11.0
Model provider: openai-codex
Default model: gpt-5.5
```

### First-Time Setup

```bash
cp .env.example .env
chmod 600 .env
# edit .env with the real Tailscale host, SSH user, and password
```

Install system dependencies on the Mac mini:

```bash
scripts/install-mac-mini-deps.sh
```

This installs Homebrew if missing, then installs `ripgrep` and `ffmpeg`.

Install or update Hermes Agent:

```bash
scripts/deploy-hermes-mac-mini.sh
```

The deploy script runs the official Hermes installer with `--skip-setup` and
verifies the remote `hermes` command with `hermes doctor`.

Configure Hermes to use local ChatGPT/Codex OAuth credentials:

```bash
scripts/configure-hermes-openai-codex.sh
```

This installs the Codex CLI cask if needed, copies local `~/.codex/auth.json` to
the Mac mini, imports OpenAI Codex OAuth into Hermes, and updates
`~/.hermes/config.yaml` to use `openai-codex` with `gpt-5.5`.

If Hermes asks for device login, open the shown OpenAI URL locally and enter the
displayed code.

### Verify

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  'export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; hermes doctor'
```

Expected important checks:

```text
OpenAI Codex auth: logged in
codex CLI: installed
ripgrep (rg): installed
Default model in ~/.hermes/config.yaml: gpt-5.5
Provider in ~/.hermes/config.yaml: openai-codex
```

### Start Hermes

Interactive CLI:

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  'export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; hermes'
```

Gateway setup for messaging integrations:

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  'export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; hermes gateway setup'
```

### Notes

The MagicDNS hostname is reachable only from devices authorized in the Tailscale
tailnet. It is not a public DNS name.

The local `.env` contains SSH credentials and must stay untracked.
