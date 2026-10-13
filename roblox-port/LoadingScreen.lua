-- Optimized GTA loading UI (slideshow + mode picker + progress from bootstrap/engine probe)
local LoadingScreen = {}

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(script.Parent.LoadingScreenConfig)
local Art = require(script.Parent.LoadingScreenArt)
local PortConfig = require(script.Parent.WebPortConfig)

local CHALET_FALLBACK = Enum.Font.Bodoni
local ANIM_STEP = 1 / (PortConfig.SLIDESHOW_FPS or 24)

local function cubicInOut(t: number): number
	if t < 0.5 then
		return 4 * t * t * t
	end
	return 1 - (2 - 2 * t) ^ 3 / 2
end

local function artId(tex: string): string
	return Art[tex] or Art._default
end

local function yrShift(yr: number): number
	return -yr * 2.5
end

function LoadingScreen.new()
	local self = setmetatable({}, { __index = LoadingScreen })
	self._player = Players.LocalPlayer
	self._modeEvent = Instance.new("BindableEvent")
	self.OnModeChosen = self._modeEvent.Event
	self._stopped = false
	self._connections = {}
	self._targetPct = 0
	self._shownPct = 0
	self._lastLabel = "Starting..."
	self.startMode = 0
	self.startCommitted = false
	self.pickingMap = false
	self.waitingChoice = false
	self._order = nil
	self._orderIndex = 1
	self._alt = -1
	self._active = nil
	self._leaving = nil
	self._animAccum = 0
	self._screenPool = {}
	self._preloaded = false
	return self
end

function LoadingScreen:_connect(sig, fn)
	table.insert(self._connections, sig:Connect(fn))
end

function LoadingScreen:ApplyProgress(payload: { [string]: any })
	if self._stopped then
		return
	end
	if payload.label then
		self._lastLabel = payload.label
		if not self.waitingChoice and self._label then
			self._label.Text = payload.label
		end
	end
	if payload.pct then
		self._targetPct = math.max(self._targetPct, payload.pct)
	end
	if payload.choice and not self.startMode then
		self.waitingChoice = true
		if payload.label and self._label then
			self._label.Text = payload.label
		end
		self:_refreshModes()
	end
	if payload.commit then
		self.startCommitted = true
		self.pickingMap = false
		if payload.mode then
			self.startMode = payload.mode
		end
		self:_refreshModes()
	end
	if payload.compiling and self._label and not self.waitingChoice then
		self._label.Text = "Preparing shaders"
		self._targetPct = math.max(self._targetPct, 99)
	end
end

function LoadingScreen:Start()
	self:_preloadArt()
	self:_buildGui()
	self:_pickOrder()
	self:_startSlideshow()
	self:_startProgressBar()
	self:_bindInput()
	task.delay(2.5, function()
		if not self.startMode and not self.startCommitted then
			self.waitingChoice = true
			self._targetPct = math.max(self._targetPct, 62)
			self:_refreshModes()
		end
	end)
end

function LoadingScreen:Finish(done: () -> ())
	if self._stopped then
		return
	end
	self._targetPct = 100
	task.delay(0.6, function()
		if self._gui then
			local root = self._gui:FindFirstChild("Root")
			if root then
				root.BackgroundTransparency = 1
			end
			for _, d in self._gui:GetDescendants() do
				if d:IsA("GuiObject") then
					d.Visible = false
				end
			end
		end
		self:Destroy()
		if done then
			done()
		end
	end)
end

function LoadingScreen:Destroy()
	self._stopped = true
	for _, c in self._connections do
		c:Disconnect()
	end
	if self._gui then
		self._gui:Destroy()
	end
end

function LoadingScreen:_preloadArt()
	if self._preloaded then
		return
	end
	self._preloaded = true
	local assets = {}
	for _, id in Art do
		if typeof(id) == "string" and id ~= "" then
			table.insert(assets, id)
		end
	end
	if #assets > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
	end
end

