local cqueues     = require("cqueues")
local log         = require("tptmp.server.log")
local common_util = require("tptmp.common.util")

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

local periodic_traceback_instructions = false

local function periodic_tracebacks(instructions)
	periodic_traceback_instructions = instructions
end

local function cqueues_wrap(queue, func, name)
	name = name or ("coroutine created at:\n" .. debug.traceback())
	queue:wrap(function()
		if periodic_traceback_instructions then
			debug.sethook(function()
				print("traceback of [" .. name .. "]: " .. debug.traceback())
			end, "", periodic_traceback_instructions)
		end
		if not xpcall(func, function(err)
			log.here(err)
		end) then
			error(CQUEUES_WRAP_RETHROW)
		end
	end)
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

local function table_augment(tbl, thing)
	for key, value in pairs(thing) do
		tbl[key] = value
	end
	return tbl
end

return {
	cqueues_poll = cqueues_poll,
	cqueues_wrap = cqueues_wrap,
	CQUEUES_WRAP_RETHROW = CQUEUES_WRAP_RETHROW,
	version_less = common_util.version_less,
	version_equal = common_util.version_equal,
	safe_pairs = safe_pairs,
	argpack = argpack,
	argunpack = argunpack,
	array_find = array_find,
	info_merge = table_augment,
	periodic_tracebacks = periodic_tracebacks,
	table_augment = table_augment,
}
