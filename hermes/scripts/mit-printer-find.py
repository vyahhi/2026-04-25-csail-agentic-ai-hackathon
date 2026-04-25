#!/usr/bin/env python3
import argparse
import datetime as dt
import html
import json
import re
import sys
import urllib.request
from difflib import SequenceMatcher
from html.parser import HTMLParser


SOURCES = {
    "bundled_public_mit": "bundled-public-mit-printers",
    "mit_pharos": "https://kb.mit.edu/confluence/display/mitcontrib/MIT+Printer+Locations",
    "csail_macos": "https://tig.csail.mit.edu/print-copy-scan/macos-printing/",
}

CURATED_PUBLIC_MIT_PRINTERS = [
    ("Dorm Printers", "62: East Campus", "Amittai-Color.mit.edu", "amittai.mit.edu"),
    ("Dorm Printers", "E2: 70 Amherst Street", "Senior-Color.mit.edu", "Senior-p.mit.edu"),
    ("Dorm Printers", "E37: Graduate Tower at Site 4", "tower-color.mit.edu", ""),
    ("Dorm Printers", "NW10: Edgerton House", "Edgerton-Color.mit.edu", "edgerton-p.mit.edu"),
    ("Dorm Printers", "NW30: The Warehouse", "WH-Print-Color.mit.edu", "wh-print.mit.edu"),
    ("Dorm Printers", "NW35: Ashdown House", "Ashdown-Color.mit.edu", "ashdown-p.mit.edu; avery-p.mit.edu"),
    ("Dorm Printers", "NW61: Random Hall", "Jarthur-Color.mit.edu", "jarthur.mit.edu"),
    ("Dorm Printers", "NW86: Sidney Pacific", "Albany-Color.mit.edu", "albany-p.mit.edu; massave-p.mit.edu"),
    ("Dorm Printers", "W1: Maseeh Hall", "Maseeh-Color.mit.edu", "Maseeh-p.mit.edu; Electro-p.mit.edu; Tesla-p.mit.edu"),
    ("Dorm Printers", "W4: McCormick Hall", "Katharine-Color.mit.edu", "katharine-p.mit.edu"),
    ("Dorm Printers", "W7: Baker House", "Mortar-Color.mit.edu", "mortar-p.mit.edu; atwork02.mit.edu"),
    ("Dorm Printers", "W46: New Vassar", "Vassar-Color.mit.edu", "barbar-p.mit.edu"),
    ("Dorm Printers", "W51: Front desk", "", "burtonconner-p"),
    ("Dorm Printers", "W61: MacGregor House", "W61Cluster-Color.mit.edu", "w61cluster.mit.edu"),
    ("Dorm Printers", "W70: New House", "Corfu-Color.mit.edu", "clearcut-p.mit.edu; corfu-p.mit.edu"),
    ("Dorm Printers", "W71: Next House", "Tree-Eater-Color.mit.edu", "tree-eater.mit.edu"),
    ("Dorm Printers", "W79: Simmons Hall", "Simmons-Color.mit.edu", "simmons-p.mit.edu; waffle-p.mit.edu"),
    ("Dorm Printers", "W84: Tang Hall", "W84prt-Color.mit.edu", "w84prt-p.mit.edu; wg-tang-p.mit.edu"),
    ("Dorm Printers", "W85: Westgate", "Westgate-Color.mit.edu", "westgate-p.mit.edu"),
    ("Library printers", "7-238 Rotch", "Rotch-color.mit.edu; Rotch-color2.mit.edu", ""),
    ("Library printers", "10-500 Barker", "barker-color.mit.edu; barker-color2.mit.edu", ""),
    ("Library printers", "14E Lewis Library", "lewis-color.mit.edu", ""),
    ("Library printers", "14S-100 Hayden Library", "haydencolor-print.mit.edu; haydencolor2-print.mit.edu", "hayden-p.mit.edu"),
    ("Library printers", "E53-100 Dewey", "dewey-color.mit.edu; dewey-color2.mit.edu", "virus-p.mit.edu"),
    ("Sloan printers", "E51-210", "e51-210-xerox.mit.edu", ""),
    ("Sloan printers", "E62-107 Sloan Business Center", "e62-bc-color.mit.edu", "e62-bc-bw.mit.edu"),
    ("Sloan printers", "E62-231 (Outside hallway)", "", "e62-2west-bw.mit.edu"),
    ("Sloan printers", "E62-274 (Outside hallway)", "", "e62-2east-bw.mit.edu"),
    ("Other printer locations", "1-165: Civil", "", "Civil-p.mit.edu"),
    ("Other printer locations", "4-167", "Athena-Color.mit.edu; Athena-Color2.mit.edu; Athena-Color3.mit.edu", ""),
    ("Other printer locations", "11-004 Copytech", "Copytech-Color; Copytech-Color2", ""),
    ("Other printer locations", "32-Stata Lobby", "stata-color.mit.edu", "stata-p.mit.edu"),
    ("Other printer locations", "48-216-Parsons Lab", "", "celine.mit.edu"),
    ("Other printer locations", "E25-519 hallway", "", "imes-p.mit.edu"),
    ("Other printer locations", "E38-383 MIT Innovation", "ihqstudent-color.mit.edu", "ihqstudentbw-p"),
    ("Other printer locations", "E51-268 Hallway \"Nook\" (hallway outside of E51-268)", "", "E51-268-NOOK-P"),
    ("Other printer locations", "W20-540", "W20Color3.mit.edu; W20Color4.mit.edu", "ajax-p.mit.edu"),
    ("Other printer locations", "W20-575", "W20Color.mit.edu; W20Color2.mit.edu", "metis-p.mit.edu"),
]

