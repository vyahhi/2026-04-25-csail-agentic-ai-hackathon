#!/usr/bin/env python3
import argparse
import json
import os
import shlex
from pathlib import Path


def load_env_file():
    path = Path(os.environ.get("HERMES_ENV_FILE", Path.home() / ".hermes" / ".env"))
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        key = key.strip()
        if key and key not in os.environ:
            try:
                parsed = shlex.split(value, comments=False, posix=True)
                os.environ[key] = parsed[0] if parsed else ""
            except ValueError:
                os.environ[key] = value


def require_package():
    try:
        from piazza_api import Piazza
        return Piazza
    except ImportError:
        raise SystemExit("Missing piazza-api. Install with: ~/.hermes/hermes-agent/venv/bin/python -m pip install piazza-api")


def login():
    Piazza = require_package()
    email = os.environ.get("PIAZZA_EMAIL", "").strip()
    password = os.environ.get("PIAZZA_PASSWORD", "").strip()
    if not email or not password:
        raise SystemExit("Set PIAZZA_EMAIL and PIAZZA_PASSWORD in ~/.hermes/.env for read-only Piazza access.")
    p = Piazza()
    p.user_login(email=email, password=password)
    return p


def network_id():
    value = os.environ.get("PIAZZA_NETWORK_ID", "").strip()
    if not value:
        raise SystemExit("Set PIAZZA_NETWORK_ID in ~/.hermes/.env. Open the Piazza class URL and copy the network id from the URL/API.")
    return value


def list_classes(_args):
    p = login()
    profile = p.get_user_profile()
    print(json.dumps(profile, ensure_ascii=False, indent=2))


def list_posts(args):
    p = login()
    cls = p.network(network_id())
    posts = []
    for post in cls.iter_all_posts(limit=args.limit):
        posts.append({
            "nr": post.get("nr"),
            "id": post.get("id"),
            "created": post.get("created"),
            "updated": post.get("updated"),
            "type": post.get("type"),
            "subject": post.get("history", [{}])[0].get("subject") if post.get("history") else None,
            "folders": post.get("folders"),
            "tags": post.get("tags"),
        })
    print(json.dumps(posts, ensure_ascii=False, indent=2))


def read_post(args):
    p = login()
    cls = p.network(network_id())
    post = cls.get_post(args.post_id)
    print(json.dumps(post, ensure_ascii=False, indent=2))


def main():
    load_env_file()
    parser = argparse.ArgumentParser(description="Read-only Piazza helper using the unofficial piazza-api package.")
    sub = parser.add_subparsers(required=True)
    p = sub.add_parser("profile")
    p.set_defaults(func=list_classes)
    p = sub.add_parser("list")
    p.add_argument("--limit", type=int, default=20)
    p.set_defaults(func=list_posts)
    p = sub.add_parser("read")
    p.add_argument("post_id", help="Piazza post number/id, e.g. 42")
    p.set_defaults(func=read_post)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
