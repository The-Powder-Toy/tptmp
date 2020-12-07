local util = require("tptmp.server.util")

local client_block_i = {}

function client_block_i:rehash_blocked_by_()
	local dconf = self:server():dconf()
	local uids = not self:guest() and dconf:root().blocked_by[tostring(self:uid())]
	local lookup = {}
	if uids then
		for i = 1, #uids do
			lookup[uids[i]] = true
		end
	end
	self.blocked_by_ = lookup
end

return {
	commands = {
		block = {
			func = function(client, message, words, offsets)
				if not words[2] then
					return false
				end
				local unblocked_nick, blocked_nick
				local nick = words[2]
				local server = client:server()
				local other = server:client_by_nick(nick)
				if other and (other:guest() or client:guest()) then
					if other.temp_blocked_by_[client] then
						other.temp_blocked_by_[client] = nil
						unblocked_nick = other:nick()
					else
						other.temp_blocked_by_[client] = true
						blocked_nick = other:nick()
					end
				else
					local other_uid, other_nick = server:offline_user_by_nick(nick)
					if not other_uid then
						client:send_server("* No such user")
						return true
					end
					local dconf = server:dconf()
					local blocked_by = dconf:root().blocked_by
					local uids = blocked_by[tostring(other_uid)]
					local idx = uids and util.array_find(uids, client:uid())
					if idx then
						table.remove(uids, idx)
						uids[0] = #uids
						if #uids == 0 then
							blocked_by[tostring(other_uid)] = nil
						end
						dconf:commit()
						local other = server:client_by_uid(other_uid)
						if other then
							other:rehash_blocked_by_()
						end
						unblocked_nick = other_nick
					else
						if not uids then
							uids = {}
							blocked_by[tostring(other_uid)] = uids
						end
						table.insert(uids, client:uid())
						uids[0] = #uids
						dconf:commit()
						local other = server:client_by_uid(other_uid)
						if other then
							other:rehash_blocked_by_()
						end
						blocked_nick = other_nick
					end
				end
				if unblocked_nick then
					server.log_inf_("$ unblocked $", client:nick(), unblocked_nick)
					client:send_server(("* %s is no longer blocked"):format(unblocked_nick))
				end
				if blocked_nick then
					server.log_inf_("$ blocked $", client:nick(), blocked_nick)
					client:send_server(("* %s is now blocked"):format(blocked_nick))
				end
				return true
			end,
			help = "/block <user>: toggles whether a user is blocked; blocking prevents them from messaging you or interacting with you otherwise",
		},
	},
	hooks = {
		load = {
			func = function(mtidx_augment)
				mtidx_augment("client", client_block_i)
			end,
		},
		init = {
			func = function(server)
				local dconf = server:dconf()
				dconf:root().blocked_by = dconf:root().blocked_by or {}
				dconf:commit()
			end,
		},
		connect = {
			func = function(client)
				client.temp_blocked_by_ = setmetatable({}, { __mode = "k" })
				client:rehash_blocked_by_()
			end,
		},
	},
	checks = {
		can_interact_with = {
			func = function(src, dest)
				if type(dest) ~= "number" then
					if src.temp_blocked_by_[dest] then
						return false, "temporarily blocked"
					end
					if dest:guest() then
						return true
					end
					dest = dest:uid()
				end
				if src.blocked_by_[dest] then
					return false, "permanently blocked"
				end
				return true
			end,
		},
	},
}
