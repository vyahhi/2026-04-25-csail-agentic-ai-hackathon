# 2026-04-25-csail-agentic-ai-hackathon
https://www.csail.mit.edu/event/agentic-ai-hackathon

## Mac Mini Hermes Runbook

This repo contains scripts to provision Hermes Agent on the remote Mac mini over
Tailscale SSH. Connection settings live in local `.env`, which is intentionally
not tracked by git. Use `.env.example` as the template.

Repo layout:

```text
scripts/   executable deployment/configuration scripts
hermes/    files installed into the remote ~/.hermes tree
```

Keep large Markdown prompts, skills, memory files, and helper payloads under
`hermes/`. Keep `scripts/` focused on orchestration and file transfer.

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

Configure Telegram:

```bash
scripts/configure-hermes-telegram.sh
```

Required `.env` values:

```text
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USERS=152157536
TELEGRAM_HOME_CHANNEL=152157536
```

`TELEGRAM_ALLOWED_USERS` and `TELEGRAM_HOME_CHANNEL` must be numeric Telegram
user or chat IDs, not `@username` handles. Message @userinfobot to find your
numeric user ID, or send `/start` to the bot and inspect Bot API updates.

Configure the MIT Canvas course target:

```bash
scripts/configure-hermes-canvas.sh
```

Default `.env` values:

```text
CANVAS_BASE_URL=https://canvas.mit.edu
CANVAS_COURSE_ID=37338
CANVAS_COURSE_URL=https://canvas.mit.edu/courses/37338
CANVAS_API_TOKEN=
```

The script installs a local Hermes skill named `mit-canvas-course` and a helper:

```bash
~/.hermes/scripts/canvas-course-snapshot.sh
```

Source files live separately from the shell script:

```text
hermes/skills/domain/mit-canvas-course/SKILL.md
hermes/scripts/canvas-course-snapshot.sh
hermes/memories/MEMORY.md
hermes/memories/USER.md
```

Without `CANVAS_API_TOKEN`, Canvas API endpoints return `401`, so Hermes uses
public page reads only. Keep this integration view-only: use `GET` requests
only and do not submit or modify course content.

Configure MIT printer lookup and print-prep helpers:

```bash
scripts/configure-hermes-mit-printers.sh
```

This installs:

```text
hermes/skills/domain/mit-printers/SKILL.md
hermes/data/mit-printers.json
hermes/scripts/mit-printer-find.py
hermes/scripts/mit-print-file.sh
```

The Mac mini is not on the local MIT network. The printer skill therefore
focuses on finding nearby Pharos printers and preparing upload/release guidance.
Direct printing with `lp` is attempted only if a local MIT print queue is
configured; otherwise it points the user to Athena Print Center/MobilePrint at
`https://print.mit.edu`.

Configure read-only MIT email and Piazza helpers:

```bash
scripts/configure-hermes-readonly-integrations.sh
```

This installs:

```text
hermes/skills/domain/mit-email-readonly/SKILL.md
hermes/skills/domain/piazza-readonly/SKILL.md
hermes/scripts/mit-email-graph.py
hermes/scripts/piazza-readonly.py
```

MIT email uses Microsoft Graph delegated `Mail.Read`. Add a public-client
Microsoft app ID to `.env`, then run device-code login on the Mac mini:

```text
MS_GRAPH_CLIENT_ID=...
MS_GRAPH_TENANT=organizations
MS_GRAPH_SCOPES=offline_access User.Read Mail.Read
```

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-graph.py login'
```

Piazza uses the unofficial `piazza-api` package and is configured only for
read-only inspection:

```text
PIAZZA_EMAIL=...
PIAZZA_PASSWORD=...
PIAZZA_NETWORK_ID=...
```

Some Piazza classes use SSO, MFA, or captcha flows that the unofficial API may
not support. In that case, use browser-provided export/session data instead of
storing account passwords.

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

Canvas snapshot:

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/canvas-course-snapshot.sh'
```

Printer lookup:

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-printer-find.py "building 10"'
```

MIT email helper:

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-graph.py folders'
```

Piazza helper:

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza-readonly.py profile'
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

Install/start the Hermes gateway service after Telegram is configured:

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  'export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; hermes gateway install && hermes gateway start && hermes gateway status'
```

### Notes

The MagicDNS hostname is reachable only from devices authorized in the Tailscale
tailnet. It is not a public DNS name.

The local `.env` contains SSH credentials and must stay untracked.
