local cqueues = require("cqueues")
local log     = require("tptmp.server.log")

local CQUEUES_WRAP_RETHROW = {}

local function cqueues_poll(...)
	local ret = { cqueues.poll(...) }
	if #ret > 0 then
		assert(ret[1], ret[2])
	end
	local ret_assoc = {}
	for _, value in pairs(ret) do
		ret_assoc[value] = true
	end
	return ret_assoc
end

local function cqueues_wrap(queue, func)
	queue:wrap(function()
		if not xpcall(func, function(err)
			log.here(err)
		end) then
			error(CQUEUES_WRAP_RETHROW)
		end
	end)
end

local function version_less(lhs, rhs)
	for i = 1, math.max(#lhs, #rhs) do
		local left = lhs[i] or 0
		local right = rhs[i] or 0
		if left < right then
			return true
		end
		if left > right then
			return false
		end
	end
	return false
end

local function version_equal(lhs, rhs)
	for i = 1, math.max(#lhs, #rhs) do
		local left = lhs[i] or 0
		local right = rhs[i] or 0
		if left ~= right then
			return false
		end
	end
	return true
end

local function safe_pairs(tbl)
	local clone = {}
	for key, value in pairs(tbl) do
		clone[key] = value
	end
	return next, clone
end

local function argpack(...)
	local pack = { [ "#" ] = select("#", ...) }
	for i = 1, pack["#"] do
		pack[i] = select(i, ...)
	end
	return pack
end

local function argunpack(pack, first)
	return table.unpack(pack, first or 1, pack["#"])
end

local function array_find(tbl, thing)
	for i = 1, #tbl do
		if tbl[i] == thing then
			return i
		end
	end
end

local function info_merge(tbl, thing)
	for key, value in pairs(thing) do
		tbl[key] = value
	end
	return tbl
end

return {
	cqueues_poll = cqueues_poll,
	cqueues_wrap = cqueues_wrap,
	CQUEUES_WRAP_RETHROW = CQUEUES_WRAP_RETHROW,
	version_less = version_less,
	version_equal = version_equal,
	safe_pairs = safe_pairs,
	argpack = argpack,
	argunpack = argunpack,
	array_find = array_find,
	info_merge = info_merge,
}
