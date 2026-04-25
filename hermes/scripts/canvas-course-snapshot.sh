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

echo "Canvas API course discovery:"
if [[ -z "${CANVAS_API_TOKEN:-}" ]]; then
  echo "  CANVAS_API_TOKEN not set; cannot list enrolled courses dynamically."
  exit 0
fi

status="$(curl -sS -o /tmp/canvas-course-api.json -w "%{http_code}" -H "Authorization: Bearer $CANVAS_API_TOKEN" "$CANVAS_BASE_URL/api/v1/courses?per_page=100&enrollment_state=active" || true)"
echo "  course list endpoint status: $status"
if [[ "$status" == "200" ]]; then
  python3 - <<'PY'
import json
from pathlib import Path

items = json.loads(Path("/tmp/canvas-course-api.json").read_text())
for item in items[:20]:
    print(f"- {item.get('id')}: {item.get('name')} [{item.get('course_code')}]")
PY
  echo
  echo "Use a discovered course ID with:"
  echo "  $CANVAS_BASE_URL/api/v1/courses/<COURSE_ID>"
else
  sed -n '1,20p' /tmp/canvas-course-api.json 2>/dev/null || true
fi
