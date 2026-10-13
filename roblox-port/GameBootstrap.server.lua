local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Required for client EngineProbe (loader.js / wasm / wgpu) during Play
pcall(function()
	if not HttpService.HttpEnabled then
		HttpService.HttpEnabled = true
	end
end)

local Config = require(ReplicatedStorage.GTA_WebPort.WebPortConfig)
local EngineProbe = require(ReplicatedStorage.GTA_WebPort.EngineProbe)
local folder = ReplicatedStorage:WaitForChild("GTA_WebPort")
local GpuConfig = require(folder:WaitForChild("GpuConfig"))
local remotes = folder:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = folder

local function ensureRemote(className: string, name: string)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = remotes
	end
	return r
end

local progressRemote = ensureRemote("RemoteEvent", "LoadProgress")
local setModeRemote = ensureRemote("RemoteEvent", "SetStartMode")
local readyRemote = ensureRemote("RemoteEvent", "GameReady")
local clientReadyRemote = ensureRemote("RemoteEvent", "ClientReady")

local playerState: { [Player]: { mode: number?, ready: boolean } } = {}

local function sendProgress(player: Player, payload: { [string]: any })
	progressRemote:FireClient(player, payload)
end

local function preloadWorldAssets(player: Player, mode: number)
	local mapName = Config.MAPS[mode]
	local mapFolder = mapName and ServerStorage:FindFirstChild(mapName)
	if not mapFolder then
		sendProgress(player, { pct = 85, label = "Preparing sandbox (Roblox world)" })
		task.wait(0.4)
		return
	end
	sendProgress(player, { pct = 78, label = "Streaming world assets" })
	local toPreload = { mapFolder }
	for _, d in mapFolder:GetDescendants() do
		if d:IsA("MeshPart") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("Sound") then
			table.insert(toPreload, d)
		end
		if #toPreload >= 200 then
			game:GetService("ContentProvider"):PreloadAsync(toPreload)
			table.clear(toPreload)
			toPreload = { mapFolder }
		end
	end
	if #toPreload > 1 then
		game:GetService("ContentProvider"):PreloadAsync(toPreload)
	end
	sendProgress(player, { pct = 92, label = "Warming up graphics" })
	task.wait(0.3)
end

local function mountWorld(player: Player, mode: number)
	local world = workspace:FindFirstChild("GTA_World") or Instance.new("Folder")
	world.Name = "GTA_World"
	world.Parent = workspace

	for _, c in world:GetChildren() do
		c:Destroy()
	end

	local mapName = Config.MAPS[mode]
	local src = mapName and ServerStorage:FindFirstChild(mapName)
	if src then
		src:Clone().Parent = world
	else
		-- Fallback: keep base place playable
		local spawn = workspace:FindFirstChild("SpawnLocation")
		if spawn and player.Character then
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = spawn.CFrame + Vector3.new(0, 4, 0)
			end
		end
	end
end

local function finishLoad(player: Player, mode: number)
	local st = playerState[player]
	if not st or st.ready then
		return
	end
	st.ready = true
	sendProgress(player, { pct = 99, label = "Preparing shaders", compiling = true })
	task.wait(0.35)
	sendProgress(player, { pct = 100, label = "Ready", world = true })
	mountWorld(player, mode)
	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			if GpuConfig.ENABLED then
				hum.WalkSpeed = 0
				hum.JumpPower = 0
			else
				hum.WalkSpeed = 16
				hum.JumpPower = 50
			end
		end
	end
	readyRemote:FireClient(player, { mode = mode })
end

local function startGameForPlayer(player: Player, mode: number)
	if typeof(mode) ~= "number" or mode < 1 or mode > 3 then
		return
	end
	local st = playerState[player]
	if not st or st.ready or st.mode then
		return
	end
	st.mode = mode
	sendProgress(player, { commit = true, mode = mode })
	task.spawn(function()
		preloadWorldAssets(player, mode)
		finishLoad(player, mode)
	end)
end

setModeRemote.OnServerEvent:Connect(function(player, mode: number)
	playerState[player] = playerState[player] or { ready = false }
	startGameForPlayer(player, mode)
end)

local function beginLoadSession(player: Player)
	local st = playerState[player]
	if not st or st.ready or st.sessionStarted then
		return
	end
	st.sessionStarted = true
	sendProgress(player, { pct = 2, label = "Starting..." })
	task.spawn(function()
		EngineProbe.run(function(payload)
			if player.Parent and playerState[player] and not playerState[player].ready then
				sendProgress(player, payload)
			end
		end)
		if player.Parent and playerState[player] and not playerState[player].ready then
			sendProgress(player, { pct = 42, label = "Engine ready — starting game" })
		end
	end)
	task.delay(0.8, function()
		if player.Parent and playerState[player] and not playerState[player].ready and not playerState[player].mode then
			sendProgress(player, {
				pct = 58,
				choice = true,
				label = "Pick mode — opens browser game (Story / Sandbox maps)",
			})
		end
	end)
	task.delay(8, function()
		if player.Parent and playerState[player] and not playerState[player].ready and not playerState[player].mode then
			sendProgress(player, { pct = 65, label = "Auto-starting Story (browser + Roblox)..." })
			startGameForPlayer(player, 1)
		end
	end)
end

clientReadyRemote.OnServerEvent:Connect(function(player)
	playerState[player] = playerState[player] or { ready = false, mode = nil }
	beginLoadSession(player)
end)

local function hookPlayer(player: Player)
	playerState[player] = playerState[player] or { ready = false, mode = nil }
	player.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 5)
		if hum then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
		end
	end)
	-- Fallback if client script is slow to fire ClientReady
	task.delay(3, function()
		if player.Parent and playerState[player] and not playerState[player].sessionStarted then
			beginLoadSession(player)
		end
	end)
end

Players.PlayerAdded:Connect(hookPlayer)
for _, player in Players:GetPlayers() do
	hookPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	playerState[player] = nil
end)
