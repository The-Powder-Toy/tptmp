local config = require("tptmp.server.config")
local util   = require("tptmp.server.util")

local room_private_i = {}

function room_private_i:is_private()
	local dconf = self:server():dconf()
	local room_info = dconf:root().rooms[self:name()]
	return room_info and room_info.private
end

function room_private_i:invite_count()
	local dconf = self:server():dconf()
	local room_info = dconf:root().rooms[self:name()]
	return room_info.invites and #room_info.invites or 0
end

function room_private_i:uid_insert_invite_(src)
	local dconf = self:server():dconf()
	local room_info = dconf:root().rooms[self:name()]
	local idx = room_info.invites and util.array_find(room_info.invites, other_uid)
	if not idx then
		room_info.invites = room_info.invites or {}
		table.insert(room_info.invites, src)
		room_info.invites[0] = #room_info.invites
		dconf:commit()
	end
end

function room_private_i:uid_remove_invite_(src)
	local dconf = self:server():dconf()
	local room_info = dconf:root().rooms[self:name()]
	local idx = room_info.invites and util.array_find(room_info.invites, other_uid)
	if idx then
		table.remove(room_info.invites, idx)
		room_info.invites[0] = #room_info.invites
		if #room_info.invites == 0 then
			room_info.invites = nil
		end
		dconf:commit()
	end
end

function room_private_i:uid_invited_(src)
	local dconf = self:server():dconf()
	local room_info = dconf:root().rooms[self:name()]
	local idx = room_info.invites and util.array_find(room_info.invites, other_uid)
	if idx then
		return true
	end
end

function room_private_i:is_invited(src)
	if type(src) ~= "number" then
		if self:is_owner(src) then
			return true
		end
		if src:guest() then
			return self.invites_clients_[src]
		end
		src = src:uid()
	end
	local dconf = self:server():dconf()
	local room_info = dconf:root().rooms[self:name()]
	return room_info and room_info.invites and util.array_find(room_info.invites, src)
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
				local invitef, uninvitef, other_nick, client_to_invite
				local other_uid, other_nick = server:offline_user_by_nick(words[3])
				local other = server:client_by_nick(words[3])
				if other then
					if not other_uid then
						other_nick = other:nick()
					end
					other_uid = other
				end
				if words[2] ~= "add" and words[2] ~= "check" and words[2] ~= "remove" then
					return false
				end
				if not other_uid then
					client:send_server(("* No user named %s"):format(words[3]))
					return
				end
				if words[2] == "check" then
					if self:is_invited(other_uid) then
						client:send_server(("* %s is currently invited"):format(other_nick))
					else
						client:send_server(("* %s is not currently invited"):format(other_nick))
					end
					return true
				end
				if room:is_private() and not room:is_owner(client) then
					client:send_server("* You are not an owner of this room")
					return true
				end
				if room:is_temporary() or (type(other_uid) ~= "number" and other_uid:guest()) then
					function invitef()
						if type(other_uid) == "number" then
							client:send_server(("* %s not online"):format(other_nick))
							return
						end
						room.invites_clients_[other_uid] = true
						client_to_invite = other_uid
						return true
					end
					function uninvitef()
						if room.invites_clients_[other_uid] then
							client:send_server(("* %s is not currently invited"):format(other_nick))
							return
						end
						room.invites_clients_[other_uid] = nil
						client:send_server(("* %s is no longer invited"):format(other_nick))
						return true
					end
				else
					function invitef()
						if room:is_invited(other_uid) then
							client:send_server(("* %s is already invited"):format(other_nick))
							return
						end
						local src = other_uid
						if type(src) ~= "number" then
							client_to_invite = src
							src = src:uid()
						end
						room:uid_insert_invite_(src)
						client:send_server(("* %s is now invited"):format(other_nick))
						return true
					end
					function uninvitef()
						if not room:is_invited(other_uid) then
							client:send_server(("* %s is not currently invited"):format(other_nick))
							return
						end
						local src = other_uid
						if type(src) ~= "number" then
							src = src:uid()
						end
						room:uid_remove_invite_(src)
						if room:is_private() then
							client:send_server(("* %s is no longer invited"):format(other_nick))
						else
							client:send_server(("* %s is no longer invited, but can still join as the room is not private"):format(other_nick))
						end
						return true
					end
				end
				if words[2] == "add" then
					if invitef() then
						room:log("$ invited $", client:nick(), other_nick)
						server:rconlog({
							event = "invite_add",
							client_name = client:name(),
							room_name = room:name(),
							other_nick = other_nick,
						})
					end
				elseif words[2] == "remove" then
					if uninvitef() then
						room:log("$ uninvited $", client:nick(), other_nick)
						server:rconlog({
							event = "invite_remove",
							client_name = client:name(),
							room_name = room:name(),
							other_nick = other_nick,
						})
					end
				end
				if client_to_invite then
					client_to_invite.accept_target_ = room:name()
					client_to_invite:send_server("* You have been invited to " .. room:name() .. ", use /accept to accept by joining")
				end
				return true
			end,
			help = "/invite add\\check\\remove <user>: invites a user to the room, letting them join even if it is private, checks whether a user is invited, or removes an existing invite",
		},
		accept = {
			func = function(client, message, words, offsets)
				if client.accept_target_ then
					local ok, err = client:server():join_room(client, client.accept_target_)
					if not ok then
						client:send_server("* Cannot join room: " .. err)
					end
					client.accept_target_ = nil
				else
					client:send_server("* Nothing to accept")
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
				if room:is_temporary() then
					client:send_server("* Temporary rooms cannot be made private")
					return true
				end
				if not room:is_owner(client) then
					client:send_server("* You are not an owner of this room")
					return true
				end
				local dconf = client:server():dconf()
				local room_info = dconf:root().rooms[room:name()]
				if words[2] == "set" then
					if room:is_private() then
						client:send_server("* Room is already private")
					else
						room_info.private = true
						dconf:commit()
						client:send_server("* Private status set")
						room:log("$ set private status", client:nick())
						server:rconlog({
							event = "private_set",
							client_name = client:name(),
							room_name = room:name(),
						})
					end
				elseif words[2] == "check" then
					if room:is_private() then
						client:send_server("* Room is currently private")
					else
						client:send_server("* Room is not currently private")
					end
				elseif words[2] == "clear" then
					if room:is_private() then
						room_info.private = nil
						dconf:commit()
						client:send_server("* Private status cleared")
						room:log("$ cleared private status", client:nick())
						server:rconlog({
							event = "private_clear",
							client_name = client:name(),
							room_name = room:name(),
						})
					else
						client:send_server("* Room is not currently private")
					end
				else
					return false
				end
				return true
			end,
			help = "/private set\\check\\clear: changes or queries the private status of the room",
		},
	},
	hooks = {
		plugin_load = {
			func = function(mtidx_augment)
				mtidx_augment("room", room_private_i)
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
					client:send_server(("* Invites: %s"):format(table.concat(invites, ", ")))
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
	},
	checks = {
		can_join_room = {
			func = function(room, client)
				if room:is_private() and not room:is_invited(client) then
					return false, "private room, ask for an invite", {
						reason = "private",
					}
				end
				return true
			end,
		},
	},
}
