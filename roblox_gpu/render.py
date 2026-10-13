"""Fetch a URL and rasterize to RGBA bytes for Roblox GpuDisplay."""
from __future__ import annotations

import io
import re
import urllib.error
import urllib.request
from typing import Tuple

from PIL import Image, ImageDraw, ImageFont

from roblox_gpu.browser_capture import capture_url

UA = "RobloxGpuBridge/1.0"
from urllib.parse import urlparse

# Browser app can open any http(s) page; block non-web schemes.
_ALLOWED_SCHEMES = ("http", "https")


def _allowed(url: str) -> bool:
    try:
        p = urlparse(url)
    except Exception:
        return False
    if p.scheme not in _ALLOWED_SCHEMES or not p.netloc:
        return False
    # Reject credentials-in-URL and empty hosts
    if "@" in p.netloc and p.username:
        return False
    return True


def _fetch(url: str, timeout: float = 25.0) -> Tuple[bytes, str]:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
        ctype = (resp.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        return data, ctype


def _text_frame(title: str, subtitle: str, w: int, h: int, tick: int) -> bytes:
    img = Image.new("RGBA", (w, h), (8, 8, 12, 255))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("consola.ttf", 14)
        font_sm = ImageFont.truetype("consola.ttf", 11)
    except OSError:
        font = ImageFont.load_default()
        font_sm = font
    draw.rectangle((0, 0, w - 1, h - 1), outline=(124, 197, 118, 255))
    draw.text((8, 8), "Roblox HTTP GPU", fill=(124, 197, 118, 255), font=font)
    draw.text((8, 28), title[:80], fill=(255, 255, 255, 255), font=font_sm)
    draw.text((8, 44), subtitle[:100], fill=(180, 180, 200, 255), font=font_sm)
    bar_w = max(1, int((tick % 100) / 100 * (w - 16)))
    draw.rectangle((8, h - 18, 8 + bar_w, h - 10), fill=(124, 197, 118, 255))
    draw.text((8, h - 32), f"frame {tick}", fill=(120, 120, 140, 255), font=font_sm)
    return img.tobytes()


def render_url_to_rgba(url: str, width: int, height: int, tick: int = 0) -> Tuple[bytes, int, int]:
    if not _allowed(url):
        raise ValueError("URL must be http(s)")
    # EditableImage tops out at 1024 per side
    width = max(32, min(1024, width))
    height = max(32, min(1024, height))

    try:
        rgba, rw, rh = capture_url(url, width, height)
        return rgba, rw, rh
    except Exception as e:
        err = str(e)[:120]
        return _text_frame("capture failed — restart serve.py", err, width, height, tick), width, height
