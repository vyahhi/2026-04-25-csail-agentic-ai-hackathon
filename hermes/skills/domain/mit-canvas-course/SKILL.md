---
name: mit-canvas-course
description: View-only access guidance for the configured Canvas course. Use when the user asks about Canvas, assignments, modules, syllabus, announcements, or course pages.
---

# MIT Canvas Course

This Hermes install is configured for a view-only Canvas target:

- `CANVAS_BASE_URL`
- `CANVAS_COURSE_ID`
- `CANVAS_COURSE_URL`
- optional `CANVAS_API_TOKEN`

## Rules

- Treat Canvas as read-only.
- Do not submit assignments, edit pages, post comments, change grades, enroll users, or perform any state-changing action.
- Use `GET` requests only for Canvas API access.
- If `CANVAS_API_TOKEN` is absent or an API endpoint returns `401`, explain that authenticated Canvas API access requires a token and fall back to public page reads.
- Prefer the Canvas REST API when `CANVAS_API_TOKEN` exists.
- For public page reads, use `curl -Ls "$CANVAS_COURSE_URL"` and extract visible text or Canvas `ENV` metadata.
- Do not rely on hard-coded course titles, assignment names, or announcements; query Canvas when answering.

## Useful Read-Only API Calls

```bash
curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID/tabs"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID/assignments?per_page=100"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$CANVAS_COURSE_ID/modules?per_page=100"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/announcements?context_codes[]=course_$CANVAS_COURSE_ID"
```

## Helper

Run this on the Mac mini for a quick status snapshot:

```bash
~/.hermes/scripts/canvas-course-snapshot.sh
```