DEPARTMENT_HINTS = {
    "csailprivate",
    "csail private",
    "department",
    "dept",
    "local queue",
    "queue name",
    "private printer",
    "internal printer",
    "tig",
    "wired csail",
    "building 45",
}


class TableParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tables = []
        self.heading = ""
        self._heading_tag = None
        self._heading_text = []
        self._table_stack = []
        self._row = None
        self._cell = None

    def handle_starttag(self, tag, attrs):
        if tag in {"h1", "h2", "h3", "h4"}:
            self._heading_tag = tag
            self._heading_text = []
        elif tag == "table":
            self._table_stack.append({"heading": self.heading, "rows": []})
        elif tag == "tr" and self._table_stack:
            self._row = []
        elif tag in {"td", "th"} and self._row is not None:
            self._cell = []
        elif tag == "br" and self._cell is not None:
            self._cell.append(" ")

    def handle_endtag(self, tag):
        if tag == self._heading_tag:
            text = clean(" ".join(self._heading_text))
            if text:
                self.heading = text
            self._heading_tag = None
            self._heading_text = []
        elif tag in {"td", "th"} and self._cell is not None and self._row is not None:
            self._row.append(clean(" ".join(self._cell)))
            self._cell = None
        elif tag == "tr" and self._row is not None and self._table_stack:
            if any(self._row):
                self._table_stack[-1]["rows"].append(self._row)
            self._row = None
        elif tag == "table" and self._table_stack:
            table = self._table_stack.pop()
            if table["rows"]:
                self.tables.append(table)

    def handle_data(self, data):
        if self._cell is not None:
            self._cell.append(data)
        if self._heading_tag is not None:
            self._heading_text.append(data)


def clean(value):
    value = html.unescape(str(value)).replace("\xa0", " ")
    return re.sub(r"\s+", " ", value).strip()


def norm(value):
    return re.sub(r"[^a-z0-9]+", " ", str(value).lower()).strip()


def fetch_tables(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Hermes MIT printer lookup/1.0",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
    })
    with urllib.request.urlopen(req, timeout=25) as resp:
        final_url = resp.geturl()
        if "accessrestricted" in final_url:
            raise RuntimeError(f"source redirected to access-restricted page: {final_url}")
        body = resp.read().decode(resp.headers.get_content_charset() or "utf-8", "ignore")
    parser = TableParser()
    parser.feed(body)
    return parser.tables


def split_hosts(value):
    value = clean(value)
    if not value or value == "&nbsp;":
        return []
    hosts = []
    for piece in re.split(r"[;,]", value):
        host = clean(piece)
        if host and host.lower() not in {"none", "n/a"}:
            hosts.append(host)
    return hosts


def building_from_location(location):
    match = re.match(r"([A-Z]*\d+[A-Z]*|W\d+|NW\d+|NE\d+|E\d+|N\d+)(?:[-:\s]|$)", location.strip(), re.I)
    return match.group(1).upper() if match else ""


def aliases_for(location, printer_type):
    aliases = {location, building_from_location(location)}
    lowered = location.lower()
    for key in ["stata", "csail", "barker", "dewey", "hayden", "rotch", "lewis", "sloan", "student center", "copytech"]:
        if key in lowered:
            aliases.add(key)
    if "stata" in lowered or "32-" in lowered or location.startswith("32"):
        aliases.update({"building 32", "stata center", "csail", "gates", "dreyfoos"})
    if "w20" in lowered:
        aliases.update({"student center", "stratton"})
    if printer_type == "csail-department":
        aliases.update({"csail", "stata", "building 32"})
    return sorted(alias for alias in aliases if alias)


