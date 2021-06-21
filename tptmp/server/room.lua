local log    = require("tptmp.server.log")
local util   = require("tptmp.server.util")
local config = require("tptmp.server.config")

local room_i = {}
local room_m = { __index = room_i }

function room_i:broadcast_ciw(source, chunk)
	for client in self:clients() do
		if client ~= source and self:server():phost():call_check_all("can_interact_with", source, client) then
			client:send_room_chunk(chunk)
		end
	end
	self:cleanup_dead_ids_()
end

function room_i:broadcast(source, chunk)
	for client in self:clients() do
		if client ~= source then
			client:send_room_chunk(chunk)
		end
	end
	self:cleanup_dead_ids_()
end

function room_i:broadcast_server(message)
	for client in self:clients() do
		client:send_server(message)
	end
	self:cleanup_dead_ids_()
end

function room_i:client_by_id(id)
	local client = self.id_to_client_[id]
	if type(client) == "table" then
		return client
	end
end

function room_i:can_join_(client)
	if self.name_ == "null" and client:guest() then
		return nil, "guests cannot join the main lobby", {
			reason = "guest_in_main_lobby",
		}
	end
	local ok, err, rconinfo = self.server_:phost():call_check_all("can_join_room", self, client)
	if not ok then
		return nil, err, rconinfo
	end
	return true
end

function room_i:join(client)
	if client:room() == self then
		return nil, "already in room", {
			reason = "already_in_room",
		}
	end
	if not self.free_ then
		return nil, "room is full", {
			reason = "room_is_full",
		}
	end
	local ok, err, rconinfo = self:can_join_(client)
	if not ok then
		return nil, err, rconinfo
	end
	if client:room() then
		client:room():leave(client)
	end
	local id = self.free_
	self.free_ = self.id_to_client_[id]
	self.id_to_client_[id] = client
	self.client_to_id_[client] = { id = id, dead = false }
	client:move_to_room(self, string.char(id))
	self.clients_ = self.clients_ + 1
	self.log_inf_("$ joined", client:nick())
	local sync_source
	local others = {}
	for other_client, other_id in self:clients() do
		if other_client ~= client then
			sync_source = other_client
			table.insert(others, {
				id = other_id,
				nick = other_client:nick(),
			})
		end
	end
	client:send_room(id, self.name_, others)
	for other_client in self:clients() do
		if other_client ~= client then
			other_client:send_join(id, client:nick())
		end
	end
	self:cleanup_dead_ids_()
	if sync_source then
		sync_source:send_sync_request(client)
	end
	self.server_:phost():call_hook("room_join", self, client)
	return true
end

function room_i:clients()
	return function(tbl, key)
		while true do
			local nkey, nvalue = next(tbl, key)
			if not nkey then
				break
			end
			if not nvalue.dead then
				return nkey, nvalue.id
			end
			key = nkey
		end
	end, self.client_to_id_
end

function room_i:cleanup_dead_ids_()
	if next(self.dead_ids_) then
		for id, client in pairs(self.dead_ids_) do
			self.id_to_client_[id] = self.free_
			self.free_ = id
			self.client_to_id_[client] = nil
		end
		self.dead_ids_ = {}
	end
end

function room_i:name()
	return self.name_
end

function room_i:cleanup()
	if self.clients_ == 0 then
		self.log_inf_("room removed")
		self.server_:cleanup_room(self.name_)
	end
end

function room_i:leave(client)
	if client:room() ~= self then
		return
	end
	self.server_:phost():call_hook("room_leave", self, client)
	local id = self.client_to_id_[client].id
	self.client_to_id_[client].dead = true
	self.dead_ids_[id] = client
	client:move_to_room(nil, nil)
	self.clients_ = self.clients_ - 1
	self.log_inf_("$ left", client:nick())
	for other_client in self:clients() do
		other_client:send_leave(id)
	end
	self:cleanup_dead_ids_()
	self:cleanup()
end

function room_i:server()
	return self.server_
end

function room_i:log(...)
	self.log_inf_(...)
end

local function new(params)
	local max_clients = math.min(config.max_clients_per_room, 255)
	local log_inf = log.derive(log.inf, "[room-" .. params.name .. "] ")
	local id_to_client = { [ max_clients ] = false }
	for i = 1, max_clients - 1 do
		id_to_client[i] = i + 1
	end
	log_inf("room created")
	local rm = setmetatable({
		server_ = params.server,
		name_ = params.name,
		dead_ids_ = {},
		client_to_id_ = {},
		id_to_client_ = id_to_client,
		free_ = 1,
		clients_ = 0,
		log_inf_ = log_inf,
	}, room_m)
	rm.server_:phost():call_hook("room_create", rm)
	return rm
end

return {
	new = new,
	room_i = room_i,
}
