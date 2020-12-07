local colours = require("tptmp.client.colours")
local util    = require("tptmp.client.util")
local utf8    = require("tptmp.client.utf8")
local config  = require("tptmp.client.config")
local manager = require("tptmp.client.manager")

local jacobsmod = rawget(_G, "jacobsmod")

local side_button_i = {}
local side_button_m = { __index = side_button_i }

function side_button_i:draw_button_()
	local inside = util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos())
	if self.active_ and not inside then
		self.active_ = false
	end
	local state
	if self.active_ or not self.window_hidden_func_() then
		state = "active"
	elseif inside then
		state = "hover"
	else
		state = "inactive"
	end
	local text_colour = colours.appearance[state].text
	local border_colour = colours.appearance[state].border
	local background_colour = colours.appearance[state].background
	gfx.fillRect(self.pos_x_ + 1, self.pos_y_ + 1, self.width_ - 2, self.height_ - 2, unpack(background_colour))
	gfx.drawRect(self.pos_x_, self.pos_y_, self.width_, self.height_, unpack(border_colour))
	gfx.drawText(self.tx_, self.ty_, self.text_, unpack(text_colour))
end

function side_button_i:update_notif_count_()
	local notif_count = self.notif_count_func_()
	local notif_important = self.notif_important_func_()
	if self.notif_count_ ~= notif_count or self.notif_important_ ~= notif_important then
		self.notif_count_ = notif_count
		self.notif_important_ = notif_important
		local notif_count_str = tostring(self.notif_count_)
		self.notif_background_ = utf8.encode_multiple(0xE03B, 0xE039) .. utf8.encode_multiple(0xE03C):rep(#notif_count_str - 1) .. utf8.encode_multiple(0xE03A)
		self.notif_border_ = utf8.encode_multiple(0xE02D, 0xE02B) .. utf8.encode_multiple(0xE02E):rep(#notif_count_str - 1) .. utf8.encode_multiple(0xE02C)
		self.notif_text_ = notif_count_str:gsub(".", function(ch)
			return utf8.encode_multiple(ch:byte() + 0xDFFF)
		end)
		self.notif_width_ = gfx.textSize(self.notif_background_)
		self.notif_last_change_ = socket.gettime()
	end
end

function side_button_i:draw_notif_count_()
	if self.notif_count_ > 0 then
		local since_last_change = socket.gettime() - self.notif_last_change_
		local fly = since_last_change > config.notif_fly_time and 0 or ((1 - since_last_change / config.notif_fly_time) * config.notif_fly_distance)
		gfx.drawText(self.pos_x_ - self.notif_width_ + 4, self.pos_y_ - 4 - fly, self.notif_background_, unpack(self.notif_important_ and colours.common.notif_important or colours.common.notif_normal))
		gfx.drawText(self.pos_x_ - self.notif_width_ + 4, self.pos_y_ - 4 - fly, self.notif_border_)
		gfx.drawText(self.pos_x_ - self.notif_width_ + 7, self.pos_y_ - 4 - fly, self.notif_text_)
	end
end

function side_button_i:handle_tick()
	self:draw_button_()
	self:update_notif_count_()
	self:draw_notif_count_()
end

function side_button_i:handle_mousedown(mx, my, button)
	if button == 1 then
		if util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos()) then
			self.active_ = true
		end
	end
end

function side_button_i:handle_mouseup(mx, my, button)
	if button == 1 then
		if self.active_ then
			if manager.minimize_conflict and not manager.hidden() then
				manager.print("minimize the manager before opening TPTMP")
			else
				if self.window_hidden_func_() then
					self.show_window_func_()
				else
					self.hide_window_func_()
				end
			end
			self.active_ = false
		end
	end
end

function side_button_i:handle_mousewheel(pos_x, pos_y, dir)
end

function side_button_i:handle_keypress(key, scan, rep, shift, ctrl, alt)
end

function side_button_i:handle_keyrelease(key, scan, rep, shift, ctrl, alt)
end

function side_button_i:handle_textinput(text)
end

function side_button_i:handle_textediting(text)
end

function side_button_i:handle_blur()
	self.active_ = false
end

local function new(params)
	local pos_x, pos_y, width, height = 613, 136, 15, 15
	if jacobsmod and tpt.oldmenu and tpt.oldmenu() == 1 then
		pos_y = 392
	elseif tpt.num_menus then
		pos_y = 392 - 16 * tpt.num_menus() - (not jacobsmod and 16 or 0)
	end
	if manager.side_button_conflict then
		pos_y = pos_y - 17
	end
	local text = "<<"
	local tw, th = gfx.textSize(text)
	local tx = pos_x + math.ceil((width - tw) / 2)
	local ty = pos_y + math.floor((height - th) / 2)
	return setmetatable({
		text_ = text,
		tx_ = tx,
		pos_x_ = pos_x,
		ty_ = ty,
		pos_y_ = pos_y,
		width_ = width,
		height_ = height,
		active_ = false,
		notif_last_change_ = 0,
		notif_count_ = 0,
		notif_important_ = false,
		notif_count_func_ = params.notif_count_func,
		notif_important_func_ = params.notif_important_func,
		show_window_func_ = params.show_window_func,
		hide_window_func_ = params.hide_window_func,
		window_hidden_func_ = params.window_hidden_func,
	}, side_button_m)
end

return {
	new = new,
}
