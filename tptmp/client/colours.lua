local utf8 = require("tptmp.client.utf8")

local function hsv_to_rgb(hue, saturation, value) -- * [0, 1), [0, 1), [0, 1)
	local sector = math.floor(hue * 6)
	local offset = hue * 6 - sector
	local red, green, blue
	if sector == 0 then
		red, green, blue = 1, offset, 0
	elseif sector == 1 then
		red, green, blue = 1 - offset, 1, 0
	elseif sector == 2 then
		red, green, blue = 0, 1, offset
	elseif sector == 3 then
		red, green, blue = 0, 1 - offset, 1
	elseif sector == 4 then
		red, green, blue = offset, 0, 1
	else
		red, green, blue = 1, 0, 1 - offset
	end
	return {
		math.floor((saturation * (red   - 1) + 1) * 0xFF * value),
		math.floor((saturation * (green - 1) + 1) * 0xFF * value),
		math.floor((saturation * (blue  - 1) + 1) * 0xFF * value),
	}
end

local function escape(rgb)
	-- * TODO[api]: Fix this TPT bug: most strings are still passed to/from Lua as zero-terminated, hence the math.max.
	return utf8.encode_multiple(15, math.max(rgb[1], 1), math.max(rgb[2], 1), math.max(rgb[3], 1))
end

local common = {}
local commonstr = {}
for key, value in pairs({
	brush           = {   0, 255,   0 },
	chat            = { 255, 255, 255 },
	error           = { 255,  50,  50 },
	event           = { 255, 255, 255 },
	join            = { 100, 255, 100 },
	leave           = { 255, 255, 100 },
	fpssyncenable   = { 255, 100, 255 },
	fpssyncdisable  = { 130, 130, 255 },
	lobby           = {   0, 200, 200 },
	neutral         = { 200, 200, 200 },
	room            = { 200, 200,   0 },
	status          = { 150, 150, 150 },
	notif_normal    = { 100, 100, 100 },
	notif_important = { 255,  50,  50 },
	player_cursor   = {   0, 255,   0, 128 },
}) do
	common[key] = value
	commonstr[key] = escape(value)
end

local appearance = {
	hover = {
		background = {  20,  20,  20 },
		text       = { 255, 255, 255 },
		border     = { 255, 255, 255 },
	},
	inactive = {
		background = {   0,   0,   0 },
		text       = { 255, 255, 255 },
		border     = { 200, 200, 200 },
	},
	active = {
		background = { 255, 255, 255 },
		text       = {   0,   0,   0 },
		border     = { 235, 235, 235 },
	},
}

return {
	escape = escape,
	common = common,
	commonstr = commonstr,
	hsv_to_rgb = hsv_to_rgb,
	appearance = appearance,
}
