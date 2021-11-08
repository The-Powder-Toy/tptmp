local config  = require("tptmp.client.config")
local colours = require("tptmp.client.colours")
local format  = require("tptmp.client.format")
local utf8    = require("tptmp.client.utf8")
local util    = require("tptmp.client.util")
local manager = require("tptmp.client.manager")
local sdl     = require("tptmp.client.sdl")

local notif_important = colours.common.notif_important
local text_bg_high = { notif_important[1] / 2, notif_important[2] / 2, notif_important[3] / 2 }
local text_bg_high_floating = { notif_important[1] / 3, notif_important[2] / 3, notif_important[3] / 3 }
local text_bg = { 0, 0, 0 }

local window_i = {}
local window_m = { __index = window_i }

local wrap_padding = 11 -- * Width of "* "

function window_i:backlog_push_join(formatted_nick)
	self:backlog_push_str(colours.commonstr.join .. "* " .. formatted_nick .. colours.commonstr.join .. " has joined", true)
end

function window_i:backlog_push_leave(formatted_nick)
	self:backlog_push_str(colours.commonstr.leave .. "* " .. formatted_nick .. colours.commonstr.leave .. " has left", true)
end

function window_i:backlog_push_fpssync_enable(formatted_nick)
	self:backlog_push_str(colours.commonstr.fpssyncenable .. "* " .. formatted_nick .. colours.commonstr.fpssyncenable .. " has enabled FPS synchronization", true)
end

function window_i:backlog_push_fpssync_disable(formatted_nick)
	self:backlog_push_str(colours.commonstr.fpssyncdisable .. "* " .. formatted_nick .. colours.commonstr.fpssyncdisable .. " has disabled FPS synchronization", true)
end

function window_i:backlog_push_error(str)
	self:backlog_push_str(colours.commonstr.error .. "* " .. str, true)
end

function window_i:get_important_(str)
	local cli = self.client_func_()
	if cli then
		if (" " .. str .. " "):lower():find("[^a-z0-9-_]" .. cli:nick():lower() .. "[^a-z0-9-_]") then
			return "highlight"
		end
	end
end

function window_i:backlog_push_say_other(formatted_nick, str)
	self:backlog_push_say(formatted_nick, str, self:get_important_(str))
end

function window_i:backlog_push_say3rd_other(formatted_nick, str)
	self:backlog_push_say3rd(formatted_nick, str, self:get_important_(str))
end

function window_i:backlog_push_say(formatted_nick, str, important)
	self:backlog_push_str(colours.commonstr.chat .. "<" .. formatted_nick .. colours.commonstr.chat .. "> " .. str, important)
end

function window_i:backlog_push_say3rd(formatted_nick, str, important)
	self:backlog_push_str(colours.commonstr.chat .. "* " .. formatted_nick .. colours.commonstr.chat .. " " .. str, important)
end

function window_i:backlog_push_room(room, members, prefix)
	local sep = colours.commonstr.neutral .. ", "
	local collect = { colours.commonstr.neutral, "* ", prefix, format.troom(room), sep }
	if next(members) then
		table.insert(collect, "present: ")
		local first = true
		for id, member in pairs(members) do
			if first then
				first = false
			else
				table.insert(collect, sep)
			end
			table.insert(collect, member.formatted_nick)
		end
	else
		table.insert(collect, "nobody else present")
	end
	self:backlog_push_str(table.concat(collect), true)
end

function window_i:backlog_push_fpssync(members)
	local sep = colours.commonstr.neutral .. ", "
	local collect = { colours.commonstr.neutral, "* " }
	if members == true then
		table.insert(collect, "FPS synchronization is enabled")
	elseif members then
		if next(members) then
			table.insert(collect, "FPS synchronization is enabled, in sync with: ")
			local first = true
			for id, member in pairs(members) do
				if first then
					first = false
				else
					table.insert(collect, sep)
				end
				table.insert(collect, member.formatted_nick)
			end
		else
			table.insert(collect, "FPS synchronization is enabled, not in sync with anyone")
		end
	else
		table.insert(collect, "FPS synchronization is disabled")
	end
	self:backlog_push_str(table.concat(collect), true)
end

function window_i:backlog_push_registered(formatted_nick)
	self:backlog_push_str(colours.commonstr.neutral .. "* Connected as " .. formatted_nick, true)
end

local server_colours = {
	n = colours.commonstr.neutral,
	e = colours.commonstr.error,
	j = colours.commonstr.join,
	l = colours.commonstr.leave,
}
function window_i:backlog_push_server(str)
	local formatted = str
		:gsub("\au([A-Za-z0-9-_#]+)", function(cap) return format.nick(cap, self.nick_colour_seed_) end)
		:gsub("\ar([A-Za-z0-9-_#]+)", function(cap) return format.room(cap)                         end)
		:gsub("\a([nejl])"          , function(cap) return server_colours[cap]                      end)
	self:backlog_push_str(formatted, true)
end

function window_i:nick_colour_seed(seed)
	self.nick_colour_seed_ = seed
end

function window_i:backlog_push_neutral(str)
	self:backlog_push_str(colours.commonstr.neutral .. str, true)
end

