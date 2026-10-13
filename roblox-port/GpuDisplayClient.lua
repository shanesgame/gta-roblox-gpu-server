local EncodingService = game:GetService("EncodingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("GTA_WebPort")
local Config = require(folder:WaitForChild("GpuConfig"))
local GpuDisplay = require(folder:WaitForChild("GpuDisplay"))

if not Config.ENABLED then
	return
end

local gpuFrame = folder:WaitForChild("Remotes"):WaitForChild("GpuFrame")
local display = GpuDisplay.new(Config.WIDTH, Config.HEIGHT, {
	pixelGridScale = Config.PIXEL_GRID_SCALE,
	rowsPerTick = Config.PIXEL_ROWS_PER_TICK,
	pixelRefreshFull = Config.PIXEL_REFRESH_FULL,
	pixelSharpBlocks = Config.PIXEL_SHARP_BLOCKS,
	fullscreen = Config.FULLSCREEN,
})
display:mount()

local GpuInputClient = require(folder:WaitForChild("GpuInputClient"))
GpuInputClient.start(folder:WaitForChild("Remotes"), Config.WIDTH, Config.HEIGHT)

-- Frames can interleave when the server has two captures in flight; assemble each seq separately.
local pending: { [number]: { total: number, got: number, w: number, h: number, parts: { buffer } } } = {}
local latestShown = 0

local function finish(seq: number, entry)
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
