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
				local diff = os.difftime(os.time(), seen)
				local units = {
					{ one =   "a year", more =   "%i years", seconds = 31556736 },
					{ one =   "a week", more =   "%i weeks", seconds =   604800 },
					{ one =    "a day", more =    "%i days", seconds =    86400 },
					{ one =  "an hour", more =   "%i hours", seconds =     3600 },
					{ one = "a minute", more = "%i minutes", seconds =       60 },
					{ one = "a second", more = "%i seconds", seconds =        1 },
				}
				local unit, count
				for i = 1, #units do
					local count_frac = diff / units[i].seconds
					if count_frac >= 1 then
						count = math.floor(count_frac)
						unit = units[i]
						break
					end
				end
				if unit then
					client:send_server(("\an* \au%s\an was last online %s ago"):format(other_nick, count == 1 and unit.one or unit.more:format(count)))
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
