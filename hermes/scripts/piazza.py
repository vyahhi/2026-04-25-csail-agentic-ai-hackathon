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


def available_classes(p):
    status = p.get_user_status()
    roles = ((status.get("config") or {}).get("roles") or {})
    classes = []
    for meta in (status.get("networks") or []):
        class_id = meta.get("id")
        classes.append({
            "id": class_id,
            "num": meta.get("course_number") or meta.get("num"),
            "name": meta.get("name"),
            "my_name": meta.get("my_name"),
            "term": meta.get("term"),
            "role": roles.get(class_id),
            "user_count": meta.get("user_count"),
            "enrollment": meta.get("enrollment"),
            "folders": meta.get("folders") or [],
            "topics": meta.get("topics") or [],
            "instructors": [inst.get("name") for inst in (meta.get("profs") or [])],
            "status": meta.get("status"),
        })
    classes.sort(key=lambda x: ((x.get("term") or ""), (x.get("num") or ""), (x.get("name") or "")), reverse=True)
    return classes, status


def resolve_network_id(args, status=None):
    if getattr(args, "network_id", None):
        return args.network_id.strip()
    value = os.environ.get("PIAZZA_NETWORK_ID", "").strip()
    if value:
        return value
    if status is None:
        raise SystemExit("No Piazza course selected.")
    last_network = (status.get("last_network") or "").strip()
    if last_network:
        return last_network
    classes = status.get("networks") or []
    if len(classes) == 1:
        return classes[0]["id"]
    raise SystemExit("Multiple Piazza courses available. Use 'classes' first, then pass --network-id if you need a specific one.")


def list_profile(_args):
    p = login()
    profile = p.get_user_profile()
    print(json.dumps(profile, ensure_ascii=False, indent=2))


def list_classes_cmd(_args):
    p = login()
    classes, status = available_classes(p)
    print(json.dumps({"classes": classes, "last_network": status.get("last_network")}, ensure_ascii=False, indent=2))


def list_posts(args):
    p = login()
    _classes, status = available_classes(p)
    cls = p.network(resolve_network_id(args, status))
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
    _classes, status = available_classes(p)
    cls = p.network(resolve_network_id(args, status))
    post = cls.get_post(args.post_id)
    print(json.dumps(post, ensure_ascii=False, indent=2))


def main():
    load_env_file()
    parser = argparse.ArgumentParser(description="Read-only Piazza helper using the unofficial piazza-api package.")
    sub = parser.add_subparsers(required=True)

    p = sub.add_parser("profile")
    p.set_defaults(func=list_profile)

    p = sub.add_parser("classes")
    p.set_defaults(func=list_classes_cmd)

    p = sub.add_parser("list")
    p.add_argument("--limit", type=int, default=20)
    p.add_argument("--network-id", help="Override the Piazza network/course id for this request")
    p.set_defaults(func=list_posts)

    p = sub.add_parser("read")
    p.add_argument("post_id", help="Piazza post number/id, e.g. 42")
    p.add_argument("--network-id", help="Override the Piazza network/course id for this request")
    p.set_defaults(func=read_post)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
