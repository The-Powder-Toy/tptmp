return {
	hooks = {
		init = {
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
						return false, "bad language"
					end
				end
				return true
			end,
		},
	},
}
