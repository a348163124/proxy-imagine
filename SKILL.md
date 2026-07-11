---
name: proxy-imagine
description: >
  Proxy text-to-image for Grok mid-relay sessions only. Calls OpenAI-compatible
  /v1/images/generations (default model grok-imagine-image) instead of built-in image_gen.
  After generation: open OS viewer (-Open), reply with HTTPS image URL + markdown image embed
  (TUI can click https links; relative paths alone do NOT show native Imagine media cards).
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

## Important: display limits

Built-in `image_gen` returns a **native media attachment** that Grok Build renders as an
in-window image card. Shell scripts **cannot** inject that channel.

| What works | What does **not** work |
|------------|-------------------------|
| `https://...` URL in the reply (Ctrl/Cmd+click often opens) | Bare `images/foo.jpg` markdown as if it were Imagine media |
| Markdown image `![](https://...)` when TUI renders remote images | Expecting shell output alone to show a media bubble |
| `-Open` / OS default viewer | `file://` / relative links always opening inside Grok |
| Local file on disk under `images/` | 100% parity with native Imagine UI |

**Do not promise native Imagine cards.** Maximize: remote HTTPS + OS open + local path.

## Session gate (soft)

**Use only when BOTH are true:**

1. Chat model is Grok-family / mid-relay (`custom-grok`, `grok-4.5`, `grok-build*`, …).
2. User wants an image, **or** ran `/proxy-imagine`.

**Skip** for Composer / non-Grok → use built-in `image_gen`.

## Hard rules (when gate passes)

1. **Do not** call built-in `image_gen` / `image_edit` (unless user insists on official).
2. Run the script with **`-OutDir "images"`** and **`-Open`** (Windows: opens default viewer).
3. Parse JSON: use `url`, `relative_path`, `file_uri`, `path`.
4. **`read_file` the local image** once (for model vision / verification).
5. **Final reply MUST include all of:**
   - Markdown remote image (if `url` present): `![](<url>)`
   - Clickable HTTPS link: `[在浏览器打开](<url>)`
   - Local relative path as text backup: `` `images/<name>.jpg` ``
   - One-line description
6. Never print API keys.

## Default endpoint

| Setting | Resolution |
|---------|------------|
| Base URL | `GROK_IMAGEN_BASE_URL` → `PROXY_IMAGEN_BASE_URL` → `https://codexone.aieania.tech` |
| API key | `GROK_IMAGEN_API_KEY` → `PROXY_IMAGEN_API_KEY` → `GROK_API_KEY` → `XAI_API_KEY` |
| Model | `GROK_IMAGEN_MODEL` → `PROXY_IMAGEN_MODEL` → `grok-imagine-image` |
| Output | workspace `./images` |

## Resolve skill root

```powershell
$skillRoot = @(
  "$env:USERPROFILE\.grok\skills\proxy-imagine",
  "$env:USERPROFILE\.agents\skills\proxy-imagine",
  (Join-Path (Get-Location) ".agents\skills\proxy-imagine"),
  (Join-Path (Get-Location) ".grok\skills\proxy-imagine")
) | Where-Object { Test-Path (Join-Path $_ "scripts\gen-image.ps1") } | Select-Object -First 1
```

## Generate (Windows PowerShell)

```powershell
& "$skillRoot\scripts\gen-image.ps1" `
  -Prompt "<full visual prompt>" `
  -OutDir "images" `
  -Name "<short-kebab-name>" `
  -Open `
  -Json
```

Python:

```bash
python "$SKILL_ROOT/scripts/gen-image.py" \
  "<prompt>" --out-dir images --name "<short-kebab-name>" --open --json
```

JSON fields: `url`, `relative_path`, `file_uri`, `path`, `bytes`, `model`, `opened`.

## Prompt craft

2–5 sentences: subject → setting → style → composition → lighting/mood.

## Workflow

1. Pass session gate.
2. Craft prompt; pick kebab `Name`.
3. Run script with `-Open -Json -OutDir images`.
4. Confirm `ok` and `bytes` > 0.
5. `read_file` local `images/<name>.jpg` (or absolute `path`).
6. Reply in this shape:

```markdown
![](HTTPS_URL_FROM_JSON)

[在浏览器打开原图](HTTPS_URL_FROM_JSON)

本地文件：`images/<name>.jpg`（已尝试用系统看图打开）

<一句画面描述>
```

If `url` is missing (b64-only response), open local file with `-Open` and give absolute `path` + `file_uri`.

## Failure handling

| Symptom | Action |
|---------|--------|
| Non-Grok session | Use `image_gen` |
| No API key | Ask for `GROK_API_KEY` |
| HTTP errors | Report; check `GROK_IMAGEN_BASE_URL` |
| User says “no display / link dead” | Re-run with `-Open`; paste fresh `url`; open local path with `Start-Process` / `open` |

## What this skill cannot do

- Inject native Grok Imagine media bubbles via shell
- Hard-filter by model id at OS level
- Video / reference edit unless proxy adds APIs
