#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

try:
    import websocket
except ImportError as exc:
    raise SystemExit(
        "websocket-client is required. Install it into the Hermes Python environment first."
    ) from exc


CDP_BASE = os.environ.get("BROWSER_CDP_URL", "http://127.0.0.1:9222")


def fetch_json(url, method="GET"):
    req = urllib.request.Request(url, method=method)
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode())


def list_targets():
    return fetch_json(f"{CDP_BASE}/json/list")


def open_outlook_page():
    fetch_json(f"{CDP_BASE}/json/new?https://outlook.office.com/mail/", method="PUT")


def find_outlook_target():
    for target in list_targets():
        url = str(target.get("url", ""))
        if target.get("type") == "page" and (
            url.startswith("https://outlook.office.com/mail/")
            or url.startswith("https://outlook.cloud.microsoft/mail/")
        ):
            return target
    return None


def cdp_evaluate(ws_url, expression):
    ws = websocket.create_connection(ws_url, timeout=20, suppress_origin=True)
    try:
        next_id = 1

        def send(method, params=None):
            nonlocal next_id
            msg_id = next_id
            next_id += 1
            ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
            return msg_id

        runtime_id = send("Runtime.enable")
        page_id = send("Page.enable")
        eval_id = send("Runtime.evaluate", {
            "expression": expression,
            "returnByValue": True,
        })

        needed = {runtime_id, page_id, eval_id}
        while needed:
            raw = ws.recv()
            msg = json.loads(raw)
            msg_id = msg.get("id")
            if msg_id not in needed:
                continue
            needed.remove(msg_id)
            if msg_id != eval_id:
                continue
            if "error" in msg:
                raise RuntimeError(json.dumps(msg["error"]))
            result = msg.get("result", {}).get("result", {})
            if "value" not in result:
                raise RuntimeError("CDP evaluation returned no value")
            return result["value"]
        raise RuntimeError("CDP evaluation did not complete")
    finally:
        try:
            ws.close()
        except Exception:
            pass


def parse_message(item):
    raw_lines = [re.sub(r"\s+", " ", line).strip() for line in str(item.get("text", "")).splitlines()]
    raw_lines = [line for line in raw_lines if line]
    lines = []
    for line in raw_lines:
        if re.fullmatch(r"[A-Z]{1,3}", line):
            continue
        if len(line) <= 3 and not re.search(r"[A-Za-z0-9]", line):
            continue
        lines.append(line)
    sender = lines[0] if lines else None
    subject = lines[1] if len(lines) > 1 else None
    aria = str(item.get("aria", ""))
    received = None
    patterns = [
        r"\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+\d{1,2}:\d{2}\s*(?:AM|PM)\b",
        r"\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+\d{1,2}/\d{1,2}\b",
        r"\b\d{1,2}:\d{2}\s*(?:AM|PM)\b",
        r"\b\d{1,2}/\d{1,2}\b",
    ]
    for pattern in patterns:
        match = re.search(pattern, aria, re.I)
        if match:
            received = match.group(0)
            break
    return {
        "sender": sender,
        "subject": subject,
        "received": received,
        "aria": aria,
    }


def list_messages(limit):
    target = find_outlook_target()
    if not target:
        open_outlook_page()
        time.sleep(5)
        target = find_outlook_target()
    if not target:
        raise RuntimeError("No Outlook target found in persistent browser session.")

    value = cdp_evaluate(
        target["webSocketDebuggerUrl"],
        f"""(() => {{
          const title = document.title;
          const href = location.href;
          const body = document.body ? document.body.innerText.slice(0, 2000) : "";
          const items = [...document.querySelectorAll('[role="option"]')].slice(0, {int(limit)}).map((el) => ({{
            text: el.innerText || "",
            aria: el.getAttribute('aria-label') || "",
          }}));
          return JSON.stringify({{ title, href, body, items }});
        }})()""",
    )
    parsed = json.loads(value)
    body = parsed.get("body", "")
    title = parsed.get("title", "")
    if re.search(r"duo|sign in|authenticate", title, re.I) or re.search(r"Stay signed in\\?|Verify with Duo|sign in", body, re.I):
        raise RuntimeError("Outlook browser session requires authentication.")
    return [parse_message(item) for item in parsed.get("items", []) if item.get("text") or item.get("aria")]


def main():
    parser = argparse.ArgumentParser(description="Read recent Outlook messages from the persistent Hermes browser session.")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("list")
    p.add_argument("--limit", type=int, default=3)
    args = parser.parse_args()

    if args.cmd == "list":
        print(json.dumps({"messages": list_messages(args.limit)}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
