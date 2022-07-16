return {
	commands = {
		room = {
			func = function(client, message, words, offsets)
				local room = client:room()
				client:send_server(("\an* Name: %s"):format(room:name()))
				client:server():phost():call_hook("room_info", room, client)
				return true
			end,
			help = "/room, no arguments: tells you information about the room",
		},
	},
}
