return {
	commands = {
		msg = {
			func = function(client, message, words, offsets)
				if not words[3] then
					return false
				end
				local str = message:sub(offsets[3])
				local server = client:server()
				local other = server:client_by_nick(words[2])
				if not other then
					client:send_server(("\an* \au%s\an is not online"):format(words[2]))
					if client.reply_to_ == words[2] then
						client.reply_to_ = nil
					end
					return true
				end
				local ok, err = server:phost():call_check_all("content_ok", server, str)
				if not ok then
					client:send_server("\ae* Cannot send message: " .. err)
					return true
				end
				client:send_server(("\an* \au%s\an << %s"):format(other:nick(), str))
				if server:phost():call_check_all("can_interact_with", client, other) then
					other:send_server(("\an* \au%s\an >> %s"):format(client:nick(), str))
					other.reply_to_ = client:nick()
					server.log_inf_("$ >> $: $", client:nick(), other:nick(), str)
					server:rconlog({
						event = "msg",
						client_name = client:name(),
						other_client_name = other:name(),
						message = str,
					})
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
					client:send_server("\ae* Nothing to reply to")
					return {}
				end
				local str = message:sub(offsets[2])
				return { "msg", client.reply_to_, str }
			end,
			help = "/reply <message>: replies to the last private message",
		},
		R = {
			alias = "reply",
		},
	},
}
