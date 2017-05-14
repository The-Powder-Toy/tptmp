function serverHooks.stalkchat(client, cmd, msg)
	if not crackbot then return end
	local nick = client.nick or "UNKNOWN"
	if crackbot and client.room then
		local output = nil
		local room = client.room
		if cmd == 19 then
			output = "\00308["..room.."]\003 <"..nick.."> "..msg
		elseif cmd == 20 then
			output = "\00308["..room.."]\003 * "..nick.." "..msg
		elseif cmd == 1 then
			if room == "null" then
				output = "\00311* "..nick.."["..client.host.."] has joined "..room
			else
				output = "\00311* "..nick.." has joined "..room
			end
		elseif cmd == -1 then
			output = "\00305* "..nick.."["..client.host.."] has quit ("..msg..")"
		end
		if output then
			crackbot:send(output.."\n")
		end
	elseif cmd == -1 and not client.room and msg ~= "Banned user" then
		crackbot:send(("\00305* "..nick.."["..client.host.."] has quit ("..msg..")"):gsub("\n", "\\n"):gsub("\r", "\\r").."\n")
	end
end