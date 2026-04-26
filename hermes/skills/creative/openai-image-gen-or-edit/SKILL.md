---
name: openai-image-gen-or-edit
description: Use Hermes' existing OpenAI OAuth auth to perform high-quality image generation or faithful image-to-image edits with OpenAI image models when the built-in image_generate path is insufficient or when you want explicit control.
---

# OpenAI Image Generation or Editing

Use this skill when the user wants either:
1. **text-to-image generation** with explicit OpenAI image-model control, or
2. **image-to-image editing** that must preserve the exact source image composition.

This skill replaces the narrower image-edit-only workflow. It covers both generation and editing.

## When to use

Trigger this skill when one or more of these are true:
1. The user wants a faithful transformation of an existing image, not just a descriptive redraw.
2. The user wants explicit OpenAI image-model control rather than relying on Hermes' default `image_generate` routing.
3. Hermes has `openai-codex` auth available (`hermes auth list openai-codex`).
4. The task fits OpenAI image generation through the ChatGPT/Codex-backed path already configured on this machine.

Common editing examples:
- "Turn this exact photo into coloring book line art"
- "Edit this image to remove the background"
- "Keep the same composition but restyle it"
- "Use the image as a seed/reference, not just a prompt"

Common generation examples:
- "Generate a poster in this style"
- "Make a diagram cover image"
- "Create a high-quality product mockup"
- "Generate a photorealistic scene from this description"

## Key finding

Hermes' built-in `image_generate` tool may be configured to use OpenAI for **text-to-image**, but it is still **prompt-only** and does not expose the full direct workflow documented here. For true image editing — and for explicit direct OpenAI image generation control — call the OpenAI Python SDK directly from `terminal()` using the existing OAuth-backed path.

## Image model used

The image-generation/editing tool model is:

- **`gpt-image-2`**

The orchestration/reasoning model in the example workflow is:

- **`gpt-5.5`**

## Preconditions

1. Check auth availability:

```bash
hermes auth list openai-codex
```

2. Confirm Hermes source checkout + venv path if needed:
- common repo: `~/.hermes/hermes-agent`
- common venv: `~/.hermes/hermes-agent/venv`

3. Verify the venv has `openai` installed.
4. Verify a usable OAuth token can be read via Hermes internals.

## Working approach

Use the Hermes repo venv and import these helpers:

```python
from agent.auxiliary_client import _read_codex_access_token, _codex_cloudflare_headers
import openai
```

Construct the client like this:

```python
client = openai.OpenAI(
    api_key=token,
    base_url='https://chatgpt.com/backend-api/codex',
    default_headers=_codex_cloudflare_headers(token),
)
```

Despite the helper names containing `codex`, this path is being used here as the already-configured OAuth transport for OpenAI image generation/editing. The user-facing skill name should stay model/task-oriented, not transport-oriented.

## Auth / billing note

On this machine, this workflow uses Hermes' `openai-codex` OAuth path rather than a separate `OPENAI_API_KEY`.

Practical implication:

- it is typically using the existing ChatGPT/Codex subscription/auth path
- it is not the normal pay-per-call OpenAI API-key flow

However, do not overstate this. Treat it as "likely covered by the existing subscription/auth path, subject to whatever quotas, throttling, or feature limits OpenAI applies." If the user asks whether it is subscription-backed, say that the auth path confirms OAuth-backed ChatGPT/Codex usage, but billing details still ultimately depend on OpenAI account terms.

## Minimal text-to-image script pattern

Run from the Hermes repo with the repo venv activated.

```bash
source ~/.hermes/hermes-agent/venv/bin/activate && python - <<'PY'
from agent.auxiliary_client import _read_codex_access_token, _codex_cloudflare_headers
from pathlib import Path
import base64, openai

out = Path('/tmp/output.png')
prompt = 'A clean modern poster illustration of autonomous agents coordinating tools, MIT-inspired but not using MIT logos.'

token = _read_codex_access_token()
client = openai.OpenAI(
    api_key=token,
    base_url='https://chatgpt.com/backend-api/codex',
    default_headers=_codex_cloudflare_headers(token),
)

image_b64_out = None
with client.responses.stream(
    model='gpt-5.5',
    store=False,
    instructions='You must fulfill image-generation requests by using the image_generation tool.',
    input=[{
        'type': 'message',
        'role': 'user',
        'content': [
            {'type': 'input_text', 'text': prompt},
        ],
    }],
    tools=[{
        'type': 'image_generation',
        'model': 'gpt-image-2',
        'size': '1024x1024',
        'quality': 'high',
        'output_format': 'png',
        'background': 'opaque',
        'partial_images': 1,
    }],
    tool_choice={
        'type': 'allowed_tools',
        'mode': 'required',
        'tools': [{'type': 'image_generation'}],
    },
) as stream:
    for event in stream:
        et = getattr(event, 'type', '')
        if et == 'response.output_item.done':
            item = getattr(event, 'item', None)
            if getattr(item, 'type', None) == 'image_generation_call':
                result = getattr(item, 'result', None)
                if isinstance(result, str) and result:
                    image_b64_out = result
        elif et == 'response.image_generation_call.partial_image':
            partial = getattr(event, 'partial_image_b64', None)
            if isinstance(partial, str) and partial:
                image_b64_out = partial
    final = stream.get_final_response()

if not image_b64_out:
    for item in getattr(final, 'output', None) or []:
        if getattr(item, 'type', None) == 'image_generation_call':
            result = getattr(item, 'result', None)
            if isinstance(result, str) and result:
                image_b64_out = result
                break

if not image_b64_out:
    raise RuntimeError(f'No image returned. Final output: {getattr(final, "output", None)!r}')

out.write_bytes(base64.b64decode(image_b64_out))
print(out)
PY
```

