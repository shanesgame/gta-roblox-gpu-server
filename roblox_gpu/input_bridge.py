"""Inject keyboard/mouse into the Playwright page used for GPU capture.

GTA (local inject hook): writes into the engine input block via window.__robloxGpuInject.
Browser / other sites: Playwright's real mouse + keyboard (CDP) so click, drag, scroll, and type work.
"""
from __future__ import annotations

from typing import Any, List, Optional, Tuple

from roblox_gpu.browser_capture import _executor, _get_page, _init_lock, _viewport

# Roblox (0 left, 1 right, 2 middle) -> Playwright button name
_BTN_NAME = {0: "left", 1: "right", 2: "middle"}
_BTN_MAP_DOM = {0: 0, 1: 2, 2: 1}  # for the GTA inject hook


def _coalesce(events: List[dict[str, Any]]) -> List[dict[str, Any]]:
	"""Keep at most one trailing mousemove (abs or delta) so we don't spam the page."""
	out: List[dict[str, Any]] = []
	for ev in events:
		if ev.get("type") == "mousemove" and out and out[-1].get("type") == "mousemove":
			# merge deltas; replace abs
			prev = out[-1]
			if ev.get("locked") and prev.get("locked"):
				prev["dx"] = int(prev.get("dx", 0)) + int(ev.get("dx", 0))
				prev["dy"] = int(prev.get("dy", 0)) + int(ev.get("dy", 0))
			else:
				out[-1] = ev
		else:
			out.append(ev)
	return out


def _xy(page, ev: dict[str, Any]) -> Tuple[float, float]:
	vw = (_viewport[0] if _viewport else 1024)
	vh = (_viewport[1] if _viewport else 576)
	size = page.viewport_size or {"width": vw, "height": vh}
	w, h = size["width"], size["height"]
	return float(ev.get("nx", 0)) * (w - 1), float(ev.get("ny", 0)) * (h - 1)


def _apply_browser(page, events: List[dict[str, Any]]) -> None:
	"""Real CDP mouse/keyboard — works for normal websites (click, drag, scroll, type)."""
	mouse = page.mouse
	keyboard = page.keyboard
	cur: Optional[Tuple[float, float]] = None
	for ev in events:
		t = ev.get("type")
		if t in ("focus", "pointerlock"):
			try:
				page.bring_to_front()
			except Exception:
				pass
			page.evaluate("() => { try { window.focus(); document.body && document.body.focus(); } catch (_) {} }")
		elif t == "pointerunlock":
			pass
		elif t == "mousemove":
			if ev.get("locked"):
				dx, dy = float(ev.get("dx", 0)), float(ev.get("dy", 0))
				if cur is None:
					cur = (dx, dy)
				else:
					cur = (cur[0] + dx, cur[1] + dy)
			else:
				cur = _xy(page, ev)
			mouse.move(cur[0], cur[1])
		elif t == "mousedown":
			if not ev.get("locked") and ("nx" in ev or "ny" in ev):
				cur = _xy(page, ev)
				mouse.move(cur[0], cur[1])
			elif cur is not None:
				mouse.move(cur[0], cur[1])
			mouse.down(button=_BTN_NAME.get(int(ev.get("button", 0)), "left"))
		elif t == "mouseup":
			if not ev.get("locked") and ("nx" in ev or "ny" in ev):
				cur = _xy(page, ev)
				mouse.move(cur[0], cur[1])
			mouse.up(button=_BTN_NAME.get(int(ev.get("button", 0)), "left"))
		elif t == "wheel":
			if cur is not None:
				mouse.move(cur[0], cur[1])
			# Playwright wheel is pixels; Roblox sends ~120 per notch
			dy = float(ev.get("dy", 0))
			if dy:
				mouse.wheel(0, dy)
		elif t in ("keydown", "keyup"):
			code = ev.get("code")
			if not code:
				continue
			try:
				(keyboard.down if t == "keydown" else keyboard.up)(code)
			except Exception as e:
				print(f"[roblox-gpu] key {code} not sendable: {e}")


def _apply_gta(page, events: List[dict[str, Any]]) -> None:
	"""GTA inject hook (synthetic events miss movementX / wasm input block)."""
	hook = "(window.__robloxGpuInject)"
	call = lambda expr, arg=None: page.evaluate(
		f"(a) => {{ const h = {hook}; if (!h) return false; {expr}; return true; }}", arg
	)
	for ev in events:
		t = ev.get("type")
		if t in ("focus", "pointerlock"):
			call("h.focus()")
		elif t == "pointerunlock":
			call("h.unlock()")
		elif t in ("keydown", "keyup"):
			code = ev.get("code")
			if code:
				page.evaluate(
					"([code, down]) => window.__robloxGpuInject.key(code, down)",
					[code, t == "keydown"],
				)
		elif t == "mousemove":
			if ev.get("locked"):
				call("h.moveDelta(a[0], a[1])", [int(ev.get("dx", 0)), int(ev.get("dy", 0))])
			else:
				call("h.moveAbs(a[0], a[1])", [float(ev.get("nx", 0)), float(ev.get("ny", 0))])
		elif t == "mousedown":
			call("h.button(a, true)", _BTN_MAP_DOM.get(int(ev.get("button", 0)), 0))
		elif t == "mouseup":
			call("h.button(a, false)", _BTN_MAP_DOM.get(int(ev.get("button", 0)), 0))
		elif t == "wheel":
			notches = int(round(float(ev.get("dy", 0)) / 120.0))
			if notches:
				call("h.wheel(a)", notches)


def _apply_events(url: str, events: List[dict[str, Any]]) -> None:
	page = _get_page(url)
	events = _coalesce(events)
	has_gta = False
	try:
		has_gta = bool(page.evaluate("() => !!window.__robloxGpuInject"))
	except Exception:
		# Page navigated / context gone — treat as a normal browser tab
		has_gta = False
	try:
		if has_gta:
			_apply_gta(page, events)
		else:
			_apply_browser(page, events)
	except Exception as e:
		msg = str(e)
		if "Execution context was destroyed" in msg or "navigation" in msg.lower():
			# Click caused a navigation; next frame will show the new page
			return
		raise


def apply_input(url: str, events: List[dict[str, Any]]) -> None:
	if not events:
		return
	with _init_lock:
		future = _executor.submit(_apply_events, url, events)
	future.result(timeout=15)
