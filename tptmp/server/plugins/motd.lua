local room_motd_i = {}

function room_motd_i:motd_empty_notify_owner_(client)
	local room_info = self:server():dconf():root().rooms[self:name()]
	if not room_info.motd then
		client:send_server("* This room does not have a message of the day set, use /motd to set one")
	end
end

return {
	commands = {
		motd = {
			func = function(client, message, words, offsets)
				local room = client:room()
				if room:is_temporary() then
					client:send_server("* Not possible to set the message of the day for a temporary room")
					return true
				end
				if not room:is_owner(client) then
					client:send_server("* You are not an owner of this room")
					return true
				end
				local motd = offsets[2] and message:sub(offsets[2]) or nil
				local server = client:server()
				if motd then
					local ok, err = server:phost():call_check_all("content_ok", server, motd)
					if not ok then
						client:send_server("* Cannot set MOTD: " .. err)
						return true
					end
					room:log("$ set motd: $", client:nick(), motd)
					client:send_server("* MOTD set")
				else
					room:log("$ cleared motd", client:nick())
					client:send_server("* MOTD cleared")
				end
				local dconf = server:dconf()
				local room_info = dconf:root().rooms[room:name()]
				room_info.motd = motd
				dconf:commit()
				return true
			end,
			help = "/motd [motd]: sets the message of the day for the room, or removes it if one is not provided",
		},
	},
	hooks = {
		load = {
			func = function(mtidx_augment)
				mtidx_augment("room", room_motd_i)
			end,
		},
		join_room = {
			func = function(room, client)
				local room_info = room:server():dconf():root().rooms[room:name()]
				if room_info then
					if room_info.motd then
						client:send_server("* MOTD: " .. room_info.motd)
					end
					if room:is_owner(client) then
						room:motd_empty_notify_owner_(client)
					end
				end
			end,
		},
		insert_room_owner = {
			func = function(room, uid)
				local client = room:server():client_by_uid(uid)
				if client then
					room:motd_empty_notify_owner_(client)
				end
			end,
		},
		room_info = {
			func = function(room, client)
				local room_info = client:server():dconf():root().rooms[room:name()]
				if room_info and room_info.motd then
					client:send_server(("* MOTD: %s"):format(room_info.motd))
				end
			end,
			after = { "private" },
		},
	},
}
