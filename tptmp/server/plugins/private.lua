local config = require("tptmp.server.config")
local util   = require("tptmp.server.util")

local server_private_i = {}
local room_private_i = {}

function server_private_i:room_is_private(room_name)
	local dconf = self:dconf()
	local room_info = dconf:root().rooms[room_name]
	return room_info and room_info.private
end

function room_private_i:is_private()
	return self:server():room_is_private(self:name())
end

function server_private_i:room_set_private(room_name)
	local dconf = self:dconf()
	local room_info = dconf:root().rooms[room_name]
	if not room_info then
		return nil, "enoent", "no such room"
	end
	if room_info.private then
		return nil, "eprivate", "already private"
	end
	room_info.private = true
	dconf:commit()
	return true
end

function room_private_i:set_private()
	return self:server():room_set_private(self:name())
end

function server_private_i:room_clear_private(room_name)
	local dconf = self:dconf()
	local room_info = dconf:root().rooms[room_name]
	if not room_info then
		return nil, "enoent", "no such room"
	end
	if not room_info.private then
		return nil, "enotprivate", "not currently private"
	end
	room_info.private = nil
	dconf:commit()
	return true
end

function room_private_i:clear_private()
	return self:server():room_clear_private(self:name())
end

function server_private_i:room_invite_count(room_name)
	local dconf = self:dconf()
	local room_info = dconf:root().rooms[room_name]
	return room_info and room_info.invites and #room_info.invites or 0
end

function room_private_i:invite_count()
	return self:server():room_invite_count(self:name())
end

function server_private_i:room_insert_invite_(room_name, uid)
	local dconf = self:dconf()
	local room_info = dconf:root().rooms[room_name]
	if not room_info then
		return nil, "einval", "no such room"
	end
	local idx = room_info.invites and util.array_find(room_info.invites, uid)
	if idx then
		return nil, "eexist", "already invited"
	end
	if self:room_invite_count() >= config.max_invites_per_room then
		return nil, "einvitelimit", "room reached invite limit"
	end
	room_info.invites = room_info.invites or {}
	table.insert(room_info.invites, uid)
	room_info.invites[0] = #room_info.invites
	dconf:commit()
	return true
end

function room_private_i:insert_invite_(uid)
	return self:server():room_insert_invite_(self:name(), uid)
end

function server_private_i:room_remove_invite_(room_name, uid)
	local dconf = self:dconf()
	local room_info = dconf:root().rooms[room_name]
	if not room_info then
		return nil, "einval", "no such room"
	end
	local idx = room_info.invites and util.array_find(room_info.invites, uid)
	if not idx then
		return nil, "enoent", "not currently invited"
	end
	table.remove(room_info.invites, idx)
	room_info.invites[0] = #room_info.invites
	if #room_info.invites == 0 then
		room_info.invites = nil
	end
	dconf:commit()
	return true
end

function room_private_i:remove_invite_(uid)
	return self:server():room_remove_invite_(self:name(), uid)
end

function server_private_i:room_uid_invited(room_name, uid)
	local dconf = self:dconf()
	local room_info = dconf:root().rooms[room_name]
	return room_info and room_info.invites and util.array_find(room_info.invites, uid)
end

function room_private_i:uid_invited(uid)
	return self:server():room_uid_invited(self:name(), uid)
end

function room_private_i:client_invited(client)
	if client:guest() then
		return self.invites_clients_[client]
	end
	return self:uid_invited(client:uid())
end

function server_private_i:uid_invited_to_(uid)
	local dconf = self:dconf()
	local rooms = {}
	for name, info in pairs(dconf:root().rooms) do
		local idx = info.invites and util.array_find(info.invites, uid)
		if idx then
			table.insert(rooms, name)
		end
	end
	return rooms
end

return {
	commands = {
		invite = {
			func = function(client, message, words, offsets)
				if not words[3] then
					return false
				end
				local room = client:room()
				local server = client:server()
				local other_uid, other_nick = server:offline_user_by_nick(words[3])
				local other = server:client_by_nick(words[3])
				if words[2] == "check" then
					local invited = false
					local exists = false
					if other_uid then
						exists = true
						invited = room:uid_invited(other_uid)
					elseif other then
						exists = true
						invited = room:client_invited(client)
					end
					if invited then
						client:send_server(("\an* \au%s\an is currently invited"):format(other_nick))
					elseif exists then
						client:send_server(("\an* \au%s\an is not currently invited"):format(other_nick))
					else
						client:send_server(("\ae* No user named \au%s"):format(words[3]))
					end
					return true
				end
				if room:is_private() and not room:owned_by_client(client) then
					client:send_server("\ae* You are not an owner of this room")
					return true
				end
				local temporary_invite = room:is_temporary() or (other and other:guest())
				if words[2] == "insert" then
					local to_invite
					if temporary_invite then
						if not other then
							client:send_server(("\ae* \au%s\ae not online"):format(other_nick))
						else
							room.invites_clients_[other] = true
							to_invite = other
							client:send_server(("\an* \au%s\an is now invited"):format(other_nick))
						end
					elseif not other_uid then
						client:send_server(("\ae* No user named \au%s"):format(words[3]))
					else
						local ok, err = room:insert_invite_(other_uid)
						if ok then
							room:log("$ invited $", client:nick(), other_nick)
							server:rconlog({
								event = "invite_insert",
								client_name = client:name(),
								room_name = room:name(),
								other_nick = other_nick,
							})
							client:send_server(("\an* \au%s\an is now invited"):format(other_nick))
						elseif err == "eexist" then
							client:send_server(("\ae* \au%s\ae is already invited"):format(other_nick))
						elseif err == "einvitelimit" then
							client:send_server(("\ae* The room has too many users invited, use /invite remove to remove one"):format(other_nick))
						end
					end
					if to_invite and to_invite:room() ~= room then
						to_invite.accept_target_ = room:name()
						to_invite:send_server(("\aj* You have been invited to \ar%s\aj, use /accept to accept by joining"):format(room:name()))
					end
					return true
				elseif words[2] == "remove" then
					if temporary_invite then
						if room.invites_clients_[other] then
							client:send_server(("\ae* \au%s\ae is not currently invited"):format(other_nick))
						else
							room.invites_clients_[other] = nil
							client:send_server(("\an* \au%s\an is no longer invited"):format(other_nick))
						end
					elseif not other_uid then
						client:send_server(("\ae* No user named \au%s"):format(words[3]))
					else
						local ok, err = room:remove_invite_(other_uid)
						if ok then
							room:log("$ uninvited $", client:nick(), other_nick)
							server:rconlog({
								event = "invite_remove",
								client_name = client:name(),
								room_name = room:name(),
								other_nick = other_nick,
							})
							if room:is_private() then
								client:send_server(("\an* \au%s\an is no longer invited"):format(other_nick))
							else
								client:send_server(("\an* \au%s\an is no longer invited, but can still join as the room is not private"):format(other_nick))
							end
						elseif err == "enoent" then
							client:send_server(("\ae* \au%s\ae is not currently invited"):format(other_nick))
						end
					end
					return true
				end
				return false
			end,
			help = "/invite insert\\check\\remove <user>: invites a user to the room, letting them join even if it is private, checks whether a user is invited, or removes an existing invite",
		},
		accept = {
			func = function(client, message, words, offsets)
				if client.accept_target_ then
					local ok, err = client:server():join_room(client, client.accept_target_)
					if not ok then
						client:send_server("\ae* Cannot join room: " .. err)
					end
					client.accept_target_ = nil
				else
					client:send_server("\ae* Nothing to accept")
				end
				return true
			end,
			help = "/accept, no arguments: accepts an invite to a room by joining it",
		},
		private = {
			func = function(client, message, words, offsets)
				if not words[2] then
					return false
				end
				local room = client:room()
				local server = client:server()
				if words[2] == "check" then
					if room:is_private() then
						client:send_server("\an* Room is currently private")
					else
						client:send_server("\an* Room is not currently private")
					end
					return true
				end
				if room:is_temporary() then
					client:send_server("\ae* Temporary rooms cannot be made private")
					return true
				end
				if not room:owned_by_client(client) then
					client:send_server("\ae* You are not an owner of this room")
					return true
				end
				if words[2] == "set" then
					local ok, err = room:set_private()
					if ok then
						client:send_server("\an* Private status set")
						room:log("$ set private status", client:nick())
						server:rconlog({
							event = "private_set",
							client_name = client:name(),
							room_name = room:name(),
						})
					elseif err == "eprivate" then
						client:send_server("\ae* Room is already private")
					end
					return true
				elseif words[2] == "clear" then
					local ok, err = room:clear_private()
					if ok then
						client:send_server("\an* Private status cleared")
						room:log("$ cleared private status", client:nick())
						server:rconlog({
							event = "private_clear",
							client_name = client:name(),
							room_name = room:name(),
						})
					elseif err == "enotprivate" then
						client:send_server("\ae* Room is not currently private")
					end
					return true
				end
				return false
			end,
			help = "/private set\\check\\clear: changes or queries the private status of the room",
		},
	},
	hooks = {
		plugin_load = {
			func = function(mtidx_augment)
				mtidx_augment("room", room_private_i)
				mtidx_augment("server", server_private_i)
			end,
		},
		room_create = {
			func = function(room)
				room.invites_clients_ = {}
			end,
		},
		room_info = {
			func = function(room, client)
				local invites = {}
				local server = client:server()
				local room_info = server:dconf():root().rooms[room:name()]
				if room_info and room_info.invites then
					for i = 1, #room_info.invites do
						local _, nick = server:offline_user_by_uid(room_info.invites[i])
						table.insert(invites, nick)
					end
				end
				for other in pairs(room.invites_clients_) do
					table.insert(invites, other:nick())
				end
				if #invites > 0 then
					table.sort(invites)
					client:send_server(("\an* Invites: \au%s"):format(table.concat(invites, "\an, \au")))
				end
			end,
			after = { "owner" },
		},
		client_cleanup = {
			func = function(client)
				for _, room in pairs(client:server():rooms()) do
					room.invites_clients_[client] = nil
				end
			end,
		},
		self_info = {
			func = function(client)
				local rooms = {}
				for _, room in pairs(client:server():rooms()) do
					if room.invites_clients_[client] then
						rooms[room:name()] = true
					end
				end
				if not client:guest() then
					for _, name in pairs(client:server():uid_invited_to_(client:uid())) do
						rooms[name] = true
					end
				end
				if next(rooms) then
					local arr = {}
					for name in pairs(rooms) do
						table.insert(arr, name)
					end
					table.sort(arr)
					client:send_server(("\an* Invited to: \ar%s"):format(table.concat(arr, "\an, \ar")))
				end
			end,
		},
	},
	checks = {
		can_join_room = {
			func = function(room, client)
				if room:is_private() and not room:client_invited(client) then
					return false, "private room, ask for an invite", {
						reason = "private",
					}
				end
				return true
			end,
		},
	},
	console = {
		invite = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.room_name) ~= "string" then
					return { status = "badroom", human = "invalid room" }
				end
				local uid = server:offline_user_by_nick(data.nick)
				if not uid then
					return { status = "nouser", human = "no such user" }
				end
				if data.action == "insert" then
					local ok, err, human = server:room_insert_invite_(data.room_name, uid)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "remove" then
					local ok, err, human = server:room_remove_invite_(data.room_name, uid)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "check" then
					return { status = "ok", banned = server:room_uid_invited(data.room_name, uid) or false }
				end
				return { status = "badaction", human = "unrecognized action" }
			end,
		},
		private = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.room_name) ~= "string" then
					return { status = "badroom", human = "invalid room" }
				end
				if data.action == "set" then
					local ok, err, human = server:room_set_private(data.room_name)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "clear" then
					local ok, err, human = server:room_clear_private(data.room_name)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "check" then
					return { status = "ok", private = server:is_private(data.room_name) or false }
				end
				return { status = "badaction", human = "unrecognized action" }
			end,
		},
	},
}
