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

Use this only for quick spot checks, not for a completeness claim.
On this MIT LDAP server, a broad first-name query can under-return even when you add paged-results controls.

### Important: avoid LDAP size-limit traps on broad first-name searches

Broad first-name queries can hit the MIT LDAP server size limit and silently omit valid matches if you only parse the returned entries. Watch for:

```text
result: 4 Size limit exceeded
numEntries: 100
```

When that happens, do **not** trust the result set as complete.

Instead:

1. Say the broad query is incomplete.
2. Narrow the search by surname, uid, or mail when possible.
3. For a request like "do you see FirstName LastName", use exact targeted filters first:

```bash
ldapsearch -x -LLL -H ldap://ldap.mit.edu -b 'dc=mit,dc=edu' \
  '(|(cn=*LastName*)(displayName=*LastName*)(sn=LastName)(mail=*username*)(uid=*username*))' \
  cn displayName givenName sn mail uid

ldapsearch -x -LLL -H ldap://ldap.mit.edu -b 'dc=mit,dc=edu' \
  '(uid=username)' '*' '+'
```

4. For "list all people named FirstName", do **not** rely on one broad query or assume paged-results control fixes it.
5. For a completeness-oriented first-name search, split the query into smaller surname buckets and merge the results. This avoids the LDAP size-limit trap and can find entries missed by the single broad query.

Example strategy:

```bash
for L in {A..Z}; do
  ldapsearch -x -LLL -H ldap://ldap.mit.edu -b 'dc=mit,dc=edu' \
    "(&(|(givenName=FirstName*)(displayName=FirstName*)(cn=FirstName*))(sn=${L}*))" \
    cn displayName givenName sn mail uid
  sleep 0.2
done
```

Then post-process to:
- keep only names / given names beginning with the requested first name
- deduplicate by `(name, mail, uid)`
- report entries with missing public email as name-only

### Exact username lookup

```bash
ldapsearch -x -LLL -H ldap://ldap.mit.edu -b 'dc=mit,dc=edu' \
  '(uid=username)' cn displayName mail uid
```

### Exact email lookup

```bash
ldapsearch -x -LLL -H ldap://ldap.mit.edu -b 'dc=mit,dc=edu' \
  '(mail=username@mit.edu)' cn displayName mail uid
```

## Notes

- Some entries expose a name but no public email.
- Results can include people whose given name merely starts with the query string unless you filter more tightly in post-processing.
- For a user request like "list all people named FirstName", prefer post-processing to keep only exact requested first-name matches and exclude longer prefix matches unless the user asked for prefix matches.
- `directory.mit.edu` itself may time out on ports 80 and 443 from this machine; that is not proof the MIT directory is unavailable, only that the website path is unreliable here.
- Some MIT addresses in email headers use subdomain aliases such as `user@csail.mit.edu` or `user@media.mit.edu` while the public LDAP `mail` attribute may only expose `user@mit.edu`. If an exact `(mail=...)` lookup fails for a MIT-looking address, retry by UID using the local part before the `@`.

## Response style

- State that the data came from the MIT public LDAP directory.
- If listing many matches, give name + public email when present.
- Call out entries that have no public email instead of inventing one.
