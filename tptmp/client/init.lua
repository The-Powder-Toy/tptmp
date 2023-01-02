local common_util = require("tptmp.common.util")

local loadtime_error
local http = rawget(_G, "http")
local socket = rawget(_G, "socket")
if sim.CELL ~= 4 then -- * Required by cursor snapping functions.
	loadtime_error = "CELL size is not 4"
elseif sim.PMAPBITS >= 13 then -- * Required by how non-element tools are encoded (extended tool IDs, XIDs).
	loadtime_error = "PMAPBITS is too large"
elseif not tpt.version or common_util.version_less({ tpt.version.major, tpt.version.minor }, { 97, 0 }) then
	loadtime_error = "version not supported"
elseif not rawget(_G, "bit") then
	loadtime_error = "no bit API"
elseif not http then
	loadtime_error = "no http API"
elseif not socket then
	loadtime_error = "no socket API"
elseif socket.bind then
	loadtime_error = "outdated socket API"
elseif tpt.version.jacob1s_mod and not tpt.tab_menu then
	loadtime_error = "mod version not supported"
elseif tpt.version.mobilemajor then
	loadtime_error = "platform not supported"
end

local config      =                        require("tptmp.client.config")
local colours     = not loadtime_error and require("tptmp.client.colours")
local window      = not loadtime_error and require("tptmp.client.window")
local side_button = not loadtime_error and require("tptmp.client.side_button")
local localcmd    = not loadtime_error and require("tptmp.client.localcmd")
local client      = not loadtime_error and require("tptmp.client.client")
local util        = not loadtime_error and require("tptmp.client.util")
local profile     = not loadtime_error and require("tptmp.client.profile")
local format      = not loadtime_error and require("tptmp.client.format")
local manager     = not loadtime_error and require("tptmp.client.manager")