def append_public_printer(printers, section, location, color_text, bw_text, source, notes):
    color_hosts = split_hosts(color_text)
    bw_hosts = split_hosts(bw_text)
    if not location or not (color_hosts or bw_hosts):
        return
    caps = ["pharos", "print"]
    if color_hosts:
        caps.append("color")
    if bw_hosts:
        caps.append("black-and-white")
    printers.append({
        "name": f"MIT Pharos {location}",
        "type": "pharos",
        "building": building_from_location(location),
        "room": location,
        "area": section,
        "aliases": aliases_for(location, "pharos"),
        "hostnames": color_hosts + bw_hosts,
        "color_hostnames": color_hosts,
        "bw_hostnames": bw_hosts,
        "capabilities": caps,
        "source": source,
        "fetched_at": now_iso(),
        "notes": notes,
    })


def add_curated_public_mit(printers):
    for section, location, color_text, bw_text in CURATED_PUBLIC_MIT_PRINTERS:
        append_public_printer(
            printers,
            section,
            location,
            color_text,
            bw_text,
            SOURCES["bundled_public_mit"],
            "Bundled public MIT printer list supplied in repo. Prefer live MIT KB data when available; use this list as an off-MITnet baseline.",
        )


def add_mit_pharos(printers, failures):
    try:
        tables = fetch_tables(SOURCES["mit_pharos"])
    except Exception as exc:
        failures.append(f"{SOURCES['mit_pharos']}: {exc}")
        return

    matched = False
    for table in tables:
        rows = table["rows"]
        if not rows:
            continue
        headers = [norm(cell) for cell in rows[0]]
        if len(headers) < 3 or "location" not in headers[0] or "hostname color" not in headers[1]:
            continue
        matched = True
        section = table["heading"] or "MIT Pharos"
        for row in rows[1:]:
            if len(row) < 3:
                continue
            location, color_text, bw_text = row[0], row[1], row[2]
            color_hosts = split_hosts(color_text)
            bw_hosts = split_hosts(bw_text)
            if not location or not (color_hosts or bw_hosts):
                continue
            append_public_printer(
                printers,
                section,
                location,
                color_text,
                bw_text,
                SOURCES["mit_pharos"],
                "Live MIT KB Pharos printer-location row. Submit via Athena Print Center/MobilePrint or configured Pharos client, then release at the device.",
            )
    if not matched:
        failures.append(f"{SOURCES['mit_pharos']}: no Pharos hostname table found in live response")


def add_csail_printers(printers, failures):
    try:
        tables = fetch_tables(SOURCES["csail_macos"])
    except Exception as exc:
        failures.append(f"{SOURCES['csail_macos']}: {exc}")
        return

    for table in tables:
        rows = table["rows"]
        if not rows:
            continue
        headers = [norm(cell) for cell in rows[0]]
        if headers[:3] != ["location", "printer queue name", "model"]:
            continue
        for row in rows[1:]:
            if len(row) < 3:
                continue
            location, queue_raw, model = [clean(cell) for cell in row[:3]]
            queue = re.sub(r"\s*\(.*?\)\s*", "", queue_raw).strip()
            if not location or not queue:
                continue
            building = "45" if location.startswith("45-") else "32"
            caps = ["print"]
            model_norm = norm(model)
            if any(token in model_norm for token in ["primelink", "6510", "c310"]):
                caps.append("color")
            if "primelink" in model_norm:
                caps.extend(["black-and-white", "copy", "scan"])
            elif "black-and-white" not in caps:
                caps.append("black-and-white")
            printers.append({
                "name": f"CSAIL {queue}",
                "type": "csail-department",
                "building": building,
                "room": f"{building}-{location}" if not location.startswith(building) else location,
                "area": "CSAIL / Stata Center" if building == "32" else "CSAIL Building 45",
                "queue": queue,
                "queue_label": queue_raw,
                "model": model,
                "aliases": aliases_for(f"{building}-{location} {queue} {queue_raw}", "csail-department"),
                "hostnames": [f"{queue}.csail.mit.edu"],
                "capabilities": sorted(set(caps)),
                "network_required": "CSAILPrivate wireless or wired CSAIL Ethernet in Building 32" if building == "32" else "MIT Secure or wired Ethernet configured on CSAIL subnet in Building 45",
                "source": SOURCES["csail_macos"],
                "fetched_at": now_iso(),
                "notes": "Live CSAIL TIG printer row. The remote Mac mini is off CSAIL/MIT local network, so this is normally lookup/setup guidance rather than direct printing.",
            })
        break