function LoadingScreen:_buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GTALoadingScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = self._player:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = Color3.new(0, 0, 0)
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.ClipsDescendants = true
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromOffset(Config.STAGE.X, Config.STAGE.Y)
	stage.Parent = root
	self._uiScale = Instance.new("UIScale")
	self._uiScale.Parent = stage

	local screens = Instance.new("Frame")
	screens.Name = "Screens"
	screens.BackgroundTransparency = 1
	screens.Size = UDim2.fromOffset(Config.STAGE.X, Config.STAGE.Y)
	screens.Parent = stage

	local logo = Instance.new("ImageLabel")
	logo.BackgroundTransparency = 1
	logo.Position = UDim2.fromOffset(95, 492.5)
	logo.Size = UDim2.fromOffset(186, 186)
	logo.Image = artId("beach_bg")
	logo.ScaleType = Enum.ScaleType.Fit
	logo.ZIndex = 5
	logo.Parent = stage

	local bars = Instance.new("Frame")
	bars.BackgroundTransparency = 1
	bars.AnchorPoint = Vector2.new(1, 0)
	bars.Position = UDim2.new(1, -96, 0, 642)
	bars.Size = UDim2.fromOffset(520, 28)
	bars.ZIndex = 6
	bars.Parent = stage

	local modes = Instance.new("Frame")
	modes.Name = "Modes"
	modes.BackgroundColor3 = Color3.new(0, 0, 0)
	modes.BackgroundTransparency = 0.294
	modes.BorderSizePixel = 0
	modes.Size = UDim2.fromOffset(360, 24)
	modes.Parent = bars
	local modesLayout = Instance.new("UIListLayout")
	modesLayout.FillDirection = Enum.FillDirection.Horizontal
	modesLayout.Padding = UDim.new(0, 8)
	modesLayout.Parent = modes

	self._modeButtons = {}
	for act, spec in {
		back = { "Back", "Backspace" },
		map5 = { "GTA V Map", "5" },
		map6 = { "GTA VI Map", "6" },
		sandbox = { "Sandbox Mode", "Space" },
		story = { "Story Mode", "Enter" },
	} do
		local b = Instance.new("TextButton")
		b.Name = act
		b.BackgroundTransparency = 1
		b.Size = UDim2.fromOffset(140, 28)
		b.Font = CHALET_FALLBACK
		b.TextSize = 14
		b.ZIndex = 8
		b.AutoButtonColor = true
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = spec[1]
		b.Parent = modes
		self._modeButtons[act] = b
		b.MouseButton1Click:Connect(function()
			self:_onAct(act)
		end)
	end

	local statusBar = Instance.new("Frame")
	statusBar.BackgroundColor3 = Color3.new(0, 0, 0)
	statusBar.BackgroundTransparency = 0.294
	statusBar.BorderSizePixel = 0
	statusBar.Position = UDim2.fromOffset(368, 0)
	statusBar.Size = UDim2.fromOffset(152, 24)
	statusBar.Parent = bars

	self._label = Instance.new("TextLabel")
	self._label.BackgroundTransparency = 1
	self._label.Size = UDim2.new(1, -40, 1, 0)
	self._label.Font = CHALET_FALLBACK
	self._label.TextSize = 12
	self._label.TextXAlignment = Enum.TextXAlignment.Left
	self._label.TextColor3 = Color3.new(1, 1, 1)
	self._label.Text = "Starting..."
	self._label.Parent = statusBar

	self._pct = Instance.new("TextLabel")
	self._pct.BackgroundTransparency = 1
	self._pct.Position = UDim2.new(1, -36, 0, 0)
	self._pct.Size = UDim2.fromOffset(32, 24)
	self._pct.Font = CHALET_FALLBACK
	self._pct.TextSize = 12
	self._pct.TextColor3 = Color3.new(1, 1, 1)
	self._pct.Text = "0%"
	self._pct.Parent = statusBar

	local barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0, 1)
	barBack.Position = UDim2.new(0, 0, 1, 0)
	barBack.Size = UDim2.new(1, 0, 0, 3)
	barBack.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	barBack.BackgroundTransparency = 0.92
	barBack.BorderSizePixel = 0
	barBack.ZIndex = 10
	barBack.Parent = root

	self._fill = Instance.new("Frame")
	self._fill.BackgroundColor3 = Color3.fromRGB(124, 197, 118)
	self._fill.BorderSizePixel = 0
	self._fill.Size = UDim2.new(0, 0, 1, 0)
	self._fill.Parent = barBack

	self._gui = gui
	self._stage = stage
	self._screensHolder = screens

	self:_connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function()
		self:_fitStage()
	end)
	self:_fitStage()
	self:_refreshModes()
