local function code_points(str)
	local cps = {}
	local cursor = 0
	while true do
		local old_cursor = cursor
		cursor = cursor + 1
		local head = str:byte(cursor)
		if not head then
			break
		end
		local size = 1
		if head >= 0x80 then
			if head < 0xC0 then
				return nil, cursor
			end
			size = 2
			if head >= 0xE0 then
				size = 3
			end
			if head >= 0xF0 then
				size = 4
			end
			if head >= 0xF8 then
				return nil, cursor
			end
			head = bit.band(head, bit.lshift(1, 7 - size) - 1)
			for ix = 2, size do
				local by = str:byte(cursor + ix - 1)
				if not by then
					return nil, cursor
				end
				if by < 0x80 or by >= 0xC0 then
					return nil, cursor + ix
				end
				head = bit.bor(bit.lshift(head, 6), bit.band(by, 0x3F))
			end
			cursor = cursor - 1 + size
		end
		local pos = old_cursor + 1
		if (head < 0x80 and size > 1)
		or (head < 0x800 and size > 2)
		or (head < 0x10000 and size > 3) then
			return nil, pos
		end
		table.insert(cps, { cp = head, pos = pos, size = size })
	end
	return cps
end

local function encode(code_point)
	if code_point < 0x80 then
		return string.char(code_point)
	elseif code_point < 0x800 then
		return string.char(
			bit.bor(0xC0,          bit.rshift(code_point,  6)       ),
			bit.bor(0x80, bit.band(           code_point     , 0x3F))
		)
	elseif code_point < 0x10000 then
		return string.char(
			bit.bor(0xE0,          bit.rshift(code_point, 12)       ),
			bit.bor(0x80, bit.band(bit.rshift(code_point,  6), 0x3F)),
			bit.bor(0x80, bit.band(           code_point     , 0x3F))
		)
	elseif code_point < 0x200000 then
		return string.char(
			bit.bor(0xF0,          bit.rshift(code_point, 18)       ),
			bit.bor(0x80, bit.band(bit.rshift(code_point, 12), 0x3F)),
			bit.bor(0x80, bit.band(bit.rshift(code_point,  6), 0x3F)),
			bit.bor(0x80, bit.band(           code_point     , 0x3F))
		)
	else
		error("invalid code point")
	end
end

local function encode_multiple(cp, ...)
	if not ... then
		return encode(cp)
	end
	local cps = { cp, ... }
	local collect = {}
	for i = 1, #cps do
		table.insert(collect, encode(cps[i]))
	end
	return table.concat(collect)
end

if tpt.version.jacob1s_mod then -- * TODO[imm]: this is not how it should be done
	function code_points(str)
		local cps = {}
		for pos in str:gmatch("().") do
			table.insert(cps, { cp = str:byte(pos), pos = pos, size = 1 })
		end
		return cps
	end

	function encode(cp)
		if cp >= 0xE000 then
			cp = cp - 0xDF80
		end
		return string.char(cp)
	end
end

return {
	code_points = code_points,
	encode = encode,
	encode_multiple = encode_multiple,
}
