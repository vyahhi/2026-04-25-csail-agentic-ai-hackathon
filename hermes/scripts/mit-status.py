#!/usr/bin/env python3
import json
import os
import shlex
import subprocess
import sys
import urllib.error
import urllib.request
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


def run(cmd, timeout=20):
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return {
        "ok": proc.returncode == 0,
        "code": proc.returncode,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
    }


def status_from_run(cmd, timeout=20, detail_from_stdout=True):
    result = run(cmd, timeout=timeout)
    detail = result["stdout"] if detail_from_stdout and result["stdout"] else result["stderr"]
    return {
        "ok": result["ok"],
        "detail": detail,
    }


def check_vpn():
    script = str(Path.home() / ".hermes" / "scripts" / "mit-vpn-globalprotect.sh")
    if not Path(script).exists():
        return {"ok": False, "detail": "VPN helper not installed"}
    result = run([script, "test-kb"], timeout=30)
    detail = result["stdout"] or result["stderr"]
    final_url = None
    for line in detail.splitlines():
        if line.startswith("MIT KB final URL: "):
            final_url = line.split(": ", 1)[1]
            break
    return {
        "ok": result["ok"],
        "detail": detail,
        "kb_url": final_url,
    }


def check_browser():
    script = str(Path.home() / ".hermes" / "scripts" / "persistent-browser-cdp.sh")
    if not Path(script).exists():
        return {"ok": False, "detail": "CDP helper not installed"}
    return status_from_run([script, "status"])


def check_gateway():
    hermes = os.environ.get("HERMES_BIN", "hermes")
    result = run([hermes, "gateway", "status"], timeout=20)
    text = result["stdout"] or result["stderr"]
    ok = result["ok"] and any(token in text.lower() for token in ["running", "loaded"])
    return {"ok": ok, "detail": text}


def parse_env_keys():
    env_path = Path.home() / ".hermes" / ".env"
    values = {}
    if not env_path.exists():
        return values
    for line in env_path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        values[key] = value
    return values


def check_telegram():
    values = parse_env_keys()
    config_path = Path.home() / ".hermes" / "config.yaml"
    busy_mode = None
    if config_path.exists():
        for line in config_path.read_text().splitlines():
            if "busy_input_mode:" in line:
                busy_mode = line.split(":", 1)[1].strip()
                break
    ok = bool(values.get("TELEGRAM_BOT_TOKEN")) and bool(values.get("TELEGRAM_ALLOWED_USERS")) and bool(values.get("TELEGRAM_HOME_CHANNEL"))
    return {
        "ok": ok,
        "detail": f"busy_input_mode={busy_mode or 'unknown'}",
        "busy_input_mode": busy_mode,
        "allowed_users_configured": bool(values.get("TELEGRAM_ALLOWED_USERS")),
        "home_channel_configured": bool(values.get("TELEGRAM_HOME_CHANNEL")),
    }


def check_canvas():
    base = os.environ.get("CANVAS_BASE_URL", "https://canvas.mit.edu").rstrip("/")
    token = os.environ.get("CANVAS_API_TOKEN", "").strip()
    if not token:
        return {"ok": False, "detail": "CANVAS_API_TOKEN not set"}
    req = urllib.request.Request(
        f"{base}/api/v1/courses?per_page=1&enrollment_state=active",
        headers={"Authorization": f"Bearer {token}", "User-Agent": "Hermes MIT status/1.0"},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            payload = json.loads(resp.read().decode())
            first = payload[0]["name"] if payload else None
            return {"ok": resp.status == 200, "detail": f"HTTP {resp.status}", "sample_course": first}
    except urllib.error.HTTPError as exc:
        return {"ok": False, "detail": f"HTTP {exc.code}"}
    except Exception as exc:
        return {"ok": False, "detail": str(exc)}


def check_apple_mail():
    helper = str(Path.home() / ".hermes" / "scripts" / "mit-email-applemail.py")
    if not Path(helper).exists():
        return {"ok": False, "detail": "Apple Mail helper not installed"}
    result = run([helper, "list", "--limit", "1"], timeout=30)
    detail = result["stdout"] or result["stderr"]
    subject = None
    if result["ok"]:
        try:
            payload = json.loads(result["stdout"])
            if payload.get("messages"):
                subject = payload["messages"][0].get("subject")
        except Exception:
            pass
    return {"ok": result["ok"], "detail": detail, "sample_subject": subject}


def check_outlook_browser():
    helper = str(Path.home() / ".hermes" / "scripts" / "mit-email-browser.py")
    if not Path(helper).exists():
        return {"ok": False, "detail": "Outlook browser helper not installed"}
    result = run([sys.executable if helper.endswith(".py") else helper, helper, "list", "--limit", "1"] if helper.endswith(".py") else [helper, "list", "--limit", "1"], timeout=30)
    detail = result["stdout"] or result["stderr"]
    subject = None
    if result["ok"]:
        try:
            payload = json.loads(result["stdout"])
            messages = payload.get("messages") or []
            if messages:
                subject = messages[0].get("subject")
        except Exception:
            pass
    return {"ok": result["ok"], "detail": detail, "sample_subject": subject}


def check_piazza():
    helper = str(Path.home() / ".hermes" / "scripts" / "piazza.py")
    if not Path(helper).exists():
        return {"ok": False, "detail": "Piazza helper not installed"}
    result = run([sys.executable if helper.endswith(".py") else helper, helper, "classes"] if helper.endswith(".py") else [helper, "classes"], timeout=30)
    detail = result["stdout"] or result["stderr"]
    classes = None
    if result["ok"]:
        try:
            payload = json.loads(result["stdout"])
            classes = len(payload.get("classes") or [])
        except Exception:
            pass
    return {"ok": result["ok"], "detail": detail, "visible_classes": classes}


def main():
    load_env_file()
    snapshot = {
        "vpn": check_vpn(),
        "browser_cdp": check_browser(),
        "gateway": check_gateway(),
        "telegram": check_telegram(),
        "canvas": check_canvas(),
        "mit_email_apple_mail": check_apple_mail(),
        "mit_email_outlook_browser": check_outlook_browser(),
        "piazza": check_piazza(),
    }
    print(json.dumps(snapshot, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
