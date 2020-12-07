local cqueues = require("cqueues")
local config  = require("tptmp.server.config")

return {
	hooks = {
		connect = {
			func = function(client)
				client.last_message_ = 0
			end,
		},
	},
	checks = {
		message_ok = {
			func = function(client, message)
				local now = cqueues.monotime()
				local last = client.last_message_
				client.last_message_ = now
				if last + config.message_interval >= now then
					client.message_interval_violations_ = (client.message_interval_violations_ or 0) + 1
					if client.message_interval_violations_ >= config.max_message_interval_violations then
						client:proto_close_("kicked for spam")
					end
					return false, "you are sending messages too quickly"
				end
				client.message_interval_violations_ = nil
				return true
			end,
		},
	},
}
