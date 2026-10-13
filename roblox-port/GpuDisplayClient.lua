local EncodingService = game:GetService("EncodingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("GTA_WebPort")
local Config = require(folder:WaitForChild("GpuConfig"))
local GpuDisplay = require(folder:WaitForChild("GpuDisplay"))
local GpuInputClient = require(folder:WaitForChild("GpuInputClient"))

if not Config.ENABLED then
	return
end

local remotes = folder:WaitForChild("Remotes")
local gpuFrame = remotes:WaitForChild("GpuFrame")
local appStarted = remotes:WaitForChild("AppStarted")
local appClosed = remotes:WaitForChild("AppClosed")
local closeApp = remotes:WaitForChild("CloseApp")
local navigateApp = remotes:WaitForChild("NavigateApp")

local display = nil
local inputHandle = nil
local chrome = nil
local pending: { [number]: { total: number, got: number, w: number, h: number, parts: { buffer } } } = {}
local latestShown = 0
local activeApp: string? = nil

local function destroyChrome()
	if chrome then
		chrome:Destroy()
		chrome = nil
	end
end

local function buildChrome(info: { [string]: any })
	destroyChrome()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "HttpGpuChrome"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2100
	gui.Parent = pg
	chrome = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(1, 0, 0, 44)
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
	bar.Parent = gui

	local back = Instance.new("TextButton")
	back.Name = "Back"
	back.Size = UDim2.fromOffset(88, 30)
	back.Position = UDim2.fromOffset(10, 7)
	back.BackgroundColor3 = Color3.fromRGB(40, 44, 52)
	back.BorderSizePixel = 0
	back.Font = Enum.Font.GothamMedium
	back.TextSize = 14
	back.TextColor3 = Color3.fromRGB(230, 230, 230)
	back.Text = "← Apps"
	back.Parent = bar
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 8)
	backCorner.Parent = back
	back.Activated:Connect(function()
		closeApp:FireServer()
	end)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(110, 0)
	title.Size = UDim2.new(0, 120, 1, 0)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(210, 210, 210)
	title.Text = tostring(info.title or info.app or "App")
	title.Parent = bar

	if info.app == "browser" then
		local box = Instance.new("TextBox")
		box.Name = "Url"
		box.ClearTextOnFocus = false
		box.Position = UDim2.new(0, 240, 0, 7)
		box.Size = UDim2.new(1, -320, 0, 30)
		box.BackgroundColor3 = Color3.fromRGB(34, 38, 46)
		box.BorderSizePixel = 0
		box.Font = Enum.Font.Code
		box.TextSize = 14
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextColor3 = Color3.fromRGB(230, 230, 230)
		box.PlaceholderText = "https://…"
		box.Text = tostring(info.url or "")
		box.Parent = bar
		local boxCorner = Instance.new("UICorner")
		boxCorner.CornerRadius = UDim.new(0, 8)
		boxCorner.Parent = box
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = box
		box.FocusLost:Connect(function(enter)
			if enter and #box.Text > 0 then
				navigateApp:FireServer(box.Text)
			end
		end)
		local go = Instance.new("TextButton")
		go.Size = UDim2.fromOffset(56, 30)
		go.Position = UDim2.new(1, -66, 0, 7)
		go.BackgroundColor3 = Color3.fromRGB(64, 140, 220)
		go.BorderSizePixel = 0
		go.Font = Enum.Font.GothamBold
		go.TextSize = 14
		go.TextColor3 = Color3.fromRGB(255, 255, 255)
		go.Text = "Go"
		go.Parent = bar
		local goCorner = Instance.new("UICorner")
		goCorner.CornerRadius = UDim.new(0, 8)
		goCorner.Parent = go
		go.Activated:Connect(function()
			if #box.Text > 0 then
				navigateApp:FireServer(box.Text)
			end
		end)
	end
end

local function stopStream()
	activeApp = nil
	pending = {}
	latestShown = 0
	if inputHandle and inputHandle.stop then
		inputHandle.stop()
	end
	inputHandle = nil
	if display then
		display:destroy()
		display = nil
	end
	destroyChrome()
end

local function startStream(info: { [string]: any })
	stopStream()
	activeApp = info.app
	buildChrome(info)
	display = GpuDisplay.new(Config.WIDTH, Config.HEIGHT, {
		pixelGridScale = Config.PIXEL_GRID_SCALE,
		rowsPerTick = Config.PIXEL_ROWS_PER_TICK,
		pixelRefreshFull = Config.PIXEL_REFRESH_FULL,
		pixelSharpBlocks = Config.PIXEL_SHARP_BLOCKS,
		fullscreen = Config.FULLSCREEN,
		topInset = 44,
	})
	display:mount()
	inputHandle = GpuInputClient.start(remotes, Config.WIDTH, Config.HEIGHT, {
		pointerLock = info.pointerLock == true,
	})
end

local function finish(seq: number, entry)
	if not display then
		return
	end
	local size = 0
	for i = 1, entry.total do
		size += buffer.len(entry.parts[i])
	end
	local packed = buffer.create(size)
	local offset = 0
	for i = 1, entry.total do
		local part = entry.parts[i]
		buffer.copy(packed, offset, part, 0, buffer.len(part))
		offset += buffer.len(part)
	end
	local ok, pixels = pcall(function()
		return EncodingService:DecompressBuffer(packed, Enum.CompressionAlgorithm.Zstd)
	end)
	if not ok then
		display:showError("zstd decompress failed: " .. tostring(pixels))
		return
	end
	display:pushPixels(pixels, entry.w, entry.h, seq)
end

gpuFrame.OnClientEvent:Connect(function(seq: number, partIndex: number, total: number, w: number, h: number, chunk: buffer?, err: string?)
	if not display then
		return
	end
	if partIndex == 0 then
		display:showError(err or "no frame")
		return
	end
	if seq <= latestShown then
		return
	end
	local entry = pending[seq]
	if not entry then
		entry = { total = total, got = 0, w = w, h = h, parts = table.create(total) }
		pending[seq] = entry
	end
	if entry.parts[partIndex] == nil and chunk then
		entry.parts[partIndex] = chunk
		entry.got += 1
	end
	if entry.got < entry.total then
		return
	end
	latestShown = seq
	for s in pending do
		if s <= seq then
			pending[s] = nil
		end
	end
	finish(seq, entry)
end)

appStarted.OnClientEvent:Connect(function(info)
	if typeof(info) ~= "table" then
		return
	end
	-- URL-only refresh (browser navigate): update chrome text, keep display
	if activeApp == info.app and display and chrome then
		local box = chrome:FindFirstChild("Bar") and chrome.Bar:FindFirstChild("Url")
		if box and box:IsA("TextBox") and typeof(info.url) == "string" then
			box.Text = info.url
		end
		return
	end
	startStream(info)
end)

appClosed.OnClientEvent:Connect(function()
	stopStream()
end)
