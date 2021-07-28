local vanilla = require("tptmp.client.profile.vanilla")
local config  = require("tptmp.client.config")

local profile_i = {}
local profile_m = { __index = profile_i }

for key, value in pairs(vanilla.profile_i) do
	profile_i[key] = value
end

function profile_i:handle_mousedown(px, py, button)
	if self.client and (tpt.tab_menu() == 1 or self.kmod_c_) and px >= sim.XRES and py < 116 and not self.kmod_a_ then
		vanilla.log_event(config.print_prefix .. "The tab menu is disabled because it does not sync (press the Alt key to override)")
		return true
	end
	return vanilla.profile_i.handle_mousedown(self, px, py, button)
end

local function new(params)
	local prof = vanilla.new(params)
	prof.buttons_.clear = { x = gfx.WIDTH - 148, y = gfx.HEIGHT - 16, w = 17, h = 15 }
	setmetatable(prof, profile_m)
	return prof
end

return {
	new = new,
	brand = "jacobs",
}