def now_iso():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def score(printer, query):
    q = norm(query)
    if not q:
        return 0.0
    fields = ("name", "building", "room", "area", "notes", "type", "queue", "model")
    haystack = " ".join(norm(printer.get(key, "")) for key in fields)
    haystack = " ".join([
        haystack,
        norm(" ".join(printer.get("capabilities", []))),
        norm(" ".join(printer.get("aliases", []))),
        norm(" ".join(printer.get("hostnames", []))),
    ])

    parts = q.split()
    exact_hits = sum(1 for part in parts if part in haystack)
    ratio = SequenceMatcher(None, q, haystack).ratio()
    building = norm(printer.get("building", ""))
    room = norm(printer.get("room", ""))
    building_boost = 0.0
    for part in parts:
        if part == building:
            building_boost += 1.5
        if room.startswith(part) or part in room:
            building_boost += 0.75

    total = exact_hits * 2.0 + building_boost + ratio
    if printer.get("type") == "pharos":
        total += 1.0
    if "csail" in parts and printer.get("type") == "csail-department":
        total += 2.5
    if "stata" in parts and printer.get("building") == "32":
        total += 1.5
    return total


def wants_department_printers(query):
    q = norm(query)
    if not q:
        return False
    if any(hint in q for hint in DEPARTMENT_HINTS):
        return True
    if "csail" in q and any(token in q for token in {"queue", "private", "department", "45"}):
        return True
    return False


def load_live_printers():
    printers = []
    failures = []
    add_curated_public_mit(printers)
    add_mit_pharos(printers, failures)
    add_csail_printers(printers, failures)
    deduped = {}
    for printer in printers:
        host_key = tuple(sorted(norm(host) for host in printer.get("hostnames", [])))
        key = (printer.get("type"), norm(printer.get("room", "")), host_key)
        existing = deduped.get(key)
        if not existing:
            deduped[key] = printer
            continue
        if existing.get("source") == SOURCES["bundled_public_mit"] and printer.get("source") != SOURCES["bundled_public_mit"]:
            deduped[key] = printer
    return list(deduped.values()), failures


def format_printer(printer, idx):
    caps = ", ".join(printer.get("capabilities", [])) or "unknown"
    print(f"{idx}. {printer['name']}")
    print(f"   Location: {printer.get('room', 'unknown')} ({printer.get('area', 'MIT')})")
    print(f"   Type: {printer.get('type', 'unknown')} | Capabilities: {caps}")
    if printer.get("queue"):
        print(f"   Queue ID: {printer['queue']}")
    if printer.get("model"):
        print(f"   Model: {printer['model']}")
    if printer.get("color_hostnames"):
        print(f"   Color hostnames: {', '.join(printer['color_hostnames'])}")
    if printer.get("bw_hostnames"):
        print(f"   B/W hostnames: {', '.join(printer['bw_hostnames'])}")
    elif printer.get("hostnames"):
        print(f"   Hostnames: {', '.join(printer['hostnames'])}")
    if printer.get("network_required"):
        print(f"   Network required: {printer['network_required']}")
    print(f"   Source: {printer.get('source')}")
    print(f"   Fetched: {printer.get('fetched_at')}")
    print(f"   Notes: {printer.get('notes', '')}")


def main():
    parser = argparse.ArgumentParser(description="Find MIT printers near a fuzzy location from live MIT/CSAIL sources.")
    parser.add_argument("query", nargs="*", help="Location query, e.g. 'stata', '32', 'barker', 'near 10'.")
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text.")
    parser.add_argument("--sources", action="store_true", help="Print the live source URLs and exit.")
    parser.add_argument("--include-department", action="store_true", help="Include department-local queues such as CSAIL printers.")
    args = parser.parse_args()

    if args.sources:
        print(json.dumps(SOURCES, indent=2))
        return

    printers, failures = load_live_printers()
    if not printers:
        print("No printer data could be fetched from live sources.", file=sys.stderr)
        for failure in failures:
            print(f"Fetch failed: {failure}", file=sys.stderr)
        sys.exit(1)

    query = " ".join(args.query)
    include_department = args.include_department or wants_department_printers(query)
    filtered = printers if include_department else [item for item in printers if item.get("type") == "pharos"]
    ranked = sorted(filtered, key=lambda item: score(item, query), reverse=True)
    ranked = ranked[: args.limit]

    if args.json:
        print(json.dumps({
            "results": ranked,
            "fetch_failures": failures,
            "sources": SOURCES,
            "department_printers_included": include_department,
        }, indent=2))
        return

    for idx, printer in enumerate(ranked, 1):
        format_printer(printer, idx)
    if failures:
        print()
        for failure in failures:
            print(f"Warning: fetch failed: {failure}", file=sys.stderr)


if __name__ == "__main__":
    main()
