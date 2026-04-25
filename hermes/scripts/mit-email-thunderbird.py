#!/usr/bin/env python3
import argparse
import configparser
import json
import mailbox
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path


def thunderbird_root():
    return Path.home() / "Library" / "Thunderbird"


def profiles_ini_path():
    return thunderbird_root() / "profiles.ini"


def load_profiles():
    path = profiles_ini_path()
    if not path.exists():
        raise SystemExit(
            f"Thunderbird profiles.ini not found at {path}. Start Thunderbird and complete first-run setup first."
        )

    parser = configparser.RawConfigParser()
    parser.read(path)
    install_defaults = {}
    for section in parser.sections():
        if not section.startswith("Install"):
            continue
        default = parser.get(section, "Default", fallback="").strip()
        if default:
            install_defaults[default] = True

    profiles = []
    for section in parser.sections():
        if not section.startswith("Profile"):
            continue
        rel = parser.get(section, "IsRelative", fallback="1").strip() == "1"
        raw_path = parser.get(section, "Path", fallback="").strip()
        if not raw_path:
            continue
        path = thunderbird_root() / raw_path if rel else Path(raw_path)
        profiles.append(
            {
                "section": section,
                "name": parser.get(section, "Name", fallback=section),
                "path": path,
                "default": parser.get(section, "Default", fallback="0").strip() == "1"
                or raw_path in install_defaults,
            }
        )
    return profiles


def default_profile():
    profiles = load_profiles()
    for profile in profiles:
        if profile["default"]:
            return profile
    if profiles:
        return profiles[0]
    raise SystemExit("No Thunderbird profiles found.")


def candidate_mailboxes(profile_path):
    roots = [profile_path / "ImapMail", profile_path / "Mail"]
    results = []
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix in {".msf", ".dat", ".sqlite", ".db", ".json"}:
                continue
            try:
                if path.stat().st_size == 0:
                    continue
            except OSError:
                continue
            results.append(path)
    return sorted(results)


def mailbox_label(path):
    parts = list(path.parts)
    if "ImapMail" in parts:
        idx = parts.index("ImapMail")
        return "/".join(parts[idx + 1 :])
    if "Mail" in parts:
        idx = parts.index("Mail")
        return "/".join(parts[idx + 1 :])
    return path.name


def inbox_candidates(profile_path):
    candidates = []
    for path in candidate_mailboxes(profile_path):
        name = path.name.lower()
        rel = mailbox_label(path).lower()
        if name == "inbox" or rel.endswith("/inbox"):
            candidates.append(path)
    return candidates


def parse_msg_date(message):
    value = message.get("date")
    if not value:
        return None
    try:
        dt = parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone()


def profiles_cmd(_args):
    payload = []
    for profile in load_profiles():
        payload.append(
            {
                "name": profile["name"],
                "path": str(profile["path"]),
                "default": profile["default"],
            }
        )
    print(json.dumps({"profiles": payload}, indent=2, ensure_ascii=False))


def mailboxes_cmd(args):
    profile = default_profile()
    rows = []
    for path in candidate_mailboxes(profile["path"]):
        rows.append(
            {
                "label": mailbox_label(path),
                "path": str(path),
                "size_bytes": path.stat().st_size,
            }
        )
    if args.inbox_only:
        rows = [row for row in rows if row["label"].lower().endswith("/inbox") or row["label"].lower() == "inbox"]
    print(
        json.dumps(
            {
                "profile": {"name": profile["name"], "path": str(profile["path"])},
                "mailboxes": rows,
            },
            indent=2,
            ensure_ascii=False,
        )
    )


def list_cmd(args):
    profile = default_profile()
    candidates = inbox_candidates(profile["path"])
    if args.mailbox:
        wanted = args.mailbox.lower()
        candidates = [path for path in candidate_mailboxes(profile["path"]) if mailbox_label(path).lower() == wanted]
    if not candidates:
        raise SystemExit(
            "No Thunderbird inbox mailbox found. Complete MIT Microsoft 365 account setup in Thunderbird first."
        )

    all_messages = []
    for path in candidates:
        try:
            mbox = mailbox.mbox(str(path))
            for key, message in mbox.iteritems():
                dt = parse_msg_date(message)
                all_messages.append(
                    {
                        "mailbox": mailbox_label(path),
                        "sender": message.get("from"),
                        "subject": message.get("subject"),
                        "date": message.get("date"),
                        "_sort": dt.timestamp() if dt else 0,
                    }
                )
        except Exception:
            continue

    all_messages.sort(key=lambda item: item["_sort"], reverse=True)
    for item in all_messages:
        item.pop("_sort", None)
    print(
        json.dumps(
            {
                "profile": {"name": profile["name"], "path": str(profile["path"])},
                "messages": all_messages[: args.limit],
            },
            indent=2,
            ensure_ascii=False,
        )
    )


def main():
    parser = argparse.ArgumentParser(
        description="Read Thunderbird local mailboxes for MIT Microsoft 365 mail without a browser."
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("profiles")
    p.set_defaults(func=profiles_cmd)

    p = sub.add_parser("mailboxes")
    p.add_argument("--inbox-only", action="store_true")
    p.set_defaults(func=mailboxes_cmd)

    p = sub.add_parser("list")
    p.add_argument("--limit", type=int, default=10)
    p.add_argument("--mailbox")
    p.set_defaults(func=list_cmd)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
