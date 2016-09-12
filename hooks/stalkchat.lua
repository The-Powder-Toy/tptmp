
addSecondaryHook(function(client, id, prot)
	if not crackbot then return end

	local room, output, nick = prot.chan(), "", client.nick or "UNKNOWN"
	if room == "null" then
		output = "N\x0311* "..nick.."["..client.host.."] has joined "..room
	else
		output = "N\x0311* "..nick.." has joined "..room
	end
	crackbot:send(output.."\n")
end, "Join_Chan", 2)

addSecondaryHook(function(client, id, prot)
	if not crackbot then return end
	
	local reason, nick = prot.reason(), client.nick or "UNKNOWN"
	crackbot:send("N\x0305* "..nick.."["..client.host.."] has quit ("..reason..")\n")
end, "Disconnect", 2)

addSecondaryHook(function(client, id, prot)
	if not crackbot then return end

	local msg, nick, room = prot.msg(), client.nick or "UNKNOWN", client.room
	crackbot:send("N\x0308["..room.."]\x03 <"..nick.."> "..msg.."\n")
end, "User_Chat", 2)

addSecondaryHook(function(client, id, prot)
	if not crackbot then return end

	local msg, nick, room = prot.msg(), client.nick or "UNKNOWN", client.room
	crackbot:send("N\x0308["..room.."]\x03 * "..nick.." "..msg.."\n")
end, "User_Me", 2)
