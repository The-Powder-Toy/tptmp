local cqueues        = require("cqueues")
local socket         = require("cqueues.socket")
local condition      = require("cqueues.condition")
local client         = require("tptmp.server.client")
local config         = require("tptmp.server.config")
local util           = require("tptmp.server.util")
local log            = require("tptmp.server.log")
local room           = require("tptmp.server.room")
local ssl            = require("openssl.ssl")
local ssl_ctx        = require("openssl.ssl.context")
local ssl_pkey       = require("openssl.pkey")
local ssl_x509       = require("openssl.x509")
local ssl_x509_chain = require("openssl.x509.chain")
local command_parser = require("tptmp.common.command_parser")
local lunajson       = require("lunajson")
local http_request   = require("http.request")

local server_i = {}
local server_m = { __index = server_i }

function server_i:load_uid_to_nick_()
	self.dconf_:root().uid_to_nick = self.dconf_:root().uid_to_nick or {}
	self.dconf_:commit()
end

function server_i:init()
	self.dconf_:hold()
	self:load_uid_to_nick_()
	self.phost_:call_hook("server_init", self)
	self.dconf_:unhold()
end

function server_i:full()
	return self.client_count_ >= config.max_clients
end

function server_i:rooms_full()
	return self.room_count_ >= config.max_rooms
end

function server_i:rooms()
	return self.name_to_room_
end

function server_i:insert_client_(client)
	local host_string = tostring(client:host())
	self.host_connections_[host_string] = (self.host_connections_[host_string] or 0) + 1
	self.name_to_client_[client:name()] = client
	self.log_inf_("$ connected from $", client:name(), host_string)
end

function server_i:connection_limit_(host)
	return (self.host_connections_[tostring(host)] or 0) >= config.max_clients_per_host
end

function server_i:register_client(client)
	client:mark_registered()
	self.client_count_ = self.client_count_ + 1
	self.nick_to_client_[client:inick()] = client
	if not client:guest() then
		self.uid_to_client_[client:uid()] = client
	end
	self.phost_:call_hook("client_register", client)
	if not client:guest() then
		self:cache_uid_to_nick_(client:uid(), client:nick())
	end
	self:rconlog({
		event = "client_register",
		client_name = client:name(),
		client_nick = client:nick(),
		uid = client:uid(),
		guest = client:guest(),
	})
end

function server_i:cache_uid_to_nick_(uid, nick)
	local uid = tostring(uid)
	if self.dconf_:root().uid_to_nick[uid] ~= nick then
		self.dconf_:root().uid_to_nick[uid] = nick
		self.dconf_:commit()
	end
end

function server_i:remove_client(client, rconinfo)
	if client:registered() then
		self.phost_:call_hook("client_disconnect", client)
		self.client_count_ = self.client_count_ - 1
		self.nick_to_client_[client:inick()] = nil
		if not client:guest() then
			self.uid_to_client_[client:uid()] = nil
		end
	end
	self.phost_:call_hook("client_cleanup", client)
	self.name_to_client_[client:name()] = nil
	local host_string = tostring(client:host())
	self.host_connections_[host_string] = self.host_connections_[host_string] - 1
	if self.host_connections_[host_string] == 0 then
		self.host_connections_[host_string] = nil
	end
	self.log_inf_("$ disconnected", client:name())
	self:rconlog(util.info_merge({
		event = "client_disconnect",
		client_name = client:name(),
	}, rconinfo))
end

function server_i:clients()
	return self.name_to_client_
end

function server_i:listen_()
	local server_socket = socket.listen({
		host = config.host,
		port = config.port,
		nodelay = true,
	})
	server_socket:listen()
	self.log_inf_("listening on $:$", config.host, config.port)
	local server_pollable = { pollfd = server_socket:pollfd(), events = "r" }
	while self.status_ == "running" do
		local ready = util.cqueues_poll(server_pollable, self.wake_)
		if ready[server_pollable] then
			self.client_unique_ = self.client_unique_ + 1
			local client = client.new({
				server = self,
				socket = server_socket:accept(),
				name = "client-" .. self.client_unique_,
			})
			self:rconlog({
				event = "client_connect",
				client_name = client:name(),
				host = tostring(client:host()),
			})
			if self:connection_limit_(client:host()) then
				client:early_drop("connection limit exceeded")
				self:rconlog(util.info_merge({
					event = "client_disconnect",
					client_name = client:name(),
					reason = "connection_limit_exceeded",
				}, rconinfo))
			else
				self:insert_client_(client)
				client:start()
			end
		end
	end
	for _, client in util.safe_pairs(self.name_to_client_) do
		client:drop("server closed", {
			reason = "server_closed",
		})
	end
	server_socket:close()
	self.status_ = "dead"
end

function server_i:start()
	assert(self.status_ == "ready", "not ready")
	self.status_ = "running"
	util.cqueues_wrap(cqueues.running(), function()
		self:listen_()
	end)
end

function server_i:stop()
	if self.status_ == "dead" or self.status_ == "stopping" then
		return
	end
	assert(self.status_ == "running", "not running")
	self.status_ = "stopping"
	self.wake_:signal()
end

function server_i:create_room(name)
	self.room_count_ = self.room_count_ + 1
	self.name_to_room_[name] = room.new({
		server = self,
		name = name,
	})
	self:rconlog({
		event = "room_create",
		room_name = name,
	})
end

function server_i:phost()
	return self.phost_
end

function server_i:client_count()
	return self.client_count_
end

function server_i:room_count()
	return self.room_count_
end

function server_i:cleanup_room(name)
	self.name_to_room_[name] = nil
	self.room_count_ = self.room_count_ - 1
	self:rconlog({
		event = "room_cleanup",
		room_name = name,
	})
end

function server_i:join_room(client, name)
	name = name:lower()
	if not self.name_to_room_[name] then
		if #name > config.max_room_name_length then
			self:rconlog({
				event = "room_join_fail",
				client_nick = client:nick(),
				room_name = name,
				reason = "room_name_too_long",
			})
			return nil, "room name too long"
		end
		if not name:find("^[a-z0-9-_]+$") then
			self:rconlog({
				event = "room_join_fail",
				client_nick = client:nick(),
				room_name = name,
				reason = "invalid_room_name",
			})
			return nil, "invalid room name"
		end
		if self:rooms_full() then
			self:rconlog({
				event = "room_join_fail",
				client_nick = client:nick(),
				room_name = name,
				reason = "room_limit_exceeded",
			})
			return nil, "room limit exceeded"
		end
		self:create_room(name)
	end
	local rm = self.name_to_room_[name]
	local ok, err, rconinfo = rm:join(client)
	if not ok then
		self:rconlog(util.info_merge({
			event = "room_join_fail",
			client_nick = client:nick(),
			room_name = name,
		}, rconinfo))
		rm:cleanup()
	end
	self:rconlog({
		event = "room_join",
		client_nick = client:nick(),
		room_name = name,
	})
	return ok, err
end

function server_i:room_by_name(name)
	return self.name_to_room_[name:lower()]
end

function server_i:client_by_nick(name)
	return self.nick_to_client_[name:lower()]
end

function server_i:client_by_uid(uid)
	return self.uid_to_client_[uid]
end

function server_i:authenticate(client, token)
	return self.auth_:authenticate(client, token)
end

function server_i:can_authenticate()
	return self.auth_ and true
end

function server_i:version()
	return self.version_
end

function server_i:parse(...)
	return self.cmdp_:parse(...)
end

function server_i:dconf()
	return self.dconf_
end

local function fetch_user(nick)
	local req, err = http_request.new_from_uri(config.uid_backend .. "?Name=" .. nick)
	if not req then
		self:rconlog({
			event = "fetch_user_fail",
			input = nick,
			stage = "new_from_uri",
			reason = err,
		})
		return nil, err
	end
	local headers, stream = req:go(config.uid_backend_timeout)
	if not headers then
		self:rconlog({
			event = "fetch_user_fail",
			input = nick,
			stage = "go",
			reason = stream,
		})
		return nil, stream
	end
	local code = headers:get(":status")
	if code ~= "200" then
		self:rconlog({
			event = "fetch_user_fail",
			input = nick,
			stage = "get_status",
			reason = "non200",
			code = tonumber(code),
		})
		return nil, "status code " .. code
	end
	local body, err = stream:get_body_as_string()
	if not body then
		self:rconlog({
			event = "fetch_user_fail",
			input = nick,
			stage = "get_body_as_string",
			err = err,
		})
		return nil, err
	end
	local ok, json = pcall(lunajson.decode, body)
	if not ok then
		self:rconlog({
			event = "fetch_user_fail",
			input = nick,
			stage = "json",
			err = json,
		})
		return nil, json
	end
	self:rconlog({
		event = "fetch_user",
		input = nick,
		uid = json.User.ID,
		nick = json.User.Username,
	})
	return json.User.ID, json.User.Username
end

function server_i:offline_user_by_nick(nick)
	nick = nick:lower()
	if nick:find("[^0-9a-z-_]") then
		return
	end
	if not config.auth then
		return
	end
	local now = cqueues.monotime()
	local cached = self.offline_user_cache_[nick]
	if cached then
		if cached.iat + config.offline_user_cache_max_age < now then
			self.offline_user_cache_[nick] = nil
		else
			return cached.uid, cached.nick
		end
	end
	local fuid, fnick
	local client = self:client_by_nick(nick)
	if client then
		fuid, fnick = client:uid(), client:nick()
	else
		fuid, fnick = fetch_user(nick)
		if not fuid then
			self.log_inf_("failed to fetch user $: $", nick, fnick)
		end
	end
	if fuid then
		self:cache_uid_to_nick_(fuid, fnick)
		self.offline_user_cache_[nick] = {
			iat = now,
			uid = fuid,
			nick = fnick,
		}
		return fuid, fnick
	end
