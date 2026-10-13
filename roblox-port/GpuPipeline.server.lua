local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

pcall(function()
	if not HttpService.HttpEnabled then
		HttpService.HttpEnabled = true
	end
end)

local folder = ReplicatedStorage:WaitForChild("GTA_WebPort")
local Config = require(folder:WaitForChild("GpuConfig"))
local InputQueue = require(folder:WaitForChild("GpuInputQueue"))

local remotes = folder:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = folder

local gpuFrame = remotes:FindFirstChild("GpuFrame")
if not gpuFrame then
	gpuFrame = Instance.new("RemoteEvent")
	gpuFrame.Name = "GpuFrame"
	gpuFrame.Parent = remotes
end

local frameSeq = 0
local inFlight = 0
-- One in-flight request: Roblox counts every HttpService call toward the 500/min budget.
local maxInFlight = 1
local chunkBytes = math.max(8000, Config.REMOTE_CHUNK_BYTES or 60000)
-- Cap at 8 fps (480/min) so we stay under Roblox's 500 HttpService requests/minute.
local fps = math.clamp(Config.FPS or 8, 1, 8)
local minInterval = 1 / fps
local lastStart = 0
local rateLimitedUntil = 0

local frameUrl = Config.HOST:gsub("/$", "") .. "/roblox-gpu/frame"

local function isRateLimit(err: string): boolean
	local lower = string.lower(err)
	return string.find(lower, "exceeded", 1, true) ~= nil
		or string.find(lower, "rate limit", 1, true) ~= nil
		or string.find(lower, "too many", 1, true) ~= nil
end

local function fetchFrame(seq: number, events: { any }?): (buffer?, number?, number?, string?)
	local body = HttpService:JSONEncode({
		url = Config.SOURCE_URL,
		w = Config.WIDTH,
		h = Config.HEIGHT,
		t = seq,
		format = "zstd",
		q = Config.COLOR_DROP_BITS or 0,
		events = events or {},
	})
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = frameUrl,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)
	if not ok then
		return nil, nil, nil, tostring(res)
	end
	if not res.Success then
		local msg = "HTTP " .. tostring(res.StatusCode)
		if res.StatusCode == 0 then
			msg = "HTTP blocked — enable Allow HTTP Requests in Game Settings"
		elseif typeof(res.Body) == "string" and #res.Body > 0 then
			local reason = res.Body:match("Message:%s*([^<\n]+)") or res.Body:sub(1, 120)
			msg ..= " · " .. reason
		end
		return nil, nil, nil, msg
	end
	local w = tonumber(res.Headers["x-gpu-width"] or res.Headers["X-Gpu-Width"]) or Config.WIDTH
	local h = tonumber(res.Headers["x-gpu-height"] or res.Headers["X-Gpu-Height"]) or Config.HEIGHT
	return buffer.fromstring(res.Body), w, h, nil
end

local function deliver(seq: number, data: buffer?, w: number?, h: number?, err: string?)
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end
	if not data or not w or not h then
		for _, player in players do
			gpuFrame:FireClient(player, seq, 0, 0, 0, 0, nil, err or "no frame")
		end
		return
	end
	local len = buffer.len(data)
	local total = math.max(1, math.ceil(len / chunkBytes))
	for part = 1, total do
		local offset = (part - 1) * chunkBytes
		local n = math.min(chunkBytes, len - offset)
		local chunk = buffer.create(n)
		buffer.copy(chunk, 0, data, offset, n)
		for _, player in players do
			gpuFrame:FireClient(player, seq, part, total, w, h, chunk, nil)
		end
	end
end

local function startCapture()
	if inFlight >= maxInFlight then
		return
	end
	local now = os.clock()
	if now < rateLimitedUntil then
		return
	end
	if now - lastStart < minInterval then
		return
	end
	inFlight += 1
	lastStart = now
	frameSeq += 1
	local seq = frameSeq
	local events = InputQueue.take()
	task.spawn(function()
		local data, w, h, err = fetchFrame(seq, events)
		if err then
			if isRateLimit(err) then
				-- Budget refills over ~20–30 s; pause hard so we don't keep failing.
				rateLimitedUntil = os.clock() + 25
				lastStart = rateLimitedUntil
				err = "HTTP rate limit — pausing 25s (Roblox allows 500 req/min)"
			else
				lastStart = os.clock() + 1
			end
		end
		inFlight -= 1
		deliver(seq, data, w, h, err)
	end)
end

task.spawn(function()
	while Config.ENABLED do
		startCapture()
		task.wait()
	end
end)
