-- Client: full-screen stream (EditableImage) or macro-pixel fallback
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GpuDisplay = {}
GpuDisplay.__index = GpuDisplay

local function tryEditableImage(w: number, h: number)
	local ok, editable = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	end)
	if ok and editable then
		return editable, nil
	end
	return nil, tostring(editable)
end

function GpuDisplay.new(width: number, height: number, opts: { [string]: any }?)
	local self = setmetatable({}, GpuDisplay)
	opts = opts or {}
	self._w = width
	self._h = height
	self._gridScale = math.max(2, math.floor(opts.pixelGridScale or 4))
	self._rowsPerTick = math.max(1, math.floor(opts.rowsPerTick or 10))
	self._pixelRefreshFull = opts.pixelRefreshFull == true
	self._sharpBlocks = opts.pixelSharpBlocks ~= false
	self._fullscreen = opts.fullscreen ~= false
	self._gui = nil
	self._imageLabel = nil
	self._editable = nil
	self._editableErr = nil
	self._status = nil
	self._holder = nil
	self._frames = 0
	self._usePixels = false
	self._pixelGrid = nil
	self._pixelCells = nil
	self._gridW = 0
	self._gridH = 0
	self._body = nil
	self._bodyW = 0
	self._bodyH = 0
	self._nextGridRow = 0
	self._pixelJob = nil
	self._lastShownSeq = 0
	self._fpsCount = 0
	self._fpsClock = os.clock()
	self._fps = 0
	return self
end

local function sampleBlock(body: string, sw: number, sh: number, gx: number, gy: number, scale: number, sharp: boolean): Color3
	if sharp then
		local px = math.min(sw - 1, gx * scale + math.floor(scale * 0.5))
		local py = math.min(sh - 1, gy * scale + math.floor(scale * 0.5))
		local o = (py * sw + px) * 4 + 1
		if o + 2 <= #body then
			return Color3.fromRGB(string.byte(body, o), string.byte(body, o + 1), string.byte(body, o + 2))
		end
		return Color3.new(0, 0, 0)
	end
	local r, g, b, n = 0, 0, 0, 0
	for dy = 0, scale - 1 do
		for dx = 0, scale - 1 do
			local px = gx * scale + dx
			local py = gy * scale + dy
			if px < sw and py < sh then
				local o = (py * sw + px) * 4 + 1
				if o + 2 <= #body then
					r += string.byte(body, o)
					g += string.byte(body, o + 1)
					b += string.byte(body, o + 2)
					n += 1
				end
			end
		end
	end
	if n == 0 then
		return Color3.new(0, 0, 0)
	end
	return Color3.fromRGB(math.floor(r / n), math.floor(g / n), math.floor(b / n))
end

function GpuDisplay:_ensurePixelGrid(gw: number, gh: number)
	if self._pixelGrid and self._gridW == gw and self._gridH == gh then
		return
	end
	if self._pixelGrid then
		self._pixelGrid:Destroy()
	end
	self._gridW = gw
	self._gridH = gh
	local holder = self._holder
	if not holder then
		return
	end
	local grid = Instance.new("Frame")
	grid.Name = "PixelGrid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 1)
	grid.ClipsDescendants = true
	grid.Parent = holder
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(1 / gw, 1 / gh)
	layout.CellPadding = UDim2.new()
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local cells = table.create(gw * gh)
	for y = 0, gh - 1 do
		for x = 0, gw - 1 do
			local cell = Instance.new("Frame")
			cell.BorderSizePixel = 0
			cell.BackgroundColor3 = Color3.new(0, 0, 0)
			cell.LayoutOrder = y * gw + x
			cell.Parent = grid
			cells[y * gw + x + 1] = cell
		end
	end
	self._pixelGrid = grid
	self._pixelCells = cells
	if self._imageLabel then
		self._imageLabel.Visible = false
	end
end

function GpuDisplay:_startPixelJob()
	if self._pixelJob or not self._usePixels then
		return
	end
	self._pixelJob = RunService.Heartbeat:Connect(function()
		local body = self._body
		local sw, sh = self._bodyW, self._bodyH
		local cells = self._pixelCells
		if not body or not cells or sw <= 0 or sh <= 0 then
			return
		end
		local scale = self._gridScale
		local gw, gh = self._gridW, self._gridH
		local row0 = self._nextGridRow
		local row1 = math.min(gh, row0 + self._rowsPerTick)
		for gy = row0, row1 - 1 do
			for gx = 0, gw - 1 do
				cells[gy * gw + gx + 1].BackgroundColor3 = sampleBlock(body, sw, sh, gx, gy, scale, self._sharpBlocks)
			end
		end
		self._nextGridRow = if row1 >= gh then 0 else row1
	end)
end

function GpuDisplay:_queuePixelFrame(body: string, w: number, h: number)
	local scale = self._gridScale
	self._body = body
	self._bodyW = w
	self._bodyH = h
	self:_ensurePixelGrid(math.ceil(w / scale), math.ceil(h / scale))
	self:_startPixelJob()
