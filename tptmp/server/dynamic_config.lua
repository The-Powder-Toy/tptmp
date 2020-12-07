local config   = require("tptmp.server.config")
local log      = require("tptmp.server.log")
local lunajson = require("lunajson")

local dynamic_config_i = {}
local dynamic_config_m = { __index = dynamic_config_i }

local function load_json(path)
	local handle, err = io.open(path, "r")
	if not handle then
		return nil, err
	end
	local ok, json = pcall(lunajson.decode, handle:read("*a"), nil, nil, true)
	handle:close()
	if not ok then
		return nil, json
	end
	return json
end

local function save_json(path, json)
	local ok, data = pcall(lunajson.encode, json)
	if not ok then
		return nil, data
	end
	local handle, err = io.open(path, "w")
	if not handle then
		return nil, err
	end
	local ok, err = handle:write(data)
	handle:close()
	if not ok then
		return nil, err
	end
	return true
end

function dynamic_config_i:hold()
	self.hold_ = self.hold_ + 1
end

function dynamic_config_i:unhold()
	self.hold_ = self.hold_ - 1
	if self.hold_ == 0 then
		if self.commit_at_unhold_ then
			self.commit_at_unhold_ = nil
			self:commit()
		end
	end
end

function dynamic_config_i:commit()
	if self.hold_ ~= 0 then
		self.commit_at_unhold_ = true
		return
	end
	if not self.main_missing_ then
		assert(os.rename(config.dynamic_config_main, config.dynamic_config_xchg))
	end
	assert(save_json(config.dynamic_config_main, self.root_))
	if not self.main_missing_ then
		assert(os.remove(config.dynamic_config_xchg))
	end
	self.main_missing_ = nil
end

function dynamic_config_i:init_()
	local root, err = load_json(config.dynamic_config_xchg)
	if root then
		assert(os.remove(config.dynamic_config_xchg))
		self.log_inf_("recovered exchange configuration $", config.dynamic_config_xchg)
	else
		root, err = load_json(config.dynamic_config_main)
		if root then
			self.log_inf_("loaded main configuration $", config.dynamic_config_main)
		else
			self.log_wrn_("failed to load main configuration $: $", config.dynamic_config_main, err)
			self.main_missing_ = true
			root = {}
		end
	end
	self.root_ = root
	self:commit()
end

function dynamic_config_i:root()
	return self.root_
end

local function new(params)
	local dconf = setmetatable({
		log_wrn_ = log.derive(log.wrn, "[" .. params.name .. "] "),
		log_inf_ = log.derive(log.inf, "[" .. params.name .. "] "),
		hold_ = 0,
	}, dynamic_config_m)
	dconf:init_()
	return dconf
end

return {
	new = new,
}
