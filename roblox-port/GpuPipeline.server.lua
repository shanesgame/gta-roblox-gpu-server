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
local Session = require(folder:WaitForChild("GpuSession"))

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
-- Soft cap 12: above ~8 may eventually hit Roblox's 500/min; we back off on rate-limit errors.
local fps = math.clamp(Config.FPS or 10, 1, 12)
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

local function fetchFrame(seq: number, sourceUrl: string, events: { any }?): (buffer?, number?, number?, string?)
	local body = HttpService:JSONEncode({
		url = sourceUrl,
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
	if not Session.isActive() then
		return
	end
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
	local sourceUrl = Session.get().url
	if typeof(sourceUrl) ~= "string" then
		return
	end
	inFlight += 1
	lastStart = now
	frameSeq += 1
	local seq = frameSeq
	local events = InputQueue.take()
	task.spawn(function()
		local data, w, h, err = fetchFrame(seq, sourceUrl, events)
		if err then
			if isRateLimit(err) then
				-- Drop to a safe cadence after a hit so we don't freeze for half a minute.
				fps = 7
				minInterval = 1 / fps
				rateLimitedUntil = os.clock() + 8
				lastStart = rateLimitedUntil
				err = "HTTP rate limit — slowing to 7 fps"
			else
				lastStart = os.clock() + 0.5
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
