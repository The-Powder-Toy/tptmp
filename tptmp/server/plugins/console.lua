local util = require("tptmp.server.util")

local function serialize_client(client)
	return {
		client_name = client:name(),
		client_nick = client:nick(),
		guest = client:guest(),
		uid = client:uid(),
		host = tostring(client:host()),
		room_name = client:room():name(),
	}
end

return {
	console = {
		kick = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.client_nick) ~= "string" then
					return { status = "badnick", human = "invalid nick" }
				end
				local reason = "bye"
				if data.reason then
					if type(data.reason) ~= "string" then
						return { status = "badreason", human = "invalid reason" }
					end
					reason = data.reason
				end
				local client = server:client_by_nick(data.client_nick)
				if not client then
					return { status = "enoent", human = "user not online" }
				end
				client:drop("kicked: " .. reason, nil, {
					reason = "kicked",
					message = reason,
				})
				return { status = "ok" }
			end,
		},
		clients = {
			func = function(rcon, data)
				local server = rcon:server()
				local clients = {}
				for _, client in pairs(server:clients()) do
					table.insert(clients, serialize_client(client))
				end
				clients[0] = #clients
				return { status = "ok", clients = clients }
			end,
		},
		msg_user = {
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
				client:send_server(data.message)
				return { status = "ok" }
			end,
		},
		msg_room = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.room_name) ~= "string" then
					return { status = "badroom", human = "invalid room" }
				end
				if type(data.message) ~= "string" then
					return { status = "badmessage", human = "invalid message" }
				end
				local room = server:room_by_name(data.room_name)
				if not room then
					return { status = "enoent", human = "no such room" }
				end
				room:broadcast_server(data.message)
				return { status = "ok" }
			end,
		},
		msg_all = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.message) ~= "string" then
					return { status = "badmessage", human = "invalid message" }
				end
				for _, client in util.safe_pairs(server:clients()) do
					client:send_server(data.message)
				end
				return { status = "ok" }
			end,
		},
	},
}
