---
name: mit-canvas-course
description: View-only access guidance for MIT Canvas. Use when the user asks about Canvas, courses, assignments, modules, syllabus, announcements, or course pages.
---

# MIT Canvas

This Hermes install is configured for view-only Canvas access:

- `CANVAS_BASE_URL`
- optional `CANVAS_API_TOKEN`

## Rules

- Treat Canvas as read-only.
- Do not submit assignments, edit pages, post comments, change grades, enroll users, or perform any state-changing action.
- Use `GET` requests only for Canvas API access.
- If `CANVAS_API_TOKEN` is absent or an API endpoint returns `401`, explain that authenticated Canvas API access requires a token.
- Prefer the Canvas REST API when `CANVAS_API_TOKEN` exists.
- Discover the user's current courses dynamically before answering course-specific questions.
- Do not assume one fixed course ID or URL.
- For public page reads, only use a course URL the user provided in the current request.
- Do not rely on hard-coded course titles, assignment names, or announcements; query Canvas when answering.

## Useful Read-Only API Calls

```bash
curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses?per_page=100&enrollment_state=active"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$COURSE_ID"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$COURSE_ID/tabs"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$COURSE_ID/assignments?per_page=100"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$COURSE_ID/modules?per_page=100"

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/announcements?context_codes[]=course_$COURSE_ID"
```

## Helper

Run this on the Mac mini for a quick status snapshot:

```bash
~/.hermes/scripts/canvas-course-snapshot.sh
```
