local room_motd_i = {}

function room_motd_i:motd_empty_notify_owner_(client)
	local room_info = self:server():dconf():root().rooms[self:name()]
	if not room_info.motd then
		client:send_server("\an* This room does not have a message of the day set, use /motd to set one")
	end
end

return {
	commands = {
		motd = {
			func = function(client, message, words, offsets)
				local room = client:room()
				if room:is_temporary() then
					client:send_server("\ae* Not possible to set the message of the day for a temporary room")
					return true
				end
				if not room:is_owner(client) then
					client:send_server("\ae* You are not an owner of this room")
					return true
				end
				local motd = offsets[2] and message:sub(offsets[2]) or nil
				local server = client:server()
				if motd then
					local ok, err = server:phost():call_check_all("content_ok", server, motd)
					if not ok then
						client:send_server("\ae* Cannot set MOTD: " .. err)
						return true
					end
					room:log("$ set motd: $", client:nick(), motd)
					server:rconlog({
						event = "motd_set",
						client_name = client:name(),
						room_name = room:name(),
						motd = motd,
					})
					client:send_server("\ae* MOTD set")
				else
					room:log("$ cleared motd", client:nick())
					server:rconlog({
						event = "motd_clear",
						client_name = client:name(),
						room_name = room:name(),
					})
					client:send_server("\ae* MOTD cleared")
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
		plugin_load = {
			func = function(mtidx_augment)
				mtidx_augment("room", room_motd_i)
			end,
		},
		room_join = {
			func = function(room, client)
				local room_info = room:server():dconf():root().rooms[room:name()]
				if room_info then
					if room_info.motd then
						client:send_server("\aj* MOTD: " .. room_info.motd)
					end
					if room:is_owner(client) then
						room:motd_empty_notify_owner_(client)
					end
				end
			end,
		},
		room_insert_owner = {
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
					client:send_server("\aj* MOTD: " .. room_info.motd)
				end
			end,
			after = { "private" },
		},
		room_reserve = {
			func = function(server, name, info)
				if info.motd then
					local room_info = server:dconf():root().rooms[name]
					room_info.motd = info.motd
				end
			end,
		},
	},
}
