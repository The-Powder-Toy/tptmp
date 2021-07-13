local log          = require("tptmp.server.log")
local util         = require("tptmp.server.util")
local config       = require("tptmp.server.config")
local basexx       = require("basexx")
local lunajson     = require("lunajson")
local http_request = require("http.request")

local authenticator_i = {}
local authenticator_m = { __index = authenticator_i }

local function token_payload(token)
	local payload = token:match("^[^%.]+%.([^%.]+)%.[^%.]+$")
	if not payload then
		return nil, "no payload", {
			substage = "match",
		}
	end
	local unb64 = basexx.from_url64(payload)
	if not unb64 then
		return nil, "bad base64", {
			substage = "base64",
		}
	end
	local ok, json = pcall(lunajson.decode, unb64)
	if not ok then
		return nil, "bad json: " .. json, {
			substage = "json",
			message = json,
		}
	end
	if type(json) ~= "table" or not json.sub or json.sub:find("[^0-9]") then
		return nil, "bad payload", {
			substage = "subject",
		}
	end
	return json
end

local function check_external_auth(client, token)
	local req, err = http_request.new_from_uri(config.auth_backend .. "?Action=Check&MaxAge=" .. config.token_max_age .. "&Token=" .. token)
	if not req then
		return nil, err, {
			substage = "new_from_uri",
			reason = err,
		}
	end
	local headers, stream = req:go(config.auth_backend_timeout)
	if not headers then
		return nil, stream, {
			substage = "go",
			reason = stream,
		}
	end
	local code = headers:get(":status")
	if code ~= "200" then
		return nil, "status code " .. code, {
			substage = "get_status",
			code = tonumber(code),
		}
	end
	local body, err = stream:get_body_as_string()
	if not body then
		return nil, err, {
			substage = "get_body_as_string",
			reason = err,
		}
	end
	local ok, json = pcall(lunajson.decode, body)
	if not ok then
		return nil, json, {
			substage = "json",
			reason = json,
		}
	end
	if json.Status ~= "OK" then
		return nil, json.Status, {
			substage = "status",
			reason = json.Status,
		}
	end
	return true
end

function authenticator_i:authenticate(client, quickauth_token)
	local nick, uid = self:authenticate_token_(client, quickauth_token)
	if nick then
		return nick, uid
	end
	self.log_inf_("requesting new authentication token from $", client:name())
	client:send_quickauth_failure()
	local new_token = client:request_token()
	return self:authenticate_token_(client, new_token)
end

function authenticator_i:authenticate_token_(client, token)
	local payload, err, rconinfo = token_payload(token)
	if not payload then
		self.log_inf_("authentication token from $ refused: $", client:name(), err)
		self:rconlog(util.info_merge({
			event = "authenticate_fail",
			client_name = client:name(),
			token = token,
			stage = "payload",
		}, rconinfo))
		return
	end
	local uid = tonumber(payload.sub)
	if self.quickauth_[uid] == token and os.time() <= payload.iat + config.token_max_age then
		self.log_inf_("cached authentication token reused by $", client:name())
		self:rconlog({
			event = "authenticate",
			client_name = client:name(),
			token = token,
		})
	else
		local ok, err, rconinfo = check_external_auth(client, token)
		if not ok then
			self.log_inf_("authentication token from $ refused: $", client:name(), err)
			self:rconlog(util.info_merge({
				event = "authenticate_fail",
				client_name = client:name(),
				token = token,
				stage = "check",
			}, rconinfo))
			return
		end
		self.log_inf_("accepted and cached authentication token from $", client:name())
		self:rconlog({
			event = "authenticate",
			client_name = client:name(),
			token = token,
		})
		self.quickauth_[uid] = token
	end
	self.log_inf_("authenticated $ as $", client:name(), payload.name)
	return payload.name, uid
end

function authenticator_i:rcon(rcon)
	self.rcon_ = rcon
end

function authenticator_i:rconlog(data)
	if self.rcon_ then
		self.rcon_:log(data)
	end
end

local function new(params)
	return setmetatable({
		log_inf_ = log.derive(log.inf, "[" .. params.name .. "] "),
		quickauth_ = {},
	}, authenticator_m)
end

return {
	new = new,
}
