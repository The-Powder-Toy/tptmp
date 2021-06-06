return {
	commands = {
		back = {
			macro = function(client, message, words, offsets)
				if client.back_target_ then
					return { "join", client.back_target_ }
				end
				client:send_server("* No previous room")
				return {}
			end,
			help = "/back, no arguments: joins the room you were previously in",
		},
		B = {
			alias = "back",
		},
	},
	hooks = {
		leave_room = {
			func = function(room, client)
				client.back_target_ = room:name()
			end,
		},
	},
}
