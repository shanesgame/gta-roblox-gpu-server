// Injected into every page the capture browser opens (Playwright add_init_script), before the page's own scripts.
// Lets the Roblox input bridge drive a page that has no window.__robloxGpuInject hook (the original site):
//  - pointer lock is faked (headless has no real one): requestPointerLock() succeeds instantly and
//    document.pointerLockElement reports the element, so the game reads movementX/Y from our mousemove events;
//  - document.hasFocus() is always true and the window gets a focus event, so the game never releases the keys;
//  - window.__robloxGpuNative dispatches DOM mouse/wheel events (keys come through CDP, which produces real key events).
(() => {
	if (window.__robloxGpuNative) return;
	let lockEl = null;
	const fire = () => document.dispatchEvent(new Event('pointerlockchange'));
	Element.prototype.requestPointerLock = function () {
		if (lockEl !== this) { lockEl = this; setTimeout(fire, 0); }
		return Promise.resolve();
	};
	Document.prototype.exitPointerLock = function () { if (lockEl) { lockEl = null; setTimeout(fire, 0); } };
	Object.defineProperty(Document.prototype, 'pointerLockElement', { configurable: true, get: () => lockEl });
	Document.prototype.hasFocus = () => true;
	Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
	Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

	const canvas = () => document.querySelector('canvas') || document.body;
	const pos = { x: 0, y: 0 };
	const mouseInit = (extra) => {
		const r = canvas().getBoundingClientRect();
		return Object.assign({ bubbles: true, cancelable: true, composed: true, view: window,
			clientX: r.left + pos.x, clientY: r.top + pos.y, screenX: r.left + pos.x, screenY: r.top + pos.y }, extra);
	};
	const clamp = (v, hi) => Math.max(0, Math.min(hi, v));
	window.__robloxGpuNative = {
		focus() { window.dispatchEvent(new FocusEvent('focus')); const c = canvas(); if (c.focus) c.focus(); },
		unlock() { document.exitPointerLock(); },
		moveAbs(nx, ny) {
			const r = canvas().getBoundingClientRect();
			const x = clamp(nx * r.width, r.width - 1), y = clamp(ny * r.height, r.height - 1);
			const dx = Math.round(x - pos.x), dy = Math.round(y - pos.y);
			pos.x = x; pos.y = y;
			canvas().dispatchEvent(new MouseEvent('mousemove', mouseInit({ movementX: dx, movementY: dy })));
		},
		moveDelta(dx, dy) {
			const r = canvas().getBoundingClientRect();
			pos.x = clamp(pos.x + dx, r.width - 1); pos.y = clamp(pos.y + dy, r.height - 1);
			canvas().dispatchEvent(new MouseEvent('mousemove', mouseInit({ movementX: dx, movementY: dy })));
		},
		button(btn, down) {
			const buttons = down ? ([1, 4, 2][btn] || 1) : 0;	// DOM buttons mask: left 1, right 2, middle 4
			canvas().dispatchEvent(new MouseEvent(down ? 'mousedown' : 'mouseup', mouseInit({ button: btn, buttons })));
			if (down) canvas().dispatchEvent(new PointerEvent('pointerdown', mouseInit({ button: btn, buttons, pointerId: 1, pointerType: 'mouse', isPrimary: true })));
		},
		wheel(notches) {
			canvas().dispatchEvent(new WheelEvent('wheel', mouseInit({ deltaY: -notches * 100, deltaMode: 0 })));
		},
	};
})();