local function run()
	if rawget(_G, "TPTMP") then
		if TPTMP.version <= config.version then
			TPTMP.disableMultiplayer()
		else
			loadtime_error = "newer version already running"
		end
	end
	if loadtime_error then
		print("TPTMP " .. config.versionstr .. ": Cannot load: " .. loadtime_error)
		return
	end

	local hooks_enabled = false
	local window_status = "hidden"
	local window_hide_mode = "hidden"
	local function set_floating(floating)
		window_hide_mode = floating and "floating" or "hidden"
	end
	local function get_window_status()
		return window_status
	end
	local TPTMP = {
		version = config.version,
		versionStr = config.versionstr,
	}
	local hide_window, show_window, begin_chat
	setmetatable(TPTMP, { __newindex = function(tbl, key, value)
		if key == "chatHidden" then
			if value then
				hide_window()
			else
				show_window()
			end
			return
		end
		rawset(tbl, key, value)
	end, __index = function(tbl, key)
		if key == "chatHidden" then
			return window_status ~= "shown"
		end
		return rawget(tbl, key)
	end })
	rawset(_G, "TPTMP", TPTMP)

	local current_id, current_hist = util.get_save_id()
	local function set_id(id, hist)
		current_id, current_hist = id, hist
	end
	local function get_id()
		return current_id, current_hist
	end

	local quickauth = manager.get("quickauthToken", "")
	local function set_qa(qa)
		quickauth = qa
		manager.set("quickauthToken", quickauth)
	end
	local function get_qa()
		return quickauth
	end

	local function log_event(text)
		print(text)
	end

	local should_reconnect_at
	local cli
	local prof = profile.new({
		set_id_func = set_id,
		get_id_func = get_id,
		log_event_func = log_event,
		registered_func = function()
			return cli and cli:registered()
		end
	})
	local win
	local should_reconnect = false
	local function kill_client()
		win:set_subtitle("status", "Not connected")
		cli:fps_sync(false)
		cli:stop()
		if should_reconnect then
			should_reconnect = false
			should_reconnect_at = socket.gettime() + config.reconnect_later_timeout
			win:backlog_push_neutral("* Will attempt to reconnect in " .. config.reconnect_later_timeout .. " seconds")
		end
		cli = nil
	end
	function begin_chat()
		show_window()
		win.hide_when_chat_done = true
	end
	function hide_window()
		window_status = window_hide_mode
		win.in_focus = false
	end
	function show_window()
		if not hooks_enabled then
			TPTMP.enableMultiplayer()
		end
		window_status = "shown"
		win:backlog_bump_marker()
		win.in_focus = true
	end
	win = window.new({
		hide_window_func = hide_window,
		window_status_func = get_window_status,
		log_event_func = log_event,
		client_func = function()
			return cli and cli:registered() and cli
		end,
		localcmd_parse_func = function(str)
			return cmd:parse(str)
		end,
		should_ignore_mouse_func = function(str)
			return prof:should_ignore_mouse()
		end,
	})
	local cmd = localcmd.new({
		window_status_func = get_window_status,
		window_set_floating_func = set_floating,
		client_func = function()
			return cli and cli:registered() and cli
		end,
		new_client_func = function(params)
			should_reconnect_at = nil
			params.window = win
			params.profile = prof
			params.set_id_func = set_id
			params.get_id_func = get_id
			params.set_qa_func = set_qa
			params.get_qa_func = get_qa
			params.log_event_func = log_event
			params.should_reconnect_func = function()
				should_reconnect = true
			end
			params.should_not_reconnect_func = function()
				should_reconnect = false
			end
			cli = client.new(params)
			return cli
		end,
		kill_client_func = function()
			should_reconnect = false
			kill_client()
		end,
		window = win,
	})
	win.localcmd = cmd
	local sbtn = side_button.new({
		notif_count_func = function()
			return win:backlog_notif_count()
		end,
		notif_important_func = function()
			return win:backlog_notif_important()
		end,
		show_window_func = show_window,
		hide_window_func = hide_window,
		begin_chat_func = begin_chat,
		window_status_func = get_window_status,
		sync_func = function()
			cmd:parse("/sync")
		end,
	})

	local grab_drop_text_input
	do
		if rawget(_G, "ui") and ui.grabTextInput then
			local text_input_grabbed = false
			function grab_drop_text_input(should_grab)
				if text_input_grabbed and not should_grab then
					ui.dropTextInput()
				elseif not text_input_grabbed and should_grab then
					ui.grabTextInput()
				end
				text_input_grabbed = should_grab
			end
		end
	end

	local pcur_r, pcur_g, pcur_b, pcur_a = unpack(colours.common.player_cursor)
	local bmode_to_repr = {
		[ 0 ] = "",
		[ 1 ] = " REPL",
		[ 2 ] = " SDEL",
	}
	local function decode_rulestring(tool)
		if tool.type == "cgol" then
			return tool.repr
		end
	end
	local function handle_tick()
		local now = socket.gettime()
		if should_reconnect_at and now >= should_reconnect_at then
			should_reconnect_at = nil
			win:backlog_push_neutral("* Attempting to reconnect")
			cmd:parse("/reconnect")
		end
		if grab_drop_text_input then
			grab_drop_text_input(window_status == "shown")
		end
		if cli then
			cli:tick()
			if cli:status() ~= "running" then
				kill_client()
			end
		end
		if cli then
			for _, member in pairs(cli.id_to_member) do
				if member:can_render() then
					local px, py = member.pos_x, member.pos_y
					local sx, sy = member.size_x, member.size_y
					local rx, ry = member.rect_x, member.rect_y
					local lx, ly = member.line_x, member.line_y
					local zx, zy, zs = member.zoom_x, member.zoom_y, member.zoom_s
					if rx then
						sx, sy = 0, 0
					end
					local tool = member.last_tool or member.tool_l
					local tool_name = util.to_tool[tool] or decode_rulestring(tool) or "UNKNOWN"
					local tool_class = util.xid_class[tool]
					if elem[tool_name] and tool ~= 0 and tool_name ~= "UNKNOWN" then
						local real_name = elem.property(elem[tool_name], "Name")
						if real_name ~= "" then
							tool_name = real_name
						end
					end
					local add_argb = false
					if tool_name:find("^DEFAULT_DECOR_") then
						add_argb = true
					end
					tool_name = tool_name:match("[^_]+$") or tool_name
					if add_argb then
						tool_name = ("%s %02X%02X%02X%02X"):format(tool_name, member.deco_a, member.deco_r, member.deco_g, member.deco_b)
					end
					local repl_tool_name
					if member.bmode ~= 0 then
						local repl_tool = member.tool_x
						repl_tool_name = util.to_tool[repl_tool] or "UNKNOWN"
						local repl_tool_class = util.xid_class[repl_tool]
						if elem[repl_tool_name] and repl_tool ~= 0 and repl_tool_name ~= "UNKNOWN" then
							local real_name = elem.property(elem[repl_tool_name], "Name")
							if real_name ~= "" then
								repl_tool_name = real_name
							end
						end
						repl_tool_name = repl_tool_name:match("[^_]+$") or repl_tool_name
					end
					if zx and util.inside_rect(zx, zy, zs, zs, px, py) then
						gfx.drawRect(zx - 1, zy - 1, zs + 2, zs + 2, pcur_r, pcur_g, pcur_b, pcur_a)
						if zs > 8 then
							gfx.drawText(zx, zy, "\238\129\165", pcur_r, pcur_g, pcur_b, pcur_a)
						end
					end
					local offx, offy = 6, -9
					local player_info = member.formatted_nick
					if cli.fps_sync_ and member.fps_sync then
						player_info = ("%s %s%+i"):format(player_info, colours.commonstr.brush, member.fps_sync_count_diff)
					end
					local brush_info
					if member.select or member.place then
						local xlo, ylo, xhi, yhi, action
						if member.select then
							xlo = math.min(px, member.select_x)
							ylo = math.min(py, member.select_y)
							xhi = math.max(px, member.select_x)
							yhi = math.max(py, member.select_y)
							action = member.select
						else
							xlo = math.min(sim.XRES - member.place_w, math.max(0, px - math.floor(member.place_w / 2)))
							ylo = math.min(sim.YRES - member.place_h, math.max(0, py - math.floor(member.place_h / 2)))
							xhi = xlo + member.place_w
							yhi = ylo + member.place_h
							action = member.place
						end
						gfx.drawRect(xlo, ylo, xhi - xlo + 1, yhi - ylo + 1, pcur_r, pcur_g, pcur_b, pcur_a)
						brush_info = action
					else
						local dsx, dsy = sx * 2 + 1, sy * 2 + 1
						if tool_class == "WL" then
							px, py = util.wall_snap_coords(px, py)
							sx, sy = util.wall_snap_coords(sx, sy)
							offx, offy = offx + 3, offy + 1
							dsx, dsy = 2 * sx + 4, 2 * sy + 4
						end
						if sx < 50 then
							offx = offx + sx
						end
						brush_info = ("%s %ix%i%s %s"):format(tool_name, dsx, dsy, bmode_to_repr[member.bmode], repl_tool_name or "")
						if not rx then
							if not lx and member.kmod_s and member.kmod_c then
								gfx.drawLine(px - 5, py, px + 5, py, pcur_r, pcur_g, pcur_b, pcur_a)
								gfx.drawLine(px, py - 5, px, py + 5, pcur_r, pcur_g, pcur_b, pcur_a)
							elseif tool_class == "WL" then
								gfx.drawRect(px - sx, py - sy, dsx, dsy, pcur_r, pcur_g, pcur_b, pcur_a)
							elseif member.shape == 0 then
								gfx.drawCircle(px, py, sx, sy, pcur_r, pcur_g, pcur_b, pcur_a)
							elseif member.shape == 1 then
								gfx.drawRect(px - sx, py - sy, sx * 2 + 1, sy * 2 + 1, pcur_r, pcur_g, pcur_b, pcur_a)
							elseif member.shape == 2 then
								gfx.drawLine(px - sx, py + sy, px     , py - sy, pcur_r, pcur_g, pcur_b, pcur_a)
								gfx.drawLine(px - sx, py + sy, px + sx, py + sy, pcur_r, pcur_g, pcur_b, pcur_a)
								gfx.drawLine(px     , py - sy, px + sx, py + sy, pcur_r, pcur_g, pcur_b, pcur_a)
							end
						end
						if lx then
							if member.kmod_a then
								px, py = util.line_snap_coords(lx, ly, px, py)
							end
							gfx.drawLine(lx, ly, px, py, pcur_r, pcur_g, pcur_b, pcur_a)
						end
						if rx then
							if member.kmod_a then
								px, py = util.rect_snap_coords(rx, ry, px, py)
							end
							local x, y, w, h = util.corners_to_rect(px, py, rx, ry)
							gfx.drawRect(x, y, w, h, pcur_r, pcur_g, pcur_b, pcur_a)
						end
					end
					gfx.drawText(px + offx, py + offy, player_info, pcur_r, pcur_g, pcur_b, pcur_a)
					gfx.drawText(px + offx, py + offy + 12, brush_info, pcur_r, pcur_g, pcur_b, pcur_a)
				end
			end
		end
		if window_status ~= "hidden" and win:handle_tick() then
			return false
		end
		if sbtn:handle_tick() then
			return false
		end
		prof:handle_tick()
	end

	local function handle_mousemove(px, py, dx, dy)
		if prof:handle_mousemove(px, py, dx, dy) then
			return false
		end
	end

	local function handle_mousedown(px, py, button)
		if window_status == "shown" and win:handle_mousedown(px, py, button) then
			return false
		end
		if sbtn:handle_mousedown(px, py, button) then
			return false
		end
		if prof:handle_mousedown(px, py, button) then
			return false
		end
	end

	local function handle_mouseup(px, py, button, reason)
		if window_status == "shown" and win:handle_mouseup(px, py, button, reason) then
			return false
		end
		if sbtn:handle_mouseup(px, py, button, reason) then
			return false
		end
		if prof:handle_mouseup(px, py, button, reason) then
			return false
		end
	end

	local function handle_mousewheel(px, py, dir)
		if window_status == "shown" and win:handle_mousewheel(px, py, dir) then
			return false
		end
		if sbtn:handle_mousewheel(px, py, dir) then
			return false
		end
		if prof:handle_mousewheel(px, py, dir) then
			return false
		end
	end

	local function handle_keypress(key, scan, rep, shift, ctrl, alt)
		if window_status == "shown" and win:handle_keypress(key, scan, rep, shift, ctrl, alt) then
			return false
		end
		if sbtn:handle_keypress(key, scan, rep, shift, ctrl, alt) then
			return false
		end
		if prof:handle_keypress(key, scan, rep, shift, ctrl, alt) then
			return false
		end
	end

	local function handle_keyrelease(key, scan, rep, shift, ctrl, alt)
		if window_status == "shown" and win:handle_keyrelease(key, scan, rep, shift, ctrl, alt) then
			return false
		end
		if sbtn:handle_keyrelease(key, scan, rep, shift, ctrl, alt) then
			return false
		end
		if prof:handle_keyrelease(key, scan, rep, shift, ctrl, alt) then
			return false
		end
	end

	local function handle_textinput(text)
		if window_status == "shown" and win:handle_textinput(text) then
			return false
		end
		if sbtn:handle_textinput(text) then
			return false
		end
		if prof:handle_textinput(text) then
			return false
		end
	end

	local function handle_textediting(text)
		if window_status == "shown" and win:handle_textediting(text) then
			return false
		end
		if sbtn:handle_textediting(text) then
			return false
		end
		if prof:handle_textediting(text) then
			return false
		end
	end

	local function handle_blur()
		if window_status == "shown" and win:handle_blur() then
			return false
		end
		if sbtn:handle_blur() then
			return false
		end
		if prof:handle_blur() then
			return false
		end
	end

	evt.register(evt.tick      , handle_tick      )
	evt.register(evt.mousemove , handle_mousemove )
	evt.register(evt.mousedown , handle_mousedown )
	evt.register(evt.mouseup   , handle_mouseup   )
	evt.register(evt.mousewheel, handle_mousewheel)
	evt.register(evt.keypress  , handle_keypress  )
	evt.register(evt.textinput , handle_textinput )
	evt.register(evt.keyrelease, handle_keyrelease)
	evt.register(evt.blur      , handle_blur      )
	if evt.textediting then
		evt.register(evt.textediting, handle_textediting)
	end

	function TPTMP.disableMultiplayer()
		if cli then
			cmd:parse("/fpssync off")
			cmd:parse("/disconnect")
		end
		evt.unregister(evt.tick      , handle_tick      )
		evt.unregister(evt.mousemove , handle_mousemove )
		evt.unregister(evt.mousedown , handle_mousedown )
		evt.unregister(evt.mouseup   , handle_mouseup   )
		evt.unregister(evt.mousewheel, handle_mousewheel)
		evt.unregister(evt.keypress  , handle_keypress  )
		evt.unregister(evt.textinput , handle_textinput )
		evt.unregister(evt.keyrelease, handle_keyrelease)
		evt.unregister(evt.blur      , handle_blur      )
		if evt.textediting then
			evt.unregister(evt.textediting, handle_textediting)
		end
		_G.TPTMP = nil
	end

	function TPTMP.enableMultiplayer()
		hooks_enabled = true
		TPTMP.enableMultiplayer = nil
	end

	win:set_subtitle("status", "Not connected")
	win:backlog_push_neutral("* Type " .. colours.commonstr.error .. "/connect" .. colours.commonstr.neutral .. " to join a server, " .. colours.commonstr.error .. "/list" .. colours.commonstr.neutral .. " for a list of commands, or " .. colours.commonstr.error .. "/help" .. colours.commonstr.neutral .. " for command help")
	win:backlog_notif_reset()
end

return {
	run = run,
}
