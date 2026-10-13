-- Shared input queue: GpuInputBridge pushes, GpuPipeline drains into the frame POST.
local q: { any } = {}

return {
	push = function(batch: { any })
		if typeof(batch) ~= "table" then
			return
		end
		for _, ev in batch do
			table.insert(q, ev)
		end
		while #q > 400 do
			table.remove(q, 1)
		end
	end,
	take = function(): { any }?
		if #q == 0 then
			return nil
		end
		local out = q
		q = {}
		return out
	end,
}
