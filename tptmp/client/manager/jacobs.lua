local config = require("tptmp.client.config")

local MANAGER = rawget(_G, "MANAGER")

local function get(key, default)
	local value = MANAGER.getsetting(config.manager_namespace, key)
	return type(value) == "string" and value or default
end

local function set(key, value)
	MANAGER.savesetting(config.manager_namespace, key, value)
end

local function hidden()
	return MANAGER.hidden
end

local function print(msg)
	return MANAGER.print(msg)
end

return {
	hidden = hidden,
	get = get,
	set = set,
	print = print,
	brand = "jacobs",
	minimize_conflict = true,
	side_button_conflict = true,
}
