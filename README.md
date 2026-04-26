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
- quick MIT health command: `/mitstatus`

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
and returns only sources it could fetch live. With MIT VPN connected, Hermes
can reach direct IPP printer endpoints such as:

```text
ipp://stata-p.mit.edu/printers/stata-p
ipp://stata-color.mit.edu/printers/stata-color
```

That browserless path was verified from the Mac mini over VPN with successful
`Print-Job` submissions, but MIT’s public Pharos docs emphasize the Pharos
queue/client and MobilePrint flows rather than specific-printer IPP accounting.
So Hermes now treats direct IPP as an explicit advanced option only. The normal
default path is:

1. a configured local `lp`/Pharos queue, if present
2. Athena Print Center/MobilePrint at `https://print.mit.edu`

I still did not find a documented stable public API for remote MobilePrint
submission/release, so Hermes keeps a browser-backed helper for that path. The
shell wrapper falls back to instruction-only output only if both the documented
queue path and the browser-backed path are unavailable.

Configure MIT VPN / GlobalProtect:

```bash
scripts/configure-mit-vpn-globalprotect.sh
```

MIT's VPN uses Prisma Access GlobalProtect with portal `gpvpn.mit.edu`. The
script installs or updates the Hermes VPN skill/helper on the Mac mini, checks
the current app/CLI state, and opens the portal on the Mac mini desktop. The
actual MIT Kerberos login and Duo approval remain interactive, but the rest of
the workflow can be driven from Hermes or SSH:

```text
hermes/skills/domain/mit-vpn-globalprotect/SKILL.md
hermes/scripts/mit-vpn-globalprotect.sh
```

Current verified behavior on the audited Mac mini:

- GlobalProtect is installed and can connect successfully to `gpvpn.mit.edu`
- MIT-only resources load once connected:
  - `https://kb.mit.edu`
  - `https://print.mit.edu`
  - `https://canvas.mit.edu` (redirects to `https://web.mit.edu/canvas/`)
- ordinary internet still works while VPN is up
- Tailscale remained connected during testing
- the observed routing looks like split/selective routing rather than a full tunnel

Typical setup and verification flow:

1. Run the installer/bootstrap:

```bash
scripts/configure-mit-vpn-globalprotect.sh
```

2. On the Mac mini desktop, complete the GlobalProtect / MIT login / Duo flow.

3. Verify from SSH or Hermes:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-vpn-globalprotect.sh status'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-vpn-globalprotect.sh test'
```

4. If the GUI app is already running and the CLI says an old instance exists,
use the existing GlobalProtect app window on the Mac mini desktop instead of
starting more CLI instances.

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
hermes/skills/domain/mit-email/SKILL.md
hermes/skills/domain/mit-status/SKILL.md
hermes/skills/domain/piazza/SKILL.md
hermes/scripts/mit-email-applemail.py
hermes/scripts/mit-email-browser.py
hermes/scripts/mit-status.py
hermes/scripts/piazza.py
```

Supported now on this Mac mini:

1. Apple Mail via the local helper, with Mail.app configured on the Mac mini.
2. Saved Outlook browser session as a fallback.

Plain IMAP password auth is not reliable against MIT Microsoft 365 and should not be the default Hermes path.

The repo also installs a customized `himalaya` skill that keeps generic IMAP/SMTP usage available for non-MIT accounts while explicitly routing MIT mailbox work to `mit-email` first.

Apple Mail is the current preferred non-browser path on the audited Mac mini because
the MIT mailbox is already present there and `mit-email-applemail.py` can read it.

The live remote `mit-email` skill allows explicit state-changing MIT email actions
when the user asks for them. The default remains read-only. When Hermes composes
or saves an outbound MIT email message, append:

```text
Sent by Nikolay's AI agent
```

Apple Mail setup and verification:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-applemail.py mailboxes'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-email-applemail.py list --limit 3'
```

If Mail.app is not configured with the MIT Microsoft 365 account yet, the helper exits cleanly and tells Hermes to configure Mail first.

On this Mac mini, treat Apple Mail access as the Mail-app-backed helper path.
The supported live path is the Mail app itself.

The repo also installs a unified MIT assistant health helper:

```bash
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.hermes/scripts/mit-status.py'
```

That snapshot checks VPN reachability, persistent browser state, gateway status,
Telegram queue mode, Canvas API reachability, MIT email via Apple Mail and
browser fallback, and Piazza visibility. If the persistent Chrome CDP process is
down, the helper attempts to restart it before reporting the final state.

Not deployed by default:

- `hermes/scripts/mit-email-thunderbird.py`
- `hermes/scripts/mit-email-graph.py`
- `scripts/install-thunderbird-on-mac-mini.sh`

Those remain in the repo only as optional experiments/future paths. They are not
part of the supported active MIT email setup on this Mac mini and are not
installed by `scripts/configure-hermes-integrations.sh`.

Piazza uses the unofficial `piazza-api` package. The helper supports account-wide
course discovery first, and the current remote skill also allows explicit
state-changing Piazza actions when the user asks for them:

```text
PIAZZA_EMAIL=...
PIAZZA_PASSWORD=...
```

There is no repo-level `PIAZZA_NETWORK_ID` anymore. The helper discovers visible
courses dynamically and prefers the last active course or the only visible
course in the account. Use `classes` first when the account can see more than
one course, or pass `--network-id` explicitly for one-off targeting.

Some Piazza classes use SSO, MFA, or captcha flows that the unofficial API may
not support. In that case, use browser-provided export/session data instead of
storing account passwords.

Configure the daily MIT briefing cron:

```bash
scripts/configure-hermes-cron.sh
```

Default behavior:

- job name: `mit-daily-briefing`
- schedule: `0 8 * * *`
- delivery target: `telegram`

Optional `.env` overrides:

```text
HERMES_MIT_BRIEFING_NAME=mit-daily-briefing
HERMES_MIT_BRIEFING_SCHEDULE=0 8 * * *
HERMES_MIT_BRIEFING_DELIVER=telegram
# Optional remote absolute path on the Mac mini if you want repo context.
HERMES_MIT_BRIEFING_WORKDIR=
```

The cron job uses:

- `mit-email`
- `piazza`
- `mit-status`
- `mit-canvas-course`

It replaces any existing remote cron job with the same configured name, then
creates the new one and prints the current cron list.

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

Cron jobs:

```bash
set -a; source .env; set +a
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.local/bin/hermes cron list'
ssh "$MAC_MINI_SSH_USER@$MAC_MINI_TAILSCALE_DNS" \
  '~/.local/bin/hermes cron status'
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
