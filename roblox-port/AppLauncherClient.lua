-- Desktop-style app picker. Shown until Browser or GTA is launched.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local folder = ReplicatedStorage:WaitForChild("GTA_WebPort")
local Config = require(folder:WaitForChild("GpuConfig"))

if not Config.ENABLED then
	return
end

local remotes = folder:WaitForChild("Remotes")
local launchApp = remotes:WaitForChild("LaunchApp")
local appStarted = remotes:WaitForChild("AppStarted")
local appClosed = remotes:WaitForChild("AppClosed")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

pcall(function()
	StarterGui:SetCore("TopbarEnabled", true)
end)

local gui = Instance.new("ScreenGui")
gui.Name = "HttpGpuLauncher"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 2200
gui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BorderSizePixel = 0
backdrop.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
backdrop.Parent = gui

local bgGrad = Instance.new("UIGradient")
bgGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 22, 30)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(10, 12, 16)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 18, 14)),
})
bgGrad.Rotation = 125
bgGrad.Parent = backdrop

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 0, 0.14, 0)
title.Size = UDim2.new(1, 0, 0, 48)
title.Font = Enum.Font.GothamBlack
title.TextSize = 42
title.TextColor3 = Color3.fromRGB(240, 236, 228)
title.Text = "Apps"
title.Parent = backdrop

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.new(0, 0, 0.14, 48)
subtitle.Size = UDim2.new(1, 0, 0, 28)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 16
subtitle.TextColor3 = Color3.fromRGB(150, 156, 168)
subtitle.Text = "Pick something to open on the local stream"
subtitle.Parent = backdrop

local row = Instance.new("Frame")
row.Name = "Row"
row.AnchorPoint = Vector2.new(0.5, 0.5)
row.Position = UDim2.fromScale(0.5, 0.52)
row.Size = UDim2.fromOffset(560, 220)
row.BackgroundTransparency = 1
row.Parent = backdrop

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 28)
layout.Parent = row

local function makeAppCard(app)
	local card = Instance.new("TextButton")
	card.Name = "App_" .. app.id
	card.AutoButtonColor = false
	card.Size = UDim2.fromOffset(240, 200)
	card.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	card.BorderSizePixel = 0
	card.Text = ""
	card.Parent = row

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(55, 62, 74)
	stroke.Thickness = 1
	stroke.Parent = card

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 28)
	icon.Size = UDim2.fromOffset(72, 72)
	icon.BorderSizePixel = 0
	icon.Parent = card
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 16)
	iconCorner.Parent = icon

	if app.id == "browser" then
		icon.BackgroundColor3 = Color3.fromRGB(64, 140, 220)
	else
		icon.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
	end

	local iconLetter = Instance.new("TextLabel")
	iconLetter.BackgroundTransparency = 1
	iconLetter.Size = UDim2.fromScale(1, 1)
	iconLetter.Font = Enum.Font.GothamBold
	iconLetter.TextSize = 34
	iconLetter.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconLetter.Text = if app.id == "browser" then "B" else "G"
	iconLetter.Parent = icon

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 16, 0, 118)
	name.Size = UDim2.new(1, -32, 0, 28)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 22
	name.TextColor3 = Color3.fromRGB(235, 232, 224)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = app.name
	name.Parent = card

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 16, 0, 148)
	sub.Size = UDim2.new(1, -32, 0, 24)
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 14
	sub.TextColor3 = Color3.fromRGB(140, 148, 160)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = app.subtitle or ""
	sub.Parent = card

	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(38, 44, 56) }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(120, 160, 200) }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(28, 32, 40) }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(55, 62, 74) }):Play()
	end)
	card.Activated:Connect(function()
		launchApp:FireServer(app.id)
	end)
end

local apps = {}
for _, app in Config.APPS do
	table.insert(apps, app)
end
table.sort(apps, function(a, b)
	return (a.order or 99) < (b.order or 99)
end)
for _, app in apps do
	makeAppCard(app)
end

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -36)
hint.Size = UDim2.new(1, -40, 0, 24)
hint.Font = Enum.Font.Gotham
hint.TextSize = 13
hint.TextColor3 = Color3.fromRGB(110, 118, 130)
hint.Text = "Needs start_server.bat running on this PC · Esc in an app returns here"
hint.Parent = backdrop

local function showLauncher()
	gui.Enabled = true
end

local function hideLauncher()
	gui.Enabled = false
end

appStarted.OnClientEvent:Connect(function()
	hideLauncher()
end)

appClosed.OnClientEvent:Connect(function()
	showLauncher()
end)

showLauncher()
