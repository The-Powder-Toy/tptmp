local cqueues     = require("cqueues")
local condition   = require("cqueues.condition")
local errno       = require("cqueues.errno")
local buffer_list = require("tptmp.common.buffer_list")
local log         = require("tptmp.server.log")
local util        = require("tptmp.server.util")
local config      = require("tptmp.server.config")
local jnet        = require("jnet")

local PROTO_STOP = {}
local PROTO_ERROR = {}
local PROTO_CLOSE = {}

local TLS_CLIENT_HELLO = 0x16

local client_i = {}
local client_m = { __index = client_i }

function client_i:proto_stop_()
	error(setmetatable({}, PROTO_STOP))
end

function client_i:proto_close_(message, log, rconinfo)
	error(setmetatable({ msg = message, log = log, rconinfo = rconinfo }, PROTO_CLOSE))
end

function client_i:proto_error_(log, rconinfo)
	error(setmetatable({ log = log, rconinfo = rconinfo }, PROTO_ERROR))
end

function client_i:read_wait_(count)
	while true do
		if self.status_ ~= "running" then
			self:proto_stop_()
		end
		if self.rx_:pending() >= count then
			break
		end
		util.cqueues_poll(self.wake_, self.read_wake_)
	end
end

function client_i:read_(count)
	self:read_wait_(count)
	return self.rx_:get(count)
end

function client_i:read_bytes_(count)
	self:read_wait_(count)
	local data, first, last = self.rx_:next()
	if last >= first + count - 1 then
		-- * Less memory-intensive path.
		self.rx_:pop(count)
		return data:byte(first, first + count - 1)
	end
	return self.rx_:get(count):byte(1, count)
end

function client_i:read_24be_()
	local length1, length2, length3 = self:read_bytes_(3)
	return length3 | (length2 << 8) | (length1 << 16)
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
			self:proto_error_("overlong nullstr", {
				kind = "overlong_nullstr",
			})
		end
		table.insert(collect, string.char(byte))
	end
	return table.concat(collect)
end

function client_i:send_handshake_failure_(message)
	self:write_("\0")
	self:write_nullstr_(message)
	self:write_flush_()
end

function client_i:send_handshake_success_()
	self:write_("\1")
	self:write_str8_(self.nick_)
	self:write_bytes_(self.guest_ and 1 or 0)
	self:write_flush_()
end

function client_i:send_disconnect_reason_(message)
	self:write_("\2")
	self:write_str8_(message)
	self:write_flush_()
end

function client_i:send_ping_()
	self:write_flush_("\3")
end

function client_i:send_quickauth_failure()
	self:write_flush_("\4")
end

function client_i:send_downgrade_reason_(message)
	self:write_("\5")
	self:write_str8_(message)
	self:write_flush_()
end

