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
				local other_uid, other_nick = server:offline_user_by_nick(words[2])
				if not other_uid then
					client:send_server(("\ae* No user named \au%s"):format(words[2]))
					return true
				end
				local seen = server:dconf():root().seen[tostring(other_uid)]
				if not seen then
					client:send_server(("\an* \au%s\an has never been online"):format(other_nick))
					return true
				end
				local diff = os.time() - seen
				local days  = diff // 86400
				diff        = diff  % 86400
				local hours = diff //  3600
				diff        = diff  %  3600
				local mins  = diff //    60
				local secs  = diff  %    60
				local count, unit
				if days > 0 then
					count = days
					unit = days == 1 and "day" or "days"
				elseif hours > 0 then
					count = hours
					unit = hours == 1 and "hour" or "hours"
				elseif mins > 0 then
					count = mins
					unit = mins == 1 and "minute" or "minutes"
				else
					count = secs
					unit = secs == 1 and "second" or "seconds"
				end
				client:send_server(("\an* \au%s\an was ast online %s %s ago"):format(other_nick, count, unit))
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
