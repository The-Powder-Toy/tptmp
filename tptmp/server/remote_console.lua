local cqueues   = require("cqueues")
local socket    = require("cqueues.socket")
local condition = require("cqueues.condition")
local config    = require("tptmp.server.config")
local util      = require("tptmp.server.util")

local remote_console_i = {}
local remote_console_m = { __index = remote_console_i }

function remote_console_i:close_()
	if self.client_sock_ then
		self.client_sock_:close()
		self.client_sock_ = nil
	end
end

function remote_console_i:send_line(line)
	if self.client_sock_ then
		self.client_sock_:write(line:gsub("[\r\n]", " "):gsub("[^ -~]", "") .. "\n")
	end
end

function remote_console_i:listen_()
	local server_sock = socket.listen(config.rcon_host, config.rcon_port)
	server_sock:listen()
	local server_pollable = { pollfd = server_sock:pollfd(), events = "r" }
	while self.status_ == "running" do
		local ready = util.cqueues_poll(server_pollable, self.wake_)
		if ready[server_pollable] then
			self.client_sock_ = server_sock:accept()
			local client_pollable = { pollfd = self.client_sock_:pollfd(), events = "r" }
			while self.status_ == "running" do
				local ready = util.cqueues_poll(client_pollable, self.wake_)
				if ready[client_pollable] then
					local line = self.client_sock_:read("*l")
					if not line then
						break
					end
					local func, err = load(line, "=rcon", "t", self.env_)
					if func then
						func, err = pcall(func)
					end
					err = tostring(err)
					if not func then
						err = "ERROR: " .. err
					end
					self:send_line(err)
				end
			end
			self:close_()
		end
	end
	server_sock:close()
	self.status_ = "dead"
end

function remote_console_i:start()
	assert(self.status_ == "ready", "not ready")
	self.status_ = "running"
	util.cqueues_wrap(cqueues.running(), function()
		self:listen_()
	end)
end

function remote_console_i:stop()
	if self.status_ == "dead" or self.status_ == "stopping" then
		return
	end
	assert(self.status_ == "running", "not running")
	self.status_ = "stopping"
	self.wake_:signal()
end

local function new(params)
	return setmetatable({
		env_ = params.env,
		status_ = "ready",
		wake_ = condition.new(),
	}, remote_console_m)
end

return {
	new = new,
}
