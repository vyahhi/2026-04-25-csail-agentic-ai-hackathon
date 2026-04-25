---
name: openai-image-edit-via-codex
description: Use Hermes' existing OpenAI Codex OAuth auth to perform true image-to-image edits with gpt-image-2 when the built-in image_generate tool is prompt-only.
---

# OpenAI Image Edit via Codex

Use this skill when the user wants an image transformed *from the exact source image* (for example: "make this exact photo a coloring book page") and Hermes' built-in `image_generate` tool is insufficient because it only accepts text prompts.

## When to use

Trigger this skill when all of these are true:
1. The user wants a faithful transformation of an existing image, not a new image from description.
2. Hermes has `openai-codex` auth available (`hermes auth list openai-codex`).
3. The task can be done through OpenAI/Codex image generation with an input image.

Common examples:
- "Turn this exact photo into coloring book line art"
- "Edit this image to remove the background"
- "Keep the same composition but restyle it"
- "Use the image as a seed/reference, not just a prompt"

## Key finding

Hermes' built-in `image_generate` tool may be configured to use OpenAI/Codex for **text-to-image**, but it is still **prompt-only**. For true image editing, call the OpenAI Python SDK directly from `terminal()` using the Codex OAuth token and the ChatGPT/Codex Responses API `image_generation` tool.

## Preconditions

1. Load Hermes environment facts:
   - `hermes auth list openai-codex`
   - `hermes config path`
   - optionally inspect `~/.hermes/config.yaml`
2. Confirm Hermes source checkout + venv path if needed:
   - common repo: `~/.hermes/hermes-agent`
   - common venv: `~/.hermes/hermes-agent/venv`
3. Verify the venv has `openai` installed.
4. Verify a usable Codex token can be read via Hermes internals.

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

## Minimal image-edit script pattern

Run from the Hermes repo with the repo venv activated.

```bash
source /Users/nicolaw/.hermes/hermes-agent/venv/bin/activate && python - <<'PY'
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
    model='gpt-5.4',
    store=False,
    instructions='You must fulfill image editing requests by using the image_generation tool when provided.',
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

For coloring-book conversions, ask for:
- clean black-and-white line art
- white background
- no grayscale
- no shading
- no large black fills except outlines
- clear enclosed shapes suitable for coloring

## Output verification

After generation:
1. Save to an absolute local path.
2. Use `vision_analyze` on the output.
3. Check both:
   - fidelity to the source composition
   - suitability for the requested transformed style

## Speed / Optimization Guidance

For repeated workflows like "same, coloring page and print in stata":
- Do not run `vision_analyze` on the source image unless it is actually needed for prompt refinement, ambiguity resolution, or debugging.
- If the user already supplied the image and the transformation goal is clear, go straight to the Codex image-edit script.
- Keep `vision_analyze` primarily for post-generation QA on the output image.
- If the print helper fails, use the existing CDP fallback only after the normal browser helper path fails.

This means the fast path is usually:
1. image edit via Codex
2. output QA with `vision_analyze`
3. print via browser helper
4. CDP recovery only if needed

Suggested verification questions:
- "Is this a faithful coloring-book conversion of the original photo?"
- "Is this clean black-and-white line art suitable for coloring?"

Important: `vision_analyze` here is for QA only, not for generation. If the user asks whether you used image editing versus description-based redraw, state this explicitly: the transformation was produced from the source image by the Codex/OpenAI image-edit flow, while `vision_analyze` was only used to inspect the source or verify the result.

## Optional config improvement

If the user wants Hermes to prefer OpenAI/Codex for ordinary image generation too, set:

```yaml
image_gen:
  provider: openai-codex
  model: gpt-image-2-high
```

in `~/.hermes/config.yaml`.

This improves the default text-to-image backend, but does **not** by itself enable image editing through the built-in `image_generate` tool.

## Pitfalls

- `image_generate` may still be prompt-only even when OpenAI/Codex is configured.
- The system Python may not have `openai`; use Hermes repo venv.
- `openai.OpenAI()` without a token will fail immediately.
- Use Hermes helper functions for Codex token + headers; do not guess headers manually.
- If you only inspect partial stream events, you can miss the final image; also sweep `final.output` after `get_final_response()`.
- Use absolute input/output paths.
- Tell the user clearly whether the result was created from the actual source image or from a descriptive redraw.

## Fast diagnosis checklist

```bash
hermes auth list openai-codex
hermes config path
source ~/.hermes/hermes-agent/venv/bin/activate
python - <<'PY'
from agent.auxiliary_client import _read_codex_access_token
print(bool(_read_codex_access_token()))
PY
```

If all of the above work, proceed with the direct Codex image-edit script.
