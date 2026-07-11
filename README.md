# proxy-imagine

Agent skill: generate and **edit images**, and generate **videos**, via an OpenAI/xAI-compatible
**mid-relay** instead of Grok’s built-in `image_gen` / `image_edit` / `image_to_video`
(official-only auth).

| Kind | Endpoint | Default model | Script |
|------|----------|---------------|--------|
| Image | `POST /v1/images/generations` | `grok-imagine-image` | `scripts/gen-image.ps1` / `.py` |
| Edit | `POST /v1/images/edits` (JSON) | `grok-imagine-image-quality` | `scripts/gen-edit.ps1` / `.py` |
| Video | `POST /v1/videos/generations` + poll `GET /v1/videos/{id}` | `grok-imagine-video` | `scripts/gen-video.ps1` / `.py` |

- Soft gate: **Grok-family / mid-relay** chat; skip Composer / non-Grok
- After generate: prefer `-Open`, HTTPS URL in reply, local relative path
- No API keys in the repo — uses `GROK_API_KEY` (and optional `GROK_*` overrides)
- **Edits use JSON** (`image.url` + `type: image_url`), not OpenAI multipart form-data

## Layout

```text
proxy-imagine/
  SKILL.md
  scripts/
    gen-image.ps1 / gen-image.py
    gen-edit.ps1  / gen-edit.py
    gen-video.ps1 / gen-video.py
  README.md
```

## Install

```bash
npx skills add a348163124/proxy-imagine -g -y
# or
npx skills add https://github.com/a348163124/proxy-imagine -g -y
```

## Image

```powershell
.\scripts\gen-image.ps1 -Prompt "a red lantern watercolor" -OutDir images -Name lantern -Open -Json
```

```bash
python scripts/gen-image.py "a red lantern watercolor" --out-dir images --name lantern --open --json
```

## Image edit

Local file (encoded as `data:` URI automatically):

```powershell
.\scripts\gen-edit.ps1 `
  -Prompt "pencil sketch with detailed shading" `
  -ImagePath .\images\sunset-cat.jpg `
  -OutDir images -Name sunset-cat-sketch -Open -Json
```

Public URL:

```powershell
.\scripts\gen-edit.ps1 `
  -Prompt "make it a rainy night scene" `
  -ImageUrl "https://example.com/cat.jpg" `
  -Name cat-rain -Open -Json
```

```bash
python scripts/gen-edit.py "pencil sketch with detailed shading" \
  --image-path images/sunset-cat.jpg --out-dir images --name sunset-cat-sketch --open --json
```

Override model if the relay catalog differs:

```powershell
.\scripts\gen-edit.ps1 -Prompt "..." -ImagePath .\images\x.jpg -Model grok-imagine-image -Json
```

## Video

Text-to-video:

```powershell
.\scripts\gen-video.ps1 -Prompt "cat on windowsill at sunset, soft fur motion" -Duration 6 -OutDir videos -Name cat -Open -Json
```

Image-to-video (recommended when you have a still):

```powershell
.\scripts\gen-video.ps1 `
  -Prompt "gentle breeze, subtle blink" `
  -ImagePath .\images\sunset-cat.jpg `
  -Duration 6 -OutDir videos -Name cat-motion -Open -Json
```

```bash
python scripts/gen-video.py "gentle breeze, subtle blink" \
  --image-path images/sunset-cat.jpg --duration 6 --out-dir videos --name cat-motion --open --json
```

**Note:** Duration is often **6 or 10** seconds on the backend. Requests for 3s may stay `pending`.

## Environment

| Variable | Purpose |
|----------|---------|
| `GROK_API_KEY` | Bearer token |
| `GROK_IMAGEN_BASE_URL` / `GROK_EDIT_BASE_URL` / `GROK_VIDEO_BASE_URL` | Proxy host |
| `GROK_IMAGEN_MODEL` | Image model (default `grok-imagine-image`) |
| `GROK_EDIT_MODEL` | Edit model (default `grok-imagine-image-quality`) |
| `GROK_VIDEO_MODEL` | Video model (default `grok-imagine-video`) |
| `GROK_IMAGEN_OUT_DIR` / `GROK_EDIT_OUT_DIR` / `GROK_VIDEO_OUT_DIR` | Output dirs |

## License

MIT (or your choice when publishing).
