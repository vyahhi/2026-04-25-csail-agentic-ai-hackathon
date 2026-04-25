#!/usr/bin/env python3
import argparse
import json
import re
from difflib import SequenceMatcher
from pathlib import Path


def norm(value):
    return re.sub(r"[^a-z0-9]+", " ", str(value).lower()).strip()


def score(printer, query):
    q = norm(query)
    if not q:
        return 0.0
    haystack = " ".join(
        norm(printer.get(key, ""))
        for key in ("name", "building", "room", "area", "notes", "type")
    )
    capabilities = " ".join(printer.get("capabilities", []))
    aliases = " ".join(printer.get("aliases", []))
    hostnames = " ".join(printer.get("hostnames", []))
    haystack = f"{haystack} {norm(capabilities)} {norm(aliases)} {norm(hostnames)}"

    parts = q.split()
    exact_hits = sum(1 for part in parts if part in haystack)
    ratio = SequenceMatcher(None, q, haystack).ratio()

    building = norm(printer.get("building", ""))
    room = norm(printer.get("room", ""))
    building_boost = 0.0
    for part in parts:
        if part == building:
            building_boost += 1.0
        if room.startswith(part) or part in room:
            building_boost += 0.5

    total = exact_hits * 2.0 + building_boost + ratio
    if printer.get("type") == "pharos":
        total += 1.5
    if "support" in printer.get("capabilities", []):
        total -= 2.0
    return total


def main():
    parser = argparse.ArgumentParser(description="Find MIT printers near a fuzzy location.")
    parser.add_argument("query", nargs="*", help="Location query, e.g. 'stata', '32', 'barker', 'near 10'.")
    parser.add_argument("--data", default=str(Path.home() / ".hermes" / "data" / "mit-printers.json"))
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text.")
    args = parser.parse_args()

    data = json.loads(Path(args.data).read_text())
    query = " ".join(args.query)
    ranked = sorted(data, key=lambda item: score(item, query), reverse=True)
    ranked = ranked[: args.limit]

    if args.json:
        print(json.dumps(ranked, indent=2))
        return

    for idx, printer in enumerate(ranked, 1):
        caps = ", ".join(printer.get("capabilities", [])) or "unknown"
        print(f"{idx}. {printer['name']}")
        print(f"   Location: {printer.get('room', 'unknown')} ({printer.get('area', 'MIT')})")
        print(f"   Type: {printer.get('type', 'unknown')} | Capabilities: {caps}")
        if printer.get("queue"):
            print(f"   Queue: {printer['queue']}")
        if printer.get("hostnames"):
            print(f"   Hostnames: {', '.join(printer['hostnames'])}")
        print(f"   Notes: {printer.get('notes', '')}")


if __name__ == "__main__":
    main()
