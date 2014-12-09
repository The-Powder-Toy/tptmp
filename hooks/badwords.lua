badwords = {"fuck", "fag", "rape", "nigger", "\n", "\r", "\t"}

function serverHooks.badwords(client, cmd, msg)
	if cmd==19 or cmd==20 then
		for i,v in ipairs(badwords) do
			if msg:lower():find(v) then
				client.socket:close()
				return true
			end
		end
	end
end