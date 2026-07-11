---
name: proxy-imagine
description: >
  Proxy text-to-image for Grok mid-relay sessions only. Calls OpenAI-compatible
  /v1/images/generations (default model grok-imagine-image) instead of built-in image_gen.
  After generation: MUST read_file the saved image for in-session preview, then reply with a
  clickable workspace-relative path (e.g. images/foo.jpg).
  Use when the active chat model is Grok-family (custom-grok, grok-4.5, grok-build, grok-4*,
  or any [model.*] pointing at a non-xAI base_url) AND the user wants generate/draw/create
  an image, illustration, poster, scene; image_gen fails with incorrect API key; /proxy-imagine;
  出图/画图/生成图片/插图. Do NOT use when the session model is Composer, Cursor composer,
  or other non-Grok models — use built-in image_gen there instead.
when-to-use: >
  Active model is Grok-family or custom-grok mid-relay; user asks to generate or draw an image;
  official image_gen API key error on proxy setups; /proxy-imagine. Skip for composer-2.5,
  grok-composer*, non-Grok providers, or when user explicitly wants official xAI Imagine.
---

# Proxy Imagine

Route image generation through the user's **proxy API**, not Grok's built-in `image_gen`.

Built-in `image_gen` always authenticates against official xAI and **cannot** use custom `base_url`.
This skill is the equivalent path when **chat is already on a Grok mid-relay**.

Shell download ≠ native Imagine media pipeline. To get as close as possible to in-window display:

1. Save under the **workspace** `images/` folder.
2. **`read_file` the image file** so Grok can show a multimodal preview.
3. Reply with a **short workspace-relative markdown link** (not a long absolute path).

## Session gate (soft — check before acting)

**Use this skill only when BOTH are true:**

1. **Chat model is Grok-family** — e.g. `custom-grok`, `grok-4.5`, `grok-4*`, `grok-build*`,
   or a custom `[model.*]` whose underlying id/name is Grok and whose `base_url` is a mid-relay.
2. **User wants an image** (generate / draw / 出图 / 插图 / poster / scene, etc.), **or** they ran `/proxy-imagine`.

**Do NOT use this skill when:**

| Situation | Instead |
|-----------|---------|
| Session model is **Composer** / `grok-composer*` / Cursor composer / other non-Grok | Built-in `image_gen` |
| User explicitly wants **official xAI Imagine** | Built-in `image_gen` |
| Unsure of current model and it is clearly non-Grok | Built-in `image_gen` |
| Only video / reference image-edit is needed | Official tools or say unsupported on proxy |

Heuristics if the active model id is not printed in context:

- Default config on this machine is often `custom-grok` → **proxy skill applies**
- Names containing `composer` (and not a Grok chat id) → **skip this skill**
- User says they switched to Composer / non-Grok → **skip this skill**

This gate is **soft**. The platform does not hard-filter skills by model id.

## Hard rules (when the gate passes)

1. **Do not call** built-in `image_gen` / `image_edit` (unless the user insists on the official path).
2. Run the script via the shell; write under workspace **`images/`** (create if needed).
3. **After a successful save, you MUST `read_file` the image** (the actual `.jpg` / `.png` path).  
   This loads the pixels into the session so the UI can show a preview — **do not skip**.
4. In the final user-visible reply:
   - Lead with a **workspace-relative** markdown link, e.g. `[images/suzhou-bay-sunset.jpg](images/suzhou-bay-sunset.jpg)`  
     or bare `` `images/suzhou-bay-sunset.jpg` `` (prefer the link form).
   - **Do not** put only a long absolute path like `C:\Users\...` as the primary link.
   - One short line describing the image is enough.
5. Never print API keys. JSON from the script may include `path` / `url` / `model` only.

## Default endpoint