## Minimal image-edit script pattern

Run from the Hermes repo with the repo venv activated.

```bash
source ~/.hermes/hermes-agent/venv/bin/activate && python - <<'PY'
from agent.auxiliary_client import _read_codex_access_token, _codex_cloudflare_headers
from pathlib import Path
import base64, openai

src = Path('/absolute/path/to/input.jpg')
out = Path('/tmp/output.png')

mime = 'image/jpeg'  # use image/png for PNG input
img_b64 = base64.b64encode(src.read_bytes()).decode('ascii')
image_url = f'data:{mime};base64,{img_b64}'

prompt = (
    'Transform this exact image while preserving composition and major objects. '
    'Return clean black-and-white coloring-book line art only.'
)

token = _read_codex_access_token()
client = openai.OpenAI(
    api_key=token,
    base_url='https://chatgpt.com/backend-api/codex',
    default_headers=_codex_cloudflare_headers(token),
)

image_b64_out = None
with client.responses.stream(
    model='gpt-5.5',
    store=False,
    instructions='You must fulfill image editing requests by using the image_generation tool when provided an input image.',
    input=[{
        'type': 'message',
        'role': 'user',
        'content': [
            {'type': 'input_text', 'text': prompt},
            {'type': 'input_image', 'image_url': image_url},
        ],
    }],
    tools=[{
        'type': 'image_generation',
        'model': 'gpt-image-2',
        'size': '1024x1536',
        'quality': 'high',
        'output_format': 'png',
        'background': 'opaque',
        'partial_images': 1,
    }],
    tool_choice={
        'type': 'allowed_tools',
        'mode': 'required',
        'tools': [{'type': 'image_generation'}],
    },
) as stream:
    for event in stream:
        et = getattr(event, 'type', '')
        if et == 'response.output_item.done':
            item = getattr(event, 'item', None)
            if getattr(item, 'type', None) == 'image_generation_call':
                result = getattr(item, 'result', None)
                if isinstance(result, str) and result:
                    image_b64_out = result
        elif et == 'response.image_generation_call.partial_image':
            partial = getattr(event, 'partial_image_b64', None)
            if isinstance(partial, str) and partial:
                image_b64_out = partial
    final = stream.get_final_response()

if not image_b64_out:
    for item in getattr(final, 'output', None) or []:
        if getattr(item, 'type', None) == 'image_generation_call':
            result = getattr(item, 'result', None)
            if isinstance(result, str) and result:
                image_b64_out = result
                break

if not image_b64_out:
    raise RuntimeError(f'No image returned. Final output: {getattr(final, "output", None)!r}')

out.write_bytes(base64.b64decode(image_b64_out))
print(out)
PY
```

## Prompting guidance

For faithful edits, explicitly say:
- preserve the **exact composition**
- preserve **camera angle / perspective**
- preserve **subject pose and placement**
- preserve **major objects and background layout**
- do **not invent a new scene**
- specify the target style exactly

For generation, explicitly say:
- desired visual style
- subject and composition
- lighting
- color palette
- aspect ratio or intended use
- any exclusions (logos, text, artifacts, watermarks)

For coloring-book conversions, ask for:
- clean black-and-white line art
- white background
- no grayscale
- no shading
- no large black fills except outlines
- clear enclosed shapes suitable for coloring

## Output verification

After generation or editing:
1. Save to an absolute local path.
2. Use `vision_analyze` on the output when visual QA matters.
3. Check both:
   - fidelity to the user request
   - suitability for the requested output style
4. For edits specifically, also check fidelity to the source composition.

## Speed / optimization guidance

- Do **not** run `vision_analyze` on the source image unless it is actually needed for prompt refinement, ambiguity resolution, or debugging.
- If the user already supplied the image and the transformation goal is clear, go straight to the direct OpenAI image-edit script.
- Keep `vision_analyze` primarily for **post-generation QA** on the output image.
- If the built-in `image_generate` tool is sufficient and no exact-source editing is required, it may still be the faster default path.
- Prefer this skill when the user wants either exact-source editing or explicit direct control over the OpenAI image workflow.

## Optional config note

If the user wants Hermes to prefer OpenAI for ordinary prompt-only image generation too, a config like this may be relevant:

```yaml
image_gen:
  provider: openai-codex
  model: gpt-image-2-high
```

This improves the default text-to-image backend, but does **not** by itself enable true image editing through the built-in `image_generate` tool.

## Pitfalls

- `image_generate` may still be prompt-only even when OpenAI is configured.
- The system Python may not have `openai`; use the Hermes repo venv.
- `openai.OpenAI()` without a token will fail immediately.
- Use Hermes helper functions for OAuth token + headers; do not guess headers manually.
- If you only inspect partial stream events, you can miss the final image; also sweep `final.output` after `get_final_response()`.
- Use absolute input/output paths.
- Tell the user clearly whether the result was created from the actual source image or from a descriptive redraw.

## Fast diagnosis checklist

```bash
hermes auth list openai-codex
source ~/.hermes/hermes-agent/venv/bin/activate
python - <<'PY'
from agent.auxiliary_client import _read_codex_access_token
print(bool(_read_codex_access_token()))
PY
```

If all of the above work, proceed with the direct OpenAI image generation/editing script.
