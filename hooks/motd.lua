motd = {}

function serverHooks.motd(client, cmd, msg)
	if cmd==1 and client.room then
		if motd and motd[client.room] then
			serverMsg(client, "[MOTD] "..motd[client.room])
		elseif client.nick and client.room == "null" then
			--serverMsg(client, "[MOTD] BREAKING NEWS! "..client.nick.." has joined the room.")
			serverMsg(client, "Welcome to TPTMP! Use /join to join a private channel")
			return
		end
	end
end

function commandHooks.motd(client, msg, msgsplit)
	if client.room and client.room ~= "null" and rooms[client.room] and clients[rooms[client.room][1]] and clients[rooms[client.room][1]].nick == client.nick then
		motd[client.room] = msg
		serverMsg(client, "MotD set")
	else
		serverMsg(client, "You can't set a MotD in here.")
	end
	return true
end