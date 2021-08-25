local config         = require("tptmp.client.config")
local format         = require("tptmp.client.format")
local manager        = require("tptmp.client.manager")
local command_parser = require("tptmp.common.command_parser")
local colours        = require("tptmp.client.colours")

local localcmd_i = {}
local localcmd_m = { __index = localcmd_i }

local function parse_fps_sync(fps_sync)
	fps_sync = fps_sync and tonumber(fps_sync) or false
	fps_sync = fps_sync and math.floor(fps_sync) or false
	fps_sync = fps_sync and fps_sync >= 2 and fps_sync or false
	return fps_sync
end

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
					localcmd.window_:set_size(width, height)
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
					if localcmd.window_status_func_() ~= "hidden" then
						localcmd.window_:backlog_push_neutral("* Simulation synchronized")
					end
				else
					if localcmd.window_status_func_() ~= "hidden" then
						localcmd.window_:backlog_push_error("Not connected, cannot sync")
					end
				end
				return true
			end,
			help = "/sync, no arguments: synchronizes your simulation with everyone else's in the room; shortcut is Alt+S",
		},
		S = {
			alias = "sync",
		},
		fpssync = {
			func = function(localcmd, message, words, offsets)
				local cli = localcmd.client_func_()
				if words[2] == "on" then
					if not localcmd.fps_sync_ then
						localcmd.fps_sync_ = tpt.setfpscap()
					end
					if words[3] then
						local fps_sync = parse_fps_sync(words[3])
						if not fps_sync then
							return false
						end
						localcmd.fps_sync_ = fps_sync
					end
					manager.set("fpsSync", tostring(localcmd.fps_sync_))
					if cli then
						cli:fps_sync(localcmd.fps_sync_)
					end
					localcmd.window_:backlog_push_neutral("* FPS synchronization enabled")
					return true
				elseif words[2] == "check" or not words[2] then
					if localcmd.fps_sync_ then
						local cli = localcmd.client_func_()
						if cli then
							cli:push_fpssync()
						else
							localcmd.window_:backlog_push_fpssync(true)
						end
					else
						localcmd.window_:backlog_push_fpssync(false)
					end
					return true
				elseif words[2] == "off" then
					localcmd.fps_sync_ = false
					manager.set("fpsSync", tostring(localcmd.fps_sync_))
					if cli then
						cli:fps_sync(localcmd.fps_sync_)
					end
					localcmd.window_:backlog_push_neutral("* FPS synchronization disabled")
					return true
				end
				return false
			end,
			help = "/fpssync on [targetfps]\\check\\off: enables or disables FPS synchronization with those in the room who also have it enabled; targetfps defaults to the current FPS cap",
		},
		floating = {
			func = function(localcmd, message, words, offsets)
				local cli = localcmd.client_func_()
				if words[2] == "on" then
					localcmd.floating_ = true
					localcmd.window_set_floating_func_(true)
					manager.set("floating", "on")
					localcmd.window_:backlog_push_neutral("* Floating mode enabled")
					return true
				elseif words[2] == "check" or not words[2] then
					if localcmd.floating_ then
						localcmd.window_:backlog_push_neutral("* Floating mode currenly enabled")
					else
						localcmd.window_:backlog_push_neutral("* Floating mode currenly disabled")
					end
					return true
				elseif words[2] == "off" then
					localcmd.floating_ = false
					localcmd.window_set_floating_func_(false)
					manager.set("floating", "false")
					localcmd.window_:backlog_push_neutral("* Floating mode disabled")
					return true
				end
				return false
			end,
			help = "/floating on\\check\\off: enables or disables floating mode: messages are drawn even when the window is hidden",
		},
		connect = {
			macro = function(localcmd, message, words, offsets)
				return { "connectroom", "", unpack(words, 2) }
			end,
			help = "/connect [host[:[+]port]]: connects the default TPTMP server or the specified one, add + to connect securely",
		},
		C = {
			alias = "connect",
		},
		reconnect = {
			macro = function(localcmd, message, words, offsets)
				if not localcmd.reconnect_ then
					localcmd.window_:backlog_push_error("No successful connection on record, cannot reconnect")
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
					return false
				elseif cli then
					localcmd.window_:backlog_push_error("Already connected")
				else
					local host = words[3] or config.default_host
					local host_without_port, port = host:match("^(.+):(%+?[^:]+)$")
					host = host_without_port or host
					local secure
					if port then
						secure = port:find("%+") and true
					else
						secure = config.default_secure
					end
					local new_cli = localcmd.new_client_func_({
						host = host,
						port = port and tonumber(port:gsub("[^0-9]", ""):sub(1, 5)) or config.default_port,
						secure = secure,
						initial_room = words[2],
						localcmd = localcmd,
					})
					new_cli:nick_colour_seed(localcmd.nick_colour_seed_)
					new_cli:fps_sync(localcmd.fps_sync_)
					new_cli:start()
				end
				return true
			end,
			help = "/connectroom <room> [host[:[+]port]]: same as /connect, but skips the lobby and joins the specified room",
		},
		CR = {
			alias = "connectroom",
		},
		disconnect = {
			func = function(localcmd, message, words, offsets)
				local cli = localcmd.client_func_()
				if cli then
					localcmd.kill_client_func_()
				else
					localcmd.window_:backlog_push_error("Not connected, cannot disconnect")
				end
				return true
			end,
			help = "/disconnect, no arguments: disconnects from the current server",
		},
		D = {
			alias = "disconnect",
		},
		quit = {
			alias = "disconnect",
		},
		Q = {
			alias = "disconnect",
		},
		names = {
			func = function(localcmd, message, words, offsets)
				local cli = localcmd.client_func_()
				if cli then
					cli:push_names("Currently in ")
				else
					localcmd.window_:backlog_push_error("Not connected, cannot list users")
				end
				return true
			end,
			help = "/names, no arguments: tells you which room you are in and lists users present",
		},
		clear = {
			func = function(localcmd, message, words, offsets)
				localcmd.window_:backlog_reset()
				localcmd.window_:backlog_push_neutral("* Backlog cleared")
				return true
			end,
			help = "/clear, no arguments: clears the chat window",
		},
		hide = {
			func = function(localcmd, message, words, offsets)
				localcmd.window_.hide_window_func_()
				return true
			end,
			help = "/hide, no arguments: hides the chat window; shortcut is Shift+Escape, this toggles window visibility (different from Escape without Shift, which defocuses the input box, and its counterpart Enter, which focuses it)",
		},
		me = {
			func = function(localcmd, message, words, offsets)
				local cli = localcmd.client_func_()
				if not words[2] then
					return false
				elseif cli then
					local msg = message:sub(offsets[2])
					localcmd.window_:backlog_push_say3rd(cli:formatted_nick(), msg)
					cli:send_say3rd(msg)
				else
					localcmd.window_:backlog_push_error("Not connected, message not sent")
				end
				return true
			end,
			help = "/me <message>: says something in third person",
		},
		ncseed = {
			func = function(localcmd, message, words, offsets)
				localcmd.nick_colour_seed_ = words[2] or tostring(math.random())
				manager.set("nickColourSeed", tostring(localcmd.nick_colour_seed_))
				local cli = localcmd.client_func_()
				localcmd.window_:nick_colour_seed(localcmd.nick_colour_seed_)
				if cli then
					cli:nick_colour_seed(localcmd.nick_colour_seed_)
				end
				return true
			end,
			help = "/ncseed [seed]: set nick colour seed, randomize it if not specified, default is 0",
		},
	},
	respond = function(localcmd, message)
		localcmd.window_:backlog_push_neutral(message)
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
	help_format = colours.commonstr.neutral .. "* %s",
	alias_format = colours.commonstr.neutral .. "* /%s is an alias for /%s",
	list_format = colours.commonstr.neutral .. "* Client commands: %s",
	unknown_format = colours.commonstr.error .. "* No such command, try /list (maybe it is server-only, connect and try again)",
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
	manager.set("reconnectRoom", self.reconnect_.room)
	manager.set("reconnectHost", self.reconnect_.host)
	manager.set("reconnectPort", self.reconnect_.port)
	manager.set("reconnectSecure", self.reconnect_.secr)
end

local function new(params)
	local reconnect = {
		room = manager.get("reconnectRoom", ""),
		host = manager.get("reconnectHost", ""),
		port = manager.get("reconnectPort", ""),
		secr = manager.get("reconnectSecure", ""),
	}
	if #reconnect.room == 0 or #reconnect.host == 0 or #reconnect.port == 0 then
		reconnect = nil
	end
	local fps_sync = parse_fps_sync(manager.get("fpsSync", "0"))
	local floating = manager.get("floating", "off") == "on"
	local cmd = setmetatable({
		fps_sync_ = fps_sync,
		floating_ = floating,
		reconnect_ = reconnect,
		window_status_func_ = params.window_status_func,
		window_set_floating_func_ = params.window_set_floating_func,
		client_func_ = params.client_func,
		new_client_func_ = params.new_client_func,
		kill_client_func_ = params.kill_client_func,
		nick_colour_seed_ = manager.get("nickColourSeed", "0"),
		window_ = params.window,
	}, localcmd_m)
	cmd.window_:nick_colour_seed(cmd.nick_colour_seed_)
	cmd.window_set_floating_func_(floating)
	return cmd
end

return {
	new = new,
}
