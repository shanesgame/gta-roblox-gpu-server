-- Shared config for web-port loading + optional local engine host (serve.py)
return {
	-- Local mirror from gta-browser-local (enable HttpService in Studio + allow HTTP to 127.0.0.1)
	ENGINE_HOST = "http://127.0.0.1:8765",
	BUILD_PATH = "/b/8b0b5899ed",
	DATA_PATH = "/data",

	-- Roblox-side world folders (create under ServerStorage when maps exist)
	MAPS = {
		[1] = "StoryWorld",
		[2] = "SandboxV",
		[3] = "SandboxVI",
	},

	-- Loading UI perf
	SLIDESHOW_FPS = 24,
	USE_SCREEN_POOL = true,

	-- If true, probe ENGINE_HOST during load (progress for engine/io/gpu phases)
	PROBE_WEB_ENGINE = true,

	-- After mode pick, open local browser build (Story / Sandbox V / VI)
	OPEN_BROWSER_GAME = true,
	-- When HTTP GPU is on, BrowserPlay skips the big URL banner (still tries OpenBrowserWindow)

	BROWSER_QUERY = {
		[1] = "?mode=story",
		[2] = "?mode=sandbox",
		[3] = "?mode=sandbox&map=env_test",
	},
}
