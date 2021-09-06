local config = require("tptmp.client.config")

local data

local function load_data()
	if data then
		return
	end
	data = {}
	local handle = io.open(config.null_manager_path, "r")
	if not handle then
		return
	end
	for line in handle:read("*a"):gmatch("[^\r\n]+") do
		local key, value = line:match("^([^=]+)=(.*)$")
		if key then
			data[key] = value
		end
	end
	handle:close()
end

local function save_data()
	local handle = io.open(config.null_manager_path, "w")
	if not handle then
		return
	end
	local collect = {}
	for key, value in pairs(data) do
		table.insert(collect, tostring(key))
		table.insert(collect, "=")
		table.insert(collect, tostring(value))
		table.insert(collect, "\n")
	end
	handle:write(table.concat(collect))
	handle:close()
end

local function get(key, default)
	load_data()
	return data[key] or default
end

local function set(key, value)
	data[key] = value
	save_data()
end

local function print(msg)
	print(msg)
end

return {
	get = get,
	set = set,
	print = print,
	brand = "null",
}
