#!/usr/bin/env python3
import argparse
import json
import os
import subprocess


RECORD_SEP = chr(30)
FIELD_SEP = chr(31)


def preferred_email():
    return (os.environ.get("MIT_EMAIL_ADDRESS") or "").strip().lower()


def run_osascript(script):
    wrapped = f"with timeout of 300 seconds\n{script}\nend timeout"
    proc = subprocess.run(["osascript", "-e", wrapped], capture_output=True, text=True)
    if proc.returncode != 0:
        msg = (proc.stderr or proc.stdout or "AppleScript failed").strip()
        raise RuntimeError(msg)
    return proc.stdout.rstrip("\n")


def parse_delimited(text, field_names):
    if not text:
        return []
    rows = []
    for rec in text.split(RECORD_SEP):
        if not rec:
            continue
        parts = rec.split(FIELD_SEP)
        row = {}
        for i, name in enumerate(field_names):
            row[name] = parts[i] if i < len(parts) else ""
        rows.append(row)
    return rows


def select_preferred_account(accounts):
    if not accounts:
        raise SystemExit("No enabled Apple Mail account found.")
    preferred = preferred_email()
    if preferred:
        for acct in accounts:
            hay = " ".join(str(acct.get(k, "")) for k in ("name", "user_name", "email_addresses")).lower()
            if preferred in hay:
                return acct
    return accounts[0]


def mail_accounts():
    script = f'''
set oldTIDs to AppleScript's text item delimiters
set AppleScript's text item delimiters to "{FIELD_SEP}"
tell application "Mail"
    set recs to {{}}
    repeat with acct in every account
        if enabled of acct is true then
            set emailsText to (email addresses of acct) as string
            set end of recs to ((name of acct as string) & "{FIELD_SEP}" & (user name of acct as string) & "{FIELD_SEP}" & emailsText)
        end if
    end repeat
end tell
set AppleScript's text item delimiters to "{RECORD_SEP}"
set outText to recs as string
set AppleScript's text item delimiters to oldTIDs
return outText
'''
    return parse_delimited(run_osascript(script), ["name", "user_name", "email_addresses"])


def apple_mailboxes(account_name):
    script = f'''
set oldTIDs to AppleScript's text item delimiters
set AppleScript's text item delimiters to "{FIELD_SEP}"
tell application "Mail"
    set recs to {{}}
    set idx to 0
    repeat with mb in every mailbox of account "{account_name}"
        set idx to idx + 1
        set end of recs to ((idx as string) & "{FIELD_SEP}" & (name of mb as string) & "{FIELD_SEP}" & (count of messages of mb as string) & "{FIELD_SEP}" & (unread count of mb as string))
    end repeat
end tell
set AppleScript's text item delimiters to "{RECORD_SEP}"
set outText to recs as string
set AppleScript's text item delimiters to oldTIDs
return outText
'''
    rows = parse_delimited(run_osascript(script), ["rowid", "name", "total_count", "unread_count"])
    for row in rows:
        row["rowid"] = int(row["rowid"])
        row["total_count"] = int(row["total_count"])
        row["unread_count"] = int(row["unread_count"])
        row["source"] = "applescript"
        row["url"] = f'mailbox://{account_name}/{row["name"]}'
        row["account_name"] = account_name
    return rows


def apple_messages(account_name, mailbox_name, limit):
    script = f'''
set oldTIDs to AppleScript's text item delimiters
set AppleScript's text item delimiters to "{FIELD_SEP}"
tell application "Mail"
    set targetMailbox to mailbox "{mailbox_name}" of account "{account_name}"
    set msgCount to count of messages of targetMailbox
    if msgCount is 0 then
        return ""
    end if
    set maxCount to {limit}
    if msgCount < maxCount then set maxCount to msgCount
    set recs to {{}}
    repeat with i from 1 to maxCount
        set m to message i of targetMailbox
        set msgContent to content of m as string
        if (length of msgContent) > 280 then
            set msgContent to (text 1 thru 280 of msgContent)
        end if
        set end of recs to ((id of m as string) & "{FIELD_SEP}" & (sender of m as string) & "{FIELD_SEP}" & (subject of m as string) & "{FIELD_SEP}" & (date received of m as string) & "{FIELD_SEP}" & (read status of m as string) & "{FIELD_SEP}" & (flagged status of m as string) & "{FIELD_SEP}" & msgContent)
    end repeat
end tell
set AppleScript's text item delimiters to "{RECORD_SEP}"
set outText to recs as string
set AppleScript's text item delimiters to oldTIDs
return outText
'''
    rows = parse_delimited(run_osascript(script), ["rowid", "sender", "subject", "received_local", "is_read", "flagged", "snippet"])
    for row in rows:
        row["rowid"] = int(row["rowid"])
        row["mailbox_url"] = f"mailbox://{account_name}/{mailbox_name}"
        row["is_read"] = str(row["is_read"]).lower() == "true"
        row["flagged"] = str(row["flagged"]).lower() == "true"
        row["snippet"] = " ".join((row.get("snippet") or "").split())
    return rows


def list_mailboxes_applescript():
    account = select_preferred_account(mail_accounts())
    return {"backend": "applescript", "account": account, "mailboxes": apple_mailboxes(account["name"])}


def list_messages_applescript(args):
    account = select_preferred_account(mail_accounts())
    mailboxes = apple_mailboxes(account["name"])
    target = None
    if args.mailbox_rowid:
        for mb in mailboxes:
            if mb["rowid"] == args.mailbox_rowid:
                target = mb
                break
    elif args.mailbox_filter:
        flt = args.mailbox_filter.lower()
        for mb in mailboxes:
            if flt in mb["name"].lower() or flt in mb["url"].lower():
                target = mb
                break
    else:
        for mb in mailboxes:
            if mb["name"].lower() == "inbox":
                target = mb
                break

    if not target:
        raise SystemExit("No Inbox mailbox found in Apple Mail account.")

    results = apple_messages(account["name"], target["name"], args.limit)
    for row in results:
        row["mailbox_rowid"] = target["rowid"]
    return {"backend": "applescript", "account": account, "messages": results}


def list_mailboxes(args):
    result = list_mailboxes_applescript()
    print(json.dumps(result, indent=2, ensure_ascii=False))


def list_messages(args):
    result = list_messages_applescript(args)
    print(json.dumps(result, indent=2, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description="Read Apple Mail in read-only mode for MIT mailbox access without a browser.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("mailboxes")
    p.set_defaults(func=list_mailboxes)

    p = sub.add_parser("list")
    p.add_argument("--limit", type=int, default=10)
    p.add_argument("--mailbox-filter")
    p.add_argument("--mailbox-rowid", type=int)
    p.set_defaults(func=list_messages)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