end

function LoadingScreen:_fitStage()
	local cam = workspace.CurrentCamera
	if not cam or not self._stage then
		return
	end
	local vp = cam.ViewportSize
	local s = math.min(vp.X / Config.STAGE.X, vp.Y / Config.STAGE.Y)
	self._uiScale.Scale = s
end

function LoadingScreen:_pickOrder()
	self._order = Config.ORDERS[math.random(1, #Config.ORDERS)]
end

function LoadingScreen:_acquireScreen(): Frame
	if PortConfig.USE_SCREEN_POOL then
		local f = table.remove(self._screenPool)
		if f then
			f.Visible = true
			for _, c in f:GetChildren() do
				c:Destroy()
			end
			return f
		end
	end
	local screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.BackgroundTransparency = 1
	screen.Size = UDim2.fromOffset(Config.STAGE.X, Config.STAGE.Y)
	return screen
end

function LoadingScreen:_releaseScreen(frame: Frame)
	if PortConfig.USE_SCREEN_POOL and #self._screenPool < 2 then
		frame.Visible = false
		frame.Parent = self._screensHolder
		table.insert(self._screenPool, frame)
	else
		frame:Destroy()
	end
end

function LoadingScreen:_makeScreen(defs, screen: Frame)
	local layers = {}
	for _, d in defs do
		local img = Instance.new("ImageLabel")
		img.Name = d.tex
		img.BackgroundTransparency = 1
		img.Image = artId(d.tex)
		img.ScaleType = Enum.ScaleType.Stretch
		img.Size = UDim2.fromOffset(d.w, d.h)
		img.Position = UDim2.fromOffset(d.x, d.y)
		img.Parent = screen
		local to = d.to or {}
		table.insert(layers, {
			el = img,
			x0 = d.x,
			y0 = d.y,
			yr0 = d.yr or 0,
			x1 = to.x or d.x,
			yr1 = to.yr or d.yr or 0,
		})
	end
	return layers
end

function LoadingScreen:_placeLayer(layer, x, yr)
	layer.el.Position = UDim2.fromOffset(x + yrShift(yr), layer.y0)
end

function LoadingScreen:_showScreen(defs)
	local now = os.clock()
	self._alt = self._alt <= 0 and 1 or -1
	local el = self:_acquireScreen()
	local layers = self:_makeScreen(defs, el)
	local s = {
		el = el,
		layers = layers,
		slideFrom = self._alt * Config.STAGE.X,
		slideTo = 0,
		start = now,
		settled = 0,
	}
	for _, layer in layers do
		self:_placeLayer(layer, layer.x0, layer.yr0)
	end
	el.Position = UDim2.fromOffset(s.slideFrom, 0)
	el.Parent = self._screensHolder

	if self._active then
		self._leaving = self._active
		self._leaving.slideFrom = 0
		self._leaving.slideTo = -self._alt * Config.STAGE.X
		self._leaving.start = now
	end
	self._active = s
end

function LoadingScreen:_screenDefsAt(orderSlot: number)
	return Config.SCREENS[self._order[orderSlot]]
end

function LoadingScreen:_startSlideshow()
	local function cycle()
		if self._stopped then
			return
		end
		local defs = self:_screenDefsAt(self._orderIndex)
		if defs then
			self:_showScreen(defs)
		end
		self._orderIndex = (self._orderIndex % #self._order) + 1
		task.delay(Config.CYCLE_MS / 1000, cycle)
	end
	task.delay(0.5, cycle)

	self:_connect(RunService.Heartbeat, function(dt)
		if self._stopped then
			return
		end
		self._animAccum += dt
		if self._animAccum < ANIM_STEP then
			return
		end
		self._animAccum = 0
		local now = os.clock()
		for _, s in { self._leaving, self._active } do
			if not s or not s.el or not s.el.Parent then
				continue
			end
			local p = math.clamp((now - s.start) / (Config.SLIDE_MS / 1000), 0, 1)
			s.el.Position = UDim2.fromOffset(s.slideFrom + (s.slideTo - s.slideFrom) * cubicInOut(p), 0)
			if s == self._active and p >= 1 and s.settled == 0 then
				s.settled = now
			end
			if s.settled > 0 then
				local q = math.clamp((now - s.settled) / (Config.PARALLAX_MS / 1000), 0, 1)
				for _, layer in s.layers do
					self:_placeLayer(layer, layer.x0 + (layer.x1 - layer.x0) * q, layer.yr0 + (layer.yr1 - layer.yr0) * q)
				end
			end
			if s == self._leaving and p >= 1 then
				self:_releaseScreen(s.el)
				if self._leaving == s then
					self._leaving = nil
				end
			end
		end
	end)
end

function LoadingScreen:_startProgressBar()
	self:_connect(RunService.Heartbeat, function(dt)
		if self._stopped or not self._fill then
			return
		end
		self._shownPct += (self._targetPct - self._shownPct) * math.min(1, dt * 8)
		self._fill.Size = UDim2.new(self._shownPct / 100, 0, 1, 0)
		if self._pct then
			self._pct.Text = string.format("%d%%", math.floor(self._shownPct + 0.5))
		end
	end)
end

function LoadingScreen:_refreshModes()
	local LOADING = {
		[1] = "Loading Story Mode",
		[2] = "Loading Sandbox Mode: GTA V Map",
		[3] = "Loading Sandbox Mode: GTA VI Map",
	}
	for act, b in self._modeButtons do
		local loading = not self.pickingMap
			and ((act == "story" and self.startMode == 1) or (act == "sandbox" and self.startMode >= 2))
		if loading then
			b.Text = LOADING[self.startMode] or b.Text
		end
		local hide = self.startCommitted and not loading
		if act == "back" or act == "map5" or act == "map6" then
			hide = hide or (not self.pickingMap and not loading)
		elseif act == "sandbox" or act == "story" then
			hide = hide or (self.pickingMap and act ~= "back")
		end
		b.Visible = not hide
	end
	if self.waitingChoice and not self.startMode and self._label then
		self._label.Text = if self.pickingMap
			then "Choose a map to continue"
			else "Choose Story Mode or Sandbox Mode to continue"
	end
end

function LoadingScreen:_choose(mode: number)
	self.pickingMap = false
	self.startMode = mode
	self._modeEvent:Fire(mode)
	self:_refreshModes()
end

function LoadingScreen:_onAct(act: string)
	if self.startCommitted then
		return
	end
	if act == "story" then
		self:_choose(1)
	elseif act == "map5" then
		self:_choose(2)
	elseif act == "map6" then
		self:_choose(3)
	elseif act == "sandbox" then
		self.pickingMap = true
		self:_refreshModes()
	elseif act == "back" then
		self.pickingMap = false
		self:_refreshModes()
	end
end

function LoadingScreen:_bindInput()
	self:_connect(UserInputService.InputBegan, function(input, processed)
		if processed or self.startCommitted then
			return
		end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			self:_onAct("story")
		elseif input.KeyCode == Enum.KeyCode.Space then
			self:_onAct("sandbox")
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			self:_onAct("back")
		elseif input.KeyCode == Enum.KeyCode.Five or input.KeyCode == Enum.KeyCode.KeypadFive then
			self:_onAct("map5")
		elseif input.KeyCode == Enum.KeyCode.Six or input.KeyCode == Enum.KeyCode.KeypadSix then
			self:_onAct("map6")
		end
	end)
end

return LoadingScreen
