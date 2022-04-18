local cqueues = require("cqueues")
local config  = require("tptmp.server.config")

local function enforce_message_interval(client, message)
	local now = cqueues.monotime()
	local last = client.last_message_at_
	client.last_message_at_ = now
	if last + config.message_interval >= now then
		return false, "you are sending messages too quickly"
	end
	return message
end

local function enforce_limited_capitals(client, message)
	local capital = 0
	local uncapitalized = message:gsub("[A-Z]", function(ch)
		capital = capital + 1
		return ch:lower()
	end)
	local useful = 0
	for _ in message:gmatch("[^ %.,;%-%%/\\()%[%]{}:]") do
		useful = useful + 1
	end
	if useful > 6 and capital / useful > 0.3 then
		message = uncapitalized
	end
	return message
end

local enforce = {
	enforce_message_interval,
	enforce_limited_capitals,
}

return {
	hooks = {
		client_register = {
			func = function(client)
				client.last_message_at_ = 0
			end,
		},
	},
	checks = {
		message_ok = {
			func = function(client, message)
				for i = 1, #enforce do
					local err
					message, err = enforce[i](client, message)
					if not message then
						client.spam_violations_ = (client.spam_violations_ or 0) + 1
						if client.spam_violations_ >= config.max_spam_violations then
							client:proto_close_("kicked for spam", nil, {
								reason = "kicked_for_spam",
							})
						end
						return false, err
					end
				end
				client.spam_violations_ = nil
				return "rewrite", message
			end,
		},
	},
}
