#!/usr/bin/env bash
set -euo pipefail

HERMES_ENV="$HOME/.hermes/.env"
if [[ -f "$HERMES_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$HERMES_ENV"
  set +a
fi

CANVAS_BASE_URL="${CANVAS_BASE_URL:-https://canvas.mit.edu}"
CANVAS_COURSE_ID="${CANVAS_COURSE_ID:-37338}"
CANVAS_COURSE_URL="${CANVAS_COURSE_URL:-$CANVAS_BASE_URL/courses/$CANVAS_COURSE_ID}"

echo "Canvas course URL: $CANVAS_COURSE_URL"
echo

echo "Public page:"
curl -Ls "$CANVAS_COURSE_URL" |
  python3 -c 'import re,sys,html
text=sys.stdin.read()
title=re.search(r"<title>(.*?)</title>", text, re.I|re.S)
ctx=re.search(r"context_asset_string\":\"(course_[0-9]+)", text)
login=bool(re.search(r"id=\"global_nav_login_link\"|/login", text))
print("  title:", html.unescape(title.group(1)).strip() if title else "unknown")
print("  context:", ctx.group(1) if ctx else "unknown")
print("  login_link_visible:", login)'

echo
echo "API:"
if [[ -n "${CANVAS_API_TOKEN:-}" ]]; then
  status="$(curl -sS -o /tmp/canvas-course-api.json -w "%{http_code}" -H "Authorization: Bearer $CANVAS_API_TOKEN" "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID" || true)"
else
  echo "  CANVAS_API_TOKEN not set; API may return 401."
  status="$(curl -sS -o /tmp/canvas-course-api.json -w "%{http_code}" "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID" || true)"
fi

echo "  course endpoint status: $status"
if [[ "$status" == "200" ]]; then
  python3 -m json.tool /tmp/canvas-course-api.json | sed -n '1,80p'
else
  sed -n '1,20p' /tmp/canvas-course-api.json 2>/dev/null || true
fi
