local util   = require("tptmp.server.util")
local config = require("tptmp.server.config")

local server_block_i = {}

function server_block_i:uid_blocks_(dest, src)
	local dconf = self:dconf()
	local block = dconf:root().block
	local uids = block[tostring(dest)]
	return uids and util.array_find(uids, src)
end

function server_block_i:uid_add_block_(dest, src)
	local dconf = self:dconf()
	local block = dconf:root().block
	local uids = block[tostring(dest)]
	local idx = uids and util.array_find(uids, src)
	if not idx then
		uids = uids or {}
		block[tostring(dest)] = uids
		table.insert(uids, src)
		uids[0] = #uids
		dconf:commit()
	end
end

function server_block_i:uid_remove_block_(dest, src)
	local dconf = self:dconf()
	local block = dconf:root().block
	local uids = block[tostring(dest)]
	local idx = uids and util.array_find(uids, src)
	if idx then
		table.remove(uids, idx)
		uids[0] = #uids
		if #uids == 0 then
			block[tostring(dest)] = nil
		end
		dconf:commit()
	end
end

return {
	commands = {
		block = {
			func = function(client, message, words, offsets)
				if not words[3] then
					return false
				end
				local server = client:server()
				local blockf, checkf, unblockf, other_nick
				if client:guest() then
					local other = server:client_by_nick(words[3])
					if not other then
						client:send_server(("* %s is not online"):format(words[3]))
						return true
					end
					other_nick = other:nick()
					function blockf()
						client.blocks_clients_[other] = true
					end
					function checkf()
						return client.blocks_clients_[other]
					end
					function unblockf()
						client.blocks_clients_[other] = nil
					end
				else
					local other_uid
					other_uid, other_nick = server:offline_user_by_nick(words[3])
					if not other_uid then
						client:send_server(("* No user named %s"):format(words[3]))
						return true
					end
					function blockf()
						server:uid_add_block_(client:uid(), other_uid)
					end
					function checkf()
						return server:uid_blocks_(client:uid(), other_uid)
					end
					function unblockf()
						server:uid_remove_block_(client:uid(), other_uid)
					end
				end
				if words[2] == "add" then
					if not checkf() then
						blockf()
						client:send_server(("* %s is now blocked"):format(other_nick))
						server.log_inf_("$ blocked $", client:nick(), other_nick)
						server:rconlog({
							event = "block_add",
							client_name = client:name(),
							other_nick = other_nick,
						})
					else
						client:send_server(("* %s is already blocked"):format(other_nick))
					end
					return true
				elseif words[2] == "check" then
					if checkf() then
						client:send_server(("* %s is currently blocked"):format(other_nick))
					else
						client:send_server(("* %s is not currently blocked"):format(other_nick))
					end
					return true
				elseif words[2] == "remove" then
					if checkf() then
						unblockf()
						client:send_server(("* %s is no longer blocked"):format(other_nick))
						server.log_inf_("$ unblocked $", client:nick(), other_nick)
						server:rconlog({
							event = "block_add",
							client_name = client:name(),
							other_nick = other_nick,
						})
					else
						client:send_server(("* %s is not currently blocked"):format(other_nick))
					end
					return true
				end
				return false
			end,
			help = "/block add\\check\\remove [user]: blocks a user, preventing them from messaging you or interacting with you otherwise, checks whether a user is blocked, or unblocks a user",
		},
	},
	hooks = {
		plugin_load = {
			func = function(mtidx_augment)
				mtidx_augment("server", server_block_i)
			end,
		},
		server_init = {
			func = function(server)
				local dconf = server:dconf()
				dconf:root().block = dconf:root().block or {}
				dconf:commit()
			end,
		},
		client_register = {
			func = function(client)
				client.blocks_clients_ = {}
			end,
		},
		client_disconnect = {
			func = function(client)
				for _, other in pairs(client:server():clients()) do
					if other.blocks_clients_ then
						other.blocks_clients_[client] = nil
					end
				end
			end,
		},
	},
	checks = {
		can_interact_with = {
			func = function(src, dest)
				if type(dest) ~= "number" then
					if dest.blocks_clients_[src] then
						return false, "temporarily blocked"
					end
					if dest:guest() then
						return true
					end
					dest = dest:uid()
				end
				if src:guest() then
					return true
				end
				if src:server():uid_blocks_(dest, src:uid()) then
					return false, "permanently blocked"
				end
				return true
			end,
		},
	},
}