function window_i:backlog_wrap_(msg)
	if msg == self.backlog_first_ then
		return
	end
	if msg.wrapped_to ~= self.width_ then
		local line = {}
		local wrapped = {}
		local collect = msg.collect
		local i = 0
		local word = {}
		local word_width = 0
		local line_width = 0
		local max_width = self.width_ - 8
		local line_empty = true
		local red, green, blue = 255, 255, 255
		local initial_block
		local function insert_block(block)
			if initial_block then
				table.insert(line, initial_block)
				initial_block = nil
			end
			table.insert(line, block)
		end
		local function flush_line()
			if not line_empty then
				table.insert(wrapped, table.concat(line))
				line = {}
				initial_block = colours.escape({ red, green, blue })
				line_width = wrap_padding
				line_empty = true
			end
		end
		local function flush_word()
			if #word > 0 then
				for i = 1, #word do
					insert_block(word[i])
				end
				line_empty = false
				line_width = line_width + word_width
				word = {}
				word_width = 0
			end
		end
		while i < #collect do
			i = i + 1
			if collect[i] == "\15" and i + 3 <= #collect then
				local rgb = utf8.code_points(table.concat(collect, nil, i + 1, i + 3))
				if rgb then
					for j = i, i + 3 do
						table.insert(word, collect[j])
					end
					red, green, blue = rgb[1].cp, rgb[2].cp, rgb[3].cp
				end
				i = i + 3
			else
				local i_width = gfx.textSize(collect[i])
				if collect[i]:find(config.whitespace_pattern) then
					flush_word()
					if line_width + i_width > max_width then
						flush_line()
					end
					if not line_empty then
						insert_block(collect[i])
						line_width = line_width + i_width
					end
					line_empty = false
				else
					if line_width + word_width + i_width > max_width then
						flush_line()
						if line_width + word_width + i_width > max_width then
							flush_word()
							if line_width + word_width + i_width > max_width then
								flush_line()
							end
						end
					end
					table.insert(word, collect[i])
					word_width = word_width + i_width
				end
			end
		end
		flush_word()
		flush_line()
		if #wrapped > 1 and wrapped[#wrapped] == "" then
			wrapped[#wrapped] = nil
		end
		msg.wrapped_to = self.width_
		msg.wrapped = wrapped
		self.backlog_last_wrapped_ = math.max(self.backlog_last_wrapped_, msg.unique)
	end
end

function window_i:backlog_update_()
	local max_lines = math.floor((self.height_ - 35) / 12)
	local lines_reverse = {}
	self:backlog_wrap_(self.backlog_last_visible_msg_)
	if self.backlog_auto_scroll_ then
		while self.backlog_last_visible_msg_.next ~= self.backlog_last_ do
			self.backlog_last_visible_msg_ = self.backlog_last_visible_msg_.next
		end
		self:backlog_wrap_(self.backlog_last_visible_msg_)
		self.backlog_last_visible_line_ = #self.backlog_last_visible_msg_.wrapped
	end
	self:backlog_wrap_(self.backlog_last_visible_msg_)
	self.backlog_last_visible_line_ = math.min(#self.backlog_last_visible_msg_.wrapped, self.backlog_last_visible_line_)
	local source_msg = self.backlog_last_visible_msg_
	local source_line = self.backlog_last_visible_line_
	while #lines_reverse < max_lines do
		if source_msg == self.backlog_first_ then
			break
		end
		self:insert_wrapped_line_(lines_reverse, source_msg, source_line)
		source_line = source_line - 1
		if source_line == 0 then
			source_msg = source_msg.prev
			self:backlog_wrap_(source_msg)
			source_line = #source_msg.wrapped
		end
	end
	if source_msg ~= self.backlog_first_ and source_msg.unique - 1 <= self.backlog_unique_ - config.backlog_size then
		source_msg.prev = self.backlog_first_
		self.backlog_first_.next = source_msg
	end
	local lines = {}
	for i = #lines_reverse, 1, -1 do
		table.insert(lines, lines_reverse[i])
	end
	while #lines < max_lines do
		if self.backlog_last_visible_line_ == #self.backlog_last_visible_msg_.wrapped then
			if self.backlog_last_visible_msg_.next == self.backlog_last_ then
				break
			end
			self.backlog_last_visible_msg_ = self.backlog_last_visible_msg_.next
			self:backlog_wrap_(self.backlog_last_visible_msg_)
			self.backlog_last_visible_line_ = 1
		else
			self.backlog_last_visible_line_ = self.backlog_last_visible_line_ + 1
		end
		self:insert_wrapped_line_(lines, self.backlog_last_visible_msg_, self.backlog_last_visible_line_)
	end
	self.backlog_text_ = {}
	local marker_after
	for i = 1, #lines do
		local text_width = gfx.textSize(lines[i].wrapped)
		local padding = lines[i].needs_padding and wrap_padding or 0
		local box_width = lines[i].extend_box and self.width_ or (padding + text_width + 10)
		table.insert(self.backlog_text_, {
			padding = padding,
			pushed_at = lines[i].msg.pushed_at,
			highlight = lines[i].msg.important == "highlight",
			text = lines[i].wrapped,
			box_width = box_width,
		})
		if lines[i].marker then
			marker_after = i
		end
	end
	self.backlog_lines_ = lines
	self.backlog_text_y_ = self.height_ - #lines * 12 - 15
	self.backlog_marker_y_ = self.backlog_enable_marker_ and marker_after and marker_after ~= #lines and (self.backlog_text_y_ + marker_after * 12 - 2)
end

function window_i:backlog_push_(collect, important)
	self.backlog_unique_ = self.backlog_unique_ + 1
	local msg = {
		unique = self.backlog_unique_,
		collect = collect,
		prev = self.backlog_last_.prev,
		next = self.backlog_last_,
		important = important,
		pushed_at = socket.gettime(),
	}
	self.backlog_last_.prev.next = msg
	self.backlog_last_.prev = msg
	if important then
		self.backlog_unique_important_ = self.backlog_unique_
	end
	self:backlog_update_()
end

function window_i:backlog_push_str(str, important)
	local collect = {}
	local cps = utf8.code_points(str)
	if cps then
		for i = 1, #cps do
			table.insert(collect, str:sub(cps[i].pos, cps[i].pos + cps[i].size - 1))
		end
		self:backlog_push_(collect, important)
	end
end

function window_i:backlog_bump_marker()
	self.backlog_enable_marker_ = false
	if self.backlog_last_seen_ < self.backlog_unique_ then
		self.backlog_enable_marker_ = true
		self.backlog_marker_at_ = self.backlog_last_seen_
	end
	self:backlog_update_()
end

function window_i:backlog_notif_reset()
	self.backlog_last_seen_ = self.backlog_unique_
	self:backlog_bump_marker()
end

function window_i:backlog_notif_count()
	return self.backlog_unique_ - self.backlog_last_seen_
end

function window_i:backlog_notif_important()
	return self.backlog_unique_important_ - self.backlog_last_seen_ > 0
end

function window_i:backlog_reset()
	self.backlog_unique_ = 0
	self.backlog_unique_important_ = 0
	self.backlog_last_wrapped_ = 0
	self.backlog_last_seen_ = 0
	self.backlog_marker_at_ = 0
	self.backlog_last_ = { wrapped = {}, unique = 0 }
	self.backlog_first_ = { wrapped = {} }
	self.backlog_last_.prev = self.backlog_first_
	self.backlog_first_.next = self.backlog_last_
	self.backlog_last_visible_msg_ = self.backlog_first_
	self.backlog_last_visible_line_ = 0
	self.backlog_auto_scroll_ = true
	self.backlog_enable_marker_ = false
	self:backlog_update_()
end

local close_button_off_x = -12
local close_button_off_y = 3
if tpt.version.jacob1s_mod then
	close_button_off_x = -11
	close_button_off_y = 4
end
function window_i:tick_close_()
	local border_colour = colours.appearance.inactive.border
	local close_fg = colours.appearance.inactive.text
	local close_bg
	local inside_close = util.inside_rect(self.pos_x_ + self.width_ - 15, self.pos_y_, 15, 15, util.mouse_pos())
	if self.close_active_ then
		close_fg = colours.appearance.active.text
		close_bg = colours.appearance.active.background
	elseif inside_close then
		close_fg = colours.appearance.hover.text
		close_bg = colours.appearance.hover.background
	end
	if close_bg then
		gfx.fillRect(self.pos_x_ + self.width_ - 14, self.pos_y_ + 1, 13, 13, unpack(close_bg))
	end
	gfx.drawLine(self.pos_x_ + self.width_ - 15, self.pos_y_ + 1, self.pos_x_ + self.width_ - 15, self.pos_y_ + 13, unpack(border_colour))
	gfx.drawText(self.pos_x_ + self.width_ + close_button_off_x, self.pos_y_ + close_button_off_y, utf8.encode_multiple(0xE02A), unpack(close_fg))
	if self.close_active_ and not inside_close then
		self.close_active_ = false
	end
end

function window_i:handle_tick()
	local floating = self.window_status_func_() == "floating"
	local now = socket.gettime()

	if self.backlog_auto_scroll_ and not floating then
		self.backlog_last_seen_ = self.backlog_last_wrapped_
	else
		if self.backlog_last_seen_ < self.backlog_unique_ and not self.backlog_enable_marker_ then
			self:backlog_bump_marker()
		end
	end

	if self.resizer_active_ then
		local resizer_x, resizer_y = util.mouse_pos()
		local prev_x, prev_y = self.pos_x_, self.pos_y_
		self.pos_x_ = math.min(math.max(1, self.pos_x_ + resizer_x - self.resizer_last_x_), self.pos_x_ + self.width_ - config.min_width)
		self.pos_y_ = math.min(math.max(1, self.pos_y_ + resizer_y - self.resizer_last_y_), self.pos_y_ + self.height_ - config.min_height)
		local diff_x, diff_y = self.pos_x_ - prev_x, self.pos_y_ - prev_y
		self.resizer_last_x_ = self.resizer_last_x_ + diff_x
		self.resizer_last_y_ = self.resizer_last_y_ + diff_y
		self.width_ = self.width_ - diff_x
		self.height_ = self.height_ - diff_y
		self:input_update_()
		self:backlog_update_()
		self:subtitle_update_()
		self:save_window_rect_()
	end
	if self.dragger_active_ then
		local dragger_x, dragger_y = util.mouse_pos()
		local prev_x, prev_y = self.pos_x_, self.pos_y_
		self.pos_x_ = math.min(math.max(1, self.pos_x_ + dragger_x - self.dragger_last_x_), sim.XRES - self.width_)
		self.pos_y_ = math.min(math.max(1, self.pos_y_ + dragger_y - self.dragger_last_y_), sim.YRES - self.height_)
		local diff_x, diff_y = self.pos_x_ - prev_x, self.pos_y_ - prev_y
		self.dragger_last_x_ = self.dragger_last_x_ + diff_x
		self.dragger_last_y_ = self.dragger_last_y_ + diff_y
		self:save_window_rect_()
	end

	local border_colour = colours.appearance[self.in_focus and "active" or "inactive"].border
	local background_colour = colours.appearance.inactive.background
	if not floating then
		gfx.fillRect(self.pos_x_ + 1, self.pos_y_ + 1, self.width_ - 2, self.height_ - 2, background_colour[1], background_colour[2], background_colour[3], self.alpha_)
		gfx.drawRect(self.pos_x_, self.pos_y_, self.width_, self.height_, unpack(border_colour))

		self:tick_close_()

		local subtitle_blue = 255
		if #self.input_collect_ > 0 and self.input_last_say_ + config.message_interval >= now then
			subtitle_blue = 0
		end
		gfx.drawText(self.pos_x_ + 18, self.pos_y_ + 4, self.subtitle_text_, 255, 255, subtitle_blue)

		gfx.drawText(self.pos_x_ + self.width_ - self.title_width_ - 17, self.pos_y_ + 4, self.title_)
		for i = 1, 3 do
			gfx.drawLine(self.pos_x_ + i * 3 + 1, self.pos_y_ + 3, self.pos_x_ + 3, self.pos_y_ + i * 3 + 1, unpack(border_colour))
		end
		gfx.drawLine(self.pos_x_ + 1, self.pos_y_ + 14, self.pos_x_ + self.width_ - 2, self.pos_y_ + 14, unpack(border_colour))
		gfx.drawLine(self.pos_x_ + 14, self.pos_y_ + 1, self.pos_x_ + 14, self.pos_y_ + 13, unpack(border_colour))
	end

	local prev_text, prev_fades_at, prev_alpha, prev_box_width, prev_highlight
	for i = 1, #self.backlog_text_ + 1 do
		local fades_at, alpha, box_width, highlight
		if self.backlog_text_[i] then
			fades_at = self.backlog_text_[i].pushed_at + config.floating_linger_time + config.floating_fade_time
			alpha = math.max(0, math.min(1, (fades_at - now) / config.floating_fade_time))
			box_width = self.backlog_text_[i].box_width
			highlight = self.backlog_text_[i].highlight
		end
		if not prev_fades_at then
			prev_fades_at, prev_alpha, prev_box_width, prev_highlight = fades_at, alpha, box_width, highlight
		elseif not fades_at then
			fades_at, alpha, box_width, highlight = prev_fades_at, prev_alpha, prev_box_width, prev_highlight
		end

		local comm_box_width = math.max(box_width, prev_box_width)
		local min_box_width = math.min(box_width, prev_box_width)
		local comm_fades_at = math.max(fades_at, prev_fades_at)
		local comm_alpha = math.max(alpha, prev_alpha)
		local comm_highlight = highlight or prev_highlight
		local diff_fades_at = prev_fades_at
		local diff_alpha = prev_alpha
		local diff_highlight = prev_highlight
		if box_width > prev_box_width then
			diff_fades_at = fades_at
			diff_alpha = alpha
			diff_highlight = highlight
		end
		if floating and diff_fades_at > now then
			local rgb = diff_highlight and text_bg_high_floating or text_bg
			gfx.fillRect(self.pos_x_ - 1 + min_box_width, self.pos_y_ + self.backlog_text_y_ + i * 12 - 15, comm_box_width - min_box_width, 2, rgb[1], rgb[2], rgb[3], diff_alpha * self.alpha_)
		end
		if floating and comm_fades_at > now then
			local rgb = comm_highlight and text_bg_high_floating or text_bg
			local alpha = 1
			if not highlight and prev_alpha < comm_alpha then
				alpha = prev_alpha
			end
			gfx.fillRect(self.pos_x_ - 1, self.pos_y_ + self.backlog_text_y_ + i * 12 - 15, min_box_width, 2, alpha * rgb[1], alpha * rgb[2], alpha * rgb[3], comm_alpha * self.alpha_)
		end

		if prev_text then
			local alpha = 1
			if floating then
				alpha = math.min(1, (prev_fades_at - now) / config.floating_fade_time)
			end
			if floating and prev_fades_at > now then
				local rgb = prev_highlight and text_bg_high_floating or text_bg
				gfx.fillRect(self.pos_x_ - 1, self.pos_y_ + self.backlog_text_y_ + i * 12 - 25, prev_box_width, 10, rgb[1], rgb[2], rgb[3], alpha * self.alpha_)
			end
			if not floating and prev_highlight then
				gfx.fillRect(self.pos_x_ + 1, self.pos_y_ + self.backlog_text_y_ + i * 12 - 26, self.width_ - 2, 12, text_bg_high[1], text_bg_high[2], text_bg_high[3], alpha * self.alpha_)
			end
			if not floating or prev_fades_at > now then
				gfx.drawText(self.pos_x_ + 4 + prev_text.padding, self.pos_y_ + self.backlog_text_y_ + i * 12 - 24, prev_text.text, 255, 255, 255, alpha * 255)
			end
		end
		prev_text, prev_alpha, prev_fades_at, prev_box_width, prev_highlight = self.backlog_text_[i], alpha, fades_at, box_width, highlight
	end

	if not floating then
		if self.backlog_marker_y_ then
			gfx.drawLine(self.pos_x_ + 1, self.pos_y_ + self.backlog_marker_y_, self.pos_x_ + self.width_ - 2, self.pos_y_ + self.backlog_marker_y_, unpack(notif_important))
		end

		gfx.drawLine(self.pos_x_ + 1, self.pos_y_ + self.height_ - 15, self.pos_x_ + self.width_ - 2, self.pos_y_ + self.height_ - 15, unpack(border_colour))
		if self.input_has_selection_ then
			gfx.fillRect(self.pos_x_ + self.input_sel_low_x_ + self.input_scroll_x_, self.pos_y_ + self.height_ - 13, self.input_sel_high_x_ - self.input_sel_low_x_, 11)
		end
		gfx.drawText(self.pos_x_ + 4 + self.input_text_1x_, self.pos_y_ + self.height_ - 11, self.input_text_1_)
		gfx.drawText(self.pos_x_ + 4 + self.input_text_2x_, self.pos_y_ + self.height_ - 11, self.input_text_2_, 0, 0, 0)
		gfx.drawText(self.pos_x_ + 4 + self.input_text_3x_, self.pos_y_ + self.height_ - 11, self.input_text_3_)
		if self.in_focus and now % 1 < 0.5 then
			gfx.drawLine(self.pos_x_ + self.input_cursor_x_ + self.input_scroll_x_, self.pos_y_ + self.height_ - 13, self.pos_x_ + self.input_cursor_x_ + self.input_scroll_x_, self.pos_y_ + self.height_ - 3)
		end
	end
end

function window_i:handle_mousedown(px, py, button)
	if self.should_ignore_mouse_func_() then
		return
	end
	-- * TODO[opt]: mouse selection
	if button == sdl.SDL_BUTTON_LEFT then
		if util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos()) then
			self.in_focus = true
		end
		if util.inside_rect(self.pos_x_, self.pos_y_, 15, 15, util.mouse_pos()) then
			self.resizer_active_ = true
			self.resizer_last_x_, self.resizer_last_y_ = util.mouse_pos()
			return true
		end
		if util.inside_rect(self.pos_x_ + 15, self.pos_y_, self.width_ - 30, 15, util.mouse_pos()) then
			self.dragger_active_ = true
			self.dragger_last_x_, self.dragger_last_y_ = util.mouse_pos()
			return true
		end
		if util.inside_rect(self.pos_x_ + self.width_ - 15, self.pos_y_, 15, 15, util.mouse_pos()) then
			self.close_active_ = true
			return true
		end
	elseif button == sdl.SDL_BUTTON_RIGHT then
		if util.inside_rect(self.pos_x_ + 1, self.pos_y_ + 15, self.width_ - 2, self.height_ - 30, util.mouse_pos()) then
			local _, y = util.mouse_pos()
			local line = 1 + math.floor((y - self.backlog_text_y_ - self.pos_y_) / 12)
			if self.backlog_lines_[line] then
				local collect = self.backlog_lines_[line].msg.collect
				local collect_sane = {}
				local i = 0
				while i < #collect do
					i = i + 1
					if collect[i] == "\15" then
						i = i + 3
					elseif collect[i]:byte() >= 32 then
						table.insert(collect_sane, collect[i])
					end
				end
				plat.clipboardPaste(table.concat(collect_sane))
				self.log_event_func_("Message copied to clipboard")
			end
			return true
		end
	end
	if util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos()) then
		return true
	elseif self.in_focus then
		self.in_focus = false
	end
