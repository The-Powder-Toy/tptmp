local config         = require("tptmp.client.config")
local format         = require("tptmp.client.format")
local manager        = require("tptmp.client.manager")
local command_parser = require("tptmp.common.command_parser")

local localcmd_i = {}
local localcmd_m = { __index = localcmd_i }

local cmdp = command_parser.new({
	commands = {
		help = {
			role = "help",
			help = "/help <command>: displays command usage and notes (try /help list)",
		},
		list = {
			role = "list",
			help = "/list, no arguments: lists available commands",
		},
		size = {
			func = function(localcmd, message, words, offsets)
				local width = tonumber(words[2] and #words[2] > 0 and #words[2] <= 7 and not words[2]:find("[^0-9]") and words[2] or "")
				local height = tonumber(words[3] and #words[3] > 0 and #words[3] <= 7 and not words[3]:find("[^0-9]") and words[3] or "")
				if not width or not height then
					return false
				else
					localcmd.window:set_size(width, height)
				end
				return true
			end,
			help = "/size <width> <height>: sets the size of the chat window",
		},
		sync = {
			func = function(localcmd, message, words, offsets)
				local cli = localcmd.client_func_()
				if cli then
					cli:send_sync()
					localcmd.window:backlog_push_neutral("* Simulation synchronized")
				else
					localcmd.window:backlog_push_error("Not connected, cannot sync")
				end
				return true
			end,
			help = "/sync, no arguments: synchronizes your simulation with everyone else's in the room",
			alias = "S",
		},
		connect = {
			macro = function(localcmd, message, words, offsets)
				return { "connectroom", "", unpack(words, 2) }
			end,
			help = "/connect [host[:port]]: connects the default TPTMP server or the specified one",
			alias = "C",
		},
		reconnect = {
			macro = function(localcmd, message, words, offsets)
				if not localcmd.reconnect_ then
					localcmd.window:backlog_push_error("No successful connection on record, cannot reconnect")
					return {}
				end
				return { "connectroom", localcmd.reconnect_.room, localcmd.reconnect_.host .. ":" .. localcmd.reconnect_.secr .. localcmd.reconnect_.port }
			end,
			help = "/reconnect, no arguments: connects back to the most recently visited server",
		},
		connectroom = {
			func = function(localcmd, message, words, offsets)
				local cli = localcmd.client_func_()
				if not words[2] then
					localcmd:print_help_("connectroom")
				elseif cli then
					localcmd.window:backlog_push_error("Already connected")
				else
					local host = words[3] or config.default_host
					local host_without_port, port = host:match("^(.+):(%+?[^:]+)$")
					host = host_without_port or host
					local secure
					if port then
						secure = port:find("%+") and true
					else
						secure = config.default_secure and not socket.bind
					end
					local new_cli = localcmd.new_client_func_({
						host = host,
						port = port and tonumber(port:gsub("[^0-9]", ""):sub(1, 5)) or config.default_port,
						secure = secure,
						initial_room = words[2],
						localcmd = localcmd,
					})
					new_cli:start()
				end
				return true
			end,
			help = "/connectroom <room> [host[:port]]: same as /connect, but skips the lobby and joins the specified room",
		},
		disconnect = {
			func = function(localcmd, message, words, offsets)
				local cli = localcmd.client_func_()
				if cli then
					localcmd.kill_client_func_()
				else
					localcmd.window:backlog_push_error("Not connected")
				end
				return true
			end,
			help = "/disconnect, no arguments: disconnects from the current server",
			alias = "D",
		},
		quit = {
			func = function(localcmd, message, words, offsets)
				return { "disconnect" }
			end,
			help = "/quit, no arguments: same as /disconnect",
			alias = "Q",
		},
		names = {
			func = function(localcmd, message, words, offsets)
				local cli = localcmd.client_func_()
				if cli then
					cli:push_names("Currently in ")
				else
					localcmd.window:backlog_push_error("Not connected")
				end
				return true
			end,
			help = "/names, no arguments: tells you which room you are in and lists users present",
		},
		clear = {
			func = function(localcmd, message, words, offsets)
				localcmd.window:backlog_reset()
				localcmd.window:backlog_push_neutral("* Backlog cleared")
				return true
			end,
			help = "/clear, no arguments: clears the chat window",
		},
		me = {
			func = function(localcmd, message, words, offsets)
				local cli = localcmd.client_func_()
				if not words[2] then
					return false
				elseif cli then
					local msg = message:sub(offsets[2])
					localcmd.window:backlog_push_say3rd(cli:formatted_nick(), msg)
					cli:send_say3rd(msg)
				else
					localcmd.window:backlog_push_error("Not connected, message not sent")
				end
				return true
			end,
			help = "/me <message>: says something in third person",
		},
	},
	respond = function(localcmd, message)
		localcmd.window:backlog_push_neutral("* " .. message)
	end,
	cmd_fallback = function(localcmd, message)
		local cli = localcmd.client_func_()
		if cli then
			cli:send_say("/" .. message)
			return true
		end
		return false
	end,
	help_fallback = function(localcmd, cmdstr)
		local cli = localcmd.client_func_()
		if cli then
			cli:send_say("/shelp " .. cmdstr)
			return true
		end
		return false
	end,
	list_extra = function(localcmd, cmdstr)
		local cli = localcmd.client_func_()
		if cli then
			cli:send_say("/slist")
		end
	end,
	alias_format = "/%s is an alias for /%s",
	list_format = "Client commands: %s",
	unknown_format = "No such command (maybe it is server-only, connect and try again)",
})

function localcmd_i:parse(str)
	if str:find("^/") and not str:find("^//") then
		cmdp:parse(self, str:sub(2))
		return true
	end
end

function localcmd_i:reconnect_commit(reconnect)
	self.reconnect_ = {
		room = reconnect.room,
		host = reconnect.host,
		port = tostring(reconnect.port),
		secr = reconnect.secure and "+" or "",
	}
	manager.set("rcroom", self.reconnect_.room)
	manager.set("rchost", self.reconnect_.host)
	manager.set("rcport", self.reconnect_.port)
	manager.set("rcsecr", self.reconnect_.secr)
end

local function new(params)
	local reconnect = {
		room = manager.get("rcroom", ""),
		host = manager.get("rchost", ""),
		port = manager.get("rcport", ""),
		secr = manager.get("rcsecr", ""),
	}	
	if #reconnect.room == 0 or #reconnect.host == 0 or #reconnect.port == 0 then
		reconnect = nil
	end
	return setmetatable({
		reconnect_ = reconnect,
		client_func_ = params.client_func,
		new_client_func_ = params.new_client_func,
		kill_client_func_ = params.kill_client_func,
	}, localcmd_m)
end

return {
	new = new,
}
