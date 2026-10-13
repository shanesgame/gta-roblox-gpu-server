-- Opens the local browser GTA build (WASM/WebGPU) with the same start mode as the web loader.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Config = require(script.Parent.WebPortConfig)

local QUERY = {
	[1] = "?mode=story",
	[2] = "?mode=sandbox",
	[3] = "?mode=sandbox&map=env_test",
}

local BrowserPlay = {}

local function playUrl(mode: number): string
	local q = QUERY[mode] or QUERY[1]
	return Config.ENGINE_HOST:gsub("/$", "") .. q
end

function BrowserPlay.getUrl(mode: number): string
	return playUrl(mode)
end

function BrowserPlay.open(mode: number): string
	local url = playUrl(mode)
	local gpuFolder = script.Parent:FindFirstChild("GpuConfig")
	if gpuFolder then
		local ok, gpuCfg = pcall(require, gpuFolder)
		if ok and gpuCfg.ENABLED then
			return url
		end
	end
	pcall(function()
		GuiService:OpenBrowserWindow(url)
	end)
	BrowserPlay._showFallback(url, mode)
	return url
end

function BrowserPlay._showFallback(url: string, mode: number)
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then
		return
	end
	local existing = pg:FindFirstChild("GTABrowserPlayHint")
	if existing then
		existing:Destroy()
	end

	local names = { [1] = "Story Mode", [2] = "Sandbox (GTA V)", [3] = "Sandbox (GTA VI)" }
	local gui = Instance.new("ScreenGui")
	gui.Name = "GTABrowserPlayHint"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2000
	gui.Parent = pg

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 12)
	frame.Size = UDim2.fromOffset(520, 110)
	frame.Parent = gui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -16, 0, 28)
	title.Position = UDim2.fromOffset(8, 8)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = Color3.fromRGB(124, 197, 118)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Play the real game in your browser — " .. (names[mode] or "Story")
	title.Parent = frame

	local body = Instance.new("TextBox")
	body.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	body.BackgroundTransparency = 0.3
	body.BorderSizePixel = 0
	body.ClearTextOnFocus = false
	body.Size = UDim2.new(1, -16, 0, 32)
	body.Position = UDim2.fromOffset(8, 40)
	body.Font = Enum.Font.Code
	body.TextSize = 13
	body.TextColor3 = Color3.new(1, 1, 1)
	body.Text = url
	body.TextEditable = false
	body.Parent = frame

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.new(1, -16, 0, 24)
	hint.Position = UDim2.fromOffset(8, 78)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextColor3 = Color3.fromRGB(200, 200, 200)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = "Copy URL · keep serve.py on port 8765 · Chrome/Edge recommended"
	hint.Parent = frame

	task.delay(45, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

return BrowserPlay
