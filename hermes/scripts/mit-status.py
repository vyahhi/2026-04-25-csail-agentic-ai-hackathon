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


def hermes_bin():
    explicit = os.environ.get("HERMES_BIN", "").strip()
    if explicit:
        return explicit
    local = Path.home() / ".local" / "bin" / "hermes"
    if local.exists():
        return str(local)
    return "hermes"


def hermes_python():
    venv_python = Path.home() / ".hermes" / "hermes-agent" / "venv" / "bin" / "python"
    if venv_python.exists():
        return str(venv_python)
    return sys.executable


def helper_cmd(helper, *args):
    helper_path = Path(helper)
    if helper_path.suffix == ".py":
        return [hermes_python(), str(helper_path), *args]
    return [str(helper_path), *args]


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
    result = status_from_run([script, "status"])
    detail = result["detail"].strip().lower()
    result["ok"] = result["ok"] and detail.startswith("running ")
    return result


def check_gateway():
    result = run([hermes_bin(), "gateway", "status"], timeout=20)
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
    result = run(helper_cmd(helper, "list", "--limit", "1"), timeout=30)
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
    result = run(helper_cmd(helper, "list", "--limit", "1"), timeout=30)
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
    result = run(helper_cmd(helper, "classes"), timeout=30)
    detail = result["stdout"] or result["stderr"]
    classes = None
    if result["ok"]:
        try:
            payload = json.loads(result["stdout"])
            classes = len(payload.get("classes") or [])
        except Exception:
            pass
    return {"ok": result["ok"], "detail": detail, "visible_classes": classes}


def render_summary(snapshot):
    lines = ["MIT assistant status"]
    order = [
        ("vpn", "VPN"),
        ("browser_cdp", "Browser CDP"),
        ("gateway", "Gateway"),
        ("telegram", "Telegram"),
        ("canvas", "Canvas"),
        ("mit_email_apple_mail", "MIT email (Apple Mail)"),
        ("mit_email_outlook_browser", "MIT email (Outlook browser)"),
        ("piazza", "Piazza"),
    ]
    for key, label in order:
        item = snapshot.get(key, {})
        ok = bool(item.get("ok"))
        icon = "OK" if ok else "WARN"
        detail = (item.get("detail") or "").strip().splitlines()[0] if item.get("detail") else ""
        extra = []
        if key == "canvas" and item.get("sample_course"):
            extra.append(f"course={item['sample_course']}")
        if key in ("mit_email_apple_mail", "mit_email_outlook_browser") and item.get("sample_subject"):
            extra.append(f"subject={item['sample_subject']}")
        if key == "piazza" and item.get("visible_classes") is not None:
            extra.append(f"classes={item['visible_classes']}")
        if key == "telegram" and item.get("busy_input_mode"):
            extra.append(f"busy_mode={item['busy_input_mode']}")
        if key == "vpn" and item.get("kb_url"):
            extra.append(f"kb={item['kb_url']}")
        suffix = f" ({', '.join(extra)})" if extra else ""
        lines.append(f"- {label}: {icon}{suffix}")
        if detail:
            lines.append(f"  {detail}")
    return "\n".join(lines)


def main():
    load_env_file()
    parser = argparse.ArgumentParser(description="MIT assistant health snapshot.")
    parser.add_argument("--summary", action="store_true", help="Print a human-readable summary instead of JSON")
    args = parser.parse_args()
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
    if args.summary:
        print(render_summary(snapshot))
    else:
        print(json.dumps(snapshot, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
