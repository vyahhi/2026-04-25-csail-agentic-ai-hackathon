#!/usr/bin/env python3
import argparse
import json
import os
import shlex
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime
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


def hermes_python():
    venv_python = Path.home() / ".hermes" / "hermes-agent" / "venv" / "bin" / "python"
    if venv_python.exists():
        return str(venv_python)
    return sys.executable


def load_snapshot():
    helper = Path.home() / ".hermes" / "scripts" / "mit-status.py"
    proc = subprocess.run(
        [hermes_python(), str(helper)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "mit-status.py failed")
    return json.loads(proc.stdout)


def summarize_degraded(snapshot):
    labels = {
        "vpn": "VPN",
        "browser_cdp": "Browser CDP",
        "gateway": "Gateway",
        "telegram": "Telegram",
        "canvas": "Canvas",
        "mit_email_apple_mail": "MIT email (Apple Mail)",
        "mit_email_outlook_browser": "MIT email (Outlook browser)",
        "piazza": "Piazza",
    }
    lines = []
    for key, label in labels.items():
        item = snapshot.get(key, {})
        if item.get("ok"):
            continue
        detail = (item.get("detail") or "").strip().splitlines()[0] if item.get("detail") else "degraded"
        lines.append(f"- {label}: {detail}")
    if not lines:
        return ""
    ts = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    return "MIT alert: degraded services\n" + f"time: {ts}\n" + "\n".join(lines)


def send_telegram(text):
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    chat_id = os.environ.get("TELEGRAM_HOME_CHANNEL", "").strip()
    if not token or not chat_id:
        raise RuntimeError("TELEGRAM_BOT_TOKEN or TELEGRAM_HOME_CHANNEL is not configured")
    data = urllib.parse.urlencode(
        {
            "chat_id": chat_id,
            "text": text,
            "disable_web_page_preview": "true",
        }
    ).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read().decode())
    if not payload.get("ok"):
        raise RuntimeError(f"Telegram send failed: {payload}")
    return payload


def main():
    load_env_file()
    parser = argparse.ArgumentParser(description="Send Telegram alerts only when MIT services are degraded.")
    parser.add_argument("--send", action="store_true", help="Send the degraded summary to Telegram if any component is degraded")
    parser.add_argument("--test", action="store_true", help="Send a one-time Telegram test message")
    args = parser.parse_args()

    if args.test:
        text = f"MIT alert test\n{datetime.now().astimezone().strftime('%Y-%m-%d %H:%M %Z')}"
        payload = send_telegram(text)
        print(json.dumps({"sent": True, "mode": "test", "message_id": payload["result"]["message_id"]}, indent=2))
        return

    snapshot = load_snapshot()
    summary = summarize_degraded(snapshot)
    if args.send:
        if not summary:
            print(json.dumps({"sent": False, "healthy": True}, indent=2))
            return
        payload = send_telegram(summary)
        print(json.dumps({"sent": True, "healthy": False, "message_id": payload["result"]["message_id"]}, indent=2))
        return

    print(summary)


if __name__ == "__main__":
    main()
