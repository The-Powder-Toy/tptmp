local cqueues     = require("cqueues")
local log         = require("tptmp.server.log")
local common_util = require("tptmp.common.util")

local CQUEUES_WRAP_RETHROW = {}

local function pack(...)
	return select("#", ...), { ... }
end

local function cqueues_poll(...)
	local nret, ret = pack(cqueues.poll(...))
	if nret >= 2 and not ret[1] then
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

local coro_names = setmetatable({}, { __mode = "k" })

local function named_traceback(reason)
	return reason .. " for [" .. (coro_names[coroutine.running()] or "???") .. "]: " .. debug.traceback()
end

local function cqueues_wrap(queue, func, name)
	name = name or ("coroutine created at:\n" .. debug.traceback())
	queue:wrap(function()
		coro_names[coroutine.running()] = name
		if periodic_traceback_instructions then
			debug.sethook(function()
				print(named_traceback("periodic traceback"))
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

local function format_difftime(t2, t1, overshoot)
	local diff = os.difftime(t2, t1)
	if overshoot then
		diff = math.ceil(diff)
	else
		diff = math.floor(diff)
	end
	local units = {
		{ one =   "a year", more =   "%i years", seconds = 31556736 },
		{ one =   "a week", more =   "%i weeks", seconds =   604800 },
		{ one =    "a day", more =    "%i days", seconds =    86400 },
		{ one =  "an hour", more =   "%i hours", seconds =     3600 },
		{ one = "a minute", more = "%i minutes", seconds =       60 },
		{ one = "a second", more = "%i seconds", seconds =        1 },
	}
	local unit, count
	for i = 1, #units do
		local count_frac = diff / units[i].seconds
		local use_unit = diff > units[i].seconds
		if overshoot and units[i + 1] then
			if diff + units[i + 1].seconds > units[i].seconds then
				use_unit = true
			end
		end
		if use_unit then
			if overshoot then
				count = math.ceil(count_frac)
			else
				count = math.floor(count_frac)
			end
			unit = units[i]
			break
		end
	end
	if unit then
		return count == 1 and unit.one or unit.more:format(count)
	end
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
	format_difftime = format_difftime,
	named_traceback = named_traceback,
}
