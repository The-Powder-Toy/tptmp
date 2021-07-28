local util = require("tptmp.server.util")

return {
	hooks = {
		server_init = {
			func = function(server)
				local dconf = server:dconf()
				local bad_words = dconf:root().bad_words or {}
				bad_words[0] = #bad_words
				dconf:root().bad_words = bad_words
				dconf:commit()
			end,
		},
	},
	checks = {
		content_ok = {
			func = function(server, message)
				-- * TODO[opt]: something better
				local dconf = server:dconf()
				local bad_words = dconf:root().bad_words
				for i = 1, #bad_words do
					if message:lower():find(bad_words[i]) then
						return false, "bad language", {
							reason = "bad_language",
						}
					end
				end
				return true
			end,
		},
	},
	console = {
		badwords = {
			func = function(rcon, data)
				local server = rcon:server()
				local dconf = server:dconf()
				local bad_words = dconf:root().bad_words or {}
				if type(data.word) ~= "string" then
					return { status = "badword", human = "invalid word" }
				end
				local word = data.word:lower()
				if data.action == "insert" then
					local idx = util.array_find(bad_words, word)
					if idx then
						return { status = "eexist", human = "already marked bad" }
					end
					table.insert(bad_words, word)
					dconf:commit()
					return { status = "ok" }
				elseif data.action == "remove" then
					local idx = util.array_find(bad_words, word)
					if not idx then
						return { status = "enoent", human = "not currently marked bad" }
					end
					table.remove(bad_words, idx)
					dconf:commit()
					return { status = "ok" }
				elseif data.action == "check" then
					local idx = util.array_find(bad_words, word)
					return { status = "ok", marked = idx and true or false }
				end
				return { status = "badaction", human = "unrecognized action" }
			end,
		},
	},
}
