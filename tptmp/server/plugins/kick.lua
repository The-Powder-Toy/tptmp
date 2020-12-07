return {
	commands = {
		kick = {
			func = function(client, message, words, offsets)
				if not words[2] then
					return false
				end
				local reason = offsets[3] and message:sub(offsets[3]) or "bye"
				local server = client:server()
				local room = client:room()
				if not room:is_owner(client) then
					client:send_server("* You are not an owner of this room")
					return true
				end
				local other = server:client_by_nick(words[2])
				if not (other and other:room() == room) then
					client:send_server("* User not present in this room")
					return true
				end
				other:send_server(("* You have been kicked by %s: %s"):format(client:nick(), reason))
				room:log("$ kicked $: $", client:nick(), other:nick(), reason)
				local ok, err = server:join_room(other, other:lobby_name())
				if not ok then
					other:drop("cannot join lobby: " .. err)
				end
				return true
			end,
			help = "/kick <user> <reason>: kicks a user from the room for the specified reason",
		},
	},
}
