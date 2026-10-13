"""Headless browser screenshots — all Playwright calls run on one worker thread."""
from __future__ import annotations

import base64
import io
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional, Tuple

from PIL import Image

# Default viewport; the page is resized to the requested stream size so frames need no resampling.
CAPTURE_W = 1024
CAPTURE_H = 576
JPEG_QUALITY = 92

# Playwright's bundled Chromium only gets SwiftShader (CPU) here; Edge's new headless mode uses the real GPU + WebGPU.
GPU_ARGS = [
	"--headless=new", "--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=d3d11", "--enable-unsafe-webgpu",
	# keep the capture browser lean: this PC is tight on RAM
	"--disable-extensions", "--disable-background-networking", "--no-first-run", "--disable-sync",
	"--disable-features=Translate,OptimizationHints,MediaRouter",
	# game audio plays through this PC's speakers: WebAudio may start without a user gesture
	"--autoplay-policy=no-user-gesture-required",
]
# Playwright mutes headless browsers by default; drop that so the game's sound reaches the default output device.
IGNORE_DEFAULT_ARGS = ["--mute-audio"]

_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="roblox-gpu-chromium")
_init_lock = threading.Lock()
_playwright = None
_browser = None
_page = None
_cdp = None
_page_url: Optional[str] = None
_viewport: Tuple[int, int] = (CAPTURE_W, CAPTURE_H)


_SHIM_JS = (Path(__file__).with_name("page_shim.js")).read_text(encoding="utf-8")
# Persistent profile: the original site caches gigabytes of game data in browser storage; keep it between runs.
PROFILE_DIR = Path(__file__).resolve().parent.parent / ".capture-profile"


def _ensure_browser_on_worker() -> None:
	"""_browser is a persistent BrowserContext (has new_page / close like a Browser)."""
	global _playwright, _browser
	if _browser is not None:
		return
	from playwright.sync_api import sync_playwright

	_playwright = sync_playwright().start()
	PROFILE_DIR.mkdir(parents=True, exist_ok=True)
	common = dict(
		headless=True,
		viewport={"width": CAPTURE_W, "height": CAPTURE_H},
		ignore_https_errors=True,
		accept_downloads=False,
		ignore_default_args=IGNORE_DEFAULT_ARGS,
	)
	try:
		_browser = _playwright.chromium.launch_persistent_context(str(PROFILE_DIR), channel="msedge", args=GPU_ARGS, **common)
		print("[roblox-gpu] capture browser: Edge (GPU, audio on)")
	except Exception as e:
		print(f"[roblox-gpu] Edge unavailable ({e}); falling back to bundled Chromium (software rendering)")
		_browser = _playwright.chromium.launch_persistent_context(
			str(PROFILE_DIR / "chromium"), args=["--autoplay-policy=no-user-gesture-required"], **common
		)
	_browser.add_init_script(_SHIM_JS)
	for p in list(_browser.pages):  # the profile opens a blank tab; we make our own
		try:
			p.close()
		except Exception:
			pass


def _get_page(url: str, size: Optional[Tuple[int, int]] = None):
	global _page, _page_url, _cdp, _viewport
	_ensure_browser_on_worker()
	assert _browser is not None
	if size and size != _viewport:
		_viewport = size
		if _page is not None and not _page.is_closed():
			_page.set_viewport_size({"width": size[0], "height": size[1]})
	if _page is None or _page.is_closed():
		_page = _browser.new_page()
		_page.set_viewport_size({"width": _viewport[0], "height": _viewport[1]})
		_cdp = _page.context.new_cdp_session(_page)
		_page_url = None
	if _page_url != url:
		_page.goto(url, wait_until="domcontentloaded", timeout=60_000)
		try:
			_page.wait_for_selector("canvas, #game, body", timeout=6_000)
		except Exception:
			pass
		_page.wait_for_timeout(500)
		_page_url = url
	return _page


_DEAD_PAGE_MARKERS = ("closed", "crashed", "Session closed", "Target", "detached", "Inspected target navigated")


def _reset_page() -> None:
	"""Drop the page so the next capture creates a fresh one (used after the game tab crashes, e.g. OOM)."""
	global _page, _page_url, _cdp
	try:
		if _page is not None and not _page.is_closed():
			_page.close()
	except Exception:
		pass
	_page = None
	_cdp = None
	_page_url = None


def _capture_impl(url: str, width: int, height: int) -> Tuple[bytes, int, int]:
	_get_page(url, (width, height))
	assert _cdp is not None
	try:
		shot = _cdp.send(
			"Page.captureScreenshot",
			{"format": "jpeg", "quality": JPEG_QUALITY, "optimizeForSpeed": True},
		)
	except Exception as e:
		msg = str(e)
		if any(m in msg for m in _DEAD_PAGE_MARKERS):
			print(f"[roblox-gpu] game tab died ({msg[:80]}); reloading it on the next frame")
			_reset_page()
		raise
	img = Image.open(io.BytesIO(base64.b64decode(shot["data"]))).convert("RGBA")
	if img.size != (width, height):
		img = img.resize((width, height), Image.Resampling.LANCZOS)
	return img.tobytes(), width, height


def capture_url(url: str, width: int, height: int) -> Tuple[bytes, int, int]:
	"""Thread-safe: schedules work on the dedicated browser worker."""
	with _init_lock:
		future = _executor.submit(_capture_impl, url, width, height)
	return future.result(timeout=45)


def evaluate_js(url: str, js: str, timeout: float = 20) -> object:
	"""Run JS in the game page (diagnostics). Thread-safe."""
	def _run():
		page = _get_page(url)
		return page.evaluate(js)
	with _init_lock:
		future = _executor.submit(_run)
	return future.result(timeout=timeout)


def reload_page() -> None:
	"""Drop the game tab so the next frame starts it fresh (also frees its memory)."""
	with _init_lock:
		_executor.submit(_reset_page).result(timeout=20)


def shutdown() -> None:
	def _close() -> None:
		global _playwright, _browser, _page, _page_url, _cdp
		if _page and not _page.is_closed():
			_page.close()
		_page = None
		_cdp = None
		_page_url = None
		if _browser:
			_browser.close()
			_browser = None
		if _playwright:
			_playwright.stop()
			_playwright = None

	with _init_lock:
		try:
			_executor.submit(_close).result(timeout=10)
		except Exception:
			pass
