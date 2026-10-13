local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local folder = ReplicatedStorage:WaitForChild("GTA_WebPort")
local PortConfig = require(folder:WaitForChild("WebPortConfig"))
local GpuConfig = require(folder:WaitForChild("GpuConfig"))
local LoadingScreen = require(folder:WaitForChild("LoadingScreen"))
local BrowserPlay = require(folder:WaitForChild("BrowserPlay"))

local remotes = folder:WaitForChild("Remotes")
local loadProgress = remotes:WaitForChild("LoadProgress")
local setMode = remotes:WaitForChild("SetStartMode")
local gameReady = remotes:WaitForChild("GameReady")
local clientReady = remotes:WaitForChild("ClientReady")

pcall(function()
	StarterGui:SetCore("TopbarEnabled", false)
end)

local function enableCharacter()
	local char = Players.LocalPlayer.Character
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 16
		hum.JumpPower = 50
	end
end

if GpuConfig.ENABLED then
	gameReady.OnClientEvent:Connect(function()
		local char = Players.LocalPlayer.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = 0
				hum.JumpPower = 0
			end
		end
		pcall(function()
			StarterGui:SetCore("TopbarEnabled", true)
		end)
	end)
	clientReady:FireServer()
	task.defer(function()
		setMode:FireServer(1)
	end)
	return
end

local screen = LoadingScreen.new()

loadProgress.OnClientEvent:Connect(function(payload)
	screen:ApplyProgress(payload)
end)

local launchedBrowserMode: number? = nil
local function launchBrowser(mode: number)
	if not PortConfig.OPEN_BROWSER_GAME or launchedBrowserMode == mode then
		return
	end
	launchedBrowserMode = mode
	BrowserPlay.open(mode)
end

gameReady.OnClientEvent:Connect(function(payload)
	local mode = typeof(payload) == "table" and payload.mode or 1
	launchBrowser(mode)
	screen:Finish(function()
		pcall(function()
			StarterGui:SetCore("TopbarEnabled", true)
		end)
		enableCharacter()
	end)
end)

screen.OnModeChosen:Connect(function(mode: number)
	setMode:FireServer(mode)
	launchBrowser(mode)
end)

screen:Start()
clientReady:FireServer()
