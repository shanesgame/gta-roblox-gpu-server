"""Inject keyboard/mouse into the Playwright page used for GPU capture.

Two paths:
  * the local build exposes window.__robloxGpuInject (writes straight into the engine's input block);
  * any other page (the original site) gets window.__robloxGpuNative from page_shim.js, which dispatches DOM
    mouse/wheel events under a faked pointer lock; keys go through CDP so they are real key events.
"""
from __future__ import annotations

from typing import Any, List

from roblox_gpu.browser_capture import _executor, _get_page, _init_lock

_BTN_MAP = {0: 0, 1: 2, 2: 1}  # Roblox (0 left, 1 right, 2 middle) -> DOM (0 left, 1 middle, 2 right)
_HOOK = "(window.__robloxGpuInject || window.__robloxGpuNative)"


def _apply_events(url: str, events: List[dict[str, Any]]) -> None:
	page = _get_page(url)
	call = lambda expr, arg=None: page.evaluate(f"(a) => {{ const h = {_HOOK}; if (!h) return false; {expr}; return true; }}", arg)
	for ev in events:
		t = ev.get("type")
		if t in ("focus", "pointerlock"):
			call("h.focus()")
		elif t == "pointerunlock":
			call("h.unlock()")
		elif t in ("keydown", "keyup"):
			code = ev.get("code")
			if not code:
				continue
			down = t == "keydown"
			native = page.evaluate(
				"([code, down]) => { if (!window.__robloxGpuInject) return false; window.__robloxGpuInject.key(code, down); return true; }",
				[code, down],
			)
			if not native:
				try:
					(page.keyboard.down if down else page.keyboard.up)(code)
				except Exception as e:
					print(f"[roblox-gpu] key {code} not sendable: {e}")
		elif t == "mousemove":
			if ev.get("locked"):
				call("h.moveDelta(a[0], a[1])", [int(ev.get("dx", 0)), int(ev.get("dy", 0))])
			else:
				call("h.moveAbs(a[0], a[1])", [float(ev.get("nx", 0)), float(ev.get("ny", 0))])
		elif t == "mousedown":
			call("h.button(a, true)", _BTN_MAP.get(int(ev.get("button", 0)), 0))
		elif t == "mouseup":
			call("h.button(a, false)", _BTN_MAP.get(int(ev.get("button", 0)), 0))
		elif t == "wheel":
			notches = int(round(float(ev.get("dy", 0)) / 120.0))
			if notches:
				call("h.wheel(a)", notches)


def apply_input(url: str, events: List[dict[str, Any]]) -> None:
	if not events:
		return
	with _init_lock:
		future = _executor.submit(_apply_events, url, events)
	future.result(timeout=15)
