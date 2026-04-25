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
Default model: gpt-5.4
```

Current audited remote state as of 2026-04-25:

```text
macOS: 26.3 (build 25D125)
Homebrew: installed at /opt/homebrew/bin/brew
Hermes CLI: /Users/nicolaw/.local/bin/hermes
Codex CLI: /opt/homebrew/bin/codex
ripgrep: /opt/homebrew/bin/rg
Chrome persistent CDP session: configured on localhost:9222
Mail.app: installed and MIT mailbox present in Apple Mail
Thunderbird: installed, profile directory present
Printer queues via lpstat: none configured locally
```

This repo documents and deploys the Hermes-related setup only. It does not manage
or modify any separate remote OpenClaw installation.

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
verifies the remote `hermes` command with `hermes doctor`. It also syncs:

```text
hermes/SOUL.md
hermes/memories/MEMORY.md
hermes/memories/USER.md
```

Those files define the durable MIT-personal-assistant persona and stable
machine-local operating notes for the live Hermes instance.

Configure Hermes to use local ChatGPT/Codex OAuth credentials:

```bash
scripts/configure-hermes-openai-codex.sh
```

This installs the Codex CLI cask if needed, copies local `~/.codex/auth.json` to
the Mac mini, imports OpenAI Codex OAuth into Hermes, and updates
`~/.hermes/config.yaml` to use `openai-codex` with `gpt-5.4`.

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

Telegram busy-session behavior:

- default: new messages are queued while Hermes is busy
- interrupt command: `/stop`

Configure MIT Canvas access:

```bash
scripts/configure-hermes-canvas.sh
```

Default `.env` values:

```text
CANVAS_BASE_URL=https://canvas.mit.edu
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

With `CANVAS_API_TOKEN`, Hermes can discover the user's current courses
dynamically and then inspect whichever course is relevant. Keep this
integration view-only: use `GET` requests only and do not submit or modify
course content.

Configure MIT printer lookup and print-prep helpers:

```bash
scripts/configure-hermes-mit-printers.sh
```

This installs:

```text
hermes/skills/domain/mit-printers/SKILL.md
hermes/scripts/mit-printer-find.py
hermes/scripts/mit-print-browser.py
hermes/scripts/mit-print-file.sh
```

The printer lookup helper fetches MIT KB Pharos printer locations and CSAIL TIG
printer docs live on every query. No local printer dataset is installed or used.
The MIT KB Pharos page may redirect to an access-restricted page from the
off-campus Mac mini; when that happens, the helper reports the source failure
and returns only sources it could fetch live. The Mac mini is not on the local
MIT network, so direct printing with `lp` is attempted only if a local MIT print
queue is configured. Remote Pharos printing uses Athena Print Center/MobilePrint
at `https://print.mit.edu`. Hermes also has a browser-backed helper that can
upload and release jobs through the persistent Chrome session when MIT SSO is
still valid. The shell wrapper falls back to instruction-only output only if the
browser path is not authenticated or the site flow is blocked.

Configure MIT VPN / GlobalProtect:

```bash
scripts/configure-mit-vpn-globalprotect.sh
```

MIT's VPN uses Prisma Access GlobalProtect with portal `gpvpn.mit.edu`. The
script checks whether GlobalProtect is installed on the Mac mini and opens the
portal on the Mac mini desktop. Installation and connection require interactive
MIT Kerberos and Duo approval, so they cannot be completed purely over SSH.
It also installs a Hermes skill and helper so the live agent can repeat VPN
status/open/connect/test actions later:

```text
hermes/skills/domain/mit-vpn-globalprotect/SKILL.md
hermes/scripts/mit-vpn-globalprotect.sh
```

Configure Hermes to reuse a persistent Chrome profile for MIT SSO:

```bash
scripts/configure-hermes-browser-cdp.sh
```

This installs:

```text
hermes/scripts/persistent-browser-cdp.sh
```

and updates `~/.hermes/config.yaml` with:

```text
browser:
  cdp_url: "http://127.0.0.1:9222"
```

Hermes browser tools then connect to a persistent live Chrome instance on the
Mac mini instead of launching a fresh headless profile each time. That lets MIT
Touchstone/Okta/Duo cookies survive across Hermes browser tasks for as long as
the underlying MIT session remains valid.

Useful remote commands:

```bash
~/.hermes/scripts/persistent-browser-cdp.sh start
~/.hermes/scripts/persistent-browser-cdp.sh status
~/.hermes/scripts/persistent-browser-cdp.sh stop
```

Configure MIT email and Piazza helpers:

```bash
scripts/configure-hermes-integrations.sh
```

This installs:

```text
hermes/skills/email/himalaya/SKILL.md
hermes/skills/domain/mit-email-readonly/SKILL.md
hermes/skills/domain/piazza/SKILL.md
hermes/scripts/mit-email-thunderbird.py
hermes/scripts/mit-email-applemail.py
hermes/scripts/mit-email-graph.py
hermes/scripts/mit-email-browser.py
hermes/scripts/piazza.py
```

MIT Microsoft 365 mail now has three paths:

1. Apple Mail local mailbox/index on the Mac mini, if the MIT mailbox is configured in Mail.app.
2. Thunderbird local mailbox files on the Mac mini, if the MIT mailbox is configured in Thunderbird.
3. Microsoft Graph delegated `Mail.Read`, if you provide a public-client app ID.
4. Saved Outlook browser session as a fallback.

Plain IMAP password auth is not reliable against MIT Microsoft 365 and should not be the default Hermes path.

The repo also installs a customized `himalaya` skill that keeps generic IMAP/SMTP usage available for non-MIT accounts while explicitly routing MIT mailbox work to `mit-email-readonly` first.

Apple Mail is the current preferred non-browser path on the audited Mac mini because
the MIT mailbox is already present there and `mit-email-applemail.py` can read it.
Thunderbird is installed and available as a secondary path, but the repo should not
assume it is the primary mailbox source.

Thunderbird install on the Mac mini:

```bash
scripts/install-thunderbird-on-mac-mini.sh
```

Thunderbird local-mail verification:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-thunderbird.py profiles'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-thunderbird.py mailboxes --inbox-only'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-thunderbird.py list --limit 3'
```

Graph setup:

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

Apple Mail setup and verification:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-applemail.py mailboxes'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-applemail.py list --limit 3'
```

If Mail.app is not configured with the MIT Microsoft 365 account yet, the helper exits cleanly and tells Hermes to configure Mail first.

The helper first tries the local Apple Mail SQLite index. If that path is blocked
by macOS permissions, it can fall back to read-only AppleScript queries against
Mail.app.

Piazza uses the unofficial `piazza-api` package. The helper supports account-wide
course discovery first, and the current remote skill also allows explicit
state-changing Piazza actions when the user asks for them:

```text
PIAZZA_EMAIL=...
PIAZZA_PASSWORD=...
```

`PIAZZA_NETWORK_ID` is optional. If it is unset, the helper prefers the last
active course or the only visible course in the account. Use `classes` first
when the account can see more than one course.

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
Default model in ~/.hermes/config.yaml: gpt-5.4
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
  '~/.hermes/scripts/mit-email-applemail.py list --limit 3'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-thunderbird.py list --limit 3'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-graph.py folders'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-browser.py list --limit 3'
```

Piazza helper:

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py classes'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/piazza.py list --limit 10'
```

If Piazza reports `Missing piazza-api`, rerun:

```bash
scripts/configure-hermes-integrations.sh
```

That install step is what provisions the `piazza-api` dependency into the Hermes
venv on the Mac mini.

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
