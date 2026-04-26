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

curl -fsS -H "Authorization: Bearer $CANVAS_API_TOKEN" \
  "$CANVAS_BASE_URL/api/v1/courses/$COURSE_ID/assignments/$ASSIGNMENT_ID/submissions?per_page=100&include[]=user"
```

## Practical pattern: check who missed a quiz or assignment

When the user asks who missed a quiz, who is unsubmitted, or whether draft email recipients match Canvas status:

1. Discover the active course dynamically.
2. List assignments and identify the right quiz/assignment by name.
3. Fetch submissions with `include[]=user` so names and login IDs come back in one read-only call.
4. Treat `workflow_state == "unsubmitted"` or `missing == true` as the current missing list.
5. Return the concrete recipient list as `Name — login_id` so it can be compared against an email draft.

This is useful for course-ops tasks like drafting outreach to students who missed a quiz or verifying retake email recipient lists.

## Announcement drafting constraint discovered on MIT Canvas

When working in the Canvas web UI for course announcements, the compose page may be:

```text
/courses/<COURSE_ID>/discussion_topics/new?is_announcement=true
```

Observed behavior on MIT Canvas:

- the compose form can be opened and populated in-browser
- visible actions were `Cancel` and `Publish`
- no `Save Draft` / `Save` control was exposed in the UI or obvious DOM controls

Practical implication:

- if the user asks for an announcement draft directly on Canvas, the safest achievable state may be a pre-filled, unsubmitted compose form rather than a true server-side draft
- do not click `Publish` unless the user explicitly asks for publication
- be explicit that the compose URL is not evidence of a persisted draft object

## Browser UI authoring notes for announcements

Use these only when the user explicitly requests a state-changing action in the Canvas web UI. The API guidance above remains read-only.

Observed implementation details on MIT Canvas:

- title field selector: `#TextInput___0`
- hidden textarea selector: `#discussion-topic-message-body`
- rich text editor content is also mirrored in the editor iframe / RCE surface
- Canvas may use controlled React-style inputs, so simple DOM assignment can appear to work and still fail validation on submit

Reliable pattern:

1. Set the title with the native HTMLInputElement value setter, then dispatch `input`, `change`, and `blur`.
2. Set the hidden textarea with the native HTMLTextAreaElement value setter, then dispatch `input` and `change`.
3. If the rich text editor iframe is present, mirror the body text there as well.
4. Re-read the field values before clicking `Publish`.
5. After publishing, verify success by checking that the URL changes from `/discussion_topics/new?is_announcement=true` to a concrete discussion topic URL like `/discussion_topics/<id>?is_announcement=true` and that the page shows the posted announcement.

Important failure mode observed:

- Clicking `Publish` after only superficial field assignment produced a validation error (`Title must not be empty`) even though the form had looked filled in. Re-applying the title/body with native setters and events fixed it.

## Helper

Run this on the Mac mini for a quick status snapshot:

```bash
~/.hermes/scripts/canvas-course-snapshot.sh
```
