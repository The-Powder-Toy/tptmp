local colours = require("tptmp.client.colours")

local function nick(unformatted)
	-- * TODO[opt]: a better nick colour hash?
	local hash = 9.238762
	for i = 1, #unformatted do
		hash = (hash * 13.23472364 + unformatted:byte(i)) % 235.21974612
	end
	return colours.escape(colours.hsv_to_rgb(hash % 1, 0.5, 1)) .. unformatted
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
