#!/usr/bin/env python3
import argparse
import json
import os
import sys
import time
import urllib.request

try:
    import websocket
except ImportError as exc:
    raise SystemExit("websocket-client is required. Install it into the Hermes Python environment first.") from exc


CDP_BASE = os.environ.get("BROWSER_CDP_URL", "http://127.0.0.1:9222")
PRINT_URL = "https://print.mit.edu/MyPrintCenter/#"


def fetch_json(url, method="GET"):
    req = urllib.request.Request(url, method=method)
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode())


def list_targets():
    return fetch_json(f"{CDP_BASE}/json/list")


def open_print_page():
    return fetch_json(f"{CDP_BASE}/json/new?{PRINT_URL}", method="PUT")


def find_print_target():
    candidates = []
    for target in list_targets():
        url = str(target.get("url", ""))
        if target.get("type") == "page" and url.startswith("https://print.mit.edu/MyPrintCenter"):
            candidates.append(target)
    if not candidates:
        open_print_page()
        time.sleep(3)
        for target in list_targets():
            url = str(target.get("url", ""))
            if target.get("type") == "page" and url.startswith("https://print.mit.edu/MyPrintCenter"):
                candidates.append(target)
    if not candidates:
        raise RuntimeError("No My Print Center browser tab found.")
    return candidates[0]


class CDPClient:
    def __init__(self, ws_url):
        self.ws = websocket.create_connection(ws_url, timeout=20, suppress_origin=True)
        self.next_id = 1
        self.call("Runtime.enable")
        self.call("Page.enable")
        self.call("DOM.enable")

    def close(self):
        try:
            self.ws.close()
        except Exception:
            pass

    def call(self, method, params=None):
        msg_id = self.next_id
        self.next_id += 1
        self.ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") != msg_id:
                continue
            if "error" in msg:
                raise RuntimeError(f"{method}: {json.dumps(msg['error'])}")
            return msg.get("result", {})

    def eval(self, expression):
        result = self.call("Runtime.evaluate", {"expression": expression, "returnByValue": True})
        value = result.get("result", {})
        if "value" not in value:
            raise RuntimeError("CDP evaluation returned no value")
        return value["value"]

    def query_file_input_node(self):
        root = self.call("DOM.getDocument", {"depth": -1, "pierce": True})
        node_id = root["root"]["nodeId"]
        found = self.call("DOM.querySelector", {"nodeId": node_id, "selector": 'input[type="file"][name="Content"]'})
        return found.get("nodeId", 0)

    def set_file(self, path):
        node_id = self.query_file_input_node()
        if not node_id:
            raise RuntimeError("Could not locate MobilePrint file input.")
        self.call("DOM.setFileInputFiles", {"nodeId": node_id, "files": [path]})


def snapshot(client):
    raw = client.eval(
        """(() => JSON.stringify({
          title: document.title,
          href: location.href,
          body: (document.body && document.body.innerText || '').slice(0, 12000)
        }))()"""
    )
    return json.loads(raw)


def logged_in(state):
    body = state.get("body", "")
    return "MIT Print Quota :" in body and "Upload" in body and "Log out" in body


def ensure_logged_in(client):
    state = snapshot(client)
    if logged_in(state):
        return state

    clicked = client.eval(
        """(() => {
          const btn = document.querySelector('#hybrid-login-button');
          if (btn) { btn.click(); return 'clicked'; }
          return 'missing';
        })()"""
    )
    if clicked == "clicked":
        for _ in range(12):
            time.sleep(1)
            state = snapshot(client)
            if logged_in(state):
                return state

    body = state.get("body", "")
    title = state.get("title", "")
    href = state.get("href", "")
    if any(token in f"{title}\n{body}\n{href}".lower() for token in ["duo", "touchstone", "sign in", "password"]):
        raise RuntimeError("DUO_APPROVAL_NEEDED")
    raise RuntimeError("My Print Center login is required in the persistent browser session.")


def close_blocking_dialogs(client):
    client.eval(
        """(() => {
          for (const btn of [...document.querySelectorAll('button')]) {
            if (/^ok$/i.test((btn.innerText || '').trim())) btn.click();
            if (/^cancel$/i.test((btn.innerText || '').trim()) && document.body && document.body.innerText.includes('Confirm payment and print')) btn.click();
          }
          return 'ok';
        })()"""
    )


def current_printer(client):
    return client.eval(
        """(() => {
          const el = document.querySelector('.printer-name-block.printer-name');
          return el ? (el.innerText || '').trim() : '';
        })()"""
    )


