local config = require("tptmp.server.config")
local util   = require("tptmp.server.util")

local room_owner_i = {}

function room_owner_i:is_owner(client)
	if not client:guest() then
		local room_info = self:server():dconf():root().rooms[self:name()]
		if room_info then
			return util.array_find(room_info.owners, client:uid()) and true
		end
	end
	return self.temp_owner_ == client
end

function room_owner_i:owner_count()
	local room_info = self:server():dconf():root().rooms[self:name()]
	return room_info and #room_info.owners or 0
end

function room_owner_i:set_temp_owner_(client)
	if self.temp_owner_ then
		self.temp_owner_:send_server("* You are no longer the owner of this temporary room")
	end
	self.temp_owner_ = client
	if self.temp_owner_ then
		self.temp_owner_:send_server("* You are now the owner of this temporary room, use /register to make it permanent")
	end
end

function room_owner_i:is_reserved()
	local room_info = self:server():dconf():root().rooms[self:name()]
	return room_info and room_info.reserved
end

function room_owner_i:is_temporary()
	if self:is_reserved() then
		return false
	end
	local room_info = self:server():dconf():root().rooms[self:name()]
	return not room_info or #room_info.owners == 0
end

function room_owner_i:insert_owner_(client)
	local server = self:server()
	local dconf = server:dconf()
	local rooms = dconf:root().rooms
	local room_info = rooms[self:name()]
	if not room_info then
		room_info = {
			owners = {},
		}
		rooms[self:name()] = room_info
	end
	table.insert(room_info.owners, client:uid())
	room_info.owners[0] = #room_info.owners
	client.rooms_owned_ = client.rooms_owned_ + 1
	server:phost():call_hook("insert_room_owner", self, client)
	dconf:commit()
end

function room_owner_i:remove_owner_(client)
	local server = self:server()
	local dconf = server:dconf()
	local rooms = dconf:root().rooms
	local room_info = rooms[self:name()]
	server:phost():call_hook("remove_room_owner", self, client)
	table.remove(room_info.owners, util.array_find(room_info.owners, client:uid()))
	room_info.owners[0] = #room_info.owners
	client.rooms_owned_ = client.rooms_owned_ - 1
	if self:is_temporary() then
		server:phost():call_hook("unregister_room", self)
		rooms[self:name()] = nil
	end
	dconf:commit()
end

local client_owner_i = {}

function client_owner_i:rooms_owned()
	return self.rooms_owned_
end

return {
	commands = {
		register = {
			func = function(client, message, words, offsets)
				local room = client:room()
				if room:is_reserved() then
					client:send_server("* This room is reserved")
					return true
				end
				if not room:is_temporary() then
					client:send_server("* This room is already registered")
					return true
				end
				if client:guest() then
					client:send_server("* Guests cannot register rooms")
					return true
				end
				if room:owner_count() >= config.max_owners_per_room then
					client:send_server("* The room has too many owners, have one of them use /disown to disown it")
					return true
				end
				if client:rooms_owned() >= config.max_rooms_per_owner then
					client:send_server("* You own too many rooms, use /disown to disown one")
					return true
				end
				room:set_temp_owner_(nil)
				room:log("$ registered the room and gained room ownership", client:nick())
				client:send_server("* Room successfully registered")
				room:insert_owner_(client)
				return true
			end,
			help = "/register, no arguments: registers and claims ownership of the room",
		},
		share = {
			func = function(client, message, words, offsets)
				if not words[2] then
					return false
				end
				local nick = words[2]
				local room = client:room()
				local server = client:server()
				if room:is_temporary() then
					client:send_server("* Temporary rooms cannot be shared")
					return true
				end
				if not room:is_owner(client) then
					client:send_server("* You are not an owner of this room")
					return true
				end
				local other = server:client_by_nick(nick)
				if not (other and other:room() == room) then
					client:send_server("* User not present in this room")
					return true
				end
				if room:owner_count() >= config.max_owners_per_room then
					client:send_server("* The room has too many owners, have one of them use /disown to disown it")
					return true
				end
				if other:rooms_owned() >= config.max_rooms_per_owner then
					client:send_server(("* %s owns too many rooms, have them use /disown to disown one"):format(nick))
					return true
				end
				room:log("$ shared room ownership with $", client:nick(), other:nick())
				client:send_server("* Room successfully shared")
				other:send_server("* You now have shared ownership of this room")
				room:insert_owner_(other)
				return true
			end,
			help = "/share <user>: shares ownership of the room with a user",
		},
		disown = {
			func = function(client, message, words, offsets)
				local room = client:room()
				if room:is_temporary() then
					client:send_server("* Temporary rooms cannot be disowned")
					return true
				end
				if not room:is_owner(client) then
					client:send_server("* You are not an owner of this room")
					return true
				end
				room:remove_owner_(client)
				room:log("$ relinquished room ownership", client:nick())
				if room:is_temporary() then
					client:send_server("* Room unregistered")
					room:set_temp_owner_(client)
				else
					client:send_server("* You no longer have shared ownership of this room")
				end
				return true
			end,
			help = "/disown, no arguments: relinquishes ownership of the room",
		},
	},
	hooks = {
		load = {
			func = function(mtidx_augment)
				assert(config.auth)
				mtidx_augment("room", room_owner_i)
				mtidx_augment("client", client_owner_i)
			end,
		},
		init = {
			func = function(server)
				local dconf = server:dconf()
				if not dconf:root().rooms then
					local rooms = {}
					local function reserve(name)
						rooms[name] = {
							reserved = true,
							owners = {},
						}
					end
					reserve("null")
					reserve("guest")
					dconf:root().rooms = rooms
				end
				dconf:commit()
			end,
		},
		join_room = {
			func = function(room, client)
				if room:is_temporary() and not room.temp_owner_ then
					room:set_temp_owner_(client)
				end
			end,
		},
		leave_room = {
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
		join = {
			func = function(client)
				local count = 0
				if not client:guest() then
					for _, room in pairs(client:server():dconf():root().rooms) do
						for _, uid in pairs(room.owners) do
							if uid == client:uid() then
								count = count + 1
							end
						end
					end
				end
				client.rooms_owned_ = count
			end,
		},
		room_info = {
			func = function(room, client)
				if room:is_reserved() then
					client:send_server("* Status: reserved")
				elseif room:is_temporary() then
					client:send_server("* Status: temporary")
					client:send_server(("* Owner: %s"):format(room.temp_owner_:nick()))
				else
					local server = client:server()
					local room_info = server:dconf():root().rooms[room:name()]
					if room.is_private and room:is_private() then
						client:send_server("* Status: permanent, private")
					else
						client:send_server("* Status: permanent")
					end
					local owners = {}
					for i = 1, #room_info.owners do
						local _, nick = server:offline_user_by_uid(room_info.owners[i])
						table.insert(owners, nick)
					end
					table.sort(owners)
					client:send_server(("* %s: %s"):format(#owners == 1 and "Owner" or "Owners", table.concat(owners, ", ")))
				end
			end,
		},
	},
}
