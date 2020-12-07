local function get(_, default)
	return default
end

local function set()
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
