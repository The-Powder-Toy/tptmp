local logger_m = {}

function logger_m:__call(format, ...)
	local things = { ... }
	io.stderr:write(self.prefix_)
	local last = 1
	local counter = 0
	for before, after in format:gmatch("()%$()") do
		io.stderr:write(format:sub(last, before - 1))
		counter = counter + 1
		io.stderr:write(tostring(things[counter]))
		last = after
	end
	io.stderr:write(format:sub(last))
	io.stderr:write("\n")
end

local function derive(logger, prefix)
	return setmetatable({ prefix_ = logger.prefix_ .. prefix }, logger_m)
end

local log = setmetatable({ prefix_ = "" }, logger_m)

local ftl = derive(log, "[ftl] ")
local err = derive(log, "[err] ")
local wrn = derive(log, "[wrn] ")
local inf = derive(log, "[inf] ")
local dbg = derive(log, "[dbg] ")

local function dump(...)
	local max = 1
	local buf = {}
	for key, value in pairs({ ... }) do
		if max < key then
			max = key
		end
		buf[key] = tostring(value)
	end
	for i = 1, max do
		buf[i] = buf[i] or "nil"
	end
	dbg("$", table.concat(buf, "\t"))
end

local function here(msg)
	for line in debug.traceback(tostring(msg), 2):gmatch("[^\n]+") do
		err(line)
	end
end

return {
	log = log,
	derive = derive,
	ftl = ftl,
	err = err,
	wrn = wrn,
	inf = inf,
	dbg = dbg,
	dump = dump,
	here = here,
}