def ensure_printer(client, printer_name):
    if not printer_name:
        return current_printer(client)

    current = current_printer(client)
    if current.lower() == printer_name.lower():
        return current

    js = json.dumps(printer_name)
    result = client.eval(
        f"""(() => {{
          const input = document.querySelector('input.input-printer-search');
          if (!input) return 'no-input';
          input.focus();
          input.value = {js};
          input.dispatchEvent(new Event('input', {{ bubbles: true }}));
          input.dispatchEvent(new KeyboardEvent('keyup', {{ bubbles: true, key: 'a' }}));
          return 'searching';
        }})()"""
    )
    if result == "no-input":
        raise RuntimeError("Could not locate printer selector search input.")

    for _ in range(10):
        time.sleep(1)
        state = client.eval(
            f"""(() => {{
              const exact = [...document.querySelectorAll('*')].find(el => {{
                const txt = (el.innerText || '').trim();
                return txt === {js} || txt.startsWith({js} + ' ');
              }});
              if (exact) exact.click();
              const selected = document.querySelector('.printer-name-block.printer-name');
              return JSON.stringify({{
                selected: selected ? (selected.innerText || '').trim() : '',
                exactFound: !!exact
              }});
            }})()"""
        )
        parsed = json.loads(state)
        if parsed["selected"].lower() == printer_name.lower():
            return parsed["selected"]

    current = current_printer(client)
    if current.lower() != printer_name.lower():
        raise RuntimeError(f"Could not switch MobilePrint destination to '{printer_name}'. Current destination: '{current or 'unknown'}'")
    return current


def wait_for_job_row(client, filename, timeout=90):
    js = json.dumps(filename)
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(1)
        state = json.loads(
            client.eval(
                f"""(() => JSON.stringify({{
                  hasFile: document.body && document.body.innerText.includes({js}),
                  processing: document.body && document.body.innerText.includes('Processing...'),
                  body: (document.body && document.body.innerText || '').slice(0, 8000)
                }}))()"""
            )
        )
        if state["hasFile"] and not state["processing"]:
            return state
    raise RuntimeError(f"Uploaded file '{filename}' did not become ready in My Print Center.")


def quota_value(client):
    value = client.eval(
        """(() => {
          const match = (document.body && document.body.innerText || '').match(/MIT Print Quota : \\$(\\d+\\.\\d+)/);
          return match ? match[1] : '';
        })()"""
    )
    return value or None


def select_job(client, filename):
    js = json.dumps(filename)
    for _ in range(3):
        close_blocking_dialogs(client)
        state = json.loads(
            client.eval(
                f"""(() => {{
                  const cb = [...document.querySelectorAll('input.selection-column-checkbox')].find(el =>
                    el.closest('tr') && (el.closest('tr').innerText || '').includes({js})
                  );
                  if (!cb) return JSON.stringify({{found:false, checked:false}});
                  if (!cb.checked) cb.click();
                  return JSON.stringify({{found:true, checked:cb.checked}});
                }})()"""
            )
        )
        if state["found"] and state["checked"]:
            return
        time.sleep(1)
    raise RuntimeError(f"Could not select uploaded job '{filename}'.")


def open_confirm_dialog(client):
    body = client.eval(
        """(() => {
          const btn = document.querySelector('#button-print-selection');
          if (!btn) return '';
          btn.click();
          return (document.body && document.body.innerText || '').slice(0, 8000);
        })()"""
    )
    if "You must select a printjob before releasing a job." in body:
        raise RuntimeError("Release failed because no job was selected.")
    if "Confirm payment and print" not in body:
        for _ in range(6):
            time.sleep(1)
            body = snapshot(client)["body"]
            if "Confirm payment and print" in body:
                break
    if "Confirm payment and print" not in body:
        raise RuntimeError("Could not reach the print confirmation dialog.")


def confirm_and_wait_gone(client, filename, timeout=60):
    clicked = client.eval(
        """(() => {
          const btn = [...document.querySelectorAll('button')].find(el => /^confirm$/i.test((el.innerText || '').trim()));
          if (btn) { btn.click(); return 'clicked'; }
          return 'missing';
        })()"""
    )
    if clicked != "clicked":
        raise RuntimeError("Could not find the final Confirm button.")

    js = json.dumps(filename)
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(2)
        state = json.loads(
            client.eval(
                f"""(() => JSON.stringify({{
                  hasFile: document.body && document.body.innerText.includes({js}),
                  body: (document.body && document.body.innerText || '').slice(0, 8000)
                }}))()"""
            )
        )
        if not state["hasFile"]:
            return state
    raise RuntimeError(f"Released job '{filename}' did not leave the queue in time.")


def do_print(file_path, printer_name):
    target = find_print_target()
    client = CDPClient(target["webSocketDebuggerUrl"])
    try:
        ensure_logged_in(client)
        close_blocking_dialogs(client)
        printer = ensure_printer(client, printer_name)
        before_quota = quota_value(client)
        client.set_file(file_path)
        filename = os.path.basename(file_path)
        wait_for_job_row(client, filename)
        select_job(client, filename)
        open_confirm_dialog(client)
        confirm_and_wait_gone(client, filename)
        after_quota = quota_value(client)
        return {
            "status": "printed",
            "file": file_path,
            "filename": filename,
            "printer": printer,
            "quota_before": before_quota,
            "quota_after": after_quota,
        }
    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description="Submit and release MIT MobilePrint jobs through the persistent browser session.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("print")
    p.add_argument("--file", required=True)
    p.add_argument("--printer")
    args = parser.parse_args()

    if args.cmd == "print":
        if not os.path.isfile(args.file):
            raise SystemExit(f"File not found: {args.file}")
        result = do_print(args.file, args.printer)
        print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
