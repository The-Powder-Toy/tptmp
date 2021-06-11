local config  = require("tptmp.client.config")
local colours = require("tptmp.client.colours")
local format  = require("tptmp.client.format")
local utf8    = require("tptmp.client.utf8")
local util    = require("tptmp.client.util")
local manager = require("tptmp.client.manager")

local window_i = {}
local window_m = { __index = window_i }

local wrap_padding = 11 -- * Width of "* "

function window_i:backlog_push_join(formatted_nick)
	self:backlog_push_str(colours.commonstr.join .. "* " .. formatted_nick .. colours.commonstr.join .. " has joined", true)
end

function window_i:backlog_push_leave(formatted_nick)
	self:backlog_push_str(colours.commonstr.leave .. "* " .. formatted_nick .. colours.commonstr.leave .. " has left", true)
end

function window_i:backlog_push_error(str)
	self:backlog_push_str(colours.commonstr.error .. "* " .. str, true)
end

function window_i:get_important_(str)
	local cli = self.client_func_()
	if cli then
		if (" " .. str .. " "):lower():find("[^a-z0-9-_]" .. cli:nick():lower() .. "[^a-z0-9-_]") then
			return true
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
	local sep = colours.commonstr.normal .. ", "
	local collect = { colours.commonstr.normal, "* ", prefix, format.room(room), sep }
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

function window_i:backlog_push_registered(formatted_nick)
	self:backlog_push_str(colours.commonstr.normal .. "* Connected as " .. formatted_nick, true)
end

function window_i:backlog_push_server(str)
	self:backlog_push_str(colours.commonstr.server .. str, true)
end

