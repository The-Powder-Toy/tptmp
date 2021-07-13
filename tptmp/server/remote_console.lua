local lunajson  = require("lunajson")
local cqueues   = require("cqueues")
local socket    = require("cqueues.socket")
local condition = require("cqueues.condition")
local config    = require("tptmp.server.config")
local util      = require("tptmp.server.util")
local log       = require("tptmp.server.log")

local remote_console_i = {}
local remote_console_m = { __index = remote_console_i }

function remote_console_i:close_()
	if self.client_sock_ then
		self.client_sock_:flush("n", config.rcon_sendq_flush_timeout)
		self.client_sock_:shutdown()
		self.client_sock_:close()
		self.client_sock_ = nil
	end
end

function remote_console_i:send_json_(json)
	if self.client_sock_ then
		while self.writing_ do
			self.writing_wake_:wait()
		end
		self.writing_ = true
		pcall(function()
			self.client_sock_:write(lunajson.encode(json):gsub("\n", "") .. "\n")
		end)
		self.writing_ = false
		self.writing_wake_:signal(1)
	end
end

function remote_console_i:log(data)
	self:send_json_({
		type = "log",
		data = data,
	})
end

function remote_console_i:listen_()
	local server_sock = socket.listen(config.rcon_host, config.rcon_port)
	server_sock:listen()
	local server_pollable = { pollfd = server_sock:pollfd(), events = "r" }
	while self.status_ == "running" do
		local ready = util.cqueues_poll(server_pollable, self.wake_)
		if ready[server_pollable] then
			self.client_sock_ = server_sock:accept()
			local _, host_str = self.client_sock_:peername()
			self.log_inf_("connection from $", host_str)
			local client_pollable = { pollfd = self.client_sock_:pollfd(), events = "r" }
			local last_ping_in = cqueues.monotime()
			local last_ping_out = cqueues.monotime()
			while self.status_ == "running" do
				local wait_ping_in = math.max(last_ping_in + config.rcon_ping_timeout - cqueues.monotime(), 0)
				local wait_ping_out = math.max(last_ping_out + config.rcon_ping_interval - cqueues.monotime(), 0)
				local ready = util.cqueues_poll(client_pollable, self.wake_, math.min(wait_ping_in, wait_ping_out))
				if ready[client_pollable] then
					local break_outer = false
					while true do
						local ok, line, err = pcall(function()
							return self.client_sock_:read("*l")
						end)
						if not ok then
							self.log_inf_("read failed: " .. line)
							break_outer = true
							break
						end
						if not line then
							self.log_inf_("read failed with code $", err)
							break_outer = true
							break
						end
						local ok, data = pcall(lunajson.decode, line, nil, nil, true)
						if ok then
							if data.type == "request" then
								local handler = self.handlers_[data.request]
								if handler then
									self:send_json_({
										type = "response",
										status = "handled",
										data = handler.func(self, data.data),
									})
								else
									self:send_json_({
										type = "response",
										status = "nohandler",
										human = "no such handler",
									})
									self.log_wrn_("no handler for request type $", data.request)
									break_outer = true
									break
								end
							elseif data.type == "ping" then
								last_ping_in = cqueues.monotime()
								self:send_json_({
									type = "pong",
								})
							elseif data.type == "pong" then
								-- * Nothing.
							else
								self:send_json_({
									type = "response",
									status = "notype",
									human = "no such type",
								})
								self.log_wrn_("no handler for type $", data.type)
								break_outer = true
								break
							end
						else
							self:send_json_({
								type = "response",
								status = "badjson",
								human = "invalid json",
								line = line,
								reason = data,
							})
							self.log_wrn_("bad json: $", data)
							break_outer = true
							break
						end
						local recvq = self.client_sock_:pending()
						if break_outer or recvq == 0 then
							break
						end
					end
					if break_outer then
						break
					end
				end
				if cqueues.monotime() > last_ping_in + config.rcon_ping_timeout then
					self.log_wrn_("ping timeout")
					break
				end
				if cqueues.monotime() > last_ping_out + config.rcon_ping_interval then
					self:send_json_({
						type = "ping",
					})
					last_ping_out = cqueues.monotime()
				end
			end
			self:close_()
			self.log_inf_("connection closed")
		end
	end
	server_sock:close()
	self.status_ = "dead"
end

function remote_console_i:start()
	assert(self.status_ == "ready", "not ready")
	self.status_ = "running"
	self.server_:rcon(self)
	if self.auth_ then
		self.auth_:rcon(self)
	end
	util.cqueues_wrap(cqueues.running(), function()
		self:listen_()
	end)
end

function remote_console_i:stop()
	if self.status_ == "dead" or self.status_ == "stopping" then
		return
	end
	assert(self.status_ == "running", "not running")
	self.server_:rcon(nil)
	if self.auth_ then
		self.auth_:rcon(nil)
	end
	self.status_ = "stopping"
	self.wake_:signal()
end

function remote_console_i:server()
	return self.server_
end

local function new(params)
	local handlers = {}
	for key, value in pairs(params.phost:console()) do
		handlers[key] = value
	end
	return setmetatable({
		status_ = "ready",
		handlers_ = handlers,
		server_ = params.server,
		auth_ = params.server:auth(),
		wake_ = condition.new(),
		log_inf_ = log.derive(log.inf, "[" .. params.name .. "] "),
		log_wrn_ = log.derive(log.err, "[" .. params.name .. "] "),
		writing_ = false,
		writing_wake_ = condition.new(),
	}, remote_console_m)
end

return {
	new = new,
}
