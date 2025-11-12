local config      = require("tptmp.client.config")
local buffer_list = require("tptmp.common.buffer_list")
local modulepack  = require("modulepack")

local web_i = {}
local web_m = { __index = web_i }

function web_i:connect(host, port, secure)
	if not self.socket_ then
		local address, path = host:match("^([^/]+)(/.*)$")
		if not address then
			address, path = host, "/"
		end
		self.socket_ = socket.web((secure and "wss://" or "ws://") .. address .. ":" .. port .. path, { config.websocket_protocol })
		self.tx_ = {
			push = function(_, data)
				local _, tx_size = self.socket_:status()
				local count = #data
				local want = math.min(count, config.sendq_limit - tx_size)
				self.socket_:send(data, true, 1, want)
				return want, count
			end,
		}
		self.socket_:onClose(modulepack.xpcall_wrap(function(code, reason, clean)
			self.closed_ = true
			if not clean then
				self.lasterror_ = reason
			end
		end, self.handle_error_func_))
		self.socket_:onMessage(modulepack.xpcall_wrap(function(message, binary)
			if not binary then
				self.lasterror_ = "unexpected string frame"
				self.socket_:close(1002, self.lasterror_)
			end
			local pushed, count = self.rx_:push(message)
			if pushed < count then
				self.lasterror_ = "recv queue limit exceeded"
				self.socket_:close(1002, self.lasterror_)
			end
		end, self.handle_error_func_))
	end
	if self.socket_:status() == "connecting" then
		return nil, "timeout"
	end
	if self.socket_:status() ~= "open" then
		return nil, self.lasterror_
	end
	return true
end

function web_i:close()
	self.socket_:close()
end

function web_i:before_resume()
	return true
end

function web_i:after_resume()
	if self.closed_ then
		return nil, "stop", "connection closed: " .. self.lasterror_
	end
	return true
end

function web_i:shutdown()
	self.closed_ = true
end

function web_i:rx()
	return self.rx_
end

function web_i:tx()
	return self.tx_
end

local function new(params)
	return setmetatable({
		lasterror_         = "???",
		closed_            = false,
		rx_                = buffer_list.new({ limit = config.recvq_limit }),
		handle_error_func_ = params.handle_error_func,
	}, web_m)
end

return {
	new = new,
}
