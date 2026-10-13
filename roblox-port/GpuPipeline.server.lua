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
local maxInFlight = math.max(1, Config.MAX_IN_FLIGHT or 1)
local chunkBytes = math.max(8000, Config.REMOTE_CHUNK_BYTES or 60000)
local minInterval = 1 / math.max(1, Config.FPS)
local lastStart = 0

local function frameUrl(seq: number): string
	local base = Config.HOST:gsub("/$", "")
	return string.format(
		"%s/roblox-gpu/frame?url=%s&w=%d&h=%d&t=%d&format=zstd&q=%d",
		base,
		HttpService:UrlEncode(Config.SOURCE_URL),
		Config.WIDTH,
		Config.HEIGHT,
		seq,
		Config.COLOR_DROP_BITS or 0
	)
end

local function fetchFrame(seq: number): (buffer?, number?, number?, string?)
	local ok, res = pcall(function()
		return HttpService:RequestAsync({ Url = frameUrl(seq), Method = "GET" })
	end)
	if not ok then
		return nil, nil, nil, tostring(res)
	end
	if not res.Success then
		local msg = "HTTP " .. tostring(res.StatusCode)
		if res.StatusCode == 0 then
			msg = "HTTP blocked — enable Allow HTTP Requests in Game Settings"
		elseif typeof(res.Body) == "string" and #res.Body > 0 then
			-- Python's send_error wraps the reason in HTML; pull out the "Message:" line
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
	if os.clock() - lastStart < minInterval then
		return
	end
	inFlight += 1
	lastStart = os.clock()
	frameSeq += 1
	local seq = frameSeq
	task.spawn(function()
		local data, w, h, err = fetchFrame(seq)
		if err then
			-- Don't hammer a struggling server (out of memory, restarting); retry in a second
			lastStart = os.clock() + 1
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
