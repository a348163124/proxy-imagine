#!/usr/bin/env python3
"""Generate a video via mid-relay /v1/videos/generations (async poll + download)."""

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
        s = "video"
    return s[:max_len].rstrip("-")


def api_root(base_url: str) -> str:
    base = base_url.rstrip("/")
    return base if base.endswith("/v1") else f"{base}/v1"


def http_json(method: str, url: str, api_key: str, body: dict | None = None, timeout: int = 120) -> dict:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "proxy-imagine-video/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code}: {detail}") from e


def main() -> int:
    p = argparse.ArgumentParser(description="Proxy video generation (async)")
    p.add_argument("prompt", help="Motion / scene prompt")
    p.add_argument("--out-dir", default="", help="Output directory (default: ./videos)")
    p.add_argument("--name", default="", help="Output basename without extension")
    p.add_argument("--model", default="", help="Default: grok-imagine-video")
    p.add_argument("--base-url", default="")
    p.add_argument("--api-key", default="")
    p.add_argument("--duration", type=int, default=6, help="Seconds (API may clamp; often 6/10)")
    p.add_argument("--aspect-ratio", default="16:9")
    p.add_argument("--resolution", default="480p")
    p.add_argument("--image-path", default="", help="Local still for image-to-video")
    p.add_argument("--image-url", default="", help="Public or data: URL for still frame")
    p.add_argument("--poll-seconds", type=int, default=5)
    p.add_argument("--max-polls", type=int, default=60)
    p.add_argument("--timeout", type=int, default=120)
    p.add_argument("--json", action="store_true")
    p.add_argument("--open", action="store_true")
    args = p.parse_args()

    base_url = args.base_url or env_first(
        "GROK_VIDEO_BASE_URL",
        "GROK_IMAGEN_BASE_URL",
        "PROXY_IMAGEN_BASE_URL",
        "ANTHROPIC_BASE_URL",
    ) or "https://codexone.aieania.tech"
    api_key = args.api_key or env_first(
        "GROK_VIDEO_API_KEY",
        "GROK_IMAGEN_API_KEY",
        "PROXY_IMAGEN_API_KEY",
        "GROK_API_KEY",
        "THIRD_PARTY_API_KEY",
        "XAI_API_KEY",
    )
    if not api_key:
        print("error: no API key; set GROK_API_KEY or GROK_VIDEO_API_KEY", file=sys.stderr)
        return 2

    model = args.model or env_first("GROK_VIDEO_MODEL", "PROXY_VIDEO_MODEL") or "grok-imagine-video"
    out_dir = Path(
        args.out_dir
        or env_first("GROK_VIDEO_OUT_DIR", "PROXY_VIDEO_OUT_DIR")
        or (Path.cwd() / "videos")
    ).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    name = slugify(args.name) if args.name else f"{slugify(args.prompt)}-{time.strftime('%Y%m%d-%H%M%S')}"
    root = api_root(base_url)
    create_url = f"{root}/videos/generations"

    image_url = args.image_url
    if args.image_path and not image_url:
        ip = Path(args.image_path).resolve()
        if not ip.is_file():
            print(f"error: image not found: {ip}", file=sys.stderr)
            return 2
        raw = ip.read_bytes()
        ext = ip.suffix.lower()
        mime = {
            ".png": "image/png",
            ".webp": "image/webp",
            ".gif": "image/gif",
        }.get(ext, "image/jpeg")
        image_url = f"data:{mime};base64,{base64.b64encode(raw).decode('ascii')}"

    body: dict = {
        "model": model,
        "prompt": args.prompt,
        "duration": args.duration,
    }
    if args.aspect_ratio:
        body["aspect_ratio"] = args.aspect_ratio
    if args.resolution:
        body["resolution"] = args.resolution
    if image_url:
        body["image"] = {"url": image_url}

    try:
        create = http_json("POST", create_url, api_key, body, timeout=args.timeout)
    except Exception as e:  # noqa: BLE001
        print(f"error: create failed: {e}", file=sys.stderr)
        return 1

    rid = create.get("request_id")
    if not rid:
        print(f"error: no request_id: {json.dumps(create)[:500]}", file=sys.stderr)
        return 1

    poll_url = f"{root}/videos/{rid}"
    video_url = None
    final_duration = None
    status = None

    for _ in range(args.max_polls):
        time.sleep(args.poll_seconds)
        try:
            st = http_json("GET", poll_url, api_key, None, timeout=args.timeout)
        except Exception:  # noqa: BLE001
            continue
        status = st.get("status")
        video = st.get("video") or {}
        video_url = video.get("url") or st.get("url")
        if not video_url and st.get("data"):
            video_url = (st["data"][0] or {}).get("url")
        if video.get("duration") is not None:
            final_duration = video.get("duration")

        if status == "failed" or st.get("error"):
            print(f"error: generation failed request_id={rid}: {json.dumps(st)[:800]}", file=sys.stderr)
            return 1
        if status in ("done", "completed", "succeeded") or video_url:
            break

    if not video_url:
        print(
            f"error: timed out request_id={rid} last_status={status} polls={args.max_polls}",
            file=sys.stderr,
        )
        return 1

    out_path = out_dir / f"{name}.mp4"
    try:
        with urllib.request.urlopen(video_url, timeout=args.timeout) as r:
            out_path.write_bytes(r.read())
    except Exception as e:  # noqa: BLE001
        print(f"error: download failed: {e}", file=sys.stderr)
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
        "url": video_url,
        "request_id": rid,
        "model": model,
        "duration": final_duration if final_duration is not None else args.duration,
        "endpoint": create_url,
        "bytes": full.stat().st_size,
        "opened": opened,
    }
    if args.json:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(f"URL: {video_url}")
        print(f"FILE: {file_uri}")
        print(f"PATH: {rel}")
        print(f"REQUEST_ID: {rid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
