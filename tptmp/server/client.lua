local cqueues   = require("cqueues")
local condition = require("cqueues.condition")
local errno     = require("cqueues.errno")
local log       = require("tptmp.server.log")
local util      = require("tptmp.server.util")
local config    = require("tptmp.server.config")
local jnet      = require("jnet")

local PROTO_STOP = {}
local PROTO_ERROR = {}
local PROTO_CLOSE = {}

local client_i = {}
local client_m = { __index = client_i }

function client_i:proto_stop_()
	error(setmetatable({}, PROTO_STOP))
end

function client_i:proto_close_(message, format, ...)
	error(setmetatable({ msg = message, log = format and string.format(format, ...) or message }, PROTO_CLOSE))
end

function client_i:proto_error_(...)
	error(setmetatable({ log = string.format(...) }, PROTO_ERROR))
end

function client_i:read_(count)
	local collect
	while count > 0 do
		if self.status_ ~= "running" then
			self:stop_()
			self:proto_stop_()
		end
		local recvq = self.socket_:pending()
		if recvq > config.recvq_limit then
			self.log_inf_("recv queue limit exceeded")
			self:stop_()
			self:proto_stop_()
		end
		if self.status_ == "running" and recvq == 0 then
			util.cqueues_poll(self.socket_readable_, self.wake_)
		end
		if self.status_ ~= "running" then
			self:stop_()
			self:proto_stop_()
		end
		local data, err = self.socket_:read(-count)
		if not data or (err and err ~= errno.EAGAIN) then
			if self.socket_:eof("r") then
				self.log_inf_("connection closed while reading")
			else
				self.log_inf_("read failed with code $", err)
			end
			self:stop_()
			self:proto_stop_()
		end
		if #data > 0 then
			if not collect then
				if #data == count then
					return data
				end
				collect = {}
			end
			table.insert(collect, data)
			count = count - #data
		end
	end
	return collect and table.concat(collect) or ""
end

function client_i:read_str24_()
	local length1, length2, length3 = self:read_bytes_(3)
	return self:read_(length3 | (length2 << 8) | (length1 << 16))
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

function client_i:read_bytes_(count)
	return self:read_(count):byte(1, count)
end

function client_i:send_handshake_failure_(message)
	self:write_("\0")
	self:write_nullstr_(message)
end

function client_i:send_handshake_success_()
	self:write_("\1")
	self:write_str8_(self.nick_)
	self:write_bytes_(self.guest_ and 1 or 0)
end

function client_i:send_disconnect_reason_(message)
	self:write_("\2")
	self:write_str8_(message)
end

function client_i:send_ping_()
	self:write_("\3")
end

function client_i:send_quickauth_failure()
	self:write_("\4")
end

function client_i:send_room(id, name, item_count)
	self:write_("\16")
	self:write_str8_(name)
	self:write_bytes_(id, item_count)
end

function client_i:send_room_item(id, nick)
	self:write_bytes_(id)
	self:write_str8_(nick)
end

function client_i:send_room_chunks(chunks)
	for i = 1, #chunks do
		self:write_(chunks[i])
	end
end

function client_i:send_join(id, nick)
	self:write_("\17")
	self:write_bytes_(id)
	self:write_str8_(nick)
end

function client_i:send_leave(id)
	self:write_("\18")
	self:write_bytes_(id)
end

function client_i:send_server(message)
	self:write_("\22")
	self:write_str8_(message)
end

function client_i:send_sync_request(target)
	if self.syncing_for_ then
		self.syncing_for_[target] = true
		return
	end
	self.syncing_for_ = { [ target ] = true }
	self:write_("\128")
end

local function forward_to_room(name, packet_id, payload_size)
	local packet_id_chr = string.char(packet_id)
	client_i["handle_" .. name .. "_" .. packet_id .. "_"] = function(self)
		local payload = self:read_(payload_size)
		self.room_:broadcast(self, { packet_id_chr, self.room_id_str_, payload })
	end
