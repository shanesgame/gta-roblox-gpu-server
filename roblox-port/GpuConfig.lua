return {
	HOST = "http://127.0.0.1:8765",
	-- Default / fallback URL (GTA). Active URL comes from GpuSession after the launcher.
	SOURCE_URL = "https://gta.deloskiyt.pl/?mode=story",
	WIDTH = 1024,
	HEIGHT = 576,
	-- Roblox HttpService = 500 requests/minute. Input rides on the frame POST.
	-- 10 fps ≈ 600/min peak; pipeline backs off if the limit is hit. Feels much better than 8.
	FPS = 10,
	ENABLED = true,
	COLOR_DROP_BITS = 2,
	MAX_IN_FLIGHT = 1,
	REMOTE_CHUNK_BYTES = 60000,
	FULLSCREEN = true,
	PIXEL_GRID_SCALE = 4,
	PIXEL_REFRESH_FULL = false,
	PIXEL_ROWS_PER_TICK = 40,
	PIXEL_SHARP_BLOCKS = true,
	-- Apps shown on the desktop launcher (do not auto-start GTA).
	APPS = {
		browser = {
			id = "browser",
			name = "Browser",
			subtitle = "Browse the web",
			url = "https://www.google.com/",
			pointerLock = false,
			order = 1,
		},
		gta = {
			id = "gta",
			name = "GTA V",
			subtitle = "Story / sandbox stream",
			url = "https://gta.deloskiyt.pl/?mode=story",
			pointerLock = true,
			order = 2,
		},
	},
}
