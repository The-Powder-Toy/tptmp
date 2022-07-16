local colours = require("tptmp.client.colours")
local util    = require("tptmp.client.util")

local function nick(unformatted, seed)
	return colours.escape(colours.hsv_to_rgb(util.fnv1a32(seed .. unformatted .. "bagels") / 0x100000000, 0.5, 1)) .. unformatted
end

local names = {
	[   "null" ] = "lobby",
	[  "guest" ] = "guest lobby",
	[ "kicked" ] = "a dark alley",
}

local function room(unformatted)
	local name = names[unformatted]
	return name and (colours.commonstr.lobby .. name) or (colours.commonstr.room .. unformatted)
end

local function troom(unformatted)
	local name = names[unformatted]
	return name and (colours.commonstr.lobby .. name) or ("room " .. colours.commonstr.room .. unformatted)
end

return {
	nick = nick,
	room = room,
	troom = troom,
}
