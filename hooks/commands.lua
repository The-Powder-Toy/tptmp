blocklist = blocklist or {}

local helptext = {
["slist"] = "(slist): Prints a list of server side commands.",
["shelp"] = "(shelp [<command>]): Prints help for a command.",
["online"] = "(online): Prints how many players are online and how many rooms there are.",
["names"] = "(names): Prints which channel you are in and what players are in it.",
["msg"] = "(msg <user> <message>): Sends a private message to a user.",
["seen"] = "(seen <user>): Tells you the amount of time since a user was last online.",
["motd"] = "(motd <motd>): Sets the motd for a channel, if you were the first to join.",
["invite"] = "(invite <user>): Invites a user to a channel and sends a message asking them to join.",
["uninvite"] = "(uninvite <user>): Remove an invite.",
["block"] = "(block <user>): Stop seeing private messages from user.",
["unblock"] = "(unblock <user>): See private messages from user again.",
["private"] = "(private): Toggles a channel's private status. Use /invite to invite users."
}

function commandHooks.slist(client, msg, msgsplit)
	local list = {}
	for k,v in pairs(commandHooks) do
		if helptext[k] then
			table.insert(list, k)
		end
	end
	table.sort(list)
	serverMsg(client, "Server commands: "..table.concat(list, ", "))
	return true
end

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
	serverMsg(client, "There are "..countTable(clients).." clients in "..countTable(rooms).." rooms.")
	return true
end

function commandHooks.names(client, msg, msgsplit)
	local users = {}
	for k,v in pairs(rooms[client.room]) do
		table.insert(users, clients[v].nick)
	end
	table.sort(users)
	serverMsg(client, "Currently in room "..client.room..": "..table.concat(users, ", "))
	return true
end

function commandHooks.msg(client, msg, msgsplit)
	if #msgsplit == 0 then
		commandHooks.shelp(client, "msg", {"msg"})
		return true
	end
	local to = msgsplit[1]
	local message = msg:sub(#msgsplit[1]+2)
	local sent = false
	for k, otherclient in pairs(clients) do
		if otherclient.nick == to then
			if (blocklist[client.nick] or {})[to] or (blocklist[to] or {})[client.nick] then
				serverMsg(client, "You can't send messages to this player.")
				sent = true
			else
				serverMsg(otherclient, client.nick.." whispers: "..message)
				serverMsg(client, "Message sent.")
				sent = true
			end
		end
	end
	if not sent then
		serverMsg(client, "User not online.")
	end
	return true
end
commandHooks.whisper, commandHooks.w = commandHooks.msg, commandHooks.msg

function commandHooks.block(client, msg, msgsplit)
	if #msgsplit == 0 then
		commandHooks.shelp(client, "block", {"block"})
		return true
	end
	local block = msgsplit[1]
	if block == client.nick then
		serverMsg(client, "You can't block yourself")
		return true
	end

	blocklist[client.nick] = blocklist[client.nick] or {}
	blocklist[client.nick][block] = true
	serverMsg(client, "Now blocking private messages from "..block)

	return true
end

function commandHooks.unblock(client, msg, msgsplit)
	if #msgsplit == 0 then
		commandHooks.shelp(client, "unblock", {"unblock"})
		return true
	end
	local unblock = msgsplit[1]

	blocklist[client.nick] = blocklist[client.nick] or {}
	blocklist[client.nick][unblock] = nil
	serverMsg(client, "Now allowing private messages from "..unblock)

	return true
end

--To prevent abuse of names, and forgetting, lets reset blocks on quit, maybe change to a timer later, a few days?
function serverHooks.block(client, cmd, msg)
	if cmd == -2 then
		blocklist[client.nick] = {}
	end
end

local function timestr(t)
	local seconds, minutes, hours, days
	local str = {}
	days = math.floor(t/86400)
	hours = math.floor((t%86400)/3600)
	minutes = math.floor((t%3600)/60)
	seconds = t%60
	if days > 0 then
		table.insert(str, days.." day"..(days == 1 and "" or "s"))
	end
	if hours > 0 then
		table.insert(str, hours.." hour"..(hours == 1 and "" or "s"))
	end
	if minutes > 0 then
		table.insert(str, minutes.." minute"..(minutes == 1 and "" or "s"))
	end
	if seconds > 0 then
		table.insert(str, seconds.." second"..(seconds == 1 and "" or "s"))
	end
	if #str > 1 then
		str[#str] = "and "..str[#str]
	elseif #str == 0 then
		return "0 seconds"
	end
	return table.concat(str, ", ")
end

local lastseen = {}
function commandHooks.seen(client, msg, msgsplit)
	user = msgsplit[1]
	if not user then
		commandHooks.shelp(client, "seen", {"seen"})
		return true
	end
	for k,v in pairs(clients) do
		if v.nick == user then
			serverMsg(client, user.." is online right now!")
			return true
		end
	end
	if not lastseen[user] then
		serverMsg(client, "That user hasn't been online recently.")
		return true
	end
	serverMsg(client, user.." was last seen "..timestr(os.difftime(os.time(), lastseen[user])).." ago.")
	return true
end

function serverHooks.commands(client, cmd, msg)
	if cmd == -1 and client.room == "null" then
		lastseen[client.nick] = os.time()
	end
end