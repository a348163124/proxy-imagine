# proxy-imagine

Agent skill: generate images via an **OpenAI-compatible mid-relay**
(`POST /v1/images/generations`) instead of Grok’s built-in `image_gen`
(which only talks to official xAI Imagine).

- Default image model: `grok-imagine-image`
- Soft gate: intended for **Grok-family / mid-relay** chat sessions; skip for Composer / non-Grok
- No API keys in the repo — reads `GROK_API_KEY` (and optional `GROK_IMAGEN_*`) from the environment

## Layout

```text
proxy-imagine/
  SKILL.md              # agent instructions + frontmatter
  scripts/
    gen-image.ps1       # Windows / PowerShell
    gen-image.py        # cross-platform
  .env.example
  README.md
```

## Install with `npx skills`

The [skills CLI](https://skills.sh/) installs from **Git** (usually GitHub), not from an npm package name alone.

### After you push this repo to GitHub

```bash
# Whole repo (SKILL.md at repo root)
npx skills add <your-github-user>/proxy-imagine

# Global (user-level) + non-interactive
npx skills add <your-github-user>/proxy-imagine -g -y

# Full URL
npx skills add https://github.com/<your-github-user>/proxy-imagine
```

If you later nest the skill under `skills/proxy-imagine/`:

```bash
npx skills add https://github.com/<user>/<repo>/tree/main/skills/proxy-imagine
# or
npx skills add <user>/<repo>@proxy-imagine
```

### Local path (no GitHub yet)

```bash
# From a clone / this folder
npx skills add ./proxy-imagine
# or absolute path
npx skills add "C:/Users/you/.grok/skills/proxy-imagine"
```

Install target depends on the agent (e.g. `~/.agents/skills/`, `~/.grok/skills/`, project `.agents/skills/`). Grok also discovers skills under `~/.grok/skills/` and `~/.agents/skills/`.

## Manual use (without the agent)

```powershell
# PowerShell
.\scripts\gen-image.ps1 -Prompt "a quiet harbor at dusk" -OutDir images -Name harbor-dusk -Json
```

```bash
python scripts/gen-image.py "a quiet harbor at dusk" --out-dir images --name harbor-dusk --json
```

## Environment

| Variable | Purpose |
|----------|---------|
| `GROK_API_KEY` | Bearer token for the proxy (also tries `THIRD_PARTY_API_KEY`, …) |
| `GROK_IMAGEN_BASE_URL` | Override proxy host (default: `ANTHROPIC_BASE_URL` or `https://codexone.aieania.tech`) |
| `GROK_IMAGEN_MODEL` | Image model id (default: `grok-imagine-image`) |
| `GROK_IMAGEN_API_KEY` | Optional separate key for images only |
| `GROK_IMAGEN_OUT_DIR` | Default output directory |

## License

MIT (or your choice — update this file when publishing).