| Setting | Default / resolution order |
|---------|----------------------------|
| Base URL | `GROK_IMAGEN_BASE_URL` → `PROXY_IMAGEN_BASE_URL` → `https://codexone.aieania.tech` |
| API key | `GROK_IMAGEN_API_KEY` → `PROXY_IMAGEN_API_KEY` → `GROK_API_KEY` → `XAI_API_KEY` |
| Model | `GROK_IMAGEN_MODEL` → `PROXY_IMAGEN_MODEL` → `grok-imagine-image` |
| Output dir | `GROK_IMAGEN_OUT_DIR` → `PROXY_IMAGEN_OUT_DIR` → **`./images` under workspace CWD** |

Image **API** model is the Imagine id (`grok-imagine-image` by default), **not** the chat model id.

Script directory: `<this-skill>/scripts/` next to this `SKILL.md`.

```powershell
$skillRoot = @(
  "$env:USERPROFILE\.grok\skills\proxy-imagine",
  "$env:USERPROFILE\.agents\skills\proxy-imagine",
  (Join-Path (Get-Location) ".agents\skills\proxy-imagine"),
  (Join-Path (Get-Location) ".grok\skills\proxy-imagine")
) | Where-Object { Test-Path (Join-Path $_ "scripts\gen-image.ps1") } | Select-Object -First 1
```

## Generate (prefer PowerShell on Windows)

Always use **workspace-relative** `OutDir` `images` so links stay short:

```powershell
& "$skillRoot\scripts\gen-image.ps1" `
  -Prompt "<full English or bilingual visual prompt>" `
  -OutDir "images" `
  -Name "<short-kebab-name>" `
  -Json
```

Python:

```bash
python "$SKILL_ROOT/scripts/gen-image.py" \
  "<prompt>" --out-dir images --name "<short-kebab-name>" --json
```

Parse JSON `path` (or stdout path). Convert to workspace-relative form when needed  
(e.g. if absolute, strip the CWD prefix → `images/<name>.jpg`).

## Prompt craft

Write a **complete** visual prompt (2–5 sentences):

- subject → setting → style → composition → lighting/mood
- Concrete detail; positive description
- Landscape → wide composition; portraits → subject framing

Craft the prompt yourself, then pass it to the script.

## Workflow (complete only when every step is done)

1. **Pass the session gate.** If not Grok mid-relay → use `image_gen` instead; stop.
2. Craft the visual prompt.
3. Pick a short kebab `Name` (ASCII), e.g. `suzhou-bay-sunset`.
4. Run the script with `-OutDir "images"` (workspace CWD).
5. Confirm file exists and size > 0 (from JSON `bytes` or filesystem).
6. **Required:** call **`read_file`** on the saved image path (relative preferred: `images/<name>.jpg`).
7. **Required final reply format:**

```markdown
已生成：[images/<name>.jpg](images/<name>.jpg)

<一句画面描述>
```

Do **not** finish the turn after only printing the shell JSON.  
Skipping `read_file` = incomplete (user will not get in-window preview).

## Failure handling

| Symptom | Action |
|---------|--------|
| Gate fails (non-Grok session) | Use built-in `image_gen`; do not run the script |
| No API key | Tell user to set `GROK_API_KEY` (or `GROK_IMAGEN_API_KEY`) |
| HTTP 401/403 | Key invalid for this proxy |
| HTTP 404 on endpoint | Adjust `GROK_IMAGEN_BASE_URL` |
| Timeout | Retry once; then report proxy issue |
| `read_file` fails on image | Retry once with absolute path; still give relative link if file exists |
| Built-in `image_gen` 400 incorrect API key on Grok mid-relay | Expected — use **this** skill |

## Optional overrides

```powershell
$env:GROK_IMAGEN_BASE_URL = "https://codexone.aieania.tech"
$env:GROK_IMAGEN_MODEL = "grok-imagine-image"
$env:GROK_IMAGEN_API_KEY = $env:GROK_API_KEY
```

## What this skill does not do

- 100% identical native Imagine media bubble (shell tools cannot attach that channel)
- Hard OS-level filter by active model id
- Video generation / reference image-edit on the proxy path (unless proxy adds APIs later)
