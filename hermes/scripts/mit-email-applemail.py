#!/usr/bin/env python3
import argparse
import json
import os
import sqlite3
from pathlib import Path


APPLE_EPOCH_OFFSET = 978307200


def db_path():
    return Path.home() / "Library" / "Mail" / "V10" / "MailData" / "Envelope Index"


def connect():
    path = db_path()
    if not path.exists():
        raise SystemExit(f"Apple Mail database not found: {path}")
    uri = f"file:{path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def mailbox_rows(conn):
    return conn.execute(
        """
        select rowid, url, total_count, unread_count, source
        from mailboxes
        order by rowid
        """
    ).fetchall()


def list_mailboxes(args):
    conn = connect()
    rows = mailbox_rows(conn)
    results = []
    for row in rows:
        results.append({
            "rowid": row["rowid"],
            "url": row["url"],
            "total_count": row["total_count"],
            "unread_count": row["unread_count"],
            "source": row["source"],
        })
    print(json.dumps({"mailboxes": results}, indent=2, ensure_ascii=False))


def default_mailbox_filter(rows):
    preferred = []
    for row in rows:
        url = (row["url"] or "").lower()
        if "inbox" in url and not url.startswith("local://"):
            preferred.append(row["rowid"])
    return preferred


def list_messages(args):
    conn = connect()
    rows = mailbox_rows(conn)
    mailbox_ids = default_mailbox_filter(rows)
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
    print(json.dumps({"messages": results}, indent=2, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description="Read Apple Mail local database for MIT mailbox access without a browser.")
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
