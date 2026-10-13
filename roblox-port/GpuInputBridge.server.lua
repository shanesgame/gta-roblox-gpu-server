-- Queues client input for GpuPipeline. Does NOT call HttpService itself —
-- Roblox only allows 500 HTTP requests/minute, so input rides on the frame POST.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("GTA_WebPort")
local Config = require(folder:WaitForChild("GpuConfig"))

if not Config.ENABLED then
	return
end

local Queue = require(folder:WaitForChild("GpuInputQueue"))

local remotes = folder:WaitForChild("Remotes")
local gpuInput = remotes:FindFirstChild("GpuInput")
if not gpuInput then
	gpuInput = Instance.new("RemoteEvent")
	gpuInput.Name = "GpuInput"
	gpuInput.Parent = remotes
end

gpuInput.OnServerEvent:Connect(function(_player, batch)
	if typeof(batch) ~= "table" or #batch == 0 then
		return
	end
	Queue.push(batch)
end)