end

function GpuDisplay:_attachEditable(w: number, h: number): boolean
	if self._editable then
		pcall(function()
			self._editable:Destroy()
		end)
		self._editable = nil
	end
	local editable, err = tryEditableImage(w, h)
	self._editableErr = err
	if not editable or not self._imageLabel then
		return false
	end
	-- Writes need Game Settings > Security > Allow Mesh / Image APIs; probe now so we never show the checkerboard
	local writable, werr = pcall(function()
		editable:WritePixelsBuffer(Vector2.zero, Vector2.new(1, 1), buffer.create(4))
	end)
	if not writable then
		self._editableErr = tostring(werr)
		pcall(function()
			editable:Destroy()
		end)
		return false
	end
	self._editable = editable
	self._usePixels = false
	self._imageLabel.ImageContent = Content.fromObject(editable)
	self._imageLabel.Visible = false -- shown after the first frame lands
	if self._pixelGrid then
		self._pixelGrid.Visible = false
	end
	return true
end

function GpuDisplay:mount()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "HttpGpuScreen"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2000
	gui.IgnoreGuiInset = true
	gui.Parent = pg

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = Color3.new(0, 0, 0)
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local holder = Instance.new("Frame")
	holder.Name = "Viewport"
	holder.BackgroundColor3 = Color3.new(0, 0, 0)
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = if self._fullscreen then UDim2.fromScale(1, 1) else UDim2.fromOffset(self._w, self._h)
	holder.Parent = root

	local img = Instance.new("ImageLabel")
	img.Name = "Framebuffer"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ScaleType = Enum.ScaleType.Stretch
	img.Parent = holder

	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.45
	label.Position = UDim2.fromOffset(8, 8)
	label.Size = UDim2.fromOffset(460, 20)
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(124, 197, 118)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "HTTP GPU · starting…"
	label.ZIndex = 10
	label.Parent = root

	self._gui = gui
	self._imageLabel = img
	self._status = label
	self._holder = holder

	if self:_attachEditable(self._w, self._h) then
		label.Text = "HTTP GPU · waiting for frames"
	else
		self._usePixels = true
		img.Visible = false
		label.Text = "HTTP GPU · LOW QUALITY · enable Game Settings > Security > Allow Mesh / Image APIs, then restart Play"
		label.Size = UDim2.fromOffset(720, 20)
		label.TextColor3 = Color3.fromRGB(255, 200, 80)
		warn("[HTTP GPU] " .. tostring(self._editableErr))
	end

	task.delay(4, function()
		if label.Parent then
			label.BackgroundTransparency = 0.85
			label.TextTransparency = 0.4
		end
	end)
end

function GpuDisplay:showError(err: string)
	if self._status then
		self._status.Text = "HTTP GPU · " .. err
	end
end

function GpuDisplay:pushPixels(pixels: buffer, w: number, h: number, seq: number?)
	if not self._imageLabel then
		self:mount()
	end
	if typeof(seq) == "number" then
		if seq < self._lastShownSeq then
			return
		end
		self._lastShownSeq = seq
	end
	if buffer.len(pixels) < w * h * 4 then
		self:showError(("short frame %d/%d"):format(buffer.len(pixels), w * h * 4))
		return
	end

	if w ~= self._w or h ~= self._h then
		self._w = w
		self._h = h
		if not self._usePixels and not self:_attachEditable(w, h) then
			self._usePixels = true
		end
	end

	if self._editable and not self._usePixels then
		local ok, err = pcall(function()
			self._editable:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)
		end)
		if ok then
			self._imageLabel.Visible = true
		else
			self._usePixels = true
			self._editable = nil
			self._editableErr = tostring(err)
			warn("[HTTP GPU] EditableImage write failed, using blocky fallback: " .. self._editableErr)
		end
	end
	if self._usePixels then
		self:_queuePixelFrame(buffer.tostring(pixels), w, h)
	end

	self._frames += 1
	self._fpsCount += 1
	local now = os.clock()
	if now - self._fpsClock >= 1 then
		self._fps = self._fpsCount / (now - self._fpsClock)
		self._fpsCount = 0
		self._fpsClock = now
	end
	if self._status then
		if self._usePixels then
			self._status.Text = ("HTTP GPU · LOW QUALITY · %.1f fps · enable Game Settings > Security > Allow Mesh / Image APIs"):format(self._fps)
			self._status.Size = UDim2.fromOffset(720, 20)
			self._status.TextTransparency = 0
			self._status.TextColor3 = Color3.fromRGB(255, 200, 80)
		else
			self._status.Text = ("HTTP GPU · %dx%d · %.1f fps"):format(w, h, self._fps)
		end
	end
end

function GpuDisplay:destroy()
	if self._pixelJob then
		self._pixelJob:Disconnect()
		self._pixelJob = nil
	end
	if self._gui then
		self._gui:Destroy()
	end
	self._gui = nil
	self._imageLabel = nil
	self._editable = nil
	self._status = nil
	self._holder = nil
end

return GpuDisplay
