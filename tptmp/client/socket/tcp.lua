local config      = require("tptmp.client.config")
local buffer_list = require("tptmp.common.buffer_list")

local tcp_i = {}
local tcp_m = { __index = tcp_i }

function tcp_i:before_resume()
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
				return nil, "stop", err
			end
		end
		local pushed, count = self.rx_:push(data)
		if pushed < count then
			return nil, "stop", "recv queue limit exceeded"
		end
		if closed then
			return nil, "resumestop", "connection closed: receive failed: " .. self.lasterror_
		end
		if #data < config.read_size then
			break
		end
	end
	return true
end

function tcp_i:after_resume()
	while true do
		local data, first, last = self.tx_:next()
		if not data then
			return true
		end
		local closed = false
		local count = last - first + 1
		if self.socket_:status() ~= "connected" then
			return true
		end
		local written_up_to, err, partial_up_to = self.socket_:send(data, first, last)
		if not written_up_to then
			if err == "closed" then
				written_up_to = partial_up_to
				closed = true
			elseif err == "timeout" then
				written_up_to = partial_up_to
			else
				return nil, "stop", err
			end
		end
		local written = written_up_to - first + 1
		self.tx_:pop(written)
		if closed then
			self.lasterror_ = self.socket_:lasterror()
			return nil, "stop", "connection closed: send failed: " .. self.lasterror_
		end
		if written < count then
			break
		end
	end
	return true
end

function tcp_i:connect(host, port, secure)
	return self.socket_:connect(host, port, secure)
end

function tcp_i:shutdown()
	self.socket_:shutdown()
end

function tcp_i:close()
	self.socket_:close()
end

function tcp_i:rx()
	return self.rx_
end

function tcp_i:tx()
	return self.tx_
end

local function new()
	local tcp = setmetatable({
		lasterror_ = "???",
		socket_    = socket.tcp(),
		rx_        = buffer_list.new({ limit = config.recvq_limit }),
		tx_        = buffer_list.new({ limit = config.sendq_limit }),
	}, tcp_m)
	tcp.socket_:settimeout(0)
	tcp.socket_:setoption("tcp-nodelay", true)
	return tcp
end

return {
	new = new,
}
