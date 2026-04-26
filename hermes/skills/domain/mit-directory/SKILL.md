---
name: mit-directory
description: Query the MIT people directory from the Mac mini. Prefer public LDAP over the directory website when doing name lookups.
---

# MIT Directory

Use this when the user asks for MIT people lookups, email addresses, usernames, or directory-style searches.

## Key finding

On this Mac mini, `https://directory.mit.edu/` and `directory.mit.edu` may hang or time out even when MIT VPN is up. Do **not** rely on the website as the primary path for simple lookups.

The reliable path is the public MIT LDAP server:

```bash
ldapsearch -x -H ldap://ldap.mit.edu
```

## Default workflow

1. Check the public LDAP root if needed:

```bash
ldapsearch -x -H ldap://ldap.mit.edu -s base -b '' namingContexts
```

Expected naming context includes:

```text
dc=mit, dc=edu
```

2. Search the MIT directory through LDAP instead of the web UI.

### Exact / broad name lookup

```bash
ldapsearch -x -LLL -H ldap://ldap.mit.edu -b 'dc=mit,dc=edu' \
  '(|(cn=FirstName*)(displayName=FirstName*)(givenName=FirstName*))' \
  cn displayName givenName sn mail uid
```

### Exact username lookup

```bash
ldapsearch -x -LLL -H ldap://ldap.mit.edu -b 'dc=mit,dc=edu' \
  '(uid=zuber)' cn displayName mail uid
```

### Exact email lookup

```bash
ldapsearch -x -LLL -H ldap://ldap.mit.edu -b 'dc=mit,dc=edu' \
  '(mail=mtz@mit.edu)' cn displayName mail uid
```

## Notes

- Some entries expose a name but no public email.
- Results can include people whose given name merely starts with the query string unless you filter more tightly in post-processing.
- For a user request like "list all FirstName", prefer post-processing to keep only names beginning with `FirstName`, and exclude `LongerFirstName*`, `LongerFirstNamea*`, `LongerFirstName*`, etc. unless the user asked for prefix matches.
- `directory.mit.edu` itself may time out on ports 80 and 443 from this machine; that is not proof the MIT directory is unavailable, only that the website path is unreliable here.

## Response style

- State that the data came from the MIT public LDAP directory.
- If listing many matches, give name + public email when present.
- Call out entries that have no public email instead of inventing one.
