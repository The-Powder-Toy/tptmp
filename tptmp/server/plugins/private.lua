local config = require("tptmp.server.config")
local util   = require("tptmp.server.util")

local room_private_i = {}

function room_private_i:is_private()
	local room_info = self:server():dconf():root().rooms[self:name()]
	return room_info and room_info.private
end

function room_private_i:invite_count()
	local room_info = self:server():dconf():root().rooms[self:name()]
	return room_info and room_info.invites and #room_info.invites or 0
end

function room_private_i:is_invited(client)
	if self:is_owner(client) then
		return true
	end
	if not client:guest() then
		local room_info = self:server():dconf():root().rooms[self:name()]
		if room_info and room_info.invites then
			return util.array_find(room_info.invites, client:uid()) and true
		end
	end
end

return {
	commands = {
		invite = {
			func = function(client, message, words, offsets)
				if not words[2] then
					return false
				end
				local room = client:room()
				local server = client:server()
				local other = server:client_by_nick(words[2])
				-- * TODO[req]: invite guests temporarily (until they leave)
				local other_uid, other_nick = server:offline_user_by_nick(words[2])
				if not other_uid and not other then
					client:send_server("* No such user")
					return true
				end
				if room:is_private() then
					if room:is_owner(client) then
						local dconf = room:server():dconf()
						local room_info = dconf:root().rooms[room:name()]
						if room:invite_count() >= config.max_invites_per_room then
							client:send_server("* The room has too many invites, use /uninvite to remove one")
							return true
						end
						local idx = room_info.invites and util.array_find(room_info.invites, other_uid)
						if not idx then
							if not room_info.invites then
								room_info.invites = {}
							end
							table.insert(room_info.invites, other_uid)
							room_info.invites[0] = #room_info.invites
							dconf:commit()
						end
						client:send_server("* Invite successfully sent and recorded")
					else
						client:send_server("* You are not an owner of this room")
						return true
					end
				else
					client:send_server("* Invite successfully sent")
				end
				room:log("$ invited $", client:nick(), other_nick or other:nick())
				if other and not server:phost():call_check_all("can_interact_with", client, other) then
					other = nil
				end
				if other then
					other:send_server("* You have been invited to " .. room:name() .. ", use /accept to accept and join")
					other.accept_target_ = room:name()
				end
				return true
			end,
			help = "/invite <user>: invites a user to the room, letting them join even if it is private",
		},
		uninvite = {
			func = function(client, message, words, offsets)
				if not words[2] then
					return false
				end
				local nick = words[2]
				local room = client:room()
				local server = client:server()
				if room:is_temporary() then
					client:send_server("* Temporary rooms do not have invite lists")
					return true
				end
				if not room:is_owner(client) then
					client:send_server("* You are not an owner of this room")
					return true
				end
				local other_uid, other_nick = server:offline_user_by_nick(nick)
				if not other_uid then
					client:send_server("* No such user")
					return true
				end
				local dconf = room:server():dconf()
				local room_info = dconf:root().rooms[room:name()]
				local idx = util.array_find(room_info.invites, other_uid)
				if not idx then
					client:send_server(("* %s is not currently invited"):format(nick))
					return true
				end
				table.remove(room_info.invites, idx)
				room_info.invites[0] = #room_info.invites
				if #room_info.invites == 0 then
					room_info.invites = nil
				end
				dconf:commit()
				room:log("$ uninvited $, uid $", client:nick(), other_nick, other_uid)
				client:send_server("* Invite successfully removed")
				return true
			end,
			help = "/uninvite <user>: makes an invited user unable to join a private room",
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
			help = "/accept, no arguments: accept an invite to a room and join",
		},
		private = {
			func = function(client, message, words, offsets)
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
				if room:is_private() then
					client:send_server("* Room is already private")
				else
					room_info.private = true
					room:log("$ set private status", client:nick())
					client:send_server("* Private status set")
					dconf:commit()
				end
				return true
			end,
			help = "/private, no arguments: sets the private status of the room",
		},
		unprivate = {
			func = function(client, message, words, offsets)
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
				if room:is_private() then
					room_info.private = nil
					room:log("$ cleared private status", client:nick())
					client:send_server("* Private status cleared")
					dconf:commit()
				else
					client:send_server("* Room is not currently private")
				end
				return true
			end,
			help = "/unprivate, no arguments: clears the private status of the room",
		},
	},
	hooks = {
		load = {
			func = function(mtidx_augment)
				mtidx_augment("room", room_private_i)
			end,
		},
		room_info = {
			func = function(room, client)
				local server = client:server()
				local room_info = server:dconf():root().rooms[room:name()]
				if room_info and room_info.invites then
					local invites = {}
					for i = 1, #room_info.invites do
						local _, nick = server:offline_user_by_uid(room_info.invites[i])
						table.insert(invites, nick)
					end
					table.sort(invites)
					client:send_server(("* Invites: %s"):format(table.concat(invites, ", ")))
				end
			end,
			after = { "owner" },
		},
	},
	checks = {
		can_join_room = {
			func = function(room, client)
				if room:is_private() and not room:is_invited(client) then
					return false, "private room, ask for an invite"
				end
				return true
			end,
		},
	},
}
