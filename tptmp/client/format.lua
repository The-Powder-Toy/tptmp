local colours = require("tptmp.client.colours")
local util    = require("tptmp.client.util")

local function nick(unformatted, seed)
	return colours.escape(colours.hsv_to_rgb(util.fnv1a32(seed .. unformatted .. "bagels") / 0x100000000, 0.5, 1)) .. unformatted
end

local function room(unformatted)
	if unformatted == "null" then
		return colours.commonstr.lobby .. "main lobby"
	elseif unformatted == "guest" then
		return colours.commonstr.lobby .. "guest lobby"
	else
		return "room " .. colours.commonstr.room .. unformatted
	end
end

return {
	nick = nick,
	room = room,
}