end

function client_i:handle_ping_3_()
	self.got_ping_ = true
	self.wake_:signal()
end

function client_i:check_message_(message)
	local server = self:server()
	local ok, err = server:phost():call_check_all("message_ok", self, message)
	if not ok then
		self:send_server("* Cannot send message: " .. err)
		return false
	end
	return true
end

function client_i:forward_message_(format, packet, message)
	local server = self:server()
	local ok, err = server:phost():call_check_all("content_ok", server, message)
	if not ok then
		self:send_server("* Cannot send message: " .. err)
		return
	end
	self.room_:log(format, self.nick_, message)
	self.room_:broadcast_ciw(self, { packet, self.room_id_str_, string.char(#message), message })
end

function client_i:handle_say_19_()
	local message = self:read_str8_():sub(1, config.message_size):gsub("[^\32-\255]", "")
	if not self:check_message_(message) then
		return
	end
	if message:find("^//") then
		message = message:sub(2)
	elseif message:find("^/") then
		self.server_:parse(self, message:sub(2))
		return
	end
	self:forward_message_("<$> $", "\19", message)
end

function client_i:handle_say3rd_20_()
	local message = self:read_str8_():sub(1, config.message_size):gsub("[^\32-\255]", "")
	if not self:check_message_(message) then
		return
	end
	self:forward_message_("* $ $", "\20", message)
end

local function header_24be(d24)
	local hi = (d24 >> 16) & 0xFF
	local mi = (d24 >>  8) & 0xFF
	local lo =  d24        & 0xFF
	return string.char(hi, mi, lo)
end

function client_i:handle_sync_30_()
	local location = self:read_(3)
	local data = self:read_str24_()
	self.room_:broadcast(self, { "\30", self.room_id_str_, location, header_24be(#data), data })
end

function client_i:handle_pastestamp_31_()
	local location = self:read_(3)
	local data = self:read_str24_()
	self.room_:broadcast(self, { "\31", self.room_id_str_, location, header_24be(#data), data })
end

forward_to_room(    "mousepos", 32, 3)
forward_to_room(   "brushmode", 33, 1)
forward_to_room(   "brushsize", 34, 2)
forward_to_room(  "brushshape", 35, 1)
forward_to_room(    "keybdmod", 36, 1)
forward_to_room(  "selecttool", 37, 2)
forward_to_room(    "simstate", 38, 5)
forward_to_room(       "flood", 39, 4)
forward_to_room(     "lineend", 40, 3)
forward_to_room(     "rectend", 41, 3)
forward_to_room( "pointsstart", 42, 4)
forward_to_room(  "pointscont", 43, 3)
forward_to_room(   "linestart", 44, 4)
forward_to_room(   "rectstart", 45, 4)
forward_to_room(     "stepsim", 50, 0)
forward_to_room(  "sparkclear", 60, 0)
forward_to_room(    "airclear", 61, 0)
forward_to_room(      "airinv", 62, 0)
forward_to_room(    "clearsim", 63, 0)
forward_to_room(   "brushdeco", 65, 4)
forward_to_room(   "clearrect", 67, 6)
forward_to_room(  "canceldraw", 68, 0)
forward_to_room(  "loadonline", 69, 9)
forward_to_room(   "reloadsim", 70, 0)
forward_to_room( "placestatus", 71, 4)
forward_to_room("selectstatus", 72, 4)
forward_to_room(   "zoomstart", 73, 4)
forward_to_room(     "zoomend", 74, 0)
forward_to_room(   "sparksign", 75, 3)

function client_i:proto_assert_(got, expected)
	if got ~= expected then
		self:proto_error_("unexpected packet ID (%i ~= %i)", got, expected)
	end
	return got
end

function client_i:handle_sync_done_128_()
	local data = {
		self:proto_assert_(self:read_(1), "\69"), -- * loadonline_69
		self.room_id_str_,
		self:read_(9),
		self:proto_assert_(self:read_(1), "\30"), -- * sync_30
		self.room_id_str_,
		self:read_(3),
		self:read_str24_(),
		self:proto_assert_(self:read_(1), "\38"), -- * simstate_38
		self.room_id_str_,
		self:read_(5),
	}
	for target in pairs(self.syncing_for_) do
		target:write_(      data[ 1])
		target:write_(      data[ 2])
		target:write_(      data[ 3])
		target:write_(      data[ 4])
		target:write_(      data[ 5])
		target:write_(      data[ 6])
		target:write_str24_(data[ 7])
		target:write_(      data[ 8])
		target:write_(      data[ 9])
		target:write_(      data[10])
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
			self:proto_close_("nick already in use", "nick already in use (by %s)", other.name_)
		else
			other:drop("logged in from another location")
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
	local tpt_version = { tpt_major, tpt_minor }
	local version_ok = self.server_:version()
	if version ~= version_ok then
		self:proto_close_("protocol version mismatch; try updating TPTMP", "protocol version mismatch (%i ~= %i)", version, version_ok)
	end
	if util.version_less(tpt_version, config.tpt_version_min) then
		self:proto_close_("TPT version older than first compatible; try updating TPT", "TPT version older than first compatible (%i.%i < %i.%i)", tpt_version[1], tpt_version[2], config.tpt_version_min[1], config.tpt_version_min[2])
	end
	if util.version_less(config.tpt_version_max, tpt_version) then
		self:proto_close_("TPT version newer than last compatible; contact the server owner", "TPT version newer than last compatible (%i.%i > %i.%i)", tpt_version[1], tpt_version[2], config.tpt_version_max[1], config.tpt_version_max[2])
	end
	if self.server_:full() then
		self:proto_close_("server is full", "server is full")
	end
	local ok, err, err2 = self.server_:phost():call_check_all("can_connect", self)
	if not ok then
		self:proto_close_(err, "%s", err2)
	end
	self.flags_ = self:read_bytes_(1)
	self.guest_ = false
	local quickauth_token = self:read_str8_()
	local initial_room = self:read_str8_()
	if self.server_:can_authenticate() then
		self.nick_, self.uid_ = self.server_:authenticate(self, quickauth_token)
		if not self.nick_ then
			self.guest_ = true
		end
		local ok, err, err2 = self.server_:phost():call_check_all("can_join", self)
		if not ok then
			self:proto_close_(err, "%s", err2)
		end
		if self.guest_ then
			self:unique_guest_nick_()
		end
	else
		if #self.initial_nick_ > config.max_nick_length then
			self:proto_error_("nick too long", "nick too long (%i > %i)", #self.initial_nick_, config.max_nick_length)
		end
		if self.initial_nick_:find("[^A-Za-z0-9-_]") then
			self:proto_error_("invalid nick")
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
	end)
	self.server_:phost():call_hook("join", self)
	if initial_room == "" then
		local ok, err = self.server_:join_room(self, self:lobby_name())
		if not ok then
			self:proto_close_("cannot join lobby: " .. err)
		end
	else
		local ok, err = self.server_:join_room(self, initial_room)
		if not ok then
			self:proto_close_("cannot join room: " .. err)
		end
	end
end

function client_i:early_drop(message)
	self.log_inf_("dropped early: $", message)
	self:send_handshake_failure_(message:sub(1, 255))
	self.socket_:flush("n", config.sendq_flush_timeout)
	self.socket_:shutdown()
	self.socket_:close()
	self.socket_ = nil
end

function client_i:drop(message, log_message)
	self.log_inf_("dropped: $", log_message or message)
	if self.handshake_done_ then
		self:send_disconnect_reason_(message)
	else
		self:send_handshake_failure_(message:sub(1, 255))
	end
	self:disconnect_()
end

function client_i:disconnect_()
	self:stop_()
end

function client_i:server()
	return self.server_
end

function client_i:lobby_name()
	return self.guest_ and "guest" or "null"
end

local packet_handlers = {}

function client_i:proto_()
	self.socket_:setmode("bn", "bn")
	self.socket_:onerror(function(_, _, code, _)
		self.socket_:clearerr()
		return code
	end)
	local real_error
	xpcall(function()
		if config.secure then
			local ok, err = pcall(function()
				-- * :starttls may itself throw errors, hence the pcall+assert trickery.
				assert(self.socket_:starttls(self.server_:tls_context()))
			end)
			if not ok then
				self:proto_error_("starttls failed: %s", err)
			end
			local hostname = self.socket_:checktls():getHostName()
			if hostname ~= config.secure_hostname then
				self:proto_error_("incorrect hostname: (%s ~= %s)", hostname, config.secure_hostname)
			end
		end
		util.cqueues_wrap(cqueues.running(), function()
			self:expect_ping_()
		end)
		self:handshake_()
		while true do
			local packet_id = self:read_(1)
			local handler = packet_handlers[packet_id]
			if not handler then
				self:proto_error_("invalid packet ID (%i)", packet_id:byte())
			end
			handler(self)
		end
	end, function(err)
		if getmetatable(err) == PROTO_ERROR then
			self.log_wrn_("protocol error: $", err.log)
			self:disconnect_()
		elseif getmetatable(err) == PROTO_CLOSE then
			self:drop(err.msg, err.log)
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
	self.socket_:flush("n", config.sendq_flush_timeout)
	self.socket_:shutdown()
	if self.room_ then
		self.room_:leave(self)
	end
	self.server_:remove_client(self)
	self.wake_:signal()
	while self.writing_ > 0 do
		self.wake_:wait()
	end
	self.socket_:close()
	self.socket_ = nil
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
			self:drop("ping timeout")
			break
		end
	end
end

function client_i:write_(data)
	if not self.socket_ then
		return
	end
	self.writing_ = self.writing_ + 1
	local ok, err = self.socket_:write(data)
	self.writing_ = self.writing_ - 1
	if self.status_ ~= "running" then
		self.wake_:signal()
	end
	if not ok then
		if self.socket_:eof("w") then
			self.log_inf_("connection closed while writing")
		else
			self.log_inf_("write failed with code $", err)
		end
		self:stop_()
		return
	end
	local _, sendq = self.socket_:pending()
	if sendq > config.sendq_limit then
		self.log_inf_("send queue limit exceeded")
		self:stop_()
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
	end)
end

function client_i:stop_()
	if self.status_ ~= "dead" and self.status_ ~= "stopping" then
		assert(self.status_ == "running", "not running")
		self.status_ = "stopping"
		self.wake_:signal()
	end
end

function client_i:uid()
	return self.uid_
end

function client_i:nick()
	return self.nick_
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

function client_i:host()
	return self.host_
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
	local packet_id = key:match("^handle_.+_(%d+)_$")
	if packet_id then
		local packet_id_chr = string.char(tonumber(packet_id))
		assert(not packet_handlers[packet_id_chr])
		packet_handlers[packet_id_chr] = value
	end
end

local function new(params)
	local _, host_str = params.socket:peername()
	local host = assert(jnet(host_str))
	return setmetatable({
		server_ = params.server,
		socket_ = params.socket,
		socket_readable_ = { pollfd = params.socket:pollfd(), events = "r" },
		name_ = params.name,
		host_ = host,
		status_ = "ready",
		wake_ = condition.new(),
		log_wrn_ = log.derive(log.wrn, "[" .. params.name .. "] "),
		log_inf_ = log.derive(log.inf, "[" .. params.name .. "] "),
		writing_ = 0,
	}, client_m)
end

return {
	new = new,
	client_i = client_i,
}
