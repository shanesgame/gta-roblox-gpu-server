-- Optional HTTP probe of local web engine (loader.js / wasm / manifest) — mirrors browser boot phases.
local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.WebPortConfig)

local EngineProbe = {}

local function host(): string?
	local h = Config.ENGINE_HOST
	if typeof(h) ~= "string" or h == "" or not Config.PROBE_WEB_ENGINE then
		return nil
	end
	return h:gsub("/$", "")
end

local function httpReady(): (boolean, string?)
	if not HttpService.HttpEnabled then
		return false, "HTTP disabled — Game Settings → Security → Allow HTTP Requests"
	end
	return true, nil
end

local function safeRequest(url: string, method: string): (boolean, number, string?)
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = method,
		})
	end)
	if not ok then
		return false, 0, tostring(res)
	end
	if not res.Success then
		return false, 0, ("HTTP %s"):format(tostring(res.StatusCode))
	end
	local n = tonumber(res.Headers and (res.Headers["Content-Length"] or res.Headers["content-length"])) or #(res.Body or "")
	return true, n, nil
end

function EngineProbe.run(onProgress: (payload: { pct: number, label: string }) -> ())
	local base = host()
	if not base then
		onProgress({ pct = 18, label = "Roblox engine ready" })
		return
	end

	local ready, httpMsg = httpReady()
	if not ready then
		onProgress({ pct = 12, label = httpMsg or "HTTP not available" })
		onProgress({ pct = 40, label = "Roblox-only — pick Story or Sandbox to play" })
		return
	end

	onProgress({ pct = 4, label = "Connecting to web engine host" })
	local build = base .. Config.BUILD_PATH

	local okLoader, _, loaderErr = safeRequest(build .. "/loader.js", "HEAD")
	if not okLoader then
		-- Some stacks reject HEAD; try a tiny GET
		okLoader, _, loaderErr = safeRequest(build .. "/loader.js", "GET")
	end
	local offlineLabel = "Web host offline (Roblox-only mode)"
	if loaderErr then
		offlineLabel = offlineLabel .. " — " .. loaderErr
	end
	onProgress({
		pct = okLoader and 12 or 8,
		label = okLoader and "Engine loader reachable" or offlineLabel,
	})
	if not okLoader then
		onProgress({ pct = 40, label = "Roblox-only — pick Story or Sandbox to play" })
		return
	end

	local okGame = select(1, safeRequest(build .. "/game.js", "HEAD"))
	onProgress({ pct = okGame and 18 or 14, label = "game.js reachable" })

	local okWasm, wasmBytes = safeRequest(build .. "/game.wasm", "HEAD")
	onProgress({
		pct = okWasm and 22 or 18,
		label = okWasm and ("Engine WASM reachable (" .. math.floor(wasmBytes / 1048576) .. " MB)") or "Engine WASM unavailable",
	})

	onProgress({ pct = 24, label = "I/O worker / manifest" })
	local okManifest = select(1, safeRequest(base .. Config.DATA_PATH .. "/manifest.json", "HEAD"))
	if okManifest then
		onProgress({ pct = 28, label = "Game manifest reachable" })
	end

	onProgress({ pct = 32, label = "GPU worker / shaders" })
	safeRequest(build .. "/wgpu_worker.js", "HEAD")
	safeRequest(build .. "/shaders/index.json", "HEAD")
	onProgress({ pct = 38, label = "Shader pipeline reachable" })
end

return EngineProbe