function window_i:backlog_push_neutral(str)
	self:backlog_push_str(colours.commonstr.normal .. str, true)
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
		table.insert(self.backlog_text_, {
			padding = lines[i].needs_padding and wrap_padding or 0,
			text = lines[i].wrapped,
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
	gfx.drawText(self.pos_x_ + self.width_ - 12, self.pos_y_ + 3, utf8.encode_multiple(0xE02A), unpack(close_fg))
	if self.close_active_ and not inside_close then
		self.close_active_ = false
	end
end

function window_i:handle_tick()
	if self.backlog_auto_scroll_ then
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
	gfx.fillRect(self.pos_x_ + 1, self.pos_y_ + 1, self.width_ - 2, self.height_ - 2, background_colour[1], background_colour[2], background_colour[3], self.alpha_)
	gfx.drawRect(self.pos_x_, self.pos_y_, self.width_, self.height_, unpack(border_colour))

	self:tick_close_()

	local subtitle_blue = 255
	if #self.input_collect_ > 0 and self.input_last_say_ + config.message_interval >= socket.gettime() then
		subtitle_blue = 0
	end
	gfx.drawText(self.pos_x_ + 18, self.pos_y_ + 4, self.subtitle_text_, 255, 255, subtitle_blue)

	gfx.drawText(self.pos_x_ + self.width_ - self.title_width_ - 17, self.pos_y_ + 4, self.title_)
	for i = 1, 3 do
		gfx.drawLine(self.pos_x_ + i * 3 + 1, self.pos_y_ + 3, self.pos_x_ + 3, self.pos_y_ + i * 3 + 1, unpack(border_colour))
	end
	gfx.drawLine(self.pos_x_ + 1, self.pos_y_ + 14, self.pos_x_ + self.width_ - 2, self.pos_y_ + 14, unpack(border_colour))
	gfx.drawLine(self.pos_x_ + 14, self.pos_y_ + 1, self.pos_x_ + 14, self.pos_y_ + 13, unpack(border_colour))

	for i = 1, #self.backlog_text_ do
		gfx.drawText(self.pos_x_ + 4 + self.backlog_text_[i].padding, self.pos_y_ + self.backlog_text_y_ + i * 12 - 12, self.backlog_text_[i].text)
	end
	if self.backlog_marker_y_ then
		gfx.drawLine(self.pos_x_ + 1, self.pos_y_ + self.backlog_marker_y_, self.pos_x_ + self.width_ - 2, self.pos_y_ + self.backlog_marker_y_, 255, 50, 50)
	end

	gfx.drawLine(self.pos_x_ + 1, self.pos_y_ + self.height_ - 15, self.pos_x_ + self.width_ - 2, self.pos_y_ + self.height_ - 15, unpack(border_colour))
	if self.input_has_selection_ then
		gfx.fillRect(self.pos_x_ + self.input_sel_low_x_ + self.input_scroll_x_, self.pos_y_ + self.height_ - 13, self.input_sel_high_x_ - self.input_sel_low_x_, 11)
	end
	gfx.drawText(self.pos_x_ + 4 + self.input_text_1x_, self.pos_y_ + self.height_ - 11, self.input_text_1_)
	gfx.drawText(self.pos_x_ + 4 + self.input_text_2x_, self.pos_y_ + self.height_ - 11, self.input_text_2_, 0, 0, 0)
	gfx.drawText(self.pos_x_ + 4 + self.input_text_3x_, self.pos_y_ + self.height_ - 11, self.input_text_3_)
	if self.in_focus and socket.gettime() % 1 < 0.5 then
		gfx.drawLine(self.pos_x_ + self.input_cursor_x_ + self.input_scroll_x_, self.pos_y_ + self.height_ - 13, self.pos_x_ + self.input_cursor_x_ + self.input_scroll_x_, self.pos_y_ + self.height_ - 3)
	end
end

function window_i:handle_mousedown(px, py, button)
	if self.placing_zoom_func_() then
		return
	end
	-- * TODO[opt]: mouse selection
	if button == 1 then
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
	elseif button == 3 then
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
				print(config.print_prefix .. "Message copied to clipboard")
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
	if button == 1 then
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
		if dir > 0 then
			if self.backlog_last_visible_line_ > 1 then
				self.backlog_last_visible_line_ = self.backlog_last_visible_line_ - 1
				self.backlog_auto_scroll_ = false
			elseif self.backlog_last_visible_msg_ ~= self.backlog_first_ then
				self.backlog_last_visible_msg_ = self.backlog_last_visible_msg_.prev
				self:backlog_wrap_(self.backlog_last_visible_msg_)
				self.backlog_last_visible_line_ = #self.backlog_last_visible_msg_.wrapped
				self.backlog_auto_scroll_ = false
			end
		else
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
		end
		self:backlog_update_()
		return true
	end
	if util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos()) then
		return true
	end
end

local modkey_scan = {
	[ 224 ] = true, -- * SDL_SCANCODE_LCTRL
	[ 225 ] = true, -- * SDL_SCANCODE_LSHIFT
	[ 226 ] = true, -- * SDL_SCANCODE_LALT
	[ 228 ] = true, -- * SDL_SCANCODE_RCTRL
	[ 229 ] = true, -- * SDL_SCANCODE_RSHIFT
	[ 230 ] = true, -- * SDL_SCANCODE_RALT
}
function window_i:handle_keypress(key, scan, rep, shift, ctrl, alt)
	if not self.in_focus and not self.window_hidden_func_() and scan == 40 then
		self.in_focus = true
		return true
	end
	if self.in_focus then
		if scan == 41 then -- * SDL_SCANCODE_ESCAPE
			self.in_focus = false
			self.input_autocomplete_ = nil
			if shift then
				self.hide_window_func_()
			end
		elseif scan == 43 then -- * SDL_SCANCODE_TAB
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
				for _, member in pairs(cli.id_to_member) do
					if member.nick:lower():find("^" .. util.escape_regex(self.input_autocomplete_)) then
						table.insert(nicks, member.nick)
					end
				end
				if next(nicks) then
					table.sort(nicks)
					local index = 1
					for i = 1, #nicks do
						if nicks[i] == left_word and nicks[i + 1] then
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
		elseif scan == 42 or scan == 76 then -- * SDL_SCANCODE_BACKSPACE, SDL_SCANCODE_DELETE
			local start, length
			if self.input_has_selection_ then
				start = self.input_sel_low_
				length = self.input_sel_high_ - self.input_sel_low_
				self.input_cursor_ = self.input_sel_low_
			elseif (scan == 42 and self.input_cursor_ > 0) or (scan == 76 and self.input_cursor_ < #self.input_collect_) then
				if ctrl then
					local cursor_step = scan == 76 and 1 or -1
					local check_offset = scan == 76 and 1 or  0
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
					if scan == 42 then
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
		elseif scan == 40 then -- * SDL_SCANCODE_RETURN
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
				end
			else
				self.in_focus = false
			end
			self.input_autocomplete_ = nil
		elseif scan == 82 then -- * SDL_SCANCODE_UP
			local to_select = self.input_history_select_ - 1
			if self.input_history_[to_select] then
				self:input_select_(to_select)
			end
			self.input_autocomplete_ = nil
		elseif scan == 81 then -- * SDL_SCANCODE_DOWN
			local to_select = self.input_history_select_ + 1
			if self.input_history_[to_select] then
				self:input_select_(to_select)
			end
			self.input_autocomplete_ = nil
		elseif scan == 74 or scan == 77 or scan == 79 or scan == 80 then -- * SDL_SCANCODE_HOME, SDL_SCANCODE_END, SDL_SCANCODE_RIGHT, SDL_SCANCODE_LEFT
			self.input_cursor_prev_ = self.input_cursor_
			if scan == 74 then
				self.input_cursor_ = 0
			elseif scan == 77 then
				self.input_cursor_ = #self.input_collect_
			else
				if (scan == 79 and self.input_cursor_ < #self.input_collect_) or (scan == 80 and self.input_cursor_ > 0) then
					local cursor_step = scan == 79 and 1 or -1
					local check_offset = scan == 79 and 1 or  0
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
		elseif ctrl and scan == 4 then -- * SDL_SCANCODE_A
			self.input_cursor_ = #self.input_collect_
			self.input_sel_first_ = 0
			self.input_sel_second_ = self.input_cursor_
			self:input_update_()
			self.input_autocomplete_ = nil
		elseif ctrl and scan == 6 then -- * SDL_SCANCODE_C
			if self.input_has_selection_ then
				plat.clipboardPaste(self:input_collect_range_(self.input_sel_low_ + 1, self.input_sel_high_))
			end
			self.input_autocomplete_ = nil
		elseif ctrl and scan == 25 then -- * SDL_SCANCODE_V
			local text = plat.clipboardCopy()
			if text then
				self:input_insert_(text)
			end
			self.input_autocomplete_ = nil
		elseif ctrl and scan == 27 then -- * SDL_SCANCODE_X
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
		if scan == 41 then -- * SDL_SCANCODE_ESCAPE
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
	manager.set("winx", tostring(self.pos_x_))
	manager.set("winy", tostring(self.pos_y_))
	manager.set("winw", tostring(self.width_))
	manager.set("winh", tostring(self.height_))
	manager.set("wina", tostring(self.alpha_))
end

function window_i:insert_wrapped_line_(tbl, msg, line)
	table.insert(tbl, {
		wrapped = msg.wrapped[line],
		needs_padding = line > 1,
		msg = msg,
		marker = self.backlog_marker_at_ == msg.unique and #msg.wrapped == line,
	})
end

function window_i:set_size(new_width, new_height)
	self.width_ = math.min(math.max(new_width, config.min_width), sim.XRES - 1)
	self.height_ = math.min(math.max(new_height, config.min_height), sim.YRES - 1)
	self.pos_x_ = math.min(math.max(1, self.pos_x_), sim.XRES - self.width_)
	self.pos_y_ = math.min(math.max(1, self.pos_y_), sim.YRES - self.height_)
	self:input_update_()
	self:backlog_update_()
	self:subtitle_update_()
	self:save_window_rect_()
end

function window_i:subtitle_update_()
	self.subtitle_text_ = self.subtitle_secondary_ or self.subtitle_
	local max_width = self.width_ - self.title_width_ - 43
	if gfx.textSize(self.subtitle_text_) > max_width then
		self.subtitle_text_ = self.subtitle_text_:sub(1, util.binary_search_implicit(1, #self.subtitle_text_, function(idx)
			local str = self.subtitle_text_:sub(1, idx)
			str = str:gsub("\15[\194\195].", "\15"):gsub("\15.", "\15")
			str = str:gsub("\15[\194\195].", "\15"):gsub("\15.", "\15")
			str = str:gsub("\15[\194\195].", "\15"):gsub("\15.", "\15")
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
		self.subtitle_ = "In " .. format.room(text)
	end
	self:subtitle_update_()
end

function window_i:set_subtitle_secondary(formatted_text)
	self.subtitle_secondary_ = formatted_text
	self:subtitle_update_()
end

local function new(params)
	local pos_x = tonumber(manager.get("winx", "")) or config.default_x
	local pos_y = tonumber(manager.get("winy", "")) or config.default_y
	local width = tonumber(manager.get("winw", "")) or config.default_width
	local height = tonumber(manager.get("winh", "")) or config.default_height
	local alpha = tonumber(manager.get("wina", "")) or config.default_alpha
	local title = "TPT Multiplayer v" .. config.versionstr
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
		window_hidden_func_ = params.window_hidden_func,
		client_func_ = params.client_func,
		hide_window_func_ = params.hide_window_func,
		placing_zoom_func_ = params.placing_zoom_func,
		input_history_ = { {} },
		input_history_next_ = 1,
		input_editing_ = {},
		input_last_say_ = 0,
	}, window_m)
	win:input_reset_()
	win:backlog_reset()
	return win
end

return {
	new = new,
}