end

function server_i:offline_user_by_uid(uid)
	local nick = self.dconf_:root().uid_to_nick[tostring(uid)]
	if nick then
		return uid, nick
	end
end

function server_i:rcon(rcon)
	self.rcon_ = rcon
end

function server_i:rconlog(data)
	if self.rcon_ then
		self.rcon_:log(data)
	end
end

function server_i:tls_context()
	return ssl.new(self.tls_context_)
end

function server_i:auth()
	return self.auth_
end

local function tls_context()
	local ctx = ssl_ctx.new("TLS", true)
	ctx:setCipherList(table.concat({
		"ECDHE-ECDSA-AES256-GCM-SHA384",
		"ECDHE-RSA-AES256-GCM-SHA384",
		"ECDHE-ECDSA-CHACHA20-POLY1305",
		"ECDHE-RSA-CHACHA20-POLY1305",
		"ECDHE-ECDSA-AES128-GCM-SHA256",
		"ECDHE-RSA-AES128-GCM-SHA256",
		"ECDHE-ECDSA-AES256-SHA384",
		"ECDHE-RSA-AES256-SHA384",
		"ECDHE-ECDSA-AES128-SHA256",
		"ECDHE-RSA-AES128-SHA256",
	}, ":"))
	local function get_key(func, path)
		local handle = assert(io.open(path, "rb"))
		local key = func(handle:read("*a"), "PEM")
		handle:close()
		return key
	end
	local chain = ssl_x509_chain.new()
	chain:add(get_key(ssl_x509.new, config.secure_chain_path))
	ctx:setCertificateChain(chain)
	ctx:setCertificate(get_key(ssl_x509.new, config.secure_cert_path))
	ctx:setPrivateKey(get_key(ssl_pkey.new, config.secure_pkey_path))
	ctx:setOptions(
		ssl_ctx.OP_NO_COMPRESSION  |
		ssl_ctx.OP_SINGLE_ECDH_USE |
		ssl_ctx.OP_NO_SSLv2        |
		ssl_ctx.OP_NO_SSLv3        |
		ssl_ctx.OP_NO_TLSv1        |
		ssl_ctx.OP_NO_TLSv1_1
	)
	ctx:setEphemeralKey(ssl_pkey.new({
		type = "EC",
		curve = "prime256v1",
	}))
	return ctx
end

local function new(params)
	local commands = {
		shelp = {
			role = "help",
			help = "/shelp <command>: displays server command usage and notes (try /shelp slist)",
		},
		slist = {
			role = "list",
			help = "/slist, no arguments: lists available server commands",
		},
		lobby = {
			macro = function(client, message, words, offsets)
				return { "join", client:lobby_name() }
			end,
			help = "/lobby, no arguments: joins the lobby",
		},
		L = {
			alias = "lobby",
		},
		join = {
			func = function(client, message, words, offsets)
				if not words[2] then
					return false
				end
				local server = client:server()
				local ok, err = server:phost():call_check_all("content_ok", server, words[2])
				if not ok then
					client:send_server("* Cannot join room: " .. err)
					return true
				end
				local ok, err = server:join_room(client, words[2])
				if not ok then
					client:send_server("* Cannot join room: " .. err)
					return true
				end
				return true
			end,
			help = "/join <room>: joins the specified room",
		},
		J = {
			alias = "join",
		},
		online = {
			func = function(client, message, words, offsets)
				local clients = client:server():client_count()
				local rooms = client:server():room_count()
				client:send_server(("* There %s %s %s online in %s %s"):format(
					clients == 1 and "is" or "are",
					clients,
					clients == 1 and "user" or "users",
					rooms,
					rooms == 1 and "room" or "rooms"
				))
				return true
			end,
			help = "/online, no arguments: tells you how many users are online in how many rooms",
		},
	}
	for key, value in pairs(params.phost:commands()) do
		commands[key] = value
	end
	local cmdp = command_parser.new({
		commands = commands,
		respond = function(client, message)
			client:send_server("* " .. message)
		end,
		alias_format = "/%s is an alias for /%s",
		list_format = "Server commands: %s",
		unknown_format = "No such command, try /list",
	})
	local server = setmetatable({
		auth_ = params.auth,
		version_ = params.version,
		wake_ = condition.new(),
		status_ = "ready",
		name_to_client_ = {},
		client_unique_ = 0,
		client_count_ = 0,
		room_count_ = 0,
		log_inf_ = log.derive(log.inf, "[" .. params.name .. "] "),
		name_to_room_ = {},
		nick_to_client_ = {},
		uid_to_client_ = {},
		host_connections_ = {},
		dconf_ = params.dconf,
		cmdp_ = cmdp,
		phost_ = params.phost,
		offline_user_cache_ = {},
	}, server_m)
	if config.secure then
		server.tls_context_ = tls_context()
	end
	server:init()
	return server
end

return {
	new = new,
	server_i = server_i,
}
