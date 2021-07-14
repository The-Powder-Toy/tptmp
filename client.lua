#!/usr/bin/env luajit

local DIST = ...
local MAIN_MODULE = "tptmp.client"
local ENV_DEFAULTS = {
	-- * Defaults for DIST mode.
	sim = { XRES = 0, YRES = 0, CELL = 4, PMAPBITS = 0, signs = {} },
	elem = {
		allocate = function() end,
		DEFAULT_PT_FIGH     = 0,
		DEFAULT_PT_LIGH     = 0,
		DEFAULT_PT_SPRK     = 0,
		DEFAULT_PT_STKM     = 0,
		DEFAULT_PT_STKM2    = 0,
		DEFAULT_PT_TESC     = 0,
		DEFAULT_UI_PROPERTY = 0,
		DEFAULT_UI_SAMPLE   = 0,
		DEFAULT_UI_SIGN     = 0,
		DEFAULT_UI_WIND     = 0,
		TPTMP_PT_UNKNOWN    = 0,
	},
	tpt = { version = { major = 96, minor = 0 } },
	http = {},
	socket = {},
}

if DIST then
	for key, value in pairs(ENV_DEFAULTS) do
		rawset(getfenv(1), key, value)
	end
end

local env = setmetatable({}, { __index = function(_, key)
	return rawget(_G, key) or error("__index on env: " .. tostring(key), 2)
end, __newindex = function(_, key)
	error("__newindex on env: " .. tostring(key), 2)
end})
setfenv(1, env)

math.randomseed(os.time())

local script_path = debug.getinfo(1).source
do
	assert(script_path:sub(1, 1) == "@", "something is fishy")
	script_path = script_path:sub(2)
	local slash_at
	for ix = #script_path, 1, -1 do
		if script_path:sub(ix, ix):find("[\\/]") then
			slash_at = ix
			break
		end
	end
	if slash_at then
		script_path = script_path:sub(1, slash_at - 1)
	else
		script_path = "."
	end
end

local chunks = {}
local loaded = {}
local function require(modname)
	if not loaded[modname] then
		local try = {
			modname:gsub("%.", "/") .. ".lua",
			modname:gsub("%.", "/") .. "/init.lua",
		}
		local mod
		for i = 1, #try do
			local relative = try[i]
			local handle = io.open(script_path .. "/" .. relative, "r")
			if handle then
				local content = handle:read("*a")
				handle:close()
				local func, err = loadstring(content, "=" .. relative)
				if not func then
					error(err, 0)
				end
				setfenv(func, env)
				local ok, err = pcall(func)
				if not ok then
					error(err, 0)
				end
				mod = err
				chunks[modname] = content
				break
			end
		end
		if not mod then
			error("module " .. modname .. " not found", 2)
		end
		loaded[modname] = mod
	end
	return loaded[modname]
end
rawset(env, "require", require)

local main_module = require("tptmp.client")
if DIST then
	local handle = assert(io.open(DIST, "w"))
	handle:write([[
local env__ = setmetatable({}, { __index = function(_, key)
	return rawget(_G, key) or error("__index on env: " .. tostring(key), 2)
end, __newindex = function(_, key)
	error("__newindex on env: " .. tostring(key), 2)
end})
setfenv(1, env__)

math.randomseed(os.time())

local require_preload__ = {}
local require_loaded__ = {}
local function require(modname)
	local mod = require_loaded__[modname]
	if not mod then
		mod = assert(assert(require_preload__[modname], "missing module " .. modname)())
		require_loaded__[modname] = mod
	end
	return mod
end
rawset(env__, "require", require)

]])
	local chunk_keys = {}
	for key in pairs(chunks) do
		table.insert(chunk_keys, key)
	end
	table.sort(chunk_keys)
	for i = 1, #chunk_keys do
		handle:write(([[
require_preload__["%s"] = function()

	%s
end

]]):format(chunk_keys[i], chunks[chunk_keys[i]]:gsub("\n", "\n\t")))
	end
	handle:write(([[
require("%s").run()
]]):format(MAIN_MODULE))
	handle:close()
else
	main_module.run()
end
