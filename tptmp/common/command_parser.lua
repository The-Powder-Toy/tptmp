local command_parser_i = {}
local command_parser_m = { __index = command_parser_i }

function command_parser_i:parse(ctx, message)
	local words = {}
	local offsets = {}
	for offset, word in message:gmatch("()(%S+)") do
		table.insert(offsets, offset)
		table.insert(words, word)
	end
	if not words[1] then
		self:list_(ctx)
		return
	end
	local initial_cmd = words[1]
	words[1] = words[1]:lower()
	while true do
		local cmd = self.commands_[self.aliases_[words[1]] or words[1]]
		if not cmd then
			if self.cmd_fallback_ then
				if self.cmd_fallback_(ctx, message) then
					return
				end
			end
			self.respond_(ctx, self.unknown_format_)
			return
		end
		if cmd.macro then
			words = cmd.macro(ctx, message, words, offsets)
			if not words then
				self:help_(ctx, initial_cmd)
				return
			end
			if #words == 0 then
				return
			end
			words[1] = words[1]:lower()
			offsets = {}
			local offset = 0
			for i = 1, #words do
				offsets[i] = offset + 1
				offset = offset + #words[i] + 1
			end
			message = table.concat(words, " ")
		else
			local ok = cmd.func(ctx, message, words, offsets)
			if not ok then
				self:help_(ctx, initial_cmd)
			end
			return
		end
	end
end

function command_parser_i:list_(ctx)
	self.respond_(ctx, self.list_format_:format(self.list_str_))
	if self.list_extra_ then
		self.list_extra_(ctx)
	end
	return true
end

function command_parser_i:help_(ctx, from)
	from = from or self.help_name_
	local initial_from = from
	from = from:lower()
	local to = self.aliases_[from]
	if to then
		self.respond_(ctx, self.alias_format_:format(from, to))
		from = to
	end
	local cmd = self.commands_[from]
	if cmd then
		self.respond_(ctx, self.help_format_:format(cmd.help))
		return true
	end
	if self.help_fallback_ then
		if self.help_fallback_(ctx, initial_from) then
			return true
		end
	end
	self.respond_(ctx, self.unknown_format_)
	return true
end

local function new(params)
	local cmd = setmetatable({
		respond_ = params.respond,
		help_fallback_ = params.help_fallback,
		list_extra_ = params.list_extra,
		help_format_ = params.help_format,
		alias_format_ = params.alias_format,
		list_format_ = params.list_format,
		unknown_format_ = params.unknown_format,
		cmd_fallback_ = params.cmd_fallback,
		commands_ = {},
		aliases_ = {},
	}, command_parser_m)
	local collect = {}
	for name, info in pairs(params.commands) do
		table.insert(collect, "/" .. name)
		name = name:lower()
		if info.role == "help" then
			cmd.help_name_ = name
			cmd.commands_[name] = {
				func = function(ctx, _, words)
					cmd:help_(ctx, words[2])
					return true
				end,
				help = info.help,
			}
		elseif info.role == "list" then
			cmd.commands_[name] = {
				func = function(ctx)
					cmd:list_(ctx)
					return true
				end,
				help = info.help,
			}
		elseif info.alias then
			cmd.aliases_[name] = info.alias
		elseif info.macro then
			cmd.commands_[name] = {
				macro = info.macro,
				help = info.help,
			}
		else
			cmd.commands_[name] = {
				func = info.func,
				help = info.help,
			}
		end
	end
	table.sort(collect)
	cmd.list_str_ = table.concat(collect, " ")
	return cmd
end

return {
	new = new,
}
