#!/usr/bin/env python3
import argparse
import json
import os
import shlex
import time
import urllib.parse
import urllib.request
from pathlib import Path


GRAPH = "https://graph.microsoft.com/v1.0"
DEFAULT_SCOPES = "offline_access User.Read Mail.Read"


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


def token_path():
    return Path(os.environ.get("MS_GRAPH_TOKEN_FILE", Path.home() / ".hermes" / "auth" / "ms-graph-token.json"))


def request_json(url, data=None, headers=None, method=None):
    body = None
    req_headers = dict(headers or {})
    if data is not None:
        body = urllib.parse.urlencode(data).encode()
        req_headers["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=body, headers=req_headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def tenant():
    return os.environ.get("MS_GRAPH_TENANT", "organizations")


def client_id():
    value = os.environ.get("MS_GRAPH_CLIENT_ID", "").strip()
    if not value:
        raise SystemExit(
            "MS_GRAPH_CLIENT_ID is required. Create or use a Microsoft Entra public client app "
            "with delegated Mail.Read permission, then set MS_GRAPH_CLIENT_ID in ~/.hermes/.env."
        )
    return value


def save_token(data):
    path = token_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    data["obtained_at"] = int(time.time())
    path.write_text(json.dumps(data, indent=2))
    path.chmod(0o600)


def load_token():
    path = token_path()
    if not path.exists():
        return None
    return json.loads(path.read_text())


def refresh_token(data):
    if not data or not data.get("refresh_token"):
        return None
    url = f"https://login.microsoftonline.com/{tenant()}/oauth2/v2.0/token"
    refreshed = request_json(url, {
        "client_id": client_id(),
        "grant_type": "refresh_token",
        "refresh_token": data["refresh_token"],
        "scope": os.environ.get("MS_GRAPH_SCOPES", DEFAULT_SCOPES),
    })
    save_token(refreshed)
    return refreshed


def access_token():
    data = load_token()
    if not data:
        raise SystemExit("Not logged in. Run: mit-email-graph.py login")
    expires_in = int(data.get("expires_in", 0))
    obtained_at = int(data.get("obtained_at", 0))
    if int(time.time()) > obtained_at + max(0, expires_in - 300):
        data = refresh_token(data)
        if not data:
            raise SystemExit("Token expired and no refresh token is available. Run login again.")
    return data["access_token"]


def graph_get(path):
    url = path if path.startswith("https://") else GRAPH + path
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {access_token()}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def login(args):
    url = f"https://login.microsoftonline.com/{tenant()}/oauth2/v2.0/devicecode"
    device = request_json(url, {
        "client_id": client_id(),
        "scope": os.environ.get("MS_GRAPH_SCOPES", DEFAULT_SCOPES),
    })
    print(device.get("message") or f"Open {device['verification_uri']} and enter {device['user_code']}")
    token_url = f"https://login.microsoftonline.com/{tenant()}/oauth2/v2.0/token"
    interval = int(device.get("interval", 5))
    expires_at = time.time() + int(device.get("expires_in", 900))
    while time.time() < expires_at:
        time.sleep(interval)
        try:
            token = request_json(token_url, {
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": client_id(),
                "device_code": device["device_code"],
            })
            save_token(token)
            print("Microsoft Graph login complete. Mail.Read token saved.")
            return
        except urllib.error.HTTPError as exc:
            payload = json.loads(exc.read().decode() or "{}")
            if payload.get("error") in {"authorization_pending", "slow_down"}:
                if payload.get("error") == "slow_down":
                    interval += 5
                continue
            raise SystemExit(json.dumps(payload, indent=2))
    raise SystemExit("Device login timed out.")


def me(_args):
    print(json.dumps(graph_get("/me?$select=displayName,userPrincipalName,mail,id"), indent=2))


def list_messages(args):
    params = {
        "$top": str(args.limit),
        "$select": "id,receivedDateTime,from,subject,hasAttachments,isRead,webLink",
        "$orderby": "receivedDateTime desc",
    }
    if args.search:
        params["$search"] = f'"{args.search}"'
        params.pop("$orderby", None)
    path = "/me/messages?" + urllib.parse.urlencode(params)
    data = graph_get(path)
    for item in data.get("value", []):
        sender = ((item.get("from") or {}).get("emailAddress") or {})
        print(json.dumps({
            "id": item.get("id"),
            "receivedDateTime": item.get("receivedDateTime"),
            "from": sender.get("address") or sender.get("name"),
            "subject": item.get("subject"),
            "hasAttachments": item.get("hasAttachments"),
            "isRead": item.get("isRead"),
            "webLink": item.get("webLink"),
        }, ensure_ascii=False))


def read_message(args):
    msg = graph_get(f"/me/messages/{urllib.parse.quote(args.message_id)}?$select=id,receivedDateTime,from,toRecipients,subject,body,webLink")
    body = msg.get("body") or {}
    print(json.dumps({
        "id": msg.get("id"),
        "receivedDateTime": msg.get("receivedDateTime"),
        "from": msg.get("from"),
        "toRecipients": msg.get("toRecipients"),
        "subject": msg.get("subject"),
        "bodyContentType": body.get("contentType"),
        "body": body.get("content"),
        "webLink": msg.get("webLink"),
    }, ensure_ascii=False, indent=2))


def folders(args):
    data = graph_get(f"/me/mailFolders?$top={args.limit}&$select=id,displayName,totalItemCount,unreadItemCount")
    print(json.dumps(data.get("value", []), indent=2))


def main():
    load_env_file()
    parser = argparse.ArgumentParser(description="Read-only Microsoft Graph mailbox helper for MIT Microsoft 365 mail.")
    sub = parser.add_subparsers(required=True)
    p = sub.add_parser("login")
    p.set_defaults(func=login)
    p = sub.add_parser("me")
    p.set_defaults(func=me)
    p = sub.add_parser("list")
    p.add_argument("--limit", type=int, default=10)
    p.add_argument("--search")
    p.set_defaults(func=list_messages)
    p = sub.add_parser("read")
    p.add_argument("message_id")
    p.set_defaults(func=read_message)
    p = sub.add_parser("folders")
    p.add_argument("--limit", type=int, default=50)
    p.set_defaults(func=folders)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
