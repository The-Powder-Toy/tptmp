function commandHooks.slist(client, msg, msgsplit)
	local list = {}
	for k,v in pairs(commandHooks) do
		table.insert(list, k)
	end
	serverMsg(client, "Server commands: "..table.concat(list, ", "))
	return true
end

local helptext = {
["slist"] = "(slist): Prints a list of server side commands.",
["shelp"] = "(shelp [<command>]): Prints help for a command.",
["online"] = "(online): Prints how many players are online and how many rooms there are.",
["msg"] = "(msg <user> <message>): Sends a private message to a user.",
["motd"] = "(motd <motd>): Sets the motd for a channel, if you were the first to join.",
["invite"] = "(invite <user>): Invites a user to a channel and sends a message asking them to join.",
["private"] = "(private): Toggles a channel's private status. Use /invite to invite users."
}
function commandHooks.shelp(client, msg, msgsplit)
	local command = msgsplit[1] or "shelp"
	if helptext[command] then
		serverMsg(client, helptext[command])
	else
		serverMsg(client, "No help available for that command.")
	end
	return true
end

function commandHooks.online(client, msg, msgsplit)
	--if client.nick ~= "feynman" then
		serverMsg(client, "There are "..countTable(clients).." clients in "..countTable(rooms).." rooms.")
	--else
	--	serverMsg(client, "There are over 9000 clients in over 9000 rooms")
	--end
	return true
end

function commandHooks.msg(client, msg, msgsplit)
	local to = msgsplit[1]
	local message = msg:sub(#msgsplit[1]+2)
	local sent = false
	for k, otherclient in pairs(clients) do
		if otherclient.nick == to then
			serverMsg(otherclient, client.nick.." whispers: "..message)
			serverMsg(client, "Message sent.")
			sent = true
		end
	end
	if not sent then
		serverMsg(client, "User not online.")
	end
	return true
end