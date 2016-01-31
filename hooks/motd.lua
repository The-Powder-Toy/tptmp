motd = {}
--NOTE: client.room in this hook is previous room.
--Join hook, current misses the initial connect :(
addSecondaryHook(function(client, id, prot)
	local newRoom = prot.chan()
	if motd[newRoom] then
		serverMsg(client, "[MOTD] "..motd[newRoom])
	else
		serverMsg(client, "[MOTD] BREAKING NEWS! "..client.nick.." has joined the room.")
	end
end,"Join_Chan")

function commandHooks.motd(client, msg, msgsplit)
	if client.room and client.room ~= "null" and rooms[client.room] and clients[rooms[client.room][1]] and clients[rooms[client.room][1]].nick == client.nick then
		motd[client.room] = msg
		serverMsg(client, "MotD set")
	else
		serverMsg(client, "You can't set a MotD in here.")
	end
	return true
end