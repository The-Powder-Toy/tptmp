local buffer_list = require("tptmp.common.buffer_list")
local colours     = require("tptmp.client.colours")
local config      = require("tptmp.client.config")
local util        = require("tptmp.client.util")
local format      = require("tptmp.client.format")

local log_event = print

local client_i = {}
local client_m = { __index = client_i }

local packet_handlers = {}

local index_to_lrax = {
	[ 0 ] = "tool_l",
	[ 1 ] = "tool_r",
	[ 2 ] = "tool_a",
	[ 3 ] = "tool_x",
}

local function get_auth_token(uid, sess)
	local req = http.get(config.auth_backend .. "?Action=Get", {
		[ "X-Auth-User-Id" ] = uid,
		[ "X-Auth-Session-Key" ] = sess,
	})
	local started_at = socket.gettime()
	while req:status() == "running" do
		if socket.gettime() > started_at + config.auth_backend_timeout then
			return nil, "timeout", "authentication backend down"
		end
		coroutine.yield()
	end
	local body, code = req:finish()
	if code ~= 200 then
		return nil, "non200", code
	end
	local status = body:match([["Status":"([^"]+)"]])
	if status ~= "OK" then
		return nil, "refused", status
	end
	return body:match([["Token":"([^"]+)"]])
end

function client_i:proto_error_(...)
	self:stop("protocol error: " .. string.format(...))
	coroutine.yield()
end

function client_i:proto_close_(message)
	self:stop(message)
	coroutine.yield()
end

function client_i:read_(count)
	while self.rx_:pending() < count do
		coroutine.yield()
	end
	return self.rx_:get(count)
end

function client_i:read_bytes_(count)
	while self.rx_:pending() < count do
		coroutine.yield()
	end
	local data, first, last = self.rx_:next()
	if last >= first + count - 1 then
		-- * Less memory-intensive path.
		self.rx_:pop(count)
		return data:byte(first, first + count - 1)
	end
	return self.rx_:get(count):byte(1, count)
end

function client_i:read_str24_()
	return self:read_(self:read_24be_())
end

function client_i:read_str8_()
	return self:read_(self:read_bytes_(1))
end

function client_i:read_nullstr_(max)
	local collect = {}
	while true do
		local byte = self:read_bytes_(1)
		if byte == 0 then
			break
		end
		if #collect == max then
			self:proto_error_("overlong nullstr")
		end
		table.insert(collect, string.char(byte))
	end
	return table.concat(collect)
end

function client_i:read_24be_()
	local hi, mi, lo = self:read_bytes_(3)
	return bit.bor(lo, bit.lshift(mi, 8), bit.lshift(hi, 16))
end

function client_i:read_xy_12_()
	local d24 = self:read_24be_()
	return bit.rshift(d24, 12), bit.band(d24, 0xFFF)
end

function client_i:handle_disconnect_reason_2_()
	local reason = self:read_str8_()
	self.should_not_reconnect_func_()
	self:stop(reason)
end

function client_i:handle_ping_3_()
	self.last_ping_received_at_ = socket.gettime()
end

local member_i = {}
local member_m = { __index = member_i }

function member_i:can_render()
	return self.can_render_
end

function member_i:update_can_render()
	if not self.can_render_ then
		if self.deco_a ~= nil and
		   self.kmod_c ~= nil and
		   self.shape  ~= nil and
		   self.size_x ~= nil and
		   self.pos_x  ~= nil then
			self.can_render_ = true
		end
	end
end

function client_i:add_member_(id, nick)
	if self.id_to_member[id] or id == self.self_id_ then
		self:proto_close_("member already exists")
	end
	self.id_to_member[id] = setmetatable({
		nick = nick,
		fps_sync = false,
	}, member_m)
end

function client_i:push_names(prefix)
	self.window_:backlog_push_room(self.room_name_, self.id_to_member, prefix)
end

function client_i:push_fpssync()
	local members = {}
	for _, member in pairs(self.id_to_member) do
		if member.fps_sync then
			table.insert(members, member)
		end
	end
	self.window_:backlog_push_fpssync(members)
end

function client_i:handle_room_16_()
	sim.clearSim()
	self.room_name_ = self:read_str8_()
	local item_count
	self.self_id_, item_count = self:read_bytes_(2)
	self.id_to_member = {}
	for i = 1, item_count do
		local id = self:read_bytes_(1)
		local nick = self:read_str8_()
		self:add_member_(id, nick)
	end
	self:reformat_nicks_()
	self:push_names("Joined ")
	self.window_:set_subtitle("room", self.room_name_)
	self.localcmd_:reconnect_commit({
		room = self.room_name_,
		host = self.host_,
		port = self.port_,
		secure = self.secure_,
	})
	self.profile_:user_sync()
end

function client_i:handle_join_17_()
	local id = self:read_bytes_(1)
	local nick = self:read_str8_()
	self:add_member_(id, nick)
	self:reformat_nicks_()
	self.window_:backlog_push_join(self.id_to_member[id].formatted_nick)
	self.profile_:user_sync()
end

function client_i:member_prefix_()
	local id = self:read_bytes_(1)
	local member = self.id_to_member[id]
	if not member then
		self:proto_close_("no such member")
	end
	return member, id
end

function client_i:handle_leave_18_()
	local member, id = self:member_prefix_()
	local nick = member.nick
	self.window_:backlog_push_leave(self.id_to_member[id].formatted_nick)
	self.id_to_member[id] = nil
end

function client_i:handle_say_19_()
	local member = self:member_prefix_()
	local msg = self:read_str8_()
	self.window_:backlog_push_say_other(member.formatted_nick, msg)
end

function client_i:handle_say3rd_20_()
	local member = self:member_prefix_()
	local msg = self:read_str8_()
	self.window_:backlog_push_say3rd_other(member.formatted_nick, msg)
end

function client_i:handle_server_22_()
	local msg = self:read_str8_()
	self.window_:backlog_push_server(msg)
end

function client_i:handle_sync_30_()
	local member = self:member_prefix_()
	self:read_(3)
	local data = self:read_str24_()
	local ok, err = util.stamp_load(0, 0, data, true)
	if ok then
		log_event(config.print_prefix .. colours.commonstr.event .. "Sync from " .. member.formatted_nick)
	else
		log_event(config.print_prefix .. colours.commonstr.error .. "Failed to sync from " .. member.formatted_nick .. colours.commonstr.error .. ": " .. err)
	end
end

function client_i:handle_pastestamp_31_()
	local member = self:member_prefix_()
	local x, y = self:read_xy_12_()
	local data = self:read_str24_()
	local ok, err = util.stamp_load(x, y, data, false)
	if ok then
		log_event(config.print_prefix .. colours.commonstr.event .. "Stamp from " .. member.formatted_nick) -- * Not really needed thanks to the stamp intent displays in init.lua.
	else
		log_event(config.print_prefix .. colours.commonstr.error .. "Failed to paste stamp from " .. member.formatted_nick .. colours.commonstr.error .. ": " .. err)
	end
end

function client_i:handle_mousepos_32_()
	local member = self:member_prefix_()
	member.pos_x, member.pos_y = self:read_xy_12_()
	member:update_can_render()
end

function client_i:handle_brushmode_33_()
	local member = self:member_prefix_()
	local bmode = self:read_bytes_(1)
	member.bmode = bmode < 3 and bmode or 0
	member:update_can_render()
end

function client_i:handle_brushsize_34_()
	local member = self:member_prefix_()
	local x, y = self:read_bytes_(2)
	member.size_x = x
	member.size_y = y
	member:update_can_render()
end

function client_i:handle_brushshape_35_()
	local member = self:member_prefix_()
	member.shape = self:read_bytes_(1)
	member:update_can_render()
end

function client_i:handle_keybdmod_36_()
	local member = self:member_prefix_()
	local kmod = self:read_bytes_(1)
	member.kmod_c = bit.band(kmod, 1) ~= 0
	member.kmod_s = bit.band(kmod, 2) ~= 0
	member.kmod_a = bit.band(kmod, 4) ~= 0
	member:update_can_render()
end

function client_i:handle_selecttool_37_()
	local member = self:member_prefix_()
	local hi, lo = self:read_bytes_(2)
	local tool = bit.bor(lo, bit.lshift(hi, 8))
	local index = bit.rshift(tool, 14)
	local xtype = bit.band(tool, 0x3FFF)
	member[index_to_lrax[index]] = util.to_tool[xtype] and xtype or util.from_tool.TPTMP_PT_UNKNOWN
end

function client_i:handle_stepsim_50_()
	local member = self:member_prefix_()
	tpt.set_pause(1)
	sim.framerender(1)
	log_event(config.print_prefix .. colours.commonstr.event .. "Single-frame step from " .. member.formatted_nick)
end

local simstates = {
	{
		format = "Simulation %s by %s",
		states = { "unpaused", "paused" },
		func = tpt.set_pause,
		shift = 0,
		size = 1,
	},
	{
		format = "Heat simulation %s by %s",
		states = { "disabled", "enabled" },
		func = tpt.heat,
		shift = 1,
		size = 1,
	},
	{
		format = "Ambient heat simulation %s by %s",
		states = { "disabled", "enabled" },
		func = tpt.ambient_heat,
		shift = 2,
		size = 1,
	},
	{
		format = "Newtonian gravity %s by %s",
		states = { "disabled", "enabled" },
		func = tpt.newtonian_gravity,
		shift = 3,
		size = 1,
	},
	{
		format = "Sand effect %s by %s",
		states = { "disabled", "enabled" },
		func = sim.prettyPowders,
		shift = 5,
		size = 1,
	},
	{
		format = "Water equalisation %s by %s",
		states = { "disabled", "enabled" },
		func = sim.waterEqualisation,
		shift = 4,
		size = 1,
	},
	{
		format = "Gravity mode set to %s by %s",
		states = { "vertical", "off", "radial" },
		func = sim.gravityMode,
		shift = 8,
		size = 2,
	},
	{
		format = "Air mode set to %s by %s",
		states = { "on", "pressure off", "velocity off", "off", "no update" },
		func = sim.airMode,
		shift = 10,
		size = 3,
	},
	{
		format = "Edge mode set to %s by %s",
		states = { "void", "solid", "loop" },
		func = sim.edgeMode,
		shift = 13,
		size = 2,
	},
}
function client_i:handle_simstate_38_()
	local member = self:member_prefix_()
	local lo, hi = self:read_bytes_(2)
	local temp = self:read_24be_()
	local bits = bit.bor(lo, bit.lshift(hi, 8))
	for i = 1, #simstates do
		local desc = simstates[i]
		local value = bit.band(bit.rshift(bits, desc.shift), bit.lshift(1, desc.size) - 1)
		if value + 1 > #desc.states then
			value = 0
		end
		if desc.func() ~= value then
			desc.func(value)
			log_event(config.print_prefix .. colours.commonstr.event .. desc.format:format(desc.states[value + 1], member.formatted_nick))
		end
	end
	if util.ambient_air_temp() ~= temp then
		local set = util.ambient_air_temp(temp)
		log_event(config.print_prefix .. colours.commonstr.event .. ("Ambient air temperature set to %.2f by %s"):format(set, member.formatted_nick))
	end
	self.profile_:sample_simstate()
end

function client_i:handle_flood_39_()
	local member = self:member_prefix_()
	local index = self:read_bytes_(1)
	if index > 3 then
		index = 0
	end
	member.last_tool = member[index_to_lrax[index]]
	local x, y = self:read_xy_12_()
	util.flood_any(x, y, member.last_tool, -1, -1, member)
end

function client_i:handle_lineend_40_()
	local member = self:member_prefix_()
	local x1, y1 = member.line_x, member.line_y
	local x2, y2 = self:read_xy_12_()
	if member.kmod_a then
		x2, y2 = util.line_snap_coords(x1, y1, x2, y2)
	end
	util.create_line_any(x1, y1, x2, y2, member.size_x, member.size_y, member.last_tool, member.shape, member, false)
	member.line_x, member.line_y = nil, nil
end

function client_i:handle_rectend_41_()
	local member = self:member_prefix_()
	local x1, y1 = member.rect_x, member.rect_y
	local x2, y2 = self:read_xy_12_()
	if member.kmod_a then
		x2, y2 = util.rect_snap_coords(x1, y1, x2, y2)
	end
	util.create_box_any(x1, y1, x2, y2, member.last_tool, member)
	member.rect_x, member.rect_y = nil, nil
end

function client_i:handle_pointsstart_42_()
	local member = self:member_prefix_()
	local index = self:read_bytes_(1)
	if index > 3 then
		index = 0
	end
	member.last_tool = member[index_to_lrax[index]]
	local x, y = self:read_xy_12_()
	util.create_parts_any(x, y, member.size_x, member.size_y, member.last_tool, member.shape, member)
	member.last_x = x
	member.last_y = y
end

function client_i:handle_pointscont_43_()
	local member = self:member_prefix_()
	local x, y = self:read_xy_12_()
	util.create_line_any(member.last_x, member.last_y, x, y, member.size_x, member.size_y, member.last_tool, member.shape, member, true)
	member.last_x = x
	member.last_y = y
end

function client_i:handle_linestart_44_()
	local member = self:member_prefix_()
	local index = self:read_bytes_(1)
	if index > 3 then
		index = 0
	end
	member.last_tool = member[index_to_lrax[index]]
	member.line_x, member.line_y = self:read_xy_12_()
end

function client_i:handle_rectstart_45_()
	local member = self:member_prefix_()
	local index = self:read_bytes_(1)
	if index > 3 then
		index = 0
	end
	member.last_tool = member[index_to_lrax[index]]
	member.rect_x, member.rect_y = self:read_xy_12_()
end

function client_i:handle_sparkclear_60_()
	local member = self:member_prefix_()
	tpt.reset_spark()
	log_event(config.print_prefix .. colours.commonstr.event .. "Sparks cleared by " .. member.formatted_nick)
end

function client_i:handle_airclear_61_()
	local member = self:member_prefix_()
	tpt.reset_velocity()
	tpt.set_pressure()
	log_event(config.print_prefix .. colours.commonstr.event .. "Air cleared by " .. member.formatted_nick)
end

function client_i:handle_airinv_62_()
	-- * TODO[api]: add an api for this to tpt
	local member = self:member_prefix_()
	for x = 0, sim.XRES / sim.CELL - 1 do
		for y = 0, sim.YRES / sim.CELL - 1 do
			sim.pressure(x, y, -sim.pressure(x, y))
		end
	end
	log_event(config.print_prefix .. colours.commonstr.event .. "Air inverted by " .. member.formatted_nick)
end

function client_i:handle_clearsim_63_()
	local member = self:member_prefix_()
	sim.clearSim()
	self.set_id_func_(nil, nil)
	log_event(config.print_prefix .. colours.commonstr.event .. "Simulation cleared by " .. member.formatted_nick)
end

function client_i:handle_brushdeco_65_()
	local member = self:member_prefix_()
	member.deco_a, member.deco_r, member.deco_g, member.deco_b = self:read_bytes_(4)
	member:update_can_render()
end

function client_i:handle_clearrect_67_()
	self:member_prefix_()
	local x, y = self:read_xy_12_()
	local w, h = self:read_xy_12_()
	sim.clearRect(x, y, w, h)
end

function client_i:handle_canceldraw_68_()
	local member = self:member_prefix_()
	member.rect_x, member.rect_y = nil, nil
	member.line_x, member.line_y = nil, nil
	member.last_tool = nil
end

function client_i:handle_loadonline_69_()
	local member = self:member_prefix_()
	local id = self:read_24be_()
	local histhi = self:read_24be_()
	local histlo = self:read_24be_()
	local hist = histhi * 0x1000000 + histlo
	if id > 0 then
		sim.loadSave(id, 1, hist)
		coroutine.yield() -- * sim.loadSave seems to take effect one frame late.
		self.set_id_func_(id, hist)
		log_event(config.print_prefix .. colours.commonstr.event .. "Online save " .. (hist == 0 and "id" or "history") .. ":" .. id .. " loaded by " .. member.formatted_nick)
	end
end

function client_i:handle_reloadsim_70_()
	local member = self:member_prefix_()
	if self.get_id_func_() then
		sim.reloadSave()
	end
	log_event(config.print_prefix .. colours.commonstr.event .. "Simulation reloaded by " .. member.formatted_nick)
end

function client_i:handle_placestatus_71_()
	local member = self:member_prefix_()
	local k = self:read_bytes_(1)
	local w, h = self:read_xy_12_()
	if k == 0 then
		member.place = nil
	elseif k == 1 then
		member.place = "Pasting"
	end
	member.place_w = w
	member.place_h = h
end

function client_i:handle_selectstatus_72_()
	local member = self:member_prefix_()
	local k = self:read_bytes_(1)
	local x, y = self:read_xy_12_()
	if k == 0 then
		member.select = nil
	elseif k == 1 then
		member.select = "Copying"
	elseif k == 2 then
		member.select = "Cutting"
	elseif k == 3 then
		member.select = "Stamping"
	end
	member.select_x = x
	member.select_y = y
end

function client_i:handle_zoomstart_73_()
	local member = self:member_prefix_()
	local x, y = self:read_xy_12_()
	local s = self:read_bytes_(1)
	member.zoom_x = x
	member.zoom_y = y
	member.zoom_s = s
end

function client_i:handle_zoomend_74_()
	local member = self:member_prefix_()
	member.zoom_x = nil
	member.zoom_y = nil
	member.zoom_s = nil
end

function client_i:handle_sparksign_75_()
	local member = self:member_prefix_()
	local x, y = self:read_xy_12_()
	sim.partCreate(-1, x, y, elem.DEFAULT_PT_SPRK)
end

function client_i:handle_fpssync_76_()
	local member = self:member_prefix_()
	local pack = self:read_24be_()
	local elapsed = bit.rshift(pack, 16)
	local count = bit.band(pack, 0xFFFF)
	if not member.fps_sync then
		member.fps_sync = true
		self.window_:backlog_push_fpssync_enable(member.formatted_nick)
	end
	member.fps_sync_last = socket.gettime()
	-- * TODO: do something with this
end

function client_i:handle_sync_request_128_()
	self:send_sync_done()
end

function client_i:connect_()
	self.window_:set_subtitle("status", "Connecting")
	self.socket_ = socket.tcp()
	self.socket_:settimeout(0)
	self.socket_:setoption("tcp-nodelay", true)
	if socket.bind then -- * Old socket API. -- * TODO[fin]: remove support
		if self.secure_ then
			self:proto_close_("no TLS support")
		end
		self.socket_:connect(self.host_, self.port_)
		while true do
			local _, writeable = socket.select({}, { self.socket_ }, 0)
			if writeable[self.socket_] then
				break
			end
			coroutine.yield()
		end
	else
		while true do
			local ok, err = self.socket_:connect(self.host_, self.port_, self.secure_)
			if ok then
				break
			elseif err == "timeout" then
				coroutine.yield()
			else
				self:proto_close_(err)
			end
		end
	end
	self.connected_ = true
end

function client_i:handshake_()
	self.window_:set_subtitle("status", "Registering")
	local uid, sess, name = util.get_user()
	self:write_bytes_(tpt.version.major, tpt.version.minor, config.version)
	self:write_nullstr_((name or tpt.get_name() or ""):sub(1, 255))
	self:write_bytes_(0) -- * Flags, currently unused.
	local qa_uid, qa_token = self.get_qa_func_():match("^([^:]+):([^:]+)$")
	self:write_str8_(qa_token and qa_uid == uid and qa_token or "")
	self:write_str8_(self.initial_room_ or "")
	self:write_flush_()
	local conn_status = self:read_bytes_(1)
	local auth_err
	if conn_status == 4 then -- * Quickauth failed.
		self.window_:set_subtitle("status", "Authenticating")
		local token, err, info = get_auth_token(uid, sess)
		if not token then
			if err == "non200" then
				auth_err = "authentication failed (status code " .. info .. "); try again later or try restarting TPT"
			elseif err == "timeout" then
				auth_err = "authentication failed (timeout: " .. info .. "); try again later or try restarting TPT"
			else
				auth_err = "authentication failed (" .. err .. ": " .. info .. "); try logging out and back in and restarting TPT"
			end
			token = ""
		end
		self:write_str8_(token)
		self:write_flush_()
		conn_status = self:read_bytes_(1)
		if uid then
			self.set_qa_func_((conn_status == 1) and (uid .. ":" .. token) or "")
		end
	end
	if conn_status == 1 then
		self.should_reconnect_func_()
		self.registered_ = true
		self.nick_ = self:read_str8_()
		self:reformat_nicks_()
		self.flags_ = self:read_bytes_(1)
		self.guest_ = bit.band(self.flags_, 1) ~= 0
		self.last_ping_sent_at_ = socket.gettime()
		self.connecting_since_ = nil
		if tpt.get_name() and auth_err then
			self.window_:backlog_push_error("Warning: " .. auth_err)
		end
		self.window_:backlog_push_registered(self.formatted_nick_)
		self.profile_.client = self
	elseif conn_status == 0 then
		local reason = self:read_nullstr_(255)
		self:proto_close_(auth_err or reason)
	else
		self:proto_error_("invalid connection status (%i)", conn_status)
	end
end

function client_i:send_ping()
	self:write_flush_("\3")
end

function client_i:send_say(str)
	self:write_("\19")
	self:write_str8_(str)
	self:write_flush_()
end

function client_i:send_say3rd(str)
	self:write_("\20")
	self:write_str8_(str)
	self:write_flush_()
end

function client_i:send_mousepos(px, py)
	self:write_("\32")
	self:write_xy_12_(px, py)
	self:write_flush_()
end

function client_i:send_brushmode(bmode)
	self:write_("\33")
	self:write_bytes_(bmode)
	self:write_flush_()
end

function client_i:send_brushsize(sx, sy)
	self:write_("\34")
	self:write_bytes_(sx, sy)
	self:write_flush_()
end

function client_i:send_brushshape(shape)
	self:write_("\35")
	self:write_bytes_(shape)
	self:write_flush_()
end

function client_i:send_keybdmod(c, s, a)
	self:write_("\36")
	self:write_bytes_(bit.bor(c and 1 or 0, s and 2 or 0, a and 4 or 0))
	self:write_flush_()
end

function client_i:send_selecttool(idx, xtype)
	self:write_("\37")
	local tool = bit.bor(xtype, bit.lshift(idx, 14))
	local hi = bit.band(bit.rshift(tool, 8), 0xFF)
	local lo = bit.band(           tool    , 0xFF)
	self:write_bytes_(hi, lo)
	self:write_flush_()
end

function client_i:send_simstate(ss_p, ss_h, ss_u, ss_n, ss_w, ss_g, ss_a, ss_e, ss_y, ss_t)
	self:write_("\38")
	local toggles = bit.bor(
		           ss_p    ,
		bit.lshift(ss_h, 1),
		bit.lshift(ss_u, 2),
		bit.lshift(ss_n, 3),
		bit.lshift(ss_w, 4),
		bit.lshift(ss_y, 5)
	)
	local multis = bit.bor(
		           ss_g    ,
		bit.lshift(ss_a, 2),
		bit.lshift(ss_e, 5)
	)
	self:write_bytes_(toggles, multis)
	self:write_24be_(ss_t)
	self:write_flush_()
end

function client_i:send_flood(index, x, y)
	self:write_("\39")
	self:write_bytes_(index)
	self:write_xy_12_(x, y)
	self:write_flush_()
end

function client_i:send_lineend(x, y)
	self:write_("\40")
	self:write_xy_12_(x, y)
	self:write_flush_()
end

function client_i:send_rectend(x, y)
	self:write_("\41")
	self:write_xy_12_(x, y)
	self:write_flush_()
end

function client_i:send_pointsstart(index, x, y)
	self:write_("\42")
	self:write_bytes_(index)
	self:write_xy_12_(x, y)
	self:write_flush_()
end

function client_i:send_pointscont(x, y)
	self:write_("\43")
	self:write_xy_12_(x, y)
	self:write_flush_()
end

function client_i:send_linestart(index, x, y)
	self:write_("\44")
	self:write_bytes_(index)
	self:write_xy_12_(x, y)
	self:write_flush_()
end

function client_i:send_rectstart(index, x, y)
	self:write_("\45")
	self:write_bytes_(index)
	self:write_xy_12_(x, y)
	self:write_flush_()
end

function client_i:send_stepsim()
	self:write_flush_("\50")
end

function client_i:send_sparkclear()
	self:write_flush_("\60")
end

function client_i:send_airclear()
	self:write_flush_("\61")
end

function client_i:send_airinv()
	self:write_flush_("\62")
end

function client_i:send_clearsim()
	self:write_flush_("\63")
end

function client_i:send_brushdeco(deco)
	self:write_("\65")
	self:write_bytes_(
		bit.band(bit.rshift(deco, 24), 0xFF),
		bit.band(bit.rshift(deco, 16), 0xFF),
		bit.band(bit.rshift(deco,  8), 0xFF),
		bit.band(           deco     , 0xFF)
	)
	self:write_flush_()
end

function client_i:send_clearrect(x, y, w, h)
	self:write_("\67")
	self:write_xy_12_(x, y)
	self:write_xy_12_(w, h)
	self:write_flush_()
end

function client_i:send_canceldraw()
	self:write_flush_("\68")
end

function client_i:send_loadonline(id, hist)
	self:write_("\69")
	self:write_24be_(id)
	self:write_24be_(math.floor(hist / 0x1000000))
	self:write_24be_(           hist % 0x1000000 )
	self:write_flush_()
end

function client_i:send_pastestamp_data_(pid, x, y, w, h)
	local data, err = util.stamp_save(x, y, w, h)
	if not data then
		return nil, err
	end
	self:write_(pid)
	self:write_xy_12_(x, y)
	self:write_str24_(data)
	self:write_flush_()
	return true
end

function client_i:send_pastestamp(x, y, w, h)
	local ok, err = self:send_pastestamp_data_("\31", x, y, w, h)
	if not ok then
		log_event(config.print_prefix .. colours.commonstr.error .. "Failed to send stamp: " .. err)
	end
end

function client_i:send_sync()
	local ok, err = self:send_pastestamp_data_("\30", 0, 0, sim.XRES, sim.YRES)
	if not ok then
		log_event(config.print_prefix .. colours.commonstr.error .. "Failed to send screen: " .. err)
	end
end

function client_i:send_reloadsim()
	self:write_flush_("\70")
end

function client_i:send_placestatus(k, w, h)
	self:write_("\71")
	self:write_bytes_(k)
	self:write_xy_12_(w, h)
	self:write_flush_()
end

function client_i:send_selectstatus(k, x, y)
	self:write_("\72")
	self:write_bytes_(k)
	self:write_xy_12_(x, y)
	self:write_flush_()
end

function client_i:send_zoomstart(x, y, s)
	self:write_("\73")
	self:write_xy_12_(x, y)
	self:write_bytes_(s)
	self:write_flush_()
end

function client_i:send_zoomend()
	self:write_flush_("\74")
end

function client_i:send_sparksign(x, y)
	self:write_("\75")
	self:write_xy_12_(x, y)
	self:write_flush_()
end

function client_i:send_fpssync(elapsed, count)
	self:write_("\76")
	self:write_24be_(bit.bor(bit.lshift(elapsed, 16), count))
	self:write_flush_()
end

function client_i:send_sync_done()
	self:write_flush_("\128")
	local id, hist = self.get_id_func_()
	self:send_loadonline(id or 0, hist or 0)
	self:send_sync()
	self.profile_:simstate_sync()
end

function client_i:start()
	assert(self.status_ == "ready")
	self.status_ = "running"
	local xpcall = rawget(_G, "jit") and xpcall or function(func)
		func()
		return true
	end
	self.proto_coro_ = coroutine.create(function()
		local ok, err = xpcall(function()
			self:connect_()
			self:handshake_()
			while true do
				local packet_id = self:read_bytes_(1)
				local handler = packet_handlers[packet_id]
				if not handler then
					self:proto_error_("invalid packet ID (%i)", packet_id)
				end
				handler(self)
			end
		end, function(err)
			print(debug.traceback(err, 2))
		end)
		if not ok then
			error(err)
		end
	end)
end

function client_i:tick_read_()
	if self.connected_ and not self.read_closed_ then
		while true do
			local closed = false
			local data, err, partial = self.socket_:receive(config.read_size)
			if not data then
				if err == "closed" then
					data = partial
					closed = true
				elseif err == "timeout" then
					data = partial
				else
					self:stop(err)
					break
				end
			end
			local pushed, count = self.rx_:push(data)
			if pushed < count then
				self:stop("recv queue limit exceeded")
				break
			end
			if closed then
				self:tick_resume_()
				self:stop("connection closed")
				break
			end
			if #data < config.read_size then
				break
			end
		end
	end
end

function client_i:tick_resume_()
	if self.proto_coro_ then
		local ok, err = coroutine.resume(self.proto_coro_)
		if not ok then
			self.proto_coro_ = nil
			error(err)
		end
		if self.proto_coro_ and coroutine.status(self.proto_coro_) == "dead" then
			error("proto coroutine terminated")
		end
	end
end

function client_i:tick_write_()
	if self.connected_ then
		while true do
			local data, first, last = self.tx_:next()
			if not data then
				break
			end
			local closed = false
			local count = last - first + 1
			if not socket.bind and self.socket_:status() ~= "connected" then
				break
			end
			local written_up_to, err, partial_up_to = self.socket_:send(data, first, last)
			if not written_up_to then
				if err == "closed" then
					written_up_to = partial_up_to
					closed = true
				elseif err == "timeout" then
					written_up_to = partial_up_to
				else
					self:stop(err)
					break
				end
			end
			local written = written_up_to - first + 1
			self.tx_:pop(written)
			if closed then
				self:stop("connection closed")
				break
			end
			if written < count then
				break
			end
		end
	end
end

function client_i:tick_connect_()
	if self.socket_ then
		if self.connecting_since_ and self.connecting_since_ + config.connect_timeout < socket.gettime() then
			self:stop("connect timeout")
		end
	end
end

function client_i:tick_ping_()
	if self.registered_ then
		local now = socket.gettime()
		if self.last_ping_sent_at_ + config.ping_interval < now then
			self:send_ping()
			self.last_ping_sent_at_ = now
		end
		if self.last_ping_received_at_ + config.ping_timeout < now then
			self:stop("ping timeout")
		end
	end
end

function client_i:tick_sim_()
	for _, member in pairs(self.id_to_member) do
		if member:can_render() then
			local lx, ly = member.line_x, member.line_y
			if member.last_tool == util.from_tool.DEFAULT_UI_WIND and not (member.select or member.place) and lx then
				local px, py = member.pos_x, member.pos_y
				if member.kmod_a then
					px, py = util.line_snap_coords(lx, ly, px, py)
				end
				util.create_line_any(lx, ly, px, py, member.size_x, member.size_y, member.last_tool, member.shape, member, false)
			end
		end
	end
end

function client_i:tick_fpssync_()
	if self.registered_ then
		if self.fps_sync_ then
			self.fps_sync_count_ = self.fps_sync_count_ + 1
			local now_sec = math.floor(socket.gettime())
			if now_sec > self.fps_sync_last_ then
				local count = self.fps_sync_count_
				local elapsed = now_sec - self.fps_sync_last_
				if self.fps_sync_last_ == 0 then
					elapsed = 0
				end
				if elapsed > 0xFF or count >= 0xFFFF then
					self.fps_sync_last_ = 0
					self.fps_sync_count_ = 0
				else
					self:send_fpssync(elapsed, count)
					self.fps_sync_last_ = now_sec
					self.fps_sync_count_ = 0
				end
			end
		end
		for _, member in pairs(self.id_to_member) do
			if member.fps_sync then
				if member.fps_sync_last + config.fps_sync_timeout < socket.gettime() then
					self.window_:backlog_push_fpssync_disable(member.formatted_nick)
					member.fps_sync = false
				end
				-- * TODO[imm]: do something with this
			end
		end
	end
end

function client_i:tick()
	if self.status_ ~= "running" then
		return
	end
	self:tick_read_()
	self:tick_resume_()
	self:tick_write_()
	self:tick_connect_()
	self:tick_ping_()
	self:tick_sim_()
	self:tick_fpssync_()
end

function client_i:stop(message)
	if self.status_ == "dead" then
		return
	end
	self.profile_.client = nil
	if self.socket_ then
		if self.connected_ then
			self.socket_:shutdown()
		end
		self.socket_:close()
		self.socket_ = nil
		self.connected_ = nil
		self.registered_ = nil
	end
	self.proto_coro_ = nil
	self.status_ = "dead"
	local disconnected = "Disconnected"
	if message then
		disconnected = disconnected .. ": " .. message
	end
	self.window_:backlog_push_error(disconnected)
end

function client_i:write_(data)
	if not self.write_buf_ then
		self.write_buf_ = data
	elseif type(self.write_buf_) == "string" then
		self.write_buf_ = { self.write_buf_, data }
	else
		table.insert(self.write_buf_, data)
	end
end

function client_i:write_flush_(data)
	if data then
		self:write_(data)
	end
	local buf = self.write_buf_
	self.write_buf_ = nil
	local pushed, count = self.tx_:push(type(buf) == "string" and buf or table.concat(buf))
	if pushed < count then
		self:stop("send queue limit exceeded")
	end
end

function client_i:write_bytes_(...)
	self:write_(string.char(...))
end

function client_i:write_str24_(str)
	local length = math.min(#str, 0xFFFFFF)
	self:write_24be_(length)
	self:write_(str:sub(1, length))
end

function client_i:write_str8_(str)
	local length = math.min(#str, 0xFF)
	self:write_bytes_(length)
	self:write_(str:sub(1, length))
end

function client_i:write_nullstr_(str)
	self:write_(str:gsub("[^\1-\255]", ""))
	self:write_("\0")
end

function client_i:write_24be_(d24)
	local hi = bit.band(bit.rshift(d24, 16), 0xFF)
	local mi = bit.band(bit.rshift(d24,  8), 0xFF)
	local lo = bit.band(           d24     , 0xFF)
	self:write_bytes_(hi, mi, lo)
end

function client_i:write_xy_12_(x, y)
	self:write_24be_(bit.bor(bit.lshift(x, 12), y))
end

function client_i:nick()
	return self.nick_
end

function client_i:formatted_nick()
	return self.formatted_nick_
end

function client_i:status()
	return self.status_
end

function client_i:connected()
	return self.connected_
end

function client_i:registered()
	return self.registered_
end

function client_i:nick_colour_seed(seed)
	self.nick_colour_seed_ = seed
	self:reformat_nicks_()
end

function client_i:fps_sync(fps_sync)
	self.fps_sync_ = fps_sync
	self.fps_sync_last_ = 0
	self.fps_sync_count_ = 0
end

function client_i:reformat_nicks_()
	if self.nick_ then
		self.formatted_nick_ = format.nick(self.nick_, self.nick_colour_seed_)
	end
	for _, member in pairs(self.id_to_member) do
		member.formatted_nick = format.nick(member.nick, self.nick_colour_seed_)
	end
end

for key, value in pairs(client_i) do
	local packet_id_str = key:match("^handle_.+_(%d+)_$")
	if packet_id_str then
		local packet_id = tonumber(packet_id_str)
		assert(not packet_handlers[packet_id])
		packet_handlers[packet_id] = value
	end
end

local function new(params)
	local now = socket.gettime()
	return setmetatable({
		host_ = params.host,
		port_ = params.port,
		secure_ = params.secure,
		event_log_ = params.event_log,
		backlog_ = params.backlog,
		rx_ = buffer_list.new({ limit = config.recvq_limit }),
		tx_ = buffer_list.new({ limit = config.sendq_limit }),
		connecting_since_ = now,
		last_ping_sent_at_ = now,
		last_ping_received_at_ = now,
		status_ = "ready",
		window_ = params.window,
		profile_ = params.profile,
		localcmd_ = params.localcmd,
		initial_room_ = params.initial_room,
		set_id_func_ = params.set_id_func,
		get_id_func_ = params.get_id_func,
		set_qa_func_ = params.set_qa_func,
		get_qa_func_ = params.get_qa_func,
		should_reconnect_func_ = params.should_reconnect_func,
		should_not_reconnect_func_ = params.should_not_reconnect_func,
		id_to_member = {},
		nick_colour_seed_ = 0,
		fps_sync_ = false,
	}, client_m)
end

return {
	new = new,
}
