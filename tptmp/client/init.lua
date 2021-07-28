-- * TODO[opt]: maybe exit gracefully
assert(sim.CELL == 4, "CELL size is not 4") -- * Required by cursor snapping functions.
assert(sim.PMAPBITS < 13, "PMAPBITS is too large") -- * Required by how non-element tools are encoded (extended tool IDs, XIDs).
assert(tpt.version and tpt.version.major >= 96 and tpt.version.minor >= 1, "version not supported")
assert(rawget(_G, "bit"), "no bit API")
local http = assert(rawget(_G, "http"), "no http API")
local socket = assert(rawget(_G, "socket"), "no socket API")
assert(not socket.bind, "outdated socket API")
if tpt.version.jacob1s_mod then
	assert(tpt.tab_menu, "unsupported version")
end

local colours     = require("tptmp.client.colours")
local config      = require("tptmp.client.config")
local window      = require("tptmp.client.window")
local side_button = require("tptmp.client.side_button")
local localcmd    = require("tptmp.client.localcmd")
local client      = require("tptmp.client.client")
local util        = require("tptmp.client.util")
local profile     = require("tptmp.client.profile")
local format      = require("tptmp.client.format")
local manager     = require("tptmp.client.manager")

local function run()
	local hooks_enabled = false

	if rawget(_G, "TPTMP") then
		if TPTMP.version <= config.version then
			TPTMP.disableMultiplayer()
		else
			error("newer version already running")
		end
	end
	local TPTMP = {
		version = config.version,
		versionStr = config.versionstr,
		chatHidden = true,
	}
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
	local should_reconnect_at
	local cli
	local prof = profile.new({
		set_id_func = set_id,
		get_id_func = get_id,
		registered_func = function()
			return cli and cli:registered()
		end
	})
	local win
	local should_reconnect = false
	local function kill_client()
		win:set_subtitle("status", "Not connected")
		cli:stop()
		if should_reconnect then
			should_reconnect = false
			should_reconnect_at = socket.gettime() + config.reconnect_later_timeout
			win:backlog_push_neutral("* Will attempt to reconnect in " .. config.reconnect_later_timeout .. " seconds")
		end
		cli = nil
	end
	local function hide_window()
		TPTMP.chatHidden = true
		win.in_focus = false
	end
	local function window_hidden()
		return TPTMP.chatHidden
	end
	local function show_window()
		if not hooks_enabled then
			TPTMP.enableMultiplayer()
		end
		TPTMP.chatHidden = false
		win:backlog_bump_marker()
		win.in_focus = true
	end
	win = window.new({
		hide_window_func = hide_window,
		window_hidden_func = window_hidden,
		client_func = function()
			return cli and cli:registered() and cli
		end,
		localcmd_parse_func = function(str)
			return cmd:parse(str)
		end,
		placing_zoom_func = function(str)
			return prof:placing_zoom()
		end,
	})
	local cmd = localcmd.new({
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
		window_hidden_func = window_hidden,
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
			grab_drop_text_input(not TPTMP.chatHidden)
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
					local tool_name = util.to_tool[tool] or decode_rulestring(tool) or "TPTMP_PT_UNKNOWN"
					local tool_class = util.xid_class[tool]
					if elem[tool_name] and tool ~= 0 then
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
						repl_tool_name = util.to_tool[repl_tool] or "TPTMP_PT_UNKNOWN"
						local repl_tool_class = util.xid_class[repl_tool]
						if elem[repl_tool_name] and repl_tool ~= 0 then
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
		if not TPTMP.chatHidden and win:handle_tick() then
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
		if not TPTMP.chatHidden and win:handle_mousedown(px, py, button) then
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
		if not TPTMP.chatHidden and win:handle_mouseup(px, py, button, reason) then
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
		if not TPTMP.chatHidden and win:handle_mousewheel(px, py, dir) then
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
		if not TPTMP.chatHidden and win:handle_keypress(key, scan, rep, shift, ctrl, alt) then
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
		if not TPTMP.chatHidden and win:handle_keyrelease(key, scan, rep, shift, ctrl, alt) then
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
		if not TPTMP.chatHidden and win:handle_textinput(text) then
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
		if not TPTMP.chatHidden and win:handle_textediting(text) then
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
		if not TPTMP.chatHidden and win:handle_blur() then
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
