local util   = require("tptmp.server.util")
local config = require("tptmp.server.config")

local GUEST_WILDCARD = "guest#*"

local server_block_i = {}

function server_block_i:uid_blocks_(dest, src)
	local dconf = self:dconf()
	local block = dconf:root().block
	local uids = block[tostring(dest)]
	return uids and util.array_find(uids, src)
end

function server_block_i:uid_insert_block_(dest, src)
	local dconf = self:dconf()
	local block = dconf:root().block
	local uids = block[tostring(dest)]
	local idx = uids and util.array_find(uids, src)
	if idx then
		return nil, "eexist", "already blocked"
	end
	uids = uids or {}
	block[tostring(dest)] = uids
	table.insert(uids, src)
	uids[0] = #uids
	dconf:commit()
	return true
end

function server_block_i:uid_remove_block_(dest, src)
	local dconf = self:dconf()
	local block = dconf:root().block
	local uids = block[tostring(dest)]
	local idx = uids and util.array_find(uids, src)
	if not idx then
		return nil, "enoent", "not currently blocked"
	end
	table.remove(uids, idx)
	uids[0] = #uids
	if #uids == 0 then
		block[tostring(dest)] = nil
	end
	dconf:commit()
	return true
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
				local function format_other_nick()
					return other_nick == GUEST_WILDCARD and "Guests are" or ("\au%s\an is"):format(other_nick)
				end
				local other = server:client_by_nick(words[3])
				if client:guest() or (other and other:guest()) then
					if words[3]:lower() == GUEST_WILDCARD then
						other = GUEST_WILDCARD
						other_nick = GUEST_WILDCARD
					else
						if not other then
							client:send_server(("\ae* \au%s\ae is not online"):format(words[3]))
							return true
						end
						other_nick = other:nick()
					end
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
					if words[3]:lower() == GUEST_WILDCARD then
						other_uid = GUEST_WILDCARD
						other_nick = GUEST_WILDCARD
					else
						local other_user, oerr = server:offline_user_by_nick(words[3])
						if other_user then
							other_uid, other_nick = other_user.uid, other_user.nick
						elseif oerr == "backendfail" then
							client:send_server("\ae* Warning: authentication backend down, you may have to try again later")
						end
					end
					if not other_uid then
						client:send_server(("\ae* No user named \au%s"):format(words[3]))
						return true
					end
					function blockf()
						server:uid_insert_block_(client:uid(), other_uid)
					end
					function checkf()
						return server:uid_blocks_(client:uid(), other_uid)
					end
					function unblockf()
						server:uid_remove_block_(client:uid(), other_uid)
					end
				end
				if words[2] == "insert" then
					if not checkf() then
						blockf()
						client:send_server(("\an* %s now blocked"):format(format_other_nick()))
						server.log_inf_("$ blocked $", client:nick(), other_nick)
						server:rconlog({
							event = "block_insert",
							client_name = client:name(),
							other_nick = other_nick,
						})
					else
						client:send_server(("\ae* %s already blocked"):format(format_other_nick()))
					end
					return true
				elseif words[2] == "check" then
					if checkf() then
						client:send_server(("\an* %s currently blocked"):format(format_other_nick()))
					else
						client:send_server(("\an* %s not currently blocked"):format(format_other_nick()))
					end
					return true
				elseif words[2] == "remove" then
					if checkf() then
						unblockf()
						client:send_server(("\an* %s no longer blocked"):format(format_other_nick()))
						server.log_inf_("$ unblocked $", client:nick(), other_nick)
						server:rconlog({
							event = "block_remove",
							client_name = client:name(),
							other_nick = other_nick,
						})
					else
						client:send_server(("\ae* %s not currently blocked"):format(format_other_nick()))
					end
					return true
				end
				return false
			end,
			help = "/block insert\\check\\remove [user]: blocks a user, preventing them from messaging you or interacting with you otherwise, checks whether a user is blocked, or unblocks a user; Guest#* matches all guests",
		},
	},
	hooks = {
		plugin_load = {
			func = function(mtidx)
				util.table_augment(mtidx.server, server_block_i)
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
				if dest.blocks_clients_[src] then
					return false, "client temporarily blocked"
				end
				if dest.blocks_clients_[GUEST_WILDCARD] and src:guest() then
					return false, "guests temporarily blocked"
				end
				if not dest:guest() then
					if src:guest() then
						if src:server():uid_blocks_(dest:uid(), GUEST_WILDCARD) then
							return false, "guests permanently blocked"
						end
					else
						if src:server():uid_blocks_(dest:uid(), src:uid()) then
							return false, "user permanently blocked"
						end
					end
				end
				return true
			end,
		},
	},
	console = {
		block = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.src) ~= "string" then
					return { status = "badsource", human = "invalid src nick" }
				end
				if type(data.dest) ~= "string" then
					return { status = "badtarget", human = "invalid dest nick" }
				end
				local src = data.src:lower() == GUEST_WILDCARD and GUEST_WILDCARD
				if not src then
					local err, human
					src, err, human = server:offline_user_by_nick(data.src)
					if not src then
						if err == "backendfail" then
							return { status = "backendfail", human = "failed to query user: " .. human }
						end
						return { status = "nousersource", human = "no such src user" }
					end
				end
				local dest
				do
					local err, human
					dest, err, human = server:offline_user_by_nick(data.dest)
					if not dest then
						if err == "backendfail" then
							return { status = "backendfail", human = "failed to query user: " .. human }
						end
						return { status = "nousertarget", human = "no such dest user" }
					end
				end
				if data.action == "insert" then
					local ok, err, human = server:uid_insert_block_(dest.uid, src)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "remove" then
					local ok, err, human = server:uid_remove_block_(dest.uid, src)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "check" then
					return { status = "ok", blocked = server:uid_blocks_(dest.uid, src) and true or false }
				end
				return { status = "badaction", human = "unrecognized action" }
			end,
		},
	},
}
