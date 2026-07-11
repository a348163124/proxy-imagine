#!/usr/bin/env python3
"""Generate an image via an OpenAI-compatible /images/generations proxy."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def env_first(*names: str) -> str | None:
    for n in names:
        v = os.environ.get(n)
        if v and v.strip():
            return v.strip()
    return None


def slugify(text: str, max_len: int = 48) -> str:
    s = text.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    if not s:
        s = "image"
    return s[:max_len].rstrip("-")


def resolve_endpoint(base_url: str) -> str:
    base = base_url.rstrip("/")
    if base.endswith("/v1"):
        return f"{base}/images/generations"
    return f"{base}/v1/images/generations"


def main() -> int:
    p = argparse.ArgumentParser(description="Proxy image generation (OpenAI-compatible)")
    p.add_argument("prompt", help="Image prompt")
    p.add_argument("--out-dir", default="", help="Output directory (default: ./images)")
    p.add_argument("--name", default="", help="Output basename (no extension)")
    p.add_argument("--model", default="", help="Model id (default: grok-imagine-image)")
    p.add_argument("--base-url", default="", help="Proxy base URL")
    p.add_argument("--api-key", default="", help="API key (else env)")
    p.add_argument("--timeout", type=int, default=180)
    p.add_argument("--json", action="store_true", help="Print JSON result")
    p.add_argument("--open", action="store_true", help="Open image in OS default viewer")
    args = p.parse_args()

    base_url = args.base_url or env_first(
        "GROK_IMAGEN_BASE_URL", "PROXY_IMAGEN_BASE_URL", "ANTHROPIC_BASE_URL"
    ) or "https://codexone.aieania.tech"
    api_key = args.api_key or env_first(
        "GROK_IMAGEN_API_KEY",
        "PROXY_IMAGEN_API_KEY",
        "GROK_API_KEY",
        "THIRD_PARTY_API_KEY",
        "XAI_API_KEY",
    )
    if not api_key:
        print("error: no API key; set GROK_API_KEY or GROK_IMAGEN_API_KEY", file=sys.stderr)
        return 2

    model = args.model or env_first("GROK_IMAGEN_MODEL", "PROXY_IMAGEN_MODEL") or "grok-imagine-image"
    out_dir = Path(
        args.out_dir
        or env_first("GROK_IMAGEN_OUT_DIR", "PROXY_IMAGEN_OUT_DIR")
        or (Path.cwd() / "images")
    ).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    name = slugify(args.name) if args.name else f"{slugify(args.prompt)}-{time.strftime('%Y%m%d-%H%M%S')}"
    endpoint = resolve_endpoint(base_url)
    body = json.dumps({"model": model, "prompt": args.prompt, "n": 1}).encode("utf-8")
    req = urllib.request.Request(
        endpoint,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "proxy-imagine/1.0",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=args.timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        print(f"error: HTTP {e.code}: {detail}", file=sys.stderr)
        return 1
    except Exception as e:  # noqa: BLE001
        print(f"error: request failed: {e}", file=sys.stderr)
        return 1

    data = payload.get("data") or []
    item = data[0] if data else payload
    mime = (item.get("mime_type") or "image/jpeg").lower()
    ext = "png" if "png" in mime else "webp" if "webp" in mime else "jpg"
    out_path = out_dir / f"{name}.{ext}"

    if item.get("url"):
        with urllib.request.urlopen(item["url"], timeout=args.timeout) as r:
            out_path.write_bytes(r.read())
    elif item.get("b64_json"):
        import base64

        out_path.write_bytes(base64.b64decode(item["b64_json"]))
    else:
        print(f"error: unexpected response: {json.dumps(payload)[:500]}", file=sys.stderr)
        return 1

    full = out_path.resolve()
    try:
        rel = full.relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        rel = full.as_posix()
    file_uri = full.as_uri()

    opened = False
    if args.open:
        try:
            import subprocess
            import sys as _sys

            if _sys.platform == "darwin":
                subprocess.run(["open", str(full)], check=False)
            elif _sys.platform.startswith("win"):
                os.startfile(str(full))  # type: ignore[attr-defined]
            else:
                subprocess.run(["xdg-open", str(full)], check=False)
            opened = True
        except Exception as e:  # noqa: BLE001
            print(f"warning: open failed: {e}", file=sys.stderr)

    result = {
        "ok": True,
        "path": str(full),
        "relative_path": rel,
        "file_uri": file_uri,
        "url": item.get("url"),
        "model": model,
        "endpoint": endpoint,
        "bytes": full.stat().st_size,
        "mime": mime,
        "opened": opened,
    }
    if args.json:
        print(json.dumps(result, ensure_ascii=False))
    else:
        if item.get("url"):
            print(f"URL: {item['url']}")
        print(f"FILE: {file_uri}")
        print(f"PATH: {rel}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
