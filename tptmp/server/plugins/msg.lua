return {
	commands = {
		msg = {
			func = function(client, message, words, offsets)
				if not words[3] then
					return false
				end
				local message = message:sub(offsets[3])
				local server = client:server()
				local other = server:client_by_nick(words[2])
				local ciw = true
				if other then
					ciw = server:phost():call_check_all("can_interact_with", client, other:uid())
					if not ciw and other:room() ~= client:room() then
						other = nil
					end
				end
				if not other then
					client:send_server("* User not online")
					return true
				end
				local ok, err = server:phost():call_check_all("content_ok", server, message)
				if not ok then
					client:send_server("* Cannot send message: " .. err)
					return true
				end
				client:send_server(("* %s << %s"):format(other:nick(), message))
				if ciw then
					other:send_server(("* %s >> %s"):format(client:nick(), message))
					other.reply_to_ = client:nick()
					server.log_inf_("$ >> $: $", client:nick(), other:nick(), message)
				end
				return true
			end,
			help = "/msg <user> <message>: sends a private message",
		},
		reply = {
			macro = function(client, message, words, offsets)
				if not words[2] then
					return false
				end
				if not client.reply_to_ then
					client:send_server("* Nothing to reply to")
					return {}
				end
				local message = message:sub(offsets[2])
				return { "msg", client.reply_to_, message }
			end,
			help = "/reply <message>: replies to the last private message",
			alias = "R",
		},
	},
}
