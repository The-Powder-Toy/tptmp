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
					client:send_server(("* %s is not present in this room"):format(words[2]))
					return true
				end
				other:send_server(("* You have been kicked by %s: %s"):format(client:nick(), reason))
				room:log("$ kicked $: $", client:nick(), other:nick(), reason)
				server:rconlog({
					event = "kick",
					client_nick = client:nick(),
					other_client_nick = other:nick(),
					message = reason,
				})
				local ok, err = server:join_room(other, "kicked")
				if not ok then
					other:drop("cannot join kicked: " .. err, {
						reason = "critical_join_room_fail",
						room_name = "kicked",
					})
				end
				return true
			end,
			help = "/kick <user> <reason>: kicks a user from the room for the specified reason",
		},
	},
}
