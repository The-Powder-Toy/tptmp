local util = require("tptmp.server.util")

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
				local server = client:server()
				local dconf = server:dconf()
				local room_info = dconf:root().rooms[room:name()]
				if words[2] == "get" or not words[2] then
					if room:is_temporary() then
						client:send_server("\an* Temporary rooms cannot have an MOTD set")
					elseif room_info and room_info.motd then
						client:send_server("\aj* MOTD: " .. room_info.motd)
					else
						client:send_server("\an* This room does not have an MOTD set")
					end
					return true
				end
				if words[2] ~= "set" and words[2] ~= "clear" then
					return false
				end
				if room:is_temporary() then
					client:send_server("\ae* Temporary rooms cannot have an MOTD set")
					return true
				end
				if not room:owned_by_client(client) then
					client:send_server("\ae* You are not an owner of this room")
					return true
				end
				local motd = offsets[3] and message:sub(offsets[3]) or nil
				if words[2] == "set" then
					if not motd then
						return false
					end
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
					client:send_server("\an* MOTD set")
				elseif words[2] == "clear" then
					room:log("$ cleared motd", client:nick())
					server:rconlog({
						event = "motd_clear",
						client_name = client:name(),
						room_name = room:name(),
					})
					client:send_server("\an* MOTD cleared")
				end
				room_info.motd = motd
				dconf:commit()
				return true
			end,
			help = "/motd get\\clear\\set <motd>: sets, gets or clears the message of the day for the room",
		},
	},
	hooks = {
		plugin_load = {
			func = function(mtidx)
				util.table_augment(mtidx.room, room_motd_i)
			end,
		},
		room_join = {
			func = function(room, client)
				local room_info = room:server():dconf():root().rooms[room:name()]
				if room_info then
					if room_info.motd then
						client:send_server("\aj* MOTD: " .. room_info.motd)
					end
					if room:owned_by_client(client) then
						room:motd_empty_notify_owner_(client)
					end
				end
			end,
		},
		room_insert_owner = {
			func = function(server, room_name, uid)
				local room = server:rooms()[room_name]
				local client = server:client_by_uid(uid)
				if room and client then
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
	console = {
		motd = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.room_name) ~= "string" then
					return { status = "badroom", human = "invalid room" }
				end
				local room_info = server:dconf():root().rooms[data.room_name]
				if not room_info then
					return { status = "enoent", human = "no such room" }
				end
				if data.action == "set" then
					if type(data.motd) ~= "string" and data.motd ~= nil then
						return { status = "badmotd", human = "invalid motd" }
					end
					room_info.motd = data.motd
					server:dconf():commit()
					return { status = "ok" }
				elseif data.action == "get" then
					return { status = "ok", motd = room_info.motd }
				end
				return { status = "badaction", human = "unrecognized action" }
			end,
		},
	},
}
