local config = require("tptmp.server.config")
local util   = require("tptmp.server.util")
local jnet   = require("jnet")

local server_ban_i = {}

function server_ban_i:insert_peer_ban_(peer)
	if not self.peer_bans_:insert(peer) then
		return nil, "eexist", "already banned"
	end
	self:save_peer_bans_()
	return true
end

function server_ban_i:remove_peer_ban_(peer)
	if not self.peer_bans_:remove(peer) then
		return nil, "enoent", "not currently banned"
	end
	self:save_peer_bans_()
	return true
end

function server_ban_i:save_peer_bans_()
	local tbl = {}
	for peer in self.peer_bans_:nets() do
		table.insert(tbl, tostring(peer))
	end
	tbl[0] = #tbl
	self.dconf_:root().peer_bans = tbl
	self.dconf_:commit()
end

function server_ban_i:load_peer_bans_()
	local tbl = self.dconf_:root().peer_bans or {}
	self.peer_bans_ = jnet.set()
	for i = 1, #tbl do
		self.peer_bans_:insert(jnet(tbl[i]))
	end
	self:save_peer_bans_()
end

function server_ban_i:peer_banned_(peer)
	return self.peer_bans_:contains(peer)
end

function server_ban_i:insert_uid_ban_(uid)
	if self.uid_bans_[uid] then
		return nil, "eexist", "already banned"
	end
	self.uid_bans_[uid] = true
	self:save_uid_bans_()
	return true
end

function server_ban_i:remove_uid_ban_(uid)
	if not self.uid_bans_[uid] then
		return nil, "enoent", "not currently banned"
	end
	self.uid_bans_[uid] = nil
	self:save_uid_bans_()
	return true
end

function server_ban_i:save_uid_bans_()
	local tbl = {}
	for uid in pairs(self.uid_bans_) do
		table.insert(tbl, uid)
	end
	tbl[0] = #tbl
	self.dconf_:root().uid_bans = tbl
	self.dconf_:commit()
end

function server_ban_i:load_uid_bans_()
	local tbl = self.dconf_:root().uid_bans or {}
	self.uid_bans_ = {}
	for i = 1, #tbl do
		self.uid_bans_[tbl[i]] = true
	end
	self:save_uid_bans_()
end

function server_ban_i:uid_banned_(uid)
	return self.uid_bans_[uid]
end

return {
	console = {
		ban = {
			func = function(rcon, data)
				local server = rcon:server()
				if type(data.nick) ~= "string" then
					return { status = "badnick", human = "invalid nick" }
				end
				local user = server:offline_user_by_nick(data.nick)
				if not user then
					return { status = "nouser", human = "no such user" }
				end
				if data.action == "insert" then
					local ok, err, human = server:insert_uid_ban_(user.uid)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "remove" then
					local ok, err, human = server:remove_uid_ban_(user.uid)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "check" then
					return { status = "ok", banned = server:uid_banned_(user.uid) or false }
				end
				return { status = "badaction", human = "unrecognized action" }
			end,
		},
		ipban = {
			func = function(rcon, data)
				local server = rcon:server()
				local ok, peer = pcall(jnet, data.host)
				if not ok then
					return { status = "badhost", human = "invalid host: " .. peer, reason = peer }
				end
				if data.action == "insert" then
					local ok, err, human = server:insert_peer_ban_(peer)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "remove" then
					local ok, err, human = server:remove_peer_ban_(peer)
					if not ok then
						return { status = err, human = human }
					end
					return { status = "ok" }
				elseif data.action == "check" then
					local banned_subnet = server:peer_banned_(peer)
					return { status = "ok", banned = banned_subnet and tostring(banned_subnet) or false }
				end
				return { status = "badaction", human = "unrecognized action" }
			end,
		},
	},
	hooks = {
		plugin_load = {
			func = function(mtidx)
				util.table_augment(mtidx.server, server_ban_i)
			end,
		},
		server_init = {
			func = function(server)
				server:load_peer_bans_()
				server:load_uid_bans_()
			end,
		},
	},
	checks = {
		can_connect = {
			func = function(client)
				local banned_subnet = client:server():peer_banned_(client:peer())
				if banned_subnet then
					return false, "you are banned from this server", ("host %s is banned (subnet %s)"):format(client:peer(), tostring(banned_subnet)), {
						reason = "host_banned",
						subnet = tostring(banned_subnet),
					}
				end
				return true
			end,
		},
		can_join = {
			func = function(client)
				if client:guest() then
					if not config.guests_allowed then
						return false, "authentication failed and guests are not allowed on this server", nil, {
							reason = "guests_banned",
						}
					end
				else
					if client:server():uid_banned_(client:uid()) then
						return false, "you are banned from this server", ("%s, uid %i is banned"):format(client:nick(), client:uid()), {
							reason = "uid_banned",
						}
					end
				end
				return true
			end,
		},
	},
}
