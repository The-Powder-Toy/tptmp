#!/usr/bin/env lua5.3

xpcall(function()
	local ignore_newindex = { lfs = true }
	setmetatable(_ENV or getfenv(), { __index = function()
		error("__index on env", 2)
	end, __newindex = function(_, key)
		if ignore_newindex[key] then
			return
		end
		error("__newindex on env", 2)
	end})

	local lfs            = require("lfs")
	local cqueues        = require("cqueues")
	local config         = require("tptmp.server.config")
	local log            = require("tptmp.server.log")
	local util           = require("tptmp.server.util")
	local remote_console = require("tptmp.server.remote_console")
	local authenticator  = require("tptmp.server.authenticator")
	local server         = require("tptmp.server.server")
	local dynamic_config = require("tptmp.server.dynamic_config")
	local plugin_host    = require("tptmp.server.plugin_host")
	local room           = require("tptmp.server.room")
	local client         = require("tptmp.server.client")

	math.randomseed(os.time())

	local plugins = {}
	for file in lfs.dir("tptmp/server/plugins") do
		local name = file:match("^(.+)%.lua$")
		if name then
			plugins[name] = require("tptmp.server.plugins." .. name)
			log.inf("[plugin] loaded " .. name)
		end
	end
	local phost = plugin_host.new({
		plugins = plugins,
		mtidx = {
			room = room.room_i,
			client = client.client_i,
			server = server.server_i,
		},
	})

	print = log.dump
	local queue = cqueues.new()
	local rcon, auth, serv
	local function stop()
		log.inf("stopping")
		rcon:stop()
		serv:stop()
	end

	util.cqueues_wrap(queue, function()
		local dconf = dynamic_config.new({
			name = "dconf",
		})

		if config.auth then
			auth = authenticator.new({
				name = "auth",
			})
		end

		serv = server.new({
			auth = auth,
			version = config.version,
			name = "server",
			dconf = dconf,
			phost = phost,
		})
		serv:start()

		rcon = remote_console.new({
			server = serv,
			name = "rcon",
			phost = phost,
		})
		rcon:start()
	end)

	-- * util.cqueues_wrap shouldn't throw errors.
	local ok, err = pcall(function()
		assert(queue:loop())
	end)
	if type(err) == "string" and err:find("interrupted!$") then
		log.inf("interrupted")
		ok = true
	end
	assert(ok or err == util.CQUEUES_WRAP_RETHROW, "sanity check failure")
end, function(err)
	io.stderr:write("[rip] top-level error: " .. tostring(err) .. "\n")
	io.stderr:write("[rip] " .. debug.traceback():gsub("\n", "\n[rip] ") .. "\n")
end)
