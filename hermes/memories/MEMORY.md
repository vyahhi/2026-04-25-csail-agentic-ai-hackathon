# Persistent Notes

- Canvas API access is configured in ~/.hermes/.env with CANVAS_BASE_URL, CANVAS_COURSE_ID, CANVAS_COURSE_URL, and CANVAS_API_TOKEN.
- Canvas access is read-only unless the user explicitly asks to change this policy; use GET requests only.
- When asked about Canvas content, discover current data from Canvas API GET endpoints or ~/.hermes/scripts/canvas-course-snapshot.sh instead of relying on saved course facts.
