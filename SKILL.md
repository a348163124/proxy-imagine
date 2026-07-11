---
name: proxy-imagine
description: >
  Proxy text-to-image for Grok mid-relay sessions only. Calls OpenAI-compatible
  /v1/images/generations (default model grok-imagine-image) instead of built-in image_gen.
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

## Session gate (soft — check before acting)

**Use this skill only when BOTH are true:**

1. **Chat model is Grok-family** — e.g. `custom-grok`, `grok-4.5`, `grok-4*`, `grok-build*`,
   or a custom `[model.*]` whose underlying id/name is Grok and whose `base_url` is a mid-relay
   (not pure official session-only without proxy).
2. **User wants an image** (generate / draw / 出图 / 插图 / poster / scene, etc.), **or** they ran `/proxy-imagine`.

**Do NOT use this skill when:**

| Situation | Instead |
|-----------|---------|
| Session model is **Composer** / `grok-composer*` / Cursor composer / other non-Grok | Built-in `image_gen` (or that stack's normal image path) |
| User explicitly wants **official xAI Imagine** | Built-in `image_gen` |
| Unsure of current model and it is clearly non-Grok | Built-in `image_gen` |
| Only video / reference image-edit is needed | Official tools or say unsupported on proxy |

Heuristics if the active model id is not printed in context:

- Default config on this machine is often `custom-grok` → **proxy skill applies**
- Names containing `composer` (and not a Grok chat id) → **skip this skill**
- User says they switched to Composer / non-Grok → **skip this skill**

This gate is **soft** (description + instructions). The platform does not hard-filter skills by model id.

## Hard rule (when the gate passes)

1. **Do not call** built-in `image_gen` / `image_edit` (unless the user insists on the official path).
2. Run the script below via the shell.
3. After success, tell the user the **local relative path** (e.g. `images/foo.jpg`) so it can open as a link.

## Default endpoint (this machine)

| Setting | Default / resolution order |
|---------|----------------------------|
| Base URL | `GROK_IMAGEN_BASE_URL` → `PROXY_IMAGEN_BASE_URL` → `ANTHROPIC_BASE_URL` → `https://codexone.aieania.tech` |
| API key | `GROK_IMAGEN_API_KEY` → `PROXY_IMAGEN_API_KEY` → `GROK_API_KEY` → `THIRD_PARTY_API_KEY` → `XAI_API_KEY` |
| Model | `GROK_IMAGEN_MODEL` → `PROXY_IMAGEN_MODEL` → `grok-imagine-image` |
| Output dir | `GROK_IMAGEN_OUT_DIR` → `PROXY_IMAGEN_OUT_DIR` → `./images` under CWD |

Image **API** model is always the Imagine id (`grok-imagine-image` by default), **not** the chat model id (`grok-4.5` / `custom-grok`).

Script directory: `<this-skill>/scripts/` next to this `SKILL.md`
(common installs: `~/.grok/skills/proxy-imagine/`, `~/.agents/skills/proxy-imagine/`,
`<repo>/.agents/skills/proxy-imagine/`).

Resolve the skill root first (do not hardcode a username path):

```powershell
# Prefer the path of this skill if known; else search common roots
$skillRoot = @(
  "$env:USERPROFILE\.grok\skills\proxy-imagine",
  "$env:USERPROFILE\.agents\skills\proxy-imagine",
  (Join-Path (Get-Location) ".agents\skills\proxy-imagine"),
  (Join-Path (Get-Location) ".grok\skills\proxy-imagine")
) | Where-Object { Test-Path (Join-Path $_ "scripts\gen-image.ps1") } | Select-Object -First 1
```

## Generate (prefer PowerShell on Windows)

```powershell
& "$skillRoot\scripts\gen-image.ps1" `
  -Prompt "<full English or bilingual visual prompt>" `
  -OutDir "images" `
  -Name "<short-kebab-name>" `
  -Json
```

Cross-platform Python alternative:

```bash
python "$SKILL_ROOT/scripts/gen-image.py" \
  "<prompt>" --out-dir images --name "<short-kebab-name>" --json
```

`-Json` / `--json` prints path, model, endpoint (never the API key). Without JSON flags, stdout is only the saved file path.

## Prompt craft

Write a **complete** visual prompt in the script argument (2–5 sentences of natural prose):

- subject → setting → style → composition → lighting/mood
- Prefer concrete detail over keyword spam
- Landscape → wide composition; portraits → subject framing
- Real places → name + distinctive landmarks when known

Craft the prompt yourself, then pass it to the script.

## Workflow

1. **Pass the session gate** (Grok-family mid-relay). If not, stop and use `image_gen` instead.
2. Craft the visual prompt from the user request.
3. Pick a short kebab `Name` (ASCII), e.g. `suzhou-bay-sunset`.
4. Run the script with `OutDir` = project `images`.
5. Confirm the file exists (size > 0).
6. Reply with path + one-line description. Optionally `read_file` the image to verify.

## Failure handling

| Symptom | Action |
|---------|--------|
| Gate fails (non-Grok session) | Use built-in `image_gen`; do not run the script |
| No API key | Tell user to set `GROK_API_KEY` (or `GROK_IMAGEN_API_KEY`) |
| HTTP 401/403 | Key invalid for this proxy |
| HTTP 404 on endpoint | Adjust `GROK_IMAGEN_BASE_URL` |
| Timeout | Retry once; then report proxy issue |
| Built-in `image_gen` 400 incorrect API key on Grok mid-relay | Expected — use **this** skill |

## Optional overrides

```powershell
$env:GROK_IMAGEN_BASE_URL = "https://codexone.aieania.tech"
$env:GROK_IMAGEN_MODEL = "grok-imagine-image"
$env:GROK_IMAGEN_API_KEY = $env:GROK_API_KEY
```

## What this skill does not do

- Hard OS-level filter by active model id (soft instructions only)
- Video generation (`image_to_video`) on the proxy path
- Image edit with reference uploads (unless the proxy adds that API later)
