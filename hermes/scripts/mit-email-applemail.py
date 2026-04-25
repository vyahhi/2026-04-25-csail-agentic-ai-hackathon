#!/usr/bin/env python3
import argparse
import json
import os
import sqlite3
import subprocess
from pathlib import Path


APPLE_EPOCH_OFFSET = 978307200
RECORD_SEP = chr(30)
FIELD_SEP = chr(31)


def preferred_email():
    return (os.environ.get("MIT_EMAIL_ADDRESS") or "").strip().lower()


def db_path():
    return Path.home() / "Library" / "Mail" / "V10" / "MailData" / "Envelope Index"


def connect_db():
    path = db_path()
    if not path.exists():
        raise FileNotFoundError(f"Apple Mail database not found: {path}")
    uri = f"file:{path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    return conn


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


def mailbox_rows_db(conn):
    return conn.execute(
        """
        select rowid, url, total_count, unread_count, source
        from mailboxes
        order by rowid
        """
    ).fetchall()


def default_mailbox_filter_db(rows):
    preferred = []
    for row in rows:
        url = (row["url"] or "").lower()
        if "inbox" in url and not url.startswith("local://"):
            preferred.append(row["rowid"])
    return preferred


def list_mailboxes_db():
    conn = connect_db()
    rows = mailbox_rows_db(conn)
    results = []
    for row in rows:
        results.append({
            "rowid": row["rowid"],
            "url": row["url"],
            "total_count": row["total_count"],
            "unread_count": row["unread_count"],
            "source": row["source"],
        })
    return {"backend": "sqlite", "mailboxes": results}


def list_messages_db(args):
    conn = connect_db()
    rows = mailbox_rows_db(conn)
    mailbox_ids = default_mailbox_filter_db(rows)
    if args.mailbox_rowid:
        mailbox_ids = [args.mailbox_rowid]
    elif args.mailbox_filter:
        mailbox_ids = [row["rowid"] for row in rows if args.mailbox_filter.lower() in (row["url"] or "").lower()]

    if not mailbox_ids:
        raise SystemExit(
            "No non-local Inbox mailbox found in Apple Mail. Configure the MIT Microsoft 365 account in Apple Mail first."
        )

    placeholders = ",".join("?" for _ in mailbox_ids)
    params = list(mailbox_ids)
    query = f"""
        select
          m.ROWID as rowid,
          m.mailbox as mailbox_rowid,
          mb.url as mailbox_url,
          a.address as sender_address,
          a.comment as sender_name,
          s.subject as subject,
          m.summary as summary_id,
          m.read as is_read,
          m.flagged as flagged,
          m.deleted as deleted,
          datetime(m.date_received + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') as received_local
        from messages m
        join mailboxes mb on mb.ROWID = m.mailbox
        left join addresses a on a.ROWID = m.sender
        left join subjects s on s.ROWID = m.subject
        where m.mailbox in ({placeholders}) and m.deleted = 0
        order by m.date_received desc
        limit ?
    """
    params.append(args.limit)
    results = []
    for row in conn.execute(query, params):
        sender = row["sender_name"] or row["sender_address"]
        if row["sender_name"] and row["sender_address"]:
            sender = f'{row["sender_name"]} <{row["sender_address"]}>'
        results.append({
            "rowid": row["rowid"],
            "mailbox_rowid": row["mailbox_rowid"],
            "mailbox_url": row["mailbox_url"],
            "sender": sender,
            "subject": row["subject"],
            "received_local": row["received_local"],
            "is_read": bool(row["is_read"]),
            "flagged": bool(row["flagged"]),
        })
    return {"backend": "sqlite", "messages": results}


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


def is_authorization_error(exc):
    msg = str(exc).lower()
    return "authorization denied" in msg or "operation not permitted" in msg


def list_mailboxes(args):
    try:
        result = list_mailboxes_db()
    except Exception as exc:
        if not is_authorization_error(exc):
            raise
        result = list_mailboxes_applescript()
        result["fallback_reason"] = str(exc)
    print(json.dumps(result, indent=2, ensure_ascii=False))


def list_messages(args):
    try:
        result = list_messages_db(args)
    except Exception as exc:
        if not is_authorization_error(exc):
            raise
        result = list_messages_applescript(args)
        result["fallback_reason"] = str(exc)
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
