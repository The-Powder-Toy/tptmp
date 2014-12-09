function commandHooks.online(client, msg, msgsplit)
	client.socket:send("\22There are "..countTable(clients).." clients in "..countTable(rooms).." rooms\0"..string.char(127)..string.char(255)..string.char(255))
	return true
end

function commandHooks.msg(client, msg, msgsplit)
	local to = msgsplit[1]
	local message = msg:sub(#msgsplit[1]+2)
	local sent = false
	for k, otherclient in pairs(clients) do
		if otherclient.nick == to then
			otherclient.socket:send("\22"..client.nick.." whispers: "..message.."\0"..string.char(127)..string.char(255)..string.char(255))
			client.socket:send("\22message sent\0"..string.char(127)..string.char(255)..string.char(255))
			sent = true
		end
	end
	if not sent then
		client.socket:send("\22User not online\0"..string.char(127)..string.char(255)..string.char(255))
	end
	return true
end