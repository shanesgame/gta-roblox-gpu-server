-- Map Roblox KeyCode -> browser KeyboardEvent.code (index.html VK table)
local KeyCode = Enum.KeyCode

local KEY_TO_CODE: { [Enum.KeyCode]: string } = {
	[KeyCode.Backspace] = "Backspace",
	[KeyCode.Tab] = "Tab",
	[KeyCode.Return] = "Enter",
	[KeyCode.KeypadEnter] = "NumpadEnter",
	[KeyCode.Pause] = "Pause",
	[KeyCode.CapsLock] = "CapsLock",
	[KeyCode.Escape] = "Escape",
	[KeyCode.Space] = "Space",
	[KeyCode.PageUp] = "PageUp",
	[KeyCode.PageDown] = "PageDown",
	[KeyCode.End] = "End",
	[KeyCode.Home] = "Home",
	[KeyCode.Left] = "ArrowLeft",
	[KeyCode.Up] = "ArrowUp",
	[KeyCode.Right] = "ArrowRight",
	[KeyCode.Down] = "ArrowDown",
	[KeyCode.Insert] = "Insert",
	[KeyCode.Delete] = "Delete",
	[KeyCode.LeftShift] = "ShiftLeft",
	[KeyCode.RightShift] = "ShiftRight",
	[KeyCode.LeftControl] = "ControlLeft",
	[KeyCode.RightControl] = "ControlRight",
	[KeyCode.LeftAlt] = "AltLeft",
	[KeyCode.RightAlt] = "AltRight",
	[KeyCode.Semicolon] = "Semicolon",
	[KeyCode.Equals] = "Equal",
	[KeyCode.Comma] = "Comma",
	[KeyCode.Minus] = "Minus",
	[KeyCode.Period] = "Period",
	[KeyCode.Slash] = "Slash",
	[KeyCode.Backquote] = "Backquote",
	[KeyCode.LeftBracket] = "BracketLeft",
	[KeyCode.BackSlash] = "Backslash",
	[KeyCode.RightBracket] = "BracketRight",
	[KeyCode.Quote] = "Quote",
	[KeyCode.LeftSuper] = "MetaLeft",
	[KeyCode.RightSuper] = "MetaRight",
	[KeyCode.Menu] = "ContextMenu",
	[KeyCode.NumLock] = "NumLock",
	[KeyCode.ScrollLock] = "ScrollLock",
	[KeyCode.KeypadMultiply] = "NumpadMultiply",
	[KeyCode.KeypadPlus] = "NumpadAdd",
	[KeyCode.KeypadMinus] = "NumpadSubtract",
	[KeyCode.KeypadPeriod] = "NumpadDecimal",
	[KeyCode.KeypadDivide] = "NumpadDivide",
}

for i = 0, 9 do
	local name = ({ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" })[i + 1]
	KEY_TO_CODE[KeyCode[name]] = "Digit" .. tostring(i)
	KEY_TO_CODE[KeyCode["Keypad" .. name]] = "Numpad" .. tostring(i)
end

for i = 1, 26 do
	local letter = string.char(64 + i)
	KEY_TO_CODE[KeyCode[letter]] = "Key" .. letter
end

for i = 1, 12 do
	KEY_TO_CODE[KeyCode["F" .. tostring(i)]] = "F" .. tostring(i)
end

local GpuInputMap = {}

function GpuInputMap.browserCode(key: Enum.KeyCode): string?
	return KEY_TO_CODE[key]
end

-- Roblox UserInputType mouse button -> DOM button index (0=left, 1=right, 2=middle)
function GpuInputMap.mouseButton(inputType: Enum.UserInputType): number?
	if inputType == Enum.UserInputType.MouseButton1 then
		return 0
	elseif inputType == Enum.UserInputType.MouseButton2 then
		return 1
	elseif inputType == Enum.UserInputType.MouseButton3 then
		return 2
	end
	return nil
end

return GpuInputMap