function client_i:send_room(id, name, items)
	self:write_("\16")
	self:write_str8_(name)
	self:write_bytes_(id, #items)
	for i = 1, #items do
		self:write_bytes_(items[i].id)
		self:write_str8_(items[i].nick)
	end
	self:write_flush_()
end

function client_i:send_room_chunk(chunk)
	self:write_flush_(chunk)
end

function client_i:send_join(id, nick)
	self:write_("\17")
	self:write_bytes_(id)
	self:write_str8_(nick)
	self:write_flush_()
end

function client_i:send_leave(id)
	self:write_("\18")
	self:write_bytes_(id)
	self:write_flush_()
end

function client_i:send_server(message)
	self:write_("\22")
	self:write_str8_(message)
	self:write_flush_()
end

function client_i:cancel_sync(target)
	if self.syncing_for_ then
		self.syncing_for_[target] = nil
	end
end

function client_i:send_sync_request(target)
	if self.syncing_for_ then
		self.syncing_for_[target] = true
		return
	end
	self.syncing_for_ = { [ target ] = true }
	self:write_flush_("\128")
end

local function forward_to_room(name, packet_id, payload_size)
	local packet_id_chr = string.char(packet_id)
	client_i["handle_" .. name .. "_" .. packet_id .. "_"] = function(self)
		self.room_:broadcast(self, packet_id_chr .. self.room_id_str_ .. self:read_(payload_size))
	end
end

function client_i:handle_ping_3_()
	self.got_ping_ = true
	self.wake_:signal()
end

function client_i:check_message_(message)
	if not message or message == "" then
		return
	end
	local server = self:server()
	local ok
	ok, message = server:phost():call_check_all("message_ok", self, message)
	if not ok then
		self:send_server("\ae* Cannot send message: " .. message)
		return
	end
	return message
end

function client_i:forward_message_(format, event, packet, message)
	local server = self:server()
	local ok, err, rconinfo = server:phost():call_check_all("content_ok", server, message)
	if not ok then
		self:send_server("\ae* Cannot send message: " .. err)
		self:server():rconlog(util.info_merge({
			event = event .. "_fail",
			client_name = self.name_,
			room_name = self.room_:name(),
			message = message,
		}, rconinfo))
		return
	end
	self.room_:broadcast_ciw(self, packet .. self.room_id_str_ .. string.char(#message) .. message)
	self.room_:log(format, self.nick_, message)
	self:server():rconlog({
		event = event,
		client_name = self.name_,
		room_name = self.room_:name(),
		message = message,
	})
end

local function clean_message(str)
	local collect = {}
	if pcall(function()
		for _, cp in utf8.codes(str) do
			if not ((cp >=        0 and cp <=     0x1F)
			     or (cp >=   0xE000 and cp <=   0xF8FF)
			     or (cp >=  0xF0000 and cp <=  0xFFFFD)
			     or (cp >= 0x100000 and cp <= 0x10FFFD)) then
				table.insert(collect, utf8.char(cp))
			end
		end
	end) then
		return table.concat(collect)
	end
end

function client_i:handle_say_19_()
	local message = self:check_message_(clean_message(self:read_str8_():sub(1, config.message_size)))
	if not message then
		return
	end
	if message:find("^//") then
		message = message:sub(2)
	elseif message:find("^/") then
		message = message:sub(2)
		self:server():rconlog({
			event = "command",
			client_name = self.name_,
			room_name = self.room_:name(),
			command = message,
		})
		self.server_:parse(self, message)
		return
	end
	self:forward_message_("<$> $", "say", "\19", message)
end

function client_i:handle_say3rd_20_()
	local message = self:check_message_(clean_message(self:read_str8_():sub(1, config.message_size)))
	if not message then
		return
	end
	self:forward_message_("* $ $", "say3rd", "\20", message)
end

local function header_24be(d24)
	local hi = (d24 >> 16) & 0xFF
	local mi = (d24 >>  8) & 0xFF
	local lo =  d24        & 0xFF
	return string.char(hi, mi, lo)
end

function client_i:handle_elemlist_23_()
	local length = self:read_(3)
	local cstr = self:read_str24_()
	self.room_:broadcast(self, "\23" .. self.room_id_str_ .. length .. header_24be(#cstr))
	self.room_:broadcast(self, cstr)
end

local sync_30_size = 3
do
	local location_size = 3
	assert(location_size == sync_30_size)
	function client_i:handle_sync_30_()
		-- * Update handle_sync_done_128_ if you change this.
		local location = self:read_(location_size)
		local data = self:read_str24_()
		self.room_:broadcast(self, "\30" .. self.room_id_str_ .. location .. header_24be(#data))
		self.room_:broadcast(self, data)
	end
end

function client_i:handle_pastestamp_31_()
	local location = self:read_(3)
	local data = self:read_str24_()
	self.room_:broadcast(self, "\31" .. self.room_id_str_ .. location .. header_24be(#data))
	self.room_:broadcast(self, data)
end

local simstate_38_size = 11
local loadonline_69_size = 9

forward_to_room(    "mousepos", 32, 3)
forward_to_room(   "brushmode", 33, 1)
forward_to_room(   "brushsize", 34, 2)
forward_to_room(  "brushshape", 35, 1)
forward_to_room(    "keybdmod", 36, 1)
forward_to_room(  "selecttool", 37, 2)
forward_to_room(    "simstate", 38, simstate_38_size)
forward_to_room(       "flood", 39, 4)
forward_to_room(     "lineend", 40, 3)
forward_to_room(     "rectend", 41, 3)
forward_to_room( "pointsstart", 42, 4)
forward_to_room(  "pointscont", 43, 3)
forward_to_room(   "linestart", 44, 4)
forward_to_room(   "rectstart", 45, 4)
forward_to_room( "custgolinfo", 46, 9)
forward_to_room(     "stepsim", 50, 0)
forward_to_room(  "sparkclear", 60, 0)
forward_to_room(    "airclear", 61, 0)
forward_to_room(      "airinv", 62, 0)
forward_to_room(    "clearsim", 63, 0)
forward_to_room(   "heatclear", 64, 0)
forward_to_room(   "brushdeco", 65, 4)
forward_to_room(   "clearrect", 67, 6)
forward_to_room(  "canceldraw", 68, 0)
forward_to_room(  "loadonline", 69, loadonline_69_size)
forward_to_room(   "reloadsim", 70, 0)
forward_to_room( "placestatus", 71, 4)
forward_to_room("selectstatus", 72, 4)
forward_to_room(   "zoomstart", 73, 4)
forward_to_room(     "zoomend", 74, 0)
forward_to_room(   "sparksign", 75, 3)
forward_to_room(     "fpssync", 76, 9)

function client_i:proto_assert_(got, expected)
	if got ~= expected then
		self:proto_error_(("unexpected packet ID (%i ~= %i)"):format(got, expected), {
			kind = "unexpected_packet_id",
			got = got,
			expected = expected,
		})
	end
	return got
end

function client_i:handle_sync_done_128_()
	local data = {
		self:proto_assert_(self:read_bytes_(1), 69),
		self.room_id_str_,
		self:read_(loadonline_69_size),
		self:proto_assert_(self:read_bytes_(1), 30),
		self.room_id_str_,
		self:read_(sync_30_size),
		self:read_str24_(),
		self:proto_assert_(self:read_bytes_(1), 38),
		self.room_id_str_,
		self:read_(simstate_38_size),
	}
	for target in pairs(self.syncing_for_) do
		target:write_bytes_(data[ 1])
		target:write_(      data[ 2])
		target:write_(      data[ 3])
		target:write_bytes_(data[ 4])
		target:write_(      data[ 5])
		target:write_(      data[ 6])
		target:write_str24_(data[ 7])
		target:write_bytes_(data[ 8])
		target:write_(      data[ 9])
		target:write_(      data[10])
		target:write_flush_()
	end
	self.syncing_for_ = nil
end

function client_i:ping_()
	local next_ping = cqueues.monotime() + config.ping_interval
	while self.status_ == "running" do
		local timeout = next_ping - cqueues.monotime()
		util.cqueues_poll(timeout, self.wake_)
		if next_ping < cqueues.monotime() then
			self:send_ping_()
			next_ping = cqueues.monotime() + config.ping_interval
		end
	end
end

function client_i:unique_guest_nick_()
	repeat
		self.nick_ = "Guest#" .. math.random(10000, 99999)
	until not self.server_:client_by_nick(self.nick_)
end

function client_i:deduplicate_nick_(keep_existing)
	local other = self.server_:client_by_nick(self.nick_)
	if other then
		if keep_existing then
			self:proto_close_("nick already in use", ("nick already in use (by %s)"):format(other.name_), {
				reason = "nick_collision",
				other_client_name = other.name_,
			})
		else
			other:drop("logged in from another location", nil, {
				reason = "ghosted",
				other_client_name = self.name_,
			})
			while self.status_ ~= "dead" and other.status_ ~= "dead" do
				util.cqueues_poll(self.wake_, other.wake_)
			end
		end
	end
end

function client_i:handshake_()
	local tpt_major, tpt_minor, version = self:read_bytes_(3)
	self.initial_nick_ = self:read_nullstr_(255)
	self.log_inf_("initial nick is $", self.initial_nick_)
	self.server_:rconlog({
		event = "client_initial_nick",
		client_name = self.name_,
		client_nick = self.initial_nick_,
	})
	if tpt_major == 255 and tpt_minor == 255 then
		tpt_major = self:read_24be_()
		tpt_minor = 0
		self.log_inf_("build number is $", tpt_major)
	end
	local tpt_version = { tpt_major, tpt_minor }
	local version_ok = self.server_:version()
	if version ~= version_ok then
		self:proto_close_("protocol version mismatch; try updating TPTMP, or if it is built into your mod, install it from the Online tab in the Script Manager", ("protocol version mismatch (%i ~= %i)"):format(version, version_ok), {
			reason = "proto_mismatch",
			got = version,
		})
	end
	if util.version_less(tpt_version, { config.tpt_version_min, 0 }) then
		self:proto_close_("TPT version older than first compatible; try updating TPT", ("TPT version older than first compatible (%i.%i < %i.%i)"):format(tpt_version[1], tpt_version[2], config.tpt_version_min, 0), {
			reason = "tpt_min_violation",
			got_major = tpt_version[1],
			got_minor = tpt_version[2],
		})
	end
	if util.version_less({ config.tpt_version_max, 0 }, tpt_version) then
		self:proto_close_("TPT version newer than last compatible; contact the server owner", ("TPT version newer than last compatible (%i.%i > %i.%i)"):format(tpt_version[1], tpt_version[2], config.tpt_version_max, 0), {
			reason = "tpt_max_violation",
			got_major = tpt_version[1],
			got_minor = tpt_version[2],
		})
	end
	if self.server_:full() then
		self:proto_close_("server is full", nil, {
			reason = "server_full",
		})
	end
	local ok, err, err2, rconinfo = self.server_:phost():call_check_all("can_connect", self)
	if not ok then
		self:proto_close_(err, err2, rconinfo)
	end
	self.flags_ = self:read_bytes_(1)
	self.guest_ = false
	local quickauth_token = self:read_str8_()
	local initial_room = self:read_str8_()
	if self.server_:can_authenticate() then
		local nick, uid, register_time = self.server_:authenticate(self, quickauth_token)
		if nick then
			local now = os.time()
			local account_age = now - register_time
			if config.min_account_age > account_age then
				nick = nil
				self:send_downgrade_reason_(("your account is too new, you will be playing as a guest for now; try again in %s to be able to use your real name"):format(util.format_difftime(register_time + config.min_account_age, now, true)))
			end
		end
		if nick then
			self.nick_, self.uid_, self.register_time_ = nick, uid, register_time
		else
			self.guest_ = true
		end
		local ok, err, err2, rconinfo = self.server_:phost():call_check_all("can_join", self)
		if not ok then
			self:proto_close_(err, err2, rconinfo)
		end
		if self.guest_ then
			self:unique_guest_nick_()
		end
	else
		if #self.initial_nick_ > config.max_nick_length then
			self:proto_error_(("nick too long (%i > %i)"):format(#self.initial_nick_, config.max_nick_length), {
				kind = "nick_too_long",
				got_length = #self.initial_nick_,
			})
		end
		if self.initial_nick_:find("[^A-Za-z0-9-_]") then
			self:proto_error_("invalid nick", {
				kind = "nick_invalid",
				got = self.initial_nick_,
			})
		end
		if self.initial_nick_ == "" then
			self:unique_guest_nick_()
		else
			self.nick_ = self.initial_nick_
		end
	end
	if self.uid_ then
		self:deduplicate_nick_(false)
		self.log_inf_("joined as $, uid $", self.nick_, self.uid_)
	elseif self.guest_ then
		self.log_inf_("joined as guest $", self.nick_)
	else
		self:deduplicate_nick_(true)
		self.log_inf_("joined as $ (unauthenticated)", self.nick_)
	end
	self.inick_ = self.nick_:lower()
	self.server_:register_client(self)
	self:send_handshake_success_()
	self.handshake_done_ = true
	util.cqueues_wrap(cqueues.running(), function()
		self:ping_()
	end, self:name() .. "/ping_")
	if initial_room == "" then
		local ok, err = self.server_:join_room(self, self:lobby_name())
		if not ok then
			self:proto_close_("cannot join lobby: " .. err, nil, {
				reason = "critical_join_room_fail",
				room_name = self:lobby_name(),
			})
		end
	else
		local ok, err = self.server_:join_room(self, initial_room)
		if not ok then
			self:proto_close_("cannot join room: " .. err, nil, {
				reason = "critical_join_room_fail",
				room_name = initial_room,
			})
		end
	end
end

function client_i:early_drop(message)
	self.log_inf_("dropped early: $", message)
	self:send_handshake_failure_(message:sub(1, 255))
	self.stopping_since_ = cqueues.monotime()
	self:close_socket_()
end

function client_i:drop(message, log_message, rconinfo)
	self.log_inf_("dropped: $", log_message or message)
	if self.handshake_done_ then
		self:send_disconnect_reason_(message)
	else
		self:send_handshake_failure_(message:sub(1, 255))
	end
	self:stop_(rconinfo)
end

function client_i:server()
	return self.server_
end

function client_i:lobby_name()
	return self.guest_ and "guest" or "null"
end

local packet_handlers = {}

function client_i:close_socket_()
	self.socket_:flush("n", self.stopping_since_ + config.sendq_flush_timeout - cqueues.monotime())
	self.socket_:shutdown()
	self.socket_:close()
end

function client_i:manage_socket_()
	local read_pollable = { pollfd = self.socket_:pollfd(), events = "r" }
	local write_pollable = { pollfd = self.socket_:pollfd(), events = "w" }
	local try_to_recv = true
	while self.status_ == "running" or (self.tx_:next() and self.stopping_since_ + config.sendq_flush_timeout > cqueues.monotime()) do
		if self.socket_:pending() == 0 then
			if self.tx_:next() then
				util.cqueues_poll(read_pollable, self.write_wake_, write_pollable, self.wake_)
			else
				util.cqueues_poll(read_pollable, self.write_wake_, self.wake_)
			end
		end
		while try_to_recv do
			local closed = false
			local data, err = self.socket_:recv(-config.read_size)
			if not data then
				if err == errno.EAGAIN then
					break
				end
				if self.socket_:eof("r") then
					self.log_inf_("connection reached eof")
					self:stop_({
						reason = "recv_failed",
						eof = true,
					})
					try_to_recv = false
				else
					self.log_inf_("recv failed with code $", err)
					self:stop_({
						reason = "recv_failed",
						code = err,
					})
					try_to_recv = false
				end
				break
			end
			local pushed, count = self.rx_:push(data)
			if pushed < count then
				self.log_inf_("recv queue limit exceeded")
				self:stop_({
					reason = "recvq_exceeded",
				})
				try_to_recv = false
				break
			end
			self.read_wake_:signal()
			if #data < config.read_size then
				break
			end
		end
		while self.tx_:next() and not self.socket_:eof("w") do
			local data, first, last = self.tx_:next()
			if not data then
				break
			end
			local count = last - first + 1
			local written, err = self.socket_:send(data, first, last)
			self.tx_:pop(written)
			if err then
				if err == errno.EAGAIN then
					break
				end
				if self.socket_:eof("w") then
					self.log_inf_("connection closed")
					self:stop_({
						reason = "send_failed",
						eof = true,
					})
				else
					self.log_inf_("send failed with code $", err)
					self:stop_({
						reason = "send_failed",
						code = err,
					})
				end
				break
			end
			if written < count then
				break
			end
		end
	end
	self:close_socket_()
end

function client_i:proto_()
	self.socket_:setmode("bn", "bn")
	self.socket_:onerror(function(_, _, code, _)
		self.socket_:clearerr()
		return code
	end)
	local real_error
	xpcall(function()
		local deadline = cqueues.monotime() + config.first_byte_timeout
		local first_byte_problem
		local function get_first_byte(fail_with)
			first_byte_problem = fail_with
			local first_byte = self.socket_:xread(-1, "bn", deadline - cqueues.monotime())
			if type(first_byte) == "string" and #first_byte == 1 then
				first_byte_problem = nil
			end
			if not first_byte_problem then
				assert(self.socket_:unget(first_byte))
				return first_byte
			end
		end
		local secure_level_matches
		do
			local first_byte = get_first_byte({
				message = "no client handshake",
				kind = "first_byte_timeout",
			})
			if not first_byte_problem then
				-- * This works because TLS_CLIENT_HELLO is not a valid first byte of any
				--   stream that conforms to any TPTMP protocol.
				secure_level_matches = (first_byte:byte() == TLS_CLIENT_HELLO) == config.secure
			end
		end
		-- * Defer handling starttls problems until after manage_socket_ starts,
		--   because that's when we can conveniently exit with proto_error_.
		local starttls_ok, starttls_err
		if not first_byte_problem then
			if config.secure and secure_level_matches then
				local tls_context = self.server_:tls_context()
				first_byte_problem = {
					message = "TLS handshake timed out",
					kind = "starttls_timeout",
				}
				starttls_ok, starttls_err = pcall(function()
					-- * :starttls may itself throw errors, hence the pcall+assert trickery.
					assert(self.socket_:starttls(tls_context, deadline - cqueues.monotime()))
				end)
				if not (not starttls_ok and starttls_err == errno.ETIMEDOUT) then
					first_byte_problem = nil
					-- * Get (i.e. enforce sending of) first byte again, now in TLS mode.
					get_first_byte({
						message = "no client handshake in TLS mode",
						kind = "first_tls_byte_timeout",
					})
				end
			end
		end
		util.cqueues_wrap(cqueues.running(), function()
			self:manage_socket_()
		end, self:name() .. "/manage_socket_")
		util.cqueues_wrap(cqueues.running(), function()
			self:expect_ping_()
		end, self:name() .. "/expect_ping_")
		if first_byte_problem then
			self:proto_error_(first_byte_problem.message, {
				kind = first_byte_problem.kind,
			})
		end
		if config.secure then
			if secure_level_matches then
				if not starttls_ok then
					self:proto_error_(("starttls failed: %s"):format(starttls_err), {
						kind = "starttls_failed",
						err = starttls_err,
					})
				end
				local hostname = self.socket_:checktls():getHostName()
				if hostname ~= config.host then
					self:proto_error_(("incorrect hostname: (%s ~= %s)"):format(hostname, config.host), {
						kind = "incorrect_hostname",
						got = hostname,
					})
				end
			else
				self:proto_close_("this TPTMP v2 server only supports secure connections; try updating TPTMP or prepending + to the port number", nil, {
					reason = "secure_level_mismatch",
				})
			end
		end
		self:handshake_()
		while true do
			local packet_id = self:read_bytes_(1)
			local handler = packet_handlers[packet_id]
			if not handler then
				self:proto_error_(("invalid packet ID (%i)"):format(packet_id), {
					kind = "invalid_packet_id",
					got = packet_id,
				})
			end
			handler(self)
		end
	end, function(err)
		if getmetatable(err) == PROTO_ERROR then
			self.log_wrn_("protocol error: $", err.log)
			self:stop_(util.info_merge({
				reason = "protocol_error",
			}, err.rconinfo))
		elseif getmetatable(err) == PROTO_CLOSE then
			self:drop(err.msg, err.log, err.rconinfo)
		elseif getmetatable(err) == PROTO_STOP then
			-- * Nothing.
		else
			log.here(err)
			real_error = true
		end
	end)
	if real_error then
		error("proto died")
	end
	self.status_ = "dead"
	if self.room_ then
		self.room_:leave(self)
	end
	self.server_:remove_client(self, self.stop_rconinfo_)
	self.wake_:signal()
end

function client_i:expect_ping_()
	local timeout_at = cqueues.monotime() + config.ping_timeout
	while self.status_ == "running" do
		local timeout = timeout_at - cqueues.monotime()
		util.cqueues_poll(timeout, self.wake_)
		if self.got_ping_ then
			self.got_ping_ = nil
			timeout_at = cqueues.monotime() + config.ping_timeout
		end
		if timeout_at < cqueues.monotime() then
			self:drop("ping timeout", nil, {
				reason = "ping_timeout",
			})
			break
		end
	end
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
		self.log_inf_("send queue limit exceeded")
		self:stop_({
			reason = "sendq_exceeded",
		})
	end
	self.write_wake_:signal()
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
	local hi = (d24 >> 16) & 0xFF
	local mi = (d24 >>  8) & 0xFF
	local lo =  d24        & 0xFF
	self:write_bytes_(hi, mi, lo)
end

function client_i:start()
	assert(self.status_ == "ready", "not ready")
	self.status_ = "running"
	util.cqueues_wrap(cqueues.running(), function()
		self:proto_()
	end, self:name() .. "/proto_")
end

function client_i:stop_(rconinfo)
	if self.status_ ~= "dead" and self.status_ ~= "stopping" then
		assert(self.status_ == "running", "not running")
		self.stop_rconinfo_ = rconinfo
		self.status_ = "stopping"
		self.stopping_since_ = cqueues.monotime()
		self.wake_:signal()
	end
end

function client_i:uid()
	return self.uid_
end

function client_i:nick()
	return self.nick_
end

function client_i:register_time()
	return self.register_time_
end

function client_i:inick()
	return self.inick_
end

function client_i:guest()
	return self.guest_
end

function client_i:room()
	return self.room_
end

function client_i:name()
	return self.name_
end

function client_i:peer()
	return self.peer_
end

function client_i:registered()
	return self.registered_
end

function client_i:mark_registered()
	self.registered_ = true
end

function client_i:move_to_room(room, id_str)
	self.room_ = room
	self.room_id_str_ = id_str
end

function client_i:request_token()
	return self:read_str8_()
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
	local _, peer_str = params.socket:peername()
	local peer = assert(jnet(peer_str))
	return setmetatable({
		server_ = params.server,
		socket_ = params.socket,
		name_ = params.name,
		peer_ = peer,
		status_ = "ready",
		wake_ = condition.new(),
		read_wake_ = condition.new(),
		write_wake_ = condition.new(),
		log_wrn_ = log.derive(log.wrn, "[" .. params.name .. "] "),
		log_inf_ = log.derive(log.inf, "[" .. params.name .. "] "),
		rx_ = buffer_list.new({ limit = config.recvq_limit }),
		tx_ = buffer_list.new({ limit = config.sendq_limit }),
	}, client_m)
end

return {
	new = new,
	client_i = client_i,
}
