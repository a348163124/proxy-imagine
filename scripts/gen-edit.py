#!/usr/bin/env python3
"""Edit an image via mid-relay POST /v1/images/edits (JSON, not multipart)."""

from __future__ import annotations

import argparse
import base64
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
        s = "edit"
    return s[:max_len].rstrip("-")


def resolve_endpoint(base_url: str) -> str:
    base = base_url.rstrip("/")
    if base.endswith("/v1"):
        return f"{base}/images/edits"
    return f"{base}/v1/images/edits"


def file_to_data_uri(path: Path) -> str:
    raw = path.read_bytes()
    ext = path.suffix.lower()
    mime = {
        ".png": "image/png",
        ".webp": "image/webp",
        ".gif": "image/gif",
    }.get(ext, "image/jpeg")
    b64 = base64.b64encode(raw).decode("ascii")
    return f"data:{mime};base64,{b64}"


def main() -> int:
    p = argparse.ArgumentParser(description="Proxy image edit (xAI-compatible JSON /images/edits)")
    p.add_argument("prompt", help="Edit instruction / visual prompt")
    p.add_argument("--image-path", default="", help="Local source image")
    p.add_argument("--image-url", default="", help="Public HTTPS or data: URL for source")
    p.add_argument("--out-dir", default="", help="Output directory (default: ./images)")
    p.add_argument("--name", default="", help="Output basename (no extension)")
    p.add_argument("--model", default="", help="Default: grok-imagine-image-quality")
    p.add_argument("--base-url", default="", help="Proxy base URL")
    p.add_argument("--api-key", default="", help="API key (else env)")
    p.add_argument("--aspect-ratio", default="", help="Optional; single-image edit usually keeps input ratio")
    p.add_argument("--timeout", type=int, default=180)
    p.add_argument("--json", action="store_true", help="Print JSON result")
    p.add_argument("--open", action="store_true", help="Open result in OS default viewer")
    args = p.parse_args()

    if not args.image_path and not args.image_url:
        print("error: provide --image-path and/or --image-url", file=sys.stderr)
        return 2

    base_url = args.base_url or env_first(
        "GROK_EDIT_BASE_URL",
        "GROK_IMAGEN_BASE_URL",
        "PROXY_IMAGEN_BASE_URL",
        "ANTHROPIC_BASE_URL",
    ) or "https://codexone.aieania.tech"
    api_key = args.api_key or env_first(
        "GROK_EDIT_API_KEY",
        "GROK_IMAGEN_API_KEY",
        "PROXY_IMAGEN_API_KEY",
        "GROK_API_KEY",
        "THIRD_PARTY_API_KEY",
        "XAI_API_KEY",
    )
    if not api_key:
        print("error: no API key; set GROK_API_KEY or GROK_EDIT_API_KEY", file=sys.stderr)
        return 2

    model = (
        args.model
        or env_first("GROK_EDIT_MODEL", "PROXY_EDIT_MODEL", "GROK_IMAGEN_MODEL")
        or "grok-imagine-image-quality"
    )
    out_dir = Path(
        args.out_dir
        or env_first("GROK_EDIT_OUT_DIR", "GROK_IMAGEN_OUT_DIR", "PROXY_IMAGEN_OUT_DIR")
        or (Path.cwd() / "images")
    ).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    name = (
        slugify(args.name)
        if args.name
        else f"edit-{slugify(args.prompt)}-{time.strftime('%Y%m%d-%H%M%S')}"
    )
    endpoint = resolve_endpoint(base_url)

    source_url = args.image_url
    source_path: str | None = None
    if args.image_path:
        ip = Path(args.image_path).resolve()
        if not ip.is_file():
            print(f"error: image not found: {ip}", file=sys.stderr)
            return 2
        source_path = str(ip)
        if not source_url:
            source_url = file_to_data_uri(ip)

    if not source_url:
        print("error: could not resolve source image URL", file=sys.stderr)
        return 2

    body: dict = {
        "model": model,
        "prompt": args.prompt,
        "image": {"url": source_url, "type": "image_url"},
        "n": 1,
    }
    if args.aspect_ratio:
        body["aspect_ratio"] = args.aspect_ratio

    req = urllib.request.Request(
        endpoint,
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "proxy-imagine-edit/1.0",
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

            if sys.platform == "darwin":
                subprocess.run(["open", str(full)], check=False)
            elif sys.platform.startswith("win"):
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
        "source_path": source_path,
        "source_url": args.image_url or None,
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
