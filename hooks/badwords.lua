badwords = {"fuck", "fvck", "fag", "rapes", "nigger", "assho", "bitch", "retard", "cunt", "discord"}

function serverHooks.badwords(client, cmd, msg)
	if cmd==19 or cmd==20 then
		for i,v in ipairs(badwords) do
			if msg:lower():find(v) then
				kick(client, "the server", "word in badwords list")
				return true
			end
		end
	end
end