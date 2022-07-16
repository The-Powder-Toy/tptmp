local util = require("tptmp.server.util")

return {
	commands = {
		seen = {
			func = function(client, message, words, offsets)
				if not words[2] then
					return false
				end
				if client:guest() then
					client:send_server("\ae* Guests have no reason to use /seen")
					return true
				end
				local server = client:server()
				local other = server:client_by_nick(words[2])
				if other then
					client:send_server(("\an* \au%s\an is currently online"):format(other:nick()))
					return true
				end
				local other_uid, other_nick
				local other_user = server:offline_user_by_nick(words[2])
				if other_user then
					other_uid, other_nick = other_user.uid, other_user.nick
				end
				if not other_uid then
					client:send_server(("\ae* No user named \au%s"):format(words[2]))
					return true
				end
				local seen = server:dconf():root().seen[tostring(other_uid)]
				if not seen then
					client:send_server(("\an* \au%s\an has never been online"):format(other_nick))
					return true
				end
				local timediff = util.format_difftime(os.time(), seen)
				if timediff then
					client:send_server(("\an* \au%s\an was last online %s ago"):format(other_nick, timediff))
				else
					client:send_server(("\an* \au%s\an is a Time Lord"):format(other_nick))
				end
				return true
			end,
			help = "/seen <user>: tells you when a user was last seen online",
		},
	},
	hooks = {
		server_init = {
			func = function(server)
				local dconf = server:dconf()
				dconf:root().seen = dconf:root().seen or {}
				dconf:commit()
			end,
		},
		client_disconnect = {
			func = function(client)
				if not client:guest() then
					local dconf = client:server():dconf()
					dconf:root().seen[tostring(client:uid())] = os.time()
					dconf:commit()
				end
			end,
		},
	},
}
