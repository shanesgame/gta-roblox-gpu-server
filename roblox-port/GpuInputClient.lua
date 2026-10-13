-- Forward keyboard/mouse to the headless browser via server -> POST /roblox-gpu/input
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local folder = ReplicatedStorage:WaitForChild("GTA_WebPort")
local InputMap = require(folder:WaitForChild("GpuInputMap"))

local GpuInputClient = {}

function GpuInputClient.start(remotes: Folder, streamW: number, streamH: number)
	local gpuInput = remotes:WaitForChild("GpuInput")
	local queue: { { [string]: any } } = {}
	local pointerLocked = false
	local pendingDx, pendingDy = 0, 0
	local heldKeys: { [Enum.KeyCode]: boolean } = {}

	local function push(ev: { [string]: any })
		table.insert(queue, ev)
		if #queue > 180 then
			table.remove(queue, 1)
		end
	end

	local function sinkAction(_name, _state, _input)
		return Enum.ContextActionResult.Sink
	end

	local sinkKeys = {
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.Space,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.Up,
		Enum.KeyCode.Down,
		Enum.KeyCode.Return,
		Enum.KeyCode.E,
		Enum.KeyCode.F,
		Enum.KeyCode.Q,
		Enum.KeyCode.R,
		Enum.KeyCode.Tab,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.LeftControl,
	}
	ContextActionService:BindAction("HttpGpuSinkMove", sinkAction, false, table.unpack(sinkKeys))

	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	RunService.RenderStepped:Connect(function()
		if cam and cam.Parent then
			local pos = cam.CFrame.Position
			cam.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
		end
		if pointerLocked then
			local d = UserInputService:GetMouseDelta()
			pendingDx += d.X
			pendingDy += d.Y
		end
	end)

	local function lockPointer()
		if pointerLocked then
			return
		end
		pointerLocked = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		push({ type = "focus" })
		push({ type = "pointerlock" })
	end

	local function unlockPointer()
		if not pointerLocked then
			return
		end
		pointerLocked = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		push({ type = "pointerunlock" })
		for key, _ in heldKeys do
			local code = InputMap.browserCode(key)
			if code then
				push({ type = "keyup", code = code })
			end
		end
		table.clear(heldKeys)
	end

	local function mapMouseToStream(screenX: number, screenY: number): (number, number)
		local vx, vy, vw, vh = 0, 0, streamW, streamH
		local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local holder = gui and gui:FindFirstChild("HttpGpuScreen")
		holder = holder and holder:FindFirstChild("Root") and holder.Root:FindFirstChild("Viewport")
		if holder and holder:IsA("GuiObject") then
			local ap = holder.AbsolutePosition
			local as = holder.AbsoluteSize
			vx, vy, vw, vh = ap.X, ap.Y, as.X, as.Y
		end
		local nx = math.clamp((screenX - vx) / math.max(vw, 1), 0, 1)
		local ny = math.clamp((screenY - vy) / math.max(vh, 1), 0, 1)
		return nx, ny
	end

	-- Polled below (Jump/Select can eat Space/Enter before InputBegan).
	local pollKeys = {
		Enum.KeyCode.Space,
		Enum.KeyCode.Return,
		Enum.KeyCode.KeypadEnter,
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.Up,
		Enum.KeyCode.Down,
	}
	local pollSet: { [Enum.KeyCode]: boolean } = {}
	for _, key in pollKeys do
		pollSet[key] = true
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed and input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if pollSet[input.KeyCode] then
				return
			end
			local code = InputMap.browserCode(input.KeyCode)
			if not code then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				unlockPointer()
			end
			heldKeys[input.KeyCode] = true
			push({ type = "keydown", code = code })
			return
		end
		local btn = InputMap.mouseButton(input.UserInputType)
		if btn ~= nil then
			lockPointer()
			push({ type = "mousedown", button = btn })
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if pollSet[input.KeyCode] then
				return
			end
			local code = InputMap.browserCode(input.KeyCode)
			if code then
				heldKeys[input.KeyCode] = nil
				push({ type = "keyup", code = code })
			end
			return
		end
		local btn = InputMap.mouseButton(input.UserInputType)
		if btn ~= nil then
			push({ type = "mouseup", button = btn })
		end
	end)

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local z = input.Position.Z
			if z ~= 0 then
				push({ type = "wheel", dy = -z * 120 })
			end
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and not pointerLocked then
			local nx, ny = mapMouseToStream(input.Position.X, input.Position.Y)
			push({ type = "mousemove", locked = false, nx = nx, ny = ny })
		end
	end)

	local polledDown: { [Enum.KeyCode]: boolean } = {}

	task.spawn(function()
		while true do
			task.wait(1 / 30)
			for _, key in pollKeys do
				local down = UserInputService:IsKeyDown(key)
				local was = polledDown[key] == true
				if down ~= was then
					local code = InputMap.browserCode(key)
					if code then
						if down then
							heldKeys[key] = true
							push({ type = "keydown", code = code })
						else
							heldKeys[key] = nil
							push({ type = "keyup", code = code })
						end
					end
				end
				polledDown[key] = down
			end
			if pointerLocked and (pendingDx ~= 0 or pendingDy ~= 0) then
				push({
					type = "mousemove",
					locked = true,
					dx = pendingDx,
					dy = pendingDy,
				})
				pendingDx = 0
				pendingDy = 0
			end
			if #queue > 0 then
				local batch = queue
				queue = table.create(32)
				gpuInput:FireServer(batch)
			end
		end
	end)

	push({ type = "focus" })
end

return GpuInputClient
