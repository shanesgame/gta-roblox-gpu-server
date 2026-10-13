-- Shared stream session: which app is open and which URL the capture browser shows.
local state = {
	appId = nil :: string?,
	url = nil :: string?,
	pointerLock = false,
	title = "Apps",
}

local GpuSession = {}

function GpuSession.get()
	return state
end

function GpuSession.isActive(): boolean
	return typeof(state.appId) == "string" and typeof(state.url) == "string"
end

function GpuSession.launch(appId: string, url: string, pointerLock: boolean, title: string?)
	state.appId = appId
	state.url = url
	state.pointerLock = pointerLock == true
	state.title = title or appId
end

function GpuSession.setUrl(url: string)
	if typeof(url) == "string" and #url > 0 then
		state.url = url
	end
end

function GpuSession.close()
	state.appId = nil
	state.url = nil
	state.pointerLock = false
	state.title = "Apps"
end

return GpuSession
