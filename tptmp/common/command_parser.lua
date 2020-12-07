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
	while true do
		words[1] = self.aliases_[words[1]] or words[1]
		local cmdstr = words[1] and words[1]:lower()
		local cmd = self.commands_[cmdstr]
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
	local to = self.aliases_[from]
	if to then
		self.respond_(ctx, self.alias_format_:format(from, to))
		from = to
	end
	local cmd = self.commands_[from]
	if cmd then
		self.respond_(ctx, cmd.help)
		return true
	end
	if self.help_fallback_ then
		if self.help_fallback_(ctx, from) then
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
		alias_format_ = params.alias_format,
		list_format_ = params.list_format,
		unknown_format_ = params.unknown_format,
		cmd_fallback_ = params.cmd_fallback,
		commands_ = {},
		aliases_ = {},
	}, command_parser_m)
	local collect = {}
	for name, info in pairs(params.commands) do
		local internal_info = {}
		table.insert(collect, "/" .. name)
		if info.role == "help" then
			cmd.help_name_ = name
			internal_info.func = function(ctx, _, words)
				cmd:help_(ctx, words[2])
				return true
			end
		elseif info.role == "list" then
			internal_info.func = function(ctx)
				cmd:list_(ctx)
				return true
			end
		elseif info.macro then
			internal_info.macro = info.macro
		else
			internal_info.func = info.func
		end
		internal_info.help = info.help
		if info.alias then
			table.insert(collect, "/" .. info.alias)
			cmd.aliases_[info.alias] = name
		end
		cmd.commands_[name] = internal_info
	end
	table.sort(collect)
	cmd.list_str_ = table.concat(collect, " ")
	return cmd
end

return {
	new = new,
}
