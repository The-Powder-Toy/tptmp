motd = {}

function serverHooks.motd(client, cmd, msg)
	if cmd==1 and client.room and motd and motd[client.room] then
		client.socket:send("\22[MOTD] "..motd[client.room].."\0"..string.char(127)..string.char(255)..string.char(255))
	end
end