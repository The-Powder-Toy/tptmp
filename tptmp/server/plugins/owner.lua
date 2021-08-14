local config = require("tptmp.server.config")
local util   = require("tptmp.server.util")

local server_owner_i = {}
local room_owner_i = {}

-- * Includes the temporary owner.
function server_owner_i:room_owned_by_client(room_name, client)
	if not client:guest() then
		return self:room_owned_by_uid(room_name, client:uid())
	end
	local room = self:rooms()[room_name]
	if room then
		return room.temp_owner_ == client
	end
	return false
end

-- * Doesn't include the temporary owner.
function server_owner_i:room_owned_by_uid(room_name, uid)
	local room_info = self:dconf():root().rooms[room_name]
	return room_info and util.array_find(room_info.owners, uid)
end

function room_owner_i:owned_by_uid_(src)
	return self:server():room_owned_by_uid(self:name(), src)
end

-- * Doesn't include the temporary owner.
function server_owner_i:room_owner_count_(room_name)
	local room_info = self:dconf():root().rooms[room_name]
	return room_info and #room_info.owners or 0
end

function room_owner_i:owned_by_client(client)
	return self:server():room_owned_by_client(self:name(), client)
end

function room_owner_i:owner_count_()
	return self:server():room_owner_count_(self:name())
end

function room_owner_i:set_temp_owner_(client)
	if self.temp_owner_ then
		self.temp_owner_:send_server("\al* You are no longer the owner of this temporary room")
	end
	self.temp_owner_ = client
	self:server():rconlog({
		event = "room_temp_owner_change",
		room_name = self:name(),
		client_name = client and client:name(),
	})
	if self.temp_owner_ then
		self.temp_owner_:send_server("\aj* You are now the owner of this temporary room, use /register to make it permanent")
	end
end

function server_owner_i:room_is_reserved(room_name)
	local room_info = self:dconf():root().rooms[room_name]
	return room_info and room_info.reserved
end

function room_owner_i:is_reserved()
	return self:server():room_is_reserved(self:name())
end

function server_owner_i:room_is_temporary(room_name)
	return not self:dconf():root().rooms[room_name]
end

function room_owner_i:is_temporary()
	return self:server():room_is_temporary(self:name())
end

function server_owner_i:room_insert_owner_(room_name, uid)
	local dconf = self:dconf()
	local rooms = dconf:root().rooms
	local room_info = rooms[room_name]
	local idx
	if room_info then
		if room_info.reserved then
			return nil, "ereserv", "room is reserved"
		end
		idx = util.array_find(room_info.owners, uid)
	end
	if idx then
		return nil, "eexist", "already an owner"
	end
	if self:room_owner_count_(room_name) >= config.max_owners_per_room then
		return nil, "eownerlimit", "room reached owner limit"
	end
	if #self:uid_rooms_owned_(uid) >= config.max_rooms_per_owner then
		return nil, "eroomlimit", "user reached room limit"
	end
	if not room_info then
		room_info = {
			owners = {},
		}
		rooms[room_name] = room_info
	end
	table.insert(room_info.owners, uid)
	room_info.owners[0] = #room_info.owners
	dconf:commit()
	self:phost():call_hook("room_insert_owner", self, room_name, uid)
	return true
end

function room_owner_i:insert_owner_(uid)
	return self:server():room_insert_owner_(self:name(), uid)
end

function server_owner_i:room_remove_owner_(room_name, uid)
	local dconf = self:dconf()
	local rooms = dconf:root().rooms
	local room_info = rooms[room_name]
	local idx = room_info and util.array_find(room_info.owners, uid)
	if not idx then
		return nil, "enoent", "not currently an owner"
	end
	table.remove(room_info.owners, idx)
	room_info.owners[0] = #room_info.owners
	if #room_info.owners == 0 then
		rooms[room_name] = nil
	end
	dconf:commit()
	return true
end

function room_owner_i:remove_owner_(uid)
	return self:server():room_remove_owner_(self:name(), uid)
end

function server_owner_i:uid_rooms_owned_(src)
	local rooms = {}
	for name, room in pairs(self:dconf():root().rooms) do
		for _, uid in pairs(room.owners) do
			if uid == src then
				table.insert(rooms, name)
			end
		end
	end
	return rooms
end

return {
	commands = {
		register = {
			macro = function(client, message, words, offsets)
				return { "owner", "insert", client:nick() }
			end,
			help = "/register, no arguments: registers and claims ownership of the room",
		},
		owner = {
			func = function(client, message, words, offsets)
				if not words[3] then
					return false
				end
				local room = client:room()
				local server = client:server()
				local other_uid, other_nick = server:offline_user_by_nick(words[3])
				local other = server:client_by_nick(words[3])
				if words[2] == "check" then
					local owns = false
					local exists = false
					if other_uid then
						exists = true
						owns = room:owned_by_uid_(other_uid)
					elseif other then
						exists = true
						owns = room.temp_owner_ == other
					end
					if owns then
						client:send_server(("\an* \au%s\an currently owns this room"):format(other_nick))
					elseif exists then
						client:send_server(("\an* \au%s\an does not currently own this room"):format(other_nick))
					else
						client:send_server(("\ae* No user named \au%s"):format(words[3]))
					end
					return true
				end
				if not room:is_temporary() and not room:owned_by_client(client) then
					client:send_server("\ae* You are not an owner of this room")
					return true
				end
				if words[2] == "insert" then
					if not other_uid then
						client:send_server(("\ae* No user named \au%s"):format(words[3]))
					elseif other ~= client and room:is_temporary() then
						client:send_server("\ae* This is a temporary room, use /register to make it permanent")
					elseif not other or other:room() ~= room then
						client:send_server(("\ae* \au%s\ae is not present in this room"):format(other_nick))
					else
						local room_was_temporary = room:is_temporary()
						local ok, err = room:insert_owner_(other_uid)
						if ok then
							if room_was_temporary then
								room:log("registered")
								server:rconlog({
									event = "room_register",
									room_name = room:name(),
								})
							end
							room:log("$ shared room ownership with $", client:nick(), other_nick)
							server:rconlog({
								event = "room_owner_insert",
								client_name = client:name(),
								room_name = room:name(),
								other_nick = other_nick,
							})
							if client == other then
								room:set_temp_owner_(nil)
								client:send_server("\an* Room successfully registered")
							else
								client:send_server("\an* Room ownership successfully shared")
								other:send_server("\aj* You now have shared ownership of this room")
							end
						elseif err == "eexist" then
							client:send_server(("\ae* \au%s\ae already owns this room"):format(other_nick))
						elseif err == "ereserv" then
							client:send_server("\ae* This room is reserved")
						elseif err == "eownerlimit" then
							client:send_server("\ae* The room has too many owners, have one of them use /owner remove to disown it")
						elseif err == "eroomlimit" then
							client:send_server(("\ae* \au%s\ae owns too many rooms, have them use /owner remove to disown one"):format(other_nick))
						end
					end
					return true
				elseif words[2] == "remove" then
					if not other_uid then
						client:send_server(("\ae* No user named \au%s"):format(words[3]))
					elseif room:is_temporary() then
						client:send_server("\ae* This is a temporary room, use /register to make it permanent")
					else
						local ok, err = room:remove_owner_(other_uid)
						if ok then
							room:log("$ stripped $ of room ownership", client:nick(), other_nick)
							server:rconlog({
								event = "room_owner_remove",
								client_name = client:name(),
								room_name = room:name(),
								other_nick = other_nick,
							})
							if room:is_temporary() then
								room:log("unregistered")
								server:rconlog({
									event = "room_unregister",
									room_name = room:name(),
								})
								client:send_server("\an* Room successfully unregistered")
								room:set_temp_owner_(client)
							else
								client:send_server("\an* Room ownership successfully stripped")
								if other and other:room() == room then
									other:send_server("\al* You no longer have shared ownership of this room")
								end
							end
						elseif err == "enoent" then
							client:send_server(("\ae* \au%s\ae does not currently own this room"):format(other_nick))
						end
					end
					return true
				elseif words[2] == "temp" then
					if not room:is_temporary() then
						client:send_server("\ae* This is not a temporary room, use /owner remove to disown it")
					elseif not other or other:room() ~= room then
						client:send_server(("\ae* \au%s\ae is not present in this room"):format(other_nick))
					else
						room:set_temp_owner_(other)
					end
					return true
				end
				return false
			end,
			help = "/owner insert\\check\\remove\\temp <user>: shares ownership of the room with a user, checks if a user is an owner, strips a user of their ownership, or transfers temporary ownership",
		},
	},
	hooks = {
		plugin_load = {
			func = function(mtidx_augment)
				assert(config.auth)
				mtidx_augment("room", room_owner_i)
				mtidx_augment("server", server_owner_i)
			end,
		},
		server_init = {
			func = function(server)
				local dconf = server:dconf()
				if not dconf:root().rooms then
					local rooms = {}
					local reserve = {
						null = {
							-- motd = "Welcome to TPTMPv2!",
							motd = "Welcome to TPTMPv2! This test server is run by LBPHacker, report bugs and suggestions to him. If you got v2 from the script manager and want to go back to v1, disable v2 in the script manager.", -- * TODO[fin]: remove
						},
						guest = {
							motd = "Welcome to TPTMPv2! You have landed in the guest lobby as you do not seem to be logged in.",
						},
						kicked = {
						},
					}
					for name, info in pairs(reserve) do
						rooms[name] = {
							reserved = true,
							owners = {},
						}
					end
					dconf:root().rooms = rooms
					for name, info in pairs(reserve) do
						server:phost():call_hook("room_reserve", server, name, info)
					end
				end
				dconf:commit()
			end,
		},
		room_join = {
			func = function(room, client)
				if room:is_temporary() and not room.temp_owner_ then
					room:set_temp_owner_(client)
				end
			end,
		},
		room_leave = {
			func = function(room, client)
				if room:is_temporary() and room.temp_owner_ == client then
					room:set_temp_owner_(nil)
					for other in room:clients() do
						if other ~= client then
							room:set_temp_owner_(other)
							break
						end
					end
				end
			end,
		},
		room_info = {
			func = function(room, client)
				if room:is_reserved() then
					client:send_server("\an* Status: reserved")
				elseif room:is_temporary() then
					client:send_server("\an* Status: temporary")
					client:send_server(("\an* Owner: \au%s"):format(room.temp_owner_:nick()))
				else
					local server = client:server()
					local room_info = server:dconf():root().rooms[room:name()]
					if room.is_private and room:is_private() then
						client:send_server("\an* Status: permanent, private")
					else
						client:send_server("\an* Status: permanent")
					end
					local owners = {}
					for i = 1, #room_info.owners do
						local _, nick = server:offline_user_by_uid(room_info.owners[i])
						table.insert(owners, nick)
					end
					table.sort(owners)
					client:send_server(("\an* %s: \au%s"):format(#owners == 1 and "Owner" or "Owners", table.concat(owners, "\an, \au")))
				end
			end,
		},
		self_info = {
			func = function(client)
				if client:room():is_temporary() and client:room():owned_by_client(client) then
					client:send_server("\an* Room temporarily owned: \ar" .. client:room():name())
				end
				local rooms = client:server():uid_rooms_owned_(client:uid())
				if #rooms > 0 then
					table.sort(rooms)
					client:send_server(("\an* %s: \ar%s"):format(#rooms == 1 and "Room owned" or "Rooms owned", table.concat(rooms, "\an, \ar")))
				end
			end,
		},
	},
	console = {
		owner = {
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
					local ok, err, human = server:room_insert_owner_(data.room_name, uid)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "remove" then
					local ok, err, human = server:room_remove_owner_(data.room_name, uid)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "check" then
					return { status = "ok", owns = server:room_owned_by_uid(data.room_name, uid) or false }
				end
				return { status = "badaction", human = "unrecognized action" }
			end,
		},
	},
}
