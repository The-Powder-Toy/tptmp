local util = require("tptmp.server.util")

local function serialize_client(client)
	return {
		nick = client:nick(),
		guest = client:guest(),
		uid = client:uid(),
		host = tostring(client:host()),
		room = client:room():name(),
	}
end

return {
	console = {
		kick = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.nick) ~= "string" then
					return { status = "badnick", human = "invalid nick", nick = data.nick }
				end
				local reason = "bye"
				if data.reason then
					if type(data.reason) ~= "string" then
						return { status = "badreason", human = "invalid reason", reason = data.reason }
					end
					reason = data.reason
				end
				local client = server:client_by_nick(data.nick)
				if not client then
					return { status = "enoent", human = "user not online", nick = data.nick }
				end
				client:drop("kicked: " .. reason)
				return { status = "ok" }
			end,
		},
		clients = {
			func = function(rcon, data)
				local server = rcon:server()
				local clients = {}
				for client in pairs(server.clients_) do
					table.insert(clients, serialize_client(client))
				end
				clients[0] = #clients
				return { status = "ok", clients = clients }
			end,
		},
		msg_user = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.nick) ~= "string" then
					return { status = "badnick", human = "invalid nick", nick = data.nick }
				end
				if type(data.message) ~= "string" then
					return { status = "badreason", human = "invalid message", message = data.message }
				end
				local client = server:client_by_nick(data.nick)
				if not client then
					return { status = "enoent", human = "user not online", nick = data.nick }
				end
				client:send_server(data.message)
				return { status = "ok" }
			end,
		},
		msg_room = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.room) ~= "string" then
					return { status = "badroom", human = "invalid room", room = data.room }
				end
				if type(data.message) ~= "string" then
					return { status = "badreason", human = "invalid message", message = data.message }
				end
				local room = server:room_by_name(data.room)
				if not room then
					return { status = "enoent", human = "no such room", room = data.room }
				end
				room:broadcast_server(data.message)
				return { status = "ok" }
			end,
		},
		msg_all = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.message) ~= "string" then
					return { status = "badreason", human = "invalid message", message = data.message }
				end
				for client in util.safe_pairs(server.clients_) do
					client:send_server(data.message)
				end
				return { status = "ok" }
			end,
		},
	},
}
