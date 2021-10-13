local util = require("tptmp.server.util")

local plugin_host_i = {}
local plugin_host_m = { __index = plugin_host_i }

function plugin_host_i:call_check_any(name, ...)
	local first_err
	local funcs = self.checks_[name]
	if funcs then
		for i = 1, #funcs do
			local ok, err = funcs[i](...)
			if ok then
				return true
			end
			first_err = first_err or err
		end
	end
	return nil, first_err or "(no checks performed)"
end

function plugin_host_i:call_check_all(name, ...)
	local funcs = self.checks_[name]
	if funcs then
		for i = 1, #funcs do
			local pack = util.argpack(funcs[i](...))
			if not pack[1] then
				return nil, util.argunpack(pack, 2)
			end
		end
	end
	return true
end

function plugin_host_i:call_hook(name, ...)
	local funcs = self.hooks_[name]
	if funcs then
		for i = 1, #funcs do
			funcs[i](...)
		end
	end
end

function plugin_host_i:commands()
	return self.commands_
end

function plugin_host_i:console()
	return self.console_
end

local function new(params)
	local phost = setmetatable({
		plugins_ = params.plugins,
	}, plugin_host_m)
	local hooks_by_name = {}
	local commands = {}
	local console = {}
	for plugin_name, plugin in pairs(params.plugins) do
		for command_name, command in pairs(plugin.commands or {}) do
			assert(not commands[command_name], "command already exists")
			commands[command_name] = command
		end
		for handler_name, handler in pairs(plugin.console or {}) do
			assert(not console[handler_name], "console handler already exists")
			console[handler_name] = handler
		end
		for hook_name, hook in pairs(plugin.hooks or {}) do
			hooks_by_name[hook_name] = hooks_by_name[hook_name] or {}
			hooks_by_name[hook_name][plugin_name] = {
				prev = {},
				func = hook.func,
			}
		end
	end
	phost.commands_ = commands
	phost.console_ = console
	for plugin_name, plugin in pairs(params.plugins) do
		for hook_name, hook in pairs(plugin.hooks or {}) do
			for _, after in pairs(hook.after or {}) do
				hooks_by_name[hook_name][plugin_name].prev[after] = true
			end
			for _, before in pairs(hook.before or {}) do
				hooks_by_name[hook_name][hook_name].prev[before] = true
			end
		end
	end
	local hooks = {}
	for name, hook_class in pairs(hooks_by_name) do
		local sorted = {}
		while next(hook_class) do
			local removed = {}
			for plugin_name, hook in pairs(hook_class) do
				if not next(hook.prev) then
					table.insert(sorted, hook.func)
					removed[plugin_name] = true
				end
			end
			for _, hook in pairs(hook_class) do
				for plugin_name in pairs(removed) do
					hook.prev[plugin_name] = nil
				end
			end
			for plugin_name in pairs(removed) do
				hook_class[plugin_name] = nil
			end
			assert(next(removed), "cyclic dependency")
		end
		hooks[name] = sorted
	end
	phost.hooks_ = hooks
	local checks = {}
	for _, plugin in pairs(params.plugins) do
		for check_name, check in pairs(plugin.checks or {}) do
			checks[check_name] = checks[check_name] or {}
			table.insert(checks[check_name], check.func)
		end
	end
	phost.checks_ = checks
	phost:call_hook("plugin_load", params.mtidx)
	return phost
end

return {
	new = new,
}
