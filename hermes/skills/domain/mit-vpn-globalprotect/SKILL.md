---
name: mit-vpn-globalprotect
description: Manage the Mac mini's MIT GlobalProtect VPN setup and connection workflow. Use when the user asks to connect the Mac mini to MITnet, open GlobalProtect, test MIT KB access, or prepare VPN for MIT resources.
---

# MIT VPN GlobalProtect

MIT VPN uses Prisma Access GlobalProtect with portal `gpvpn.mit.edu`.

## Rules

- Use `~/.hermes/scripts/mit-vpn-globalprotect.sh` for status, open, connect, and MIT KB tests.
- Login requires interactive MIT Kerberos and Duo approval. Do not claim VPN is connected until status or MIT KB access verifies it.
- Do not print passwords, Kerberos credentials, Duo codes, or session cookies.
- If GlobalProtect is not installed, open `https://gpvpn.mit.edu` on the Mac mini desktop and tell the user to complete installer download/login there.
- If macOS blocks Palo Alto Networks extensions/background items, tell the user to approve them in System Settings.

## Commands

```bash
~/.hermes/scripts/mit-vpn-globalprotect.sh status
~/.hermes/scripts/mit-vpn-globalprotect.sh open-portal
~/.hermes/scripts/mit-vpn-globalprotect.sh open-app
~/.hermes/scripts/mit-vpn-globalprotect.sh connect
~/.hermes/scripts/mit-vpn-globalprotect.sh test-kb
```

## Verification

After the user approves Duo, run:

```bash
~/.hermes/scripts/mit-vpn-globalprotect.sh status
~/.hermes/scripts/mit-vpn-globalprotect.sh test-kb
```

The MIT KB test should not end at `https://ist.mit.edu/accessrestricted`.
