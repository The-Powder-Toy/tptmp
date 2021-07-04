return {
	commands = {
		self = {
			func = function(client, message, words, offsets)
				client:send_server("\an* Name: \au" .. client:nick())
				client:server():phost():call_hook("self_info", client)
				return true
			end,
			help = "/self, no arguments: tells you information about yourself",
		},
	},
}