end

function window_i:handle_mouseup(px, py, button)
	if button == sdl.SDL_BUTTON_LEFT then
		if self.close_active_ then
			self.hide_window_func_()
		end
		self.resizer_active_ = false
		self.dragger_active_ = false
		self.close_active_ = false
	end
end

function window_i:handle_mousewheel(px, py, dir)
	if util.inside_rect(self.pos_x_, self.pos_y_ + 15, self.width_, self.height_ - 30, util.mouse_pos()) then
		self:backlog_wrap_(self.backlog_last_visible_msg_)
		while dir > 0 do
			if self.backlog_last_visible_line_ > 1 then
				self.backlog_last_visible_line_ = self.backlog_last_visible_line_ - 1
				self.backlog_auto_scroll_ = false
			elseif self.backlog_last_visible_msg_ ~= self.backlog_first_ then
				self.backlog_last_visible_msg_ = self.backlog_last_visible_msg_.prev
				self:backlog_wrap_(self.backlog_last_visible_msg_)
				self.backlog_last_visible_line_ = #self.backlog_last_visible_msg_.wrapped
				self.backlog_auto_scroll_ = false
			end
			dir = dir - 1
		end
		while dir < 0 do
			if self.backlog_last_visible_line_ < #self.backlog_last_visible_msg_.wrapped then
				self.backlog_last_visible_line_ = self.backlog_last_visible_line_ + 1
			elseif self.backlog_last_visible_msg_.next ~= self.backlog_last_ then
				self.backlog_last_visible_msg_ = self.backlog_last_visible_msg_.next
				self.backlog_last_visible_line_ = 1
			end
			self:backlog_wrap_(self.backlog_last_visible_msg_)
			if self.backlog_last_visible_msg_.next == self.backlog_last_ and self.backlog_last_visible_line_ == #self.backlog_last_visible_msg_.wrapped then
				self.backlog_auto_scroll_ = true
			end
			dir = dir + 1
		end
		self:backlog_update_()
		return true
	end
	if util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos()) then
		return true
	end
