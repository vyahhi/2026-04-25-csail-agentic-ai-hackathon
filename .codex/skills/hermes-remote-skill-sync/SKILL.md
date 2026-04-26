---
name: hermes-remote-skill-sync
description: Use when asked to check, sync, audit, or import skill updates from the remote Hermes Mac mini into this repo, especially requests like "check updates in skills on remote hermes mac mini, push them to repo if needed" or "check ALL skills".
---

# Hermes Remote Skill Sync

## Goal

Autonomously check the Mac mini's `~/.hermes/skills` against this repo's `hermes/skills`, bring back useful project-owned skill changes, sanitize private details, then commit and push when the repo changes.

## Primary Command

Run the audit first:

```bash
scripts/audit-remote-hermes-skills.sh --show-diff --keep-snapshot
```

For a one-command autonomous run from a clean shell:

```bash
scripts/audit-remote-hermes-skills.sh --codex-autonomous --codex-model gpt-5.5
```

## Workflow For Codex

1. Run the audit script with `--show-diff --keep-snapshot`.
2. Inspect every repo-owned `DIFF ...` file under `hermes/skills`.
3. Apply only useful remote updates with `apply_patch`; do not blindly copy whole files if the repo has newer/sanitized policy.
4. Treat remote-only hub/bundled skills as inventory, not repo content, unless the user explicitly asks to vendor them.
5. Scan candidate edits before commit:

```bash
scripts/audit-remote-hermes-skills.sh --show-diff
rg -n "Quiz [0-9]+|\\bfor (the|a|an) [^.\\n]{3,80} thread\\b|/Users/[^/[:space:]]+|[0-9]{6,}:AA[A-Za-z0-9_-]{20,}|[0-9]{4}~[A-Za-z0-9_-]{20,}" hermes/skills README.md docs scripts .env.example
```

6. Preserve these repo policies:
   - OpenAI image skill examples use `gpt-5.5`, not stale remote `gpt-5.4`.
   - Canvas guidance must be dynamic and generalized; do not commit specific course, quiz, student, or thread facts.
   - MIT email guidance may mention the footer `Sent by Nikolay's AI agent`, but not private mailbox/thread details.
   - Do not commit secrets, tokens, hostnames, raw account identifiers, or local remote user paths.
7. If there are repo changes, run a focused validation, then commit and push:

```bash
git diff -- hermes/skills README.md docs scripts
git status --short
git add <changed-files>
git commit -m "<concise message>"
git push origin main
```

8. If there are no repo-worthy changes, do not commit. Report the intentional differences and that the working tree is clean.

## What Counts As Repo-Worthy

Bring back:
- new operational findings for project-owned MIT, Canvas, Piazza, printer, email, image, PDF, or status skills
- generalized troubleshooting guidance
- stable command patterns that improve future Hermes reliability

Do not bring back:
- Hermes hub/bundled marketplace skills by default
- stale remote defaults that conflict with repo policy
- private examples from course operations, email threads, accounts, local paths, or tokens
