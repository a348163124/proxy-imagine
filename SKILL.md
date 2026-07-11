---
name: proxy-imagine
description: >
  Proxy media for Grok mid-relay sessions: text-to-image (/images/generations) and
  text/image-to-video (/videos/generations async poll). Defaults: grok-imagine-image /
  grok-imagine-video. After success: -Open, HTTPS url in reply, local relative path.
  Use when Grok-family mid-relay chat needs generate/draw image, video, 出图/画图/生成视频/短视频;
  official image_gen/image_to_video API key errors; /proxy-imagine.
  Do NOT use for Composer/non-Grok — use built-in tools there.
when-to-use: >
  Grok mid-relay session; user wants image or short video; official Imagine tools fail
  with incorrect API key; /proxy-imagine. Skip composer and non-Grok models.
---

# Proxy Imagine (image + video)

Generate **images and videos** through the user's mid-relay API — not Grok's built-in
`image_gen` / `image_to_video` (those hit official xAI and need `XAI_API_KEY`).

## Session gate (soft)

**Use when BOTH are true:**

1. Chat model is Grok-family / mid-relay (`custom-grok`, `grok-4.5`, `grok-build*`, …).
2. User wants an **image** or **video**, or ran `/proxy-imagine`.

**Skip** for Composer / non-Grok → built-in tools.

## Display limits (honest)

Shell cannot inject native Imagine media bubbles. Maximize UX with:

| Do | Don't rely on |
|----|----------------|
| `-Open` (OS viewer / player) | Bare `images/foo.jpg` as native card |
| HTTPS `url` in reply + markdown link | 100% parity with built-in Imagine UI |
| Local file under `images/` or `videos/` | |

## Resolve skill root

```powershell
$skillRoot = @(
  "$env:USERPROFILE\.grok\skills\proxy-imagine",
  "$env:USERPROFILE\.agents\skills\proxy-imagine",
  (Join-Path (Get-Location) ".agents\skills\proxy-imagine"),
  (Join-Path (Get-Location) ".grok\skills\proxy-imagine")
) | Where-Object { Test-Path (Join-Path $_ "scripts\gen-image.ps1") } | Select-Object -First 1
```

---

## A) Image generation

**Script:** `scripts/gen-image.ps1` / `gen-image.py`  
**API:** `POST {base}/v1/images/generations`  
**Default model:** `grok-imagine-image`

```powershell
& "$skillRoot\scripts\gen-image.ps1" `
  -Prompt "<visual prompt>" `
  -OutDir "images" `
  -Name "<kebab-name>" `
  -Open -Json
```

```bash
python "$SKILL_ROOT/scripts/gen-image.py" "<prompt>" --out-dir images --name <kebab> --open --json
```

Env: `GROK_API_KEY`, optional `GROK_IMAGEN_BASE_URL`, `GROK_IMAGEN_MODEL`, `GROK_IMAGEN_OUT_DIR`.

**After image:**

1. `read_file` local image (optional vision check).
2. Reply with HTTPS image URL (if present) + `` `images/<name>.jpg` ``.

---

## B) Video generation

**Script:** `scripts/gen-video.ps1` / `gen-video.py`  
**API:**

1. `POST {base}/v1/videos/generations` → `{ "request_id": "..." }`
2. Poll `GET {base}/v1/videos/{request_id}` until `status` is `done` (or url present)
3. Download `video.url` → local `.mp4`

**Default model:** `grok-imagine-video`  
**Default duration:** `6` (API often supports 6/10; **3 may stay pending** — prefer 6 unless user insists)

### Text-to-video

```powershell
& "$skillRoot\scripts\gen-video.ps1" `
  -Prompt "<motion prompt, present tense, simple action>" `
  -Duration 6 `
  -OutDir "videos" `
  -Name "<kebab-name>" `
  -Open -Json
```

### Image-to-video (preferred when a still already exists)

```powershell
& "$skillRoot\scripts\gen-video.ps1" `
  -Prompt "gentle breeze, soft blink, subtle fur motion" `
  -ImagePath "images/sunset-cat.jpg" `
  -Duration 6 `
  -OutDir "videos" `
  -Name "sunset-cat-motion" `
  -Open -Json
```

Or public still:

```powershell
-ImageUrl "https://imgen.x.ai/..."
```

Python:

```bash
python "$SKILL_ROOT/scripts/gen-video.py" "<prompt>" \
  --duration 6 --out-dir videos --name <kebab> \
  --image-path images/foo.jpg --open --json
```

Env:

| Variable | Purpose |
|----------|---------|
| `GROK_API_KEY` | Auth (shared with image) |
| `GROK_VIDEO_BASE_URL` | Override host (else same as image base) |
| `GROK_VIDEO_MODEL` | Default `grok-imagine-video` (alt: `grok-imagine-video-1.5`) |
| `GROK_VIDEO_OUT_DIR` | Default `./videos` |
| `GROK_VIDEO_API_KEY` | Optional separate key |

**Video prompt craft:** one clear motion in present tense; avoid multi-action clutter.  
If animating a still, describe **only** motion/camera, keep subject fixed.

**After video:**

1. Confirm `ok` and `bytes` > 0.
2. Reply shape:

```markdown
[在浏览器打开视频](HTTPS_VIDEO_URL)

本地：`videos/<name>.mp4`（已尝试系统播放器打开，时长约 N 秒）

<一句描述>
```

3. Do **not** call built-in `image_to_video` on mid-relay (API key fails).

**Failures:**

| Symptom | Action |
|---------|--------|
| `service_unavailable` / overloaded | Retry once after 30–60s |
| Timeout pending | Report `request_id`; try duration 6 + image-to-video |
| duration=3 stuck | Use 6; mention API may not honor 3 |

---

## Hard rules

1. Mid-relay Grok only for this skill.
2. Image → `gen-image.*`; video → `gen-video.*`.
3. Prefer **image-to-video** when user has / just generated a still of the subject.
4. Always `-Open` unless user is headless / said not to.
5. Never print API keys.
6. Prefer workspace-relative paths in the reply (`images/…`, `videos/…`) plus HTTPS.

## What this skill does not do

- Native Grok media cards via shell
- Video edit / extension endpoints (unless you add scripts later)
- Hard OS-level model filter
