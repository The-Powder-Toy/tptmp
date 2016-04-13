badwords = {"fuck", "fag", "rapes", "nigger", "assh", "bitch"}

addSecondaryHook(function(client, id, prot)
	local msg = prot.msg()
	for i,v in ipairs(badwords) do
		if msg:lower():find(v) then
			kick(id , "the server", "word in badwords list")
			return true
		end
	end
end,"User_Chat")