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
				if not room:owned_by_client(client) then
					client:send_server("\ae* You are not an owner of this room")
					return true
				end
				local other = server:client_by_nick(words[2])
				if not (other and other:room() == room) then
					client:send_server(("\ae* \au%s\ae is not present in this room"):format(words[2]))
					return true
				end
				other:send_server(("\al* You have been kicked by \au%s\al: %s"):format(client:nick(), reason))
				room:log("$ kicked $: $", client:nick(), other:nick(), reason)
				server:rconlog({
					event = "kick",
					client_name = client:name(),
					other_client_name = other:name(),
					message = reason,
				})
				local ok, err = server:join_room(other, "kicked")
				if not ok then
					other:drop("cannot join kicked: " .. err, nil, {
						reason = "critical_join_room_fail",
						room_name = "kicked",
					})
				end
				return true
			end,
			help = "/kick <user> <reason>: kicks a user from the room for the specified reason",
		},
	},
	console = {
		skick = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.client_nick) ~= "string" then
					return { status = "badnick", human = "invalid nick" }
				end
				if type(data.message) ~= "string" then
					return { status = "badmessage", human = "invalid message" }
				end
				local client = server:client_by_nick(data.client_nick)
				if not client then
					return { status = "enoent", human = "user not online" }
				end
				if not client:guest() then
					server:quickauth_flush(client:uid())
				end
				client:drop("skicked: " .. data.message, nil, {
					reason = "skicked",
					message = data.message,
				})
				return { status = "ok" }
			end,
		},
	},
}
