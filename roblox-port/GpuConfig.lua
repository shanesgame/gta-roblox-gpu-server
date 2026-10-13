return {
	HOST = "http://127.0.0.1:8765",
	-- ?mode=story matches Roblox auto-start; Enter/Space still work if the page asks again
	SOURCE_URL = "https://gta.deloskiyt.pl/?mode=story", -- original site; use "http://127.0.0.1:8765/?mode=story" for the local copy
	-- EditableImage max is 1024 per side; the browser renders at exactly this size (no resampling)
	WIDTH = 1024,
	HEIGHT = 576,
	FPS = 20,
	ENABLED = true,
	-- Frames travel zstd-compressed; 2 = 6-bit colour (~half the bytes, barely visible), 0 = lossless
	COLOR_DROP_BITS = 2,
	-- Overlap HTTP fetch with capture; client drops out-of-order frames
	MAX_IN_FLIGHT = 2,
	REMOTE_CHUNK_BYTES = 60000,
	FULLSCREEN = true,
	-- Macro fallback only if EditableImage unavailable
	PIXEL_GRID_SCALE = 4,
	PIXEL_REFRESH_FULL = false,
	PIXEL_ROWS_PER_TICK = 40,
	PIXEL_SHARP_BLOCKS = true,
}
