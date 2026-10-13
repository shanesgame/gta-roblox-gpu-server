-- Launch / close / navigate apps for the HTTP GPU stream.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("GTA_WebPort")
local Config = require(folder:WaitForChild("GpuConfig"))
local Session = require(folder:WaitForChild("GpuSession"))

if not Config.ENABLED then
	return
end

local remotes = folder:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = folder

local function ensure(name: string)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r
end

local launchApp = ensure("LaunchApp")
local closeApp = ensure("CloseApp")
local navigateApp = ensure("NavigateApp")
local appStarted = ensure("AppStarted")
local appClosed = ensure("AppClosed")

local function normalizeUrl(raw: string): string?
	if typeof(raw) ~= "string" then
		return nil
	end
	local url = raw:gsub("^%s+", ""):gsub("%s+$", "")
	if #url == 0 or #url > 2048 then
		return nil
	end
	if not string.find(url, "^https?://") then
		url = "https://" .. url
	end
	if not string.find(url, "^https?://[%w%._%-]+") then
		return nil
	end
	return url
end

local function broadcastStarted()
	local s = Session.get()
	for _, player in Players:GetPlayers() do
		appStarted:FireClient(player, {
			app = s.appId,
			url = s.url,
			pointerLock = s.pointerLock,
			title = s.title,
		})
	end
end

local function broadcastClosed()
	for _, player in Players:GetPlayers() do
		appClosed:FireClient(player)
	end
end

launchApp.OnServerEvent:Connect(function(_player, appId)
	if typeof(appId) ~= "string" then
		return
	end
	local app = Config.APPS[appId]
	if typeof(app) ~= "table" or typeof(app.url) ~= "string" then
		return
	end
	Session.launch(app.id, app.url, app.pointerLock == true, app.name)
	broadcastStarted()
end)

closeApp.OnServerEvent:Connect(function(_player)
	Session.close()
	broadcastClosed()
end)

navigateApp.OnServerEvent:Connect(function(_player, rawUrl)
	if not Session.isActive() then
		return
	end
	local url = normalizeUrl(rawUrl)
	if not url then
		return
	end
	Session.setUrl(url)
	-- Tell clients so the URL bar stays in sync
	local s = Session.get()
	for _, player in Players:GetPlayers() do
		appStarted:FireClient(player, {
			app = s.appId,
			url = s.url,
			pointerLock = s.pointerLock,
			title = s.title,
		})
	end
end)

-- Late joiners: if an app is already open, show it
Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		if Session.isActive() then
			local s = Session.get()
			appStarted:FireClient(player, {
				app = s.appId,
				url = s.url,
				pointerLock = s.pointerLock,
				title = s.title,
			})
		end
	end)
end)