end

local modkey_scan = {
	[ sdl.SDL_SCANCODE_LCTRL  ] = true,
	[ sdl.SDL_SCANCODE_LSHIFT ] = true,
	[ sdl.SDL_SCANCODE_LALT   ] = true,
	[ sdl.SDL_SCANCODE_RCTRL  ] = true,
	[ sdl.SDL_SCANCODE_RSHIFT ] = true,
	[ sdl.SDL_SCANCODE_RALT   ] = true,
}
function window_i:handle_keypress(key, scan, rep, shift, ctrl, alt)
	if not self.in_focus and self.window_status_func_() == "shown" and scan == sdl.SDL_SCANCODE_RETURN then
		self.in_focus = true
		return true
	end
	if self.in_focus then
		if not ctrl and not alt and scan == sdl.SDL_SCANCODE_ESCAPE then
			if self.in_focus then
				self.in_focus = false
				self.input_autocomplete_ = nil
				local force_hide = false
				if self.hide_when_chat_done then
					self.hide_when_chat_done = false
					force_hide = true
					self:input_reset_()
				end
				if shift or force_hide then
					self.hide_window_func_()
				end
			else
				self.in_focus = true
			end
		elseif not ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_TAB then
			local left_word_first, left_word
			local cursor = self.input_cursor_
			local check_offset = 0
			while self.input_collect_[cursor + check_offset] and not self.input_collect_[cursor + check_offset]:find(config.whitespace_pattern) do
				check_offset = check_offset - 1
			end
			if check_offset < 0 then
				left_word_first = cursor + check_offset + 1
				left_word = table.concat(self.input_collect_, "", left_word_first, cursor)
			end
			local cli = self.client_func_()
			if left_word and cli then
				left_word = left_word:lower()
				if self.input_autocomplete_ and not left_word:find("^" .. util.escape_regex(self.input_autocomplete_)) then
					self.input_autocomplete_ = nil
				end
				if not self.input_autocomplete_ then
					self.input_autocomplete_ = left_word
				end
				local nicks = {}
				local function try_complete(nick)
					if nick:lower():find("^" .. util.escape_regex(self.input_autocomplete_)) then
						table.insert(nicks, nick)
					end
				end
				try_complete(cli:nick())
				for _, member in pairs(cli.id_to_member) do
					try_complete(member.nick)
				end
				if next(nicks) then
					table.sort(nicks)
					local index = 1
					for i = 1, #nicks do
						if nicks[i]:lower() == left_word and nicks[i + 1] then
							index = i + 1
						end
					end
					self.input_sel_first_ = left_word_first - 1
					self.input_sel_second_ = cursor
					self:input_update_()
					self:input_insert_(nicks[index])
				end
			else
				self.input_autocomplete_ = nil
			end
		elseif not shift and not alt and (scan == sdl.SDL_SCANCODE_BACKSPACE or scan == sdl.SDL_SCANCODE_DELETE) then
			local start, length
			if self.input_has_selection_ then
				start = self.input_sel_low_
				length = self.input_sel_high_ - self.input_sel_low_
				self.input_cursor_ = self.input_sel_low_
			elseif (scan == sdl.SDL_SCANCODE_BACKSPACE and self.input_cursor_ > 0) or (scan == sdl.SDL_SCANCODE_DELETE and self.input_cursor_ < #self.input_collect_) then
				if ctrl then
					local cursor_step = scan == sdl.SDL_SCANCODE_DELETE and 1 or -1
					local check_offset = scan == sdl.SDL_SCANCODE_DELETE and 1 or  0
					local cursor = self.input_cursor_
					while self.input_collect_[cursor + check_offset] and self.input_collect_[cursor + check_offset]:find(config.whitespace_pattern) do
						cursor = cursor + cursor_step
					end
					while self.input_collect_[cursor + check_offset] and self.input_collect_[cursor + check_offset]:find(config.word_pattern) do
						cursor = cursor + cursor_step
					end
					if cursor == self.input_cursor_ then
						cursor = cursor + cursor_step
					end
					start = self.input_cursor_
					length = cursor - self.input_cursor_
					if length < 0 then
						start = start + length
						length = -length
					end
					self.input_cursor_ = start
				else
					if scan == sdl.SDL_SCANCODE_BACKSPACE then
						self.input_cursor_ = self.input_cursor_ - 1
					end
					start = self.input_cursor_
					length = 1
				end
			end
			if start then
				self:input_remove_(start, length)
				self:input_update_()
			end
			self.input_autocomplete_ = nil
		elseif not ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_RETURN then
			if #self.input_collect_ > 0 then
				local str = self:input_text_to_send_()
				local sent = str ~= "" and not self.message_overlong_
				if sent then
					local cli = self.client_func_()
					if self.localcmd and self.localcmd:parse(str) then
						-- * Nothing.
					elseif cli then
						local cps = utf8.code_points(str)
						local last = 0
						for i = 1, #cps do
							local new_last = cps[i].pos + cps[i].size - 1
							if new_last > config.message_size then
								break
							end
							last = new_last
						end
						local now = socket.gettime()
						if self.input_last_say_ + config.message_interval >= now then
							sent = false
						else
							self.input_last_say_  = now
							local limited_str = str:sub(1, last)
							self:backlog_push_say(cli:formatted_nick(), limited_str:gsub("^//", "/"))
							cli:send_say(limited_str)
						end
					else
						self:backlog_push_error("Not connected, message not sent")
					end
				end
				if sent then
					self.input_history_[self.input_history_next_] = self.input_editing_[self.input_history_select_]
					self.input_history_next_ = self.input_history_next_ + 1
					self.input_history_[self.input_history_next_] = {}
					self.input_history_[self.input_history_next_ - config.history_size] = nil
					self:input_reset_()
					if self.hide_when_chat_done then
						self.hide_when_chat_done = false
						self.in_focus = false
						self.hide_window_func_()
					end
				end
			else
				self.in_focus = false
			end
			self.input_autocomplete_ = nil
		elseif not ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_UP then
			local to_select = self.input_history_select_ - 1
			if self.input_history_[to_select] then
				self:input_select_(to_select)
			end
			self.input_autocomplete_ = nil
		elseif not ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_DOWN then
			local to_select = self.input_history_select_ + 1
			if self.input_history_[to_select] then
				self:input_select_(to_select)
			end
			self.input_autocomplete_ = nil
		elseif not alt and (scan == sdl.SDL_SCANCODE_HOME or scan == sdl.SDL_SCANCODE_END or scan == sdl.SDL_SCANCODE_RIGHT or scan == sdl.SDL_SCANCODE_LEFT) then
			self.input_cursor_prev_ = self.input_cursor_
			if scan == sdl.SDL_SCANCODE_HOME then
				self.input_cursor_ = 0
			elseif scan == sdl.SDL_SCANCODE_END then
				self.input_cursor_ = #self.input_collect_
			else
				if (scan == sdl.SDL_SCANCODE_RIGHT and self.input_cursor_ < #self.input_collect_) or (scan == sdl.SDL_SCANCODE_LEFT and self.input_cursor_ > 0) then
					local cursor_step = scan == sdl.SDL_SCANCODE_RIGHT and 1 or -1
					local check_offset = scan == sdl.SDL_SCANCODE_RIGHT and 1 or  0
					if ctrl then
						local cursor = self.input_cursor_
						while self.input_collect_[cursor + check_offset] and self.input_collect_[cursor + check_offset]:find(config.whitespace_pattern) do
							cursor = cursor + cursor_step
						end
						while self.input_collect_[cursor + check_offset] and self.input_collect_[cursor + check_offset]:find(config.word_pattern) do
							cursor = cursor + cursor_step
						end
						if cursor == self.input_cursor_ then
							cursor = cursor + cursor_step
						end
						self.input_cursor_ = cursor
					else
						self.input_cursor_ = self.input_cursor_ + cursor_step
					end
				end
			end
			if shift then
				if self.input_sel_first_ == self.input_sel_second_ then
					self.input_sel_first_ = self.input_cursor_prev_
				end
			else
				self.input_sel_first_ = self.input_cursor_
			end
			self.input_sel_second_ = self.input_cursor_
			self:input_update_()
			self.input_autocomplete_ = nil
		elseif ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_A then
			self.input_cursor_ = #self.input_collect_
			self.input_sel_first_ = 0
			self.input_sel_second_ = self.input_cursor_
			self:input_update_()
			self.input_autocomplete_ = nil
		elseif ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_C then
			if self.input_has_selection_ then
				plat.clipboardPaste(self:input_collect_range_(self.input_sel_low_ + 1, self.input_sel_high_))
			end
			self.input_autocomplete_ = nil
		elseif ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_V then
			local text = plat.clipboardCopy()
			if text then
				self:input_insert_(text)
			end
			self.input_autocomplete_ = nil
		elseif ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_X then
			if self.input_has_selection_ then
				local start = self.input_sel_low_
				local length = self.input_sel_high_ - self.input_sel_low_
				self.input_cursor_ = self.input_sel_low_
				plat.clipboardPaste(self:input_collect_range_(self.input_sel_low_ + 1, self.input_sel_high_))
				self:input_remove_(start, length)
				self:input_update_()
			end
			self.input_autocomplete_ = nil
		end
		return not modkey_scan[scan]
	else
		if not ctrl and not alt and scan == sdl.SDL_SCANCODE_ESCAPE then
			self.hide_window_func_()
			return true
		end
	end
end

function window_i:handle_keyrelease(key, scan, rep, shift, ctrl, alt)
	if self.in_focus then
		return not modkey_scan[scan]
	end
end

function window_i:handle_textinput(text)
	if self.in_focus then
		self:input_insert_(text)
		self.input_autocomplete_ = nil
		return true
	end
end

function window_i:handle_textediting(text)
	if self.in_focus then
		return true
	end
end

function window_i:handle_blur()
end

function window_i:save_window_rect_()
	manager.set("windowLeft", tostring(self.pos_x_))
	manager.set("windowTop", tostring(self.pos_y_))
	manager.set("windowWidth", tostring(self.width_))
	manager.set("windowHeight", tostring(self.height_))
	manager.set("windowAlpha", tostring(self.alpha_))
end

function window_i:insert_wrapped_line_(tbl, msg, line)
	table.insert(tbl, {
		wrapped = msg.wrapped[line],
		needs_padding = line > 1,
		extend_box = line < #msg.wrapped,
		msg = msg,
		marker = self.backlog_marker_at_ == msg.unique and #msg.wrapped == line,
	})
end

local function set_size_clamp(new_width, new_height, new_pos_x, new_pos_y)
	local width = math.min(math.max(new_width, config.min_width), sim.XRES - 1)
	local height = math.min(math.max(new_height, config.min_height), sim.YRES - 1)
	local pos_x = math.min(math.max(1, new_pos_x), sim.XRES - width)
	local pos_y = math.min(math.max(1, new_pos_y), sim.YRES - height)
	return width, height, pos_x, pos_y
end

function window_i:set_size(new_width, new_height)
	self.width_, self.height_, self.pos_x_, self.pos_y_ = set_size_clamp(new_width, new_height, self.pos_x_, self.pos_y_)
	self:input_update_()
	self:backlog_update_()
	self:subtitle_update_()
	self:save_window_rect_()
end

function window_i:subtitle_update_()
	self.subtitle_text_ = self.subtitle_secondary_ or self.subtitle_ or ""
	local max_width = self.width_ - self.title_width_ - 43
	if gfx.textSize(self.subtitle_text_) > max_width then
		self.subtitle_text_ = self.subtitle_text_:sub(1, util.binary_search_implicit(1, #self.subtitle_text_, function(idx)
			local str = self.subtitle_text_:sub(1, idx)
			str = str:gsub("\15[\194\195].", "\15"):gsub("\15[^\128-\255]", "\15")
			str = str:gsub("\15[\194\195].", "\15"):gsub("\15[^\128-\255]", "\15")
			str = str:gsub("\15[\194\195].", "\15"):gsub("\15[^\128-\255]", "\15")
			str = str:gsub("\15", "")
			return gfx.textSize(str .. "...") > max_width
		end) - 1) .. "..."
	end
end

function window_i:input_select_(history_index)
	self.input_history_select_ = history_index
	local editing = self.input_editing_[history_index]
	if not editing then
		editing = {}
		local original = self.input_history_[history_index]
		for i = 1, #original do
			editing[i] = original[i]
		end
		self.input_editing_[history_index] = editing
	end
	self.input_collect_ = editing
	self.input_cursor_ = #self.input_collect_
	self.input_sel_first_ = self.input_cursor_
	self.input_sel_second_ = self.input_cursor_
	self:input_update_()
end

function window_i:input_reset_()
	self.input_editing_ = {}
	self:input_select_(self.input_history_next_)
end

function window_i:input_remove_(start, length)
	for i = start + 1, #self.input_collect_ - length do
		self.input_collect_[i] = self.input_collect_[i + length]
	end
	for i = #self.input_collect_, #self.input_collect_ - length + 1, -1 do
		self.input_collect_[i] = nil
	end
	self.input_sel_first_ = self.input_cursor_
	self.input_sel_second_ = self.input_cursor_
end

function window_i:input_insert_(text)
	local cps = {}
	local unfiltered_cps = utf8.code_points(text)
	if unfiltered_cps then
		for i = 1, #unfiltered_cps do
			if unfiltered_cps[i].cp >= 32 then
				table.insert(cps, unfiltered_cps[i])
			end
		end
	end
	if #cps > 0 then
		if self.input_has_selection_ then
			local start = self.input_sel_low_
			local length = self.input_sel_high_ - self.input_sel_low_
			self.input_cursor_ = self.input_sel_low_
			self:input_remove_(start, length)
		end
		for i = #self.input_collect_, self.input_cursor_ + 1, -1 do
			self.input_collect_[i + #cps] = self.input_collect_[i]
		end
		for i = 1, #cps do
			self.input_collect_[self.input_cursor_ + i] = text:sub(cps[i].pos, cps[i].pos + cps[i].size - 1)
		end
		self.input_cursor_ = self.input_cursor_ + #cps
		self:input_update_()
	end
end

function window_i:input_clamp_text_(start, first, last)
	local shave_off_left = -start
	local shave_off_right = gfx.textSize(self:input_collect_range_(first, last)) + start - self.width_ + 10
	local new_first = util.binary_search_implicit(first, last, function(pos)
		return gfx.textSize(self:input_collect_range_(first, pos - 1)) >= shave_off_left
	end)
	local new_last = util.binary_search_implicit(first, last, function(pos)
		return gfx.textSize(self:input_collect_range_(pos, last)) < shave_off_right
	end) - 1
	local new_start = start + gfx.textSize(self:input_collect_range_(first, new_first - 1))
	return new_start, self:input_collect_range_(new_first, new_last)
end

function window_i:input_update_()
	self.input_sel_low_ = math.min(self.input_sel_first_, self.input_sel_second_)
	self.input_sel_high_ = math.max(self.input_sel_first_, self.input_sel_second_)
	self.input_text_1_ = self:input_collect_range_(1, self.input_sel_low_)
	self.input_text_1w_ = gfx.textSize(self.input_text_1_)
	self.input_text_2_ = self:input_collect_range_(self.input_sel_low_ + 1, self.input_sel_high_)
	self.input_text_2w_ = gfx.textSize(self.input_text_2_)
	self.input_text_3_ = self:input_collect_range_(self.input_sel_high_ + 1, #self.input_collect_)
	self.input_text_3w_ = gfx.textSize(self.input_text_3_)
	self.input_cursor_x_ = 4 + gfx.textSize(self:input_collect_range_(1, self.input_cursor_))
	self.input_sel_low_x_ = 3 + self.input_text_1w_
	self.input_sel_high_x_ = self.input_sel_low_x_ + 1 + self.input_text_2w_
	self.input_has_selection_ = self.input_sel_first_ ~= self.input_sel_second_
	local min_cursor_x = 4
	local max_cursor_x = self.width_ - 5
	if self.input_cursor_x_ + self.input_scroll_x_ < min_cursor_x then
		self.input_scroll_x_ = min_cursor_x - self.input_cursor_x_
	end
	if self.input_cursor_x_ + self.input_scroll_x_ > max_cursor_x then
		self.input_scroll_x_ = max_cursor_x - self.input_cursor_x_
	end
	local min_if_active = self.width_ - self.input_text_1w_ - self.input_text_2w_ - self.input_text_3w_ - 9
	if self.input_scroll_x_ < 0 and self.input_scroll_x_ < min_if_active then
		self.input_scroll_x_ = min_if_active
	end
	if min_if_active > 0 then
		self.input_scroll_x_ = 0
	end
	if self.input_sel_low_x_ < 1 - self.input_scroll_x_ then
		self.input_sel_low_x_ = 1 - self.input_scroll_x_
	end
	if self.input_sel_high_x_ > self.width_ - self.input_scroll_x_ - 1 then
		self.input_sel_high_x_ = self.width_ - self.input_scroll_x_ - 1
	end
	self.input_text_1x_ = self.input_scroll_x_
	self.input_text_2x_ = self.input_text_1x_ + self.input_text_1w_
	self.input_text_3x_ = self.input_text_2x_ + self.input_text_2w_
	self.input_text_1x_, self.input_text_1_ = self:input_clamp_text_(self.input_text_1x_, 1, self.input_sel_low_)
	self.input_text_2x_, self.input_text_2_ = self:input_clamp_text_(self.input_text_2x_, self.input_sel_low_ + 1, self.input_sel_high_)
	self.input_text_3x_, self.input_text_3_ = self:input_clamp_text_(self.input_text_3x_, self.input_sel_high_ + 1, #self.input_collect_)
	self:set_subtitle_secondary(self:input_status_())
end

function window_i:input_text_to_send_()
	return self:input_collect_range_():gsub("[\1-\31]", ""):gsub("^ *(.-) *$", "%1")
end

function window_i:input_status_()
	if #self.input_collect_ == 0 then
		return
	end
	local str = self:input_text_to_send_()
	local max_size = config.message_size
	if str:find("^/") and not str:find("^//") then
		max_size = 255
	end
	local byte_length = #str
	local bytes_left = max_size - byte_length
	if bytes_left < 0 then
		self.message_overlong_ = true
		return colours.commonstr.error .. tostring(bytes_left)
	else
		self.message_overlong_ = nil
		return tostring(bytes_left)
	end
end

function window_i:input_collect_range_(first, last)
	return table.concat(self.input_collect_, nil, first, last)
end

function window_i:set_subtitle(template, text)
	if template == "status" then
		self.subtitle_ = colours.commonstr.status .. text
	elseif template == "room" then
		self.subtitle_ = "In " .. format.troom(text)
	end
	self:subtitle_update_()
end

function window_i:alpha(alpha)
	if not alpha then
		return self.alpha_
	end
	self.alpha_ = alpha
end

function window_i:set_subtitle_secondary(formatted_text)
	self.subtitle_secondary_ = formatted_text
	self:subtitle_update_()
end

local function new(params)
	local width, height, pos_x, pos_y = set_size_clamp(
		tonumber(manager.get("windowWidth", "")) or config.default_width,
		tonumber(manager.get("windowHeight", "")) or config.default_height,
		tonumber(manager.get("windowLeft", "")) or config.default_x,
		tonumber(manager.get("windowTop", "")) or config.default_y
	)
	local alpha = tonumber(manager.get("windowAlpha", "")) or config.default_alpha
	local title = "TPT Multiplayer " .. config.versionstr
	local title_width = gfx.textSize(title)
	local win = setmetatable({
		in_focus = false,
		pos_x_ = pos_x,
		pos_y_ = pos_y,
		width_ = width,
		height_ = height,
		alpha_ = alpha,
		title_ = title,
		title_width_ = title_width,
		input_scroll_x_ = 0,
		resizer_active_ = false,
		dragger_active_ = false,
		close_active_ = false,
		window_status_func_ = params.window_status_func,
		log_event_func_ = params.log_event_func,
		client_func_ = params.client_func,
		hide_window_func_ = params.hide_window_func,
		should_ignore_mouse_func_ = params.should_ignore_mouse_func,
		input_history_ = { {} },
		input_history_next_ = 1,
		input_editing_ = {},
		input_last_say_ = 0,
		nick_colour_seed_ = 0,
		hide_when_chat_done = false,
	}, window_m)
	win:input_reset_()
	win:backlog_reset()
	return win
end

return {
	new = new,
}
