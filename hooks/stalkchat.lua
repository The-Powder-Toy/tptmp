local function writeStatFile()
	local f = io.open("C:/Inetpub/vhosts/starcatcher.us/httpdocs/Moo/Stats.txt",'w')
	f:write("There are ".. countTable(clients) .." clients in ".. countTable(rooms) .." rooms")
	f:close()
end

function serverHooks.stalkchat(client, cmd, msg)
	if crackbot then
		local output = ""
		local room = client.room or "NONE"
		local nick = client.nick or "NONE"
		if cmd == 19 then
			output = "\0308["..room.."]\03 <"..nick.."> "..msg
		elseif cmd == 20 then
			output = "\0308["..room.."]\03 * "..nick.." "..msg
		elseif cmd == 1 then
			if room == "null" then
				output = "\0311* "..nick.."["..client.host.."] has joined "..room
			else
				output = "\0311* "..nick.." has joined "..room
			end
			writeStatFile()
		elseif cmd == -1 then
			output = "\0305* "..nick.."["..client.host.."] has quit ("..msg..")"
			writeStatFile()
		end
		crackbot:send(output.."\n")
	end
end