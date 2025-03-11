local config      = require("tptmp.client.config")
local common_util = require("tptmp.common.util")

local PMAPBITS = sim.PMAPBITS

local tpt_version = { tpt.version.major, tpt.version.minor }

local function array_concat(...)
	local tbl = {}
	local arrays = { ... }
	for i = 1, #arrays do
		for j = 1, #arrays[i] do
			table.insert(tbl, arrays[i][j])
		end
	end
	return tbl
end

local function xid_registry(supported)
	table.sort(supported, function(lhs, rhs)
		-- * Doesn't matter what this is as long as it's canonical. Built-in
		--   __lt on strings is not trustworthy because it's based on the
		--   current locale, so it's not necessarily canonical.
		for i = 1, math.max(#lhs, #rhs) do
			local lb = string.byte(lhs, i) or -math.huge
			local rb = string.byte(rhs, i) or -math.huge
			if lb < rb then return true  end
			if lb > rb then return false end
		end
		return false
	end)
	local xid_class = {}
	local from_tool = {}
	local to_tool = {}
	local to_tool_index = {}
	for xtype, tool in ipairs(supported) do
		assert(not to_tool[xtype])
		assert(not from_tool[tool])
		local class = tool:match("^[^_]+_(.-)_[^_]+$")
		xid_class[xtype] = class
		to_tool[xtype] = tool
		to_tool_index[xtype] = tools.index[tool]
		from_tool[tool] = xtype
	end
	local unknown_xid = 0x3FFF
	assert(not to_tool[unknown_xid])
	from_tool["UNKNOWN"] = unknown_xid
	to_tool[unknown_xid] = "UNKNOWN"
	to_tool_index[unknown_xid] = 0
	local function assign_if_supported(tbl)
		local res = {}
		for key, value in pairs(tbl) do
			if from_tool[key] then
				res[from_tool[key]] = value
			end
		end
		return res
	end
	local create_override = assign_if_supported({
		[ "DEFAULT_PT_LIGH" ] = function(rx, ry, c)
			local tmp = rx + ry
			if tmp > 55 then
				tmp = 55
			end
			return 0, 0, elem.DEFAULT_PT_LIGH + bit.lshift(tmp, PMAPBITS)
		end,
		[ "DEFAULT_PT_TESC" ] = function(rx, ry, c)
			local tmp = rx * 4 + ry * 4 + 7
			if tmp > 300 then
				tmp = 300
			end
			return rx, ry, elem.DEFAULT_PT_TESC + bit.lshift(tmp, PMAPBITS)
		end,
		[ "DEFAULT_PT_STKM" ] = function(rx, ry, c)
			return 0, 0, elem.DEFAULT_PT_STKM
		end,
		[ "DEFAULT_PT_STKM2" ] = function(rx, ry, c)
			return 0, 0, elem.DEFAULT_PT_STKM2
		end,
		[ "DEFAULT_PT_FIGH" ] = function(rx, ry, c)
			return 0, 0, elem.DEFAULT_PT_FIGH
		end,
	})
	local no_flood = assign_if_supported({
		[ "DEFAULT_PT_SPRK"  ] = true,
		[ "DEFAULT_PT_STKM"  ] = true,
		[ "DEFAULT_PT_LIGH"  ] = true,
		[ "DEFAULT_PT_STKM2" ] = true,
		[ "DEFAULT_PT_FIGH"  ] = true,
	})
	local no_shape = assign_if_supported({
		[ "DEFAULT_PT_STKM"  ] = true,
		[ "DEFAULT_PT_LIGH"  ] = true,
		[ "DEFAULT_PT_STKM2" ] = true,
		[ "DEFAULT_PT_FIGH"  ] = true,
	})
	local no_create = assign_if_supported({
		[ "DEFAULT_UI_PROPERTY" ] = true,
		[ "DEFAULT_UI_SAMPLE"   ] = true,
		[ "DEFAULT_UI_SIGN"     ] = true,
		[ "UNKNOWN"             ] = true,
	})
	local line_only = assign_if_supported({
		[ "DEFAULT_UI_WIND" ] = true,
	})
	return {
		xid_class       = xid_class,
		from_tool       = from_tool,
		to_tool         = to_tool,
		to_tool_index   = to_tool_index,
		create_override = create_override,
		no_flood        = no_flood,
		no_shape        = no_shape,
		no_create       = no_create,
		line_only       = line_only,
		unknown_xid     = unknown_xid,
	}
end

local function heat_clear()
	local temp = sim.ambientAirTemp()
	for x = 0, sim.XRES / sim.CELL - 1 do
		for y = 0, sim.YRES / sim.CELL - 1 do
			sim.ambientHeat(x, y, temp)
		end
	end
end

local function stamp_load(x, y, data, reset)
	if data == "" then -- * Is this check needed at all?
		return nil, "no stamp data"
	end
	local stamp_temp = ("%s.%s.%s"):format(config.stamp_temp, tostring(socket.gettime()), tostring(math.random(10000, 99999)))
	local handle = io.open(stamp_temp, "wb")
	if not handle then
		return nil, "cannot write stamp data"
	end
	handle:write(data)
	handle:close()
	if reset then
		sim.clearRect(0, 0, sim.XRES, sim.YRES)
		heat_clear()
		tpt.reset_velocity()
		tpt.set_pressure()
	end
	local ok, err = sim.loadStamp(stamp_temp, x, y)
	if not ok then
		os.remove(stamp_temp)
		if err then
			return nil, "cannot load stamp data: " .. err
		else
			return nil, "cannot load stamp data"
		end
	end
	os.remove(stamp_temp)
	return true
end

local function stamp_save(x, y, w, h)
	local name = sim.saveStamp(x, y, w - 1, h - 1)
	if not name then
		return nil, "error saving stamp"
	end
	local handle = io.open("stamps/" .. name .. ".stm", "rb")
	if not handle then
		sim.deleteStamp(name)
		return nil, "cannot read stamp data"
	end
	local data = handle:read("*a")
	handle:close()
	sim.deleteStamp(name)
	return data
end

-- * Finds bynd, the smallest idx in [first, last] for which beyond(idx)
--   is true. Assumes that for all idx in [first, bynd-1] beyond(idx) is
--   false and for all idx in [bynd, last] beyond(idx) is true. beyond(first-1)
--   is implicitly false and beyond(last+1) is implicitly true, thus an
--   all-false field yields last+1 and an all-true field yields first.
local function binary_search_implicit(first, last, beyond)
	local function beyond_wrap(idx)
		if idx < first then
			return false
		end
		if idx > last then
			return true
		end
		return beyond(idx)
	end
	while first <= last do
		local mid = math.floor((first + last) / 2)
		if beyond_wrap(mid) then
			if beyond_wrap(mid - 1) then
				last = mid - 1
			else
				return mid
			end
		else
			first = mid + 1
		end
	end
	return first
end

local function inside_rect(pos_x, pos_y, width, height, check_x, check_y)
	return pos_x <= check_x and pos_y <= check_y and pos_x + width > check_x and pos_y + height > check_y
end

local function mouse_pos()
	return tpt.mousex, tpt.mousey
end

local function brush_size()
	return tpt.brushx, tpt.brushy
end

local function selected_tools()
	return tpt.selectedl, tpt.selecteda, tpt.selectedr, tpt.selectedreplace
end

local function wall_snap_coords(x, y)
	return math.floor(x / 4) * 4, math.floor(y / 4) * 4
end

local function line_snap_coords(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	if math.abs(math.floor(dx / 2)) > math.abs(dy) then
		return x2, y1
	elseif math.abs(dx) < math.abs(math.floor(dy / 2)) then
		return x1, y2
	elseif dx * dy > 0 then
		return x1 + math.floor((dx + dy) / 2), y1 + math.floor((dy + dx) / 2)
	else
		return x1 + math.floor((dx - dy) / 2), y1 + math.floor((dy - dx) / 2)
	end
end

local function rect_snap_coords(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	if dx * dy > 0 then
		return x1 + math.floor((dx + dy) / 2), y1 + math.floor((dy + dx) / 2)
	else
		return x1 + math.floor((dx - dy) / 2), y1 + math.floor((dy - dx) / 2)
	end
end

local function create_parts_any(xidr, x, y, rx, ry, xtype, brush, member)
	if not inside_rect(0, 0, sim.XRES, sim.YRES, x, y) then
		return
	end
	if xidr.line_only[xtype] or xidr.no_create[xtype] then
		return
	end
	local class = xidr.xid_class[xtype]
	local old_create = false
	if type(xtype) == "table" and xtype.type == "cgol" then
		-- * TODO[api]: add an api for setting gol colour
		xtype = xtype.elem
		old_create = true
	else
		local ov = xidr.create_override[xtype]
		if ov then
			rx, ry, xtype = ov(rx, ry, xtype)
			old_create = true
		end
	end
	local str = 1
	if member.kmod_s then
		str = 10
	elseif member.kmod_c then
		str = 0.1
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = xidr.to_tool[member.tool_x] or "DEFAULT_PT_NONE"
	end
	local bmode = sim.replaceModeFlags()
	sim.replaceModeFlags(member.bmode)
	if old_create then
		sim.createParts(x, y, rx, ry, xtype, brush, member.bmode)
	else
		local deco
		if class == "DECOR" then
			deco = sim.decoColour()
			sim.decoColour(member.deco)
		end
		sim.toolBrush(x, y, rx, ry, xidr.to_tool_index[xtype], brush, str)
		if class == "DECOR" then
			sim.decoColour(deco)
		end
	end
	sim.replaceModeFlags(bmode)
	if member.bmode ~= 0 then
		tpt.selectedreplace = selectedreplace
	end
end

local function create_line_any(xidr, x1, y1, x2, y2, rx, ry, xtype, brush, member, cont)
	-- * TODO[opt]: Revert jacob1's mod ball check.
	if not inside_rect(0, 0, sim.XRES, sim.YRES, x1, y1) or
	   not inside_rect(0, 0, sim.XRES, sim.YRES, x2, y2) then
		return
	end
	if xidr.no_create[xtype] or xidr.no_shape[xtype] then
		return
	end
	local class = xidr.xid_class[xtype]
	local old_create = false
	if type(xtype) == "table" and xtype.type == "cgol" then
		-- * TODO[api]: add an api for setting gol colour
		xtype = xtype.elem
		old_create = true
	else
		local ov = xidr.create_override[xtype]
		if ov then
			rx, ry, xtype = ov(rx, ry, xtype)
			old_create = true
		end
	end
	local str = 1
	if cont then
		if member.kmod_s then
			str = 10
		elseif member.kmod_c then
			str = 0.1
		end
		if xidr.to_tool[xtype] == "DEFAULT_TOOL_WIND" then
			str = str * 5
		end
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = xidr.to_tool[member.tool_x] or "DEFAULT_PT_NONE"
	end
	local bmode = sim.replaceModeFlags()
	sim.replaceModeFlags(member.bmode)
	if old_create then
		sim.createLine(x1, y1, x2, y2, rx, ry, xtype, brush, member.bmode)
	else
		local deco
		if class == "DECOR" then
			deco = sim.decoColour()
			sim.decoColour(member.deco)
		end
		sim.toolLine(x1, y1, x2, y2, rx, ry, xidr.to_tool_index[xtype], brush, str)
		if class == "DECOR" then
			sim.decoColour(deco)
		end
	end
	sim.replaceModeFlags(bmode)
	if member.bmode ~= 0 then
		tpt.selectedreplace = selectedreplace
	end
end

local function create_box_any(xidr, x1, y1, x2, y2, rx, ry, xtype, member)
	if not inside_rect(0, 0, sim.XRES, sim.YRES, x1, y1) or
	   not inside_rect(0, 0, sim.XRES, sim.YRES, x2, y2) then
		return
	end
	if xidr.line_only[xtype] or xidr.no_create[xtype] or xidr.no_shape[xtype] then
		return
	end
	local class = xidr.xid_class[xtype]
	local old_create = false
	if type(xtype) == "table" and xtype.type == "cgol" then
		-- * TODO[api]: add an api for setting gol colour
		xtype = xtype.elem
		old_create = true
	else
		local ov = xidr.create_override[xtype]
		if ov then
			rx, ry, xtype = ov(rx, ry, xtype)
			old_create = true
		end
	end
	local str = 1
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = xidr.to_tool[member.tool_x] or "DEFAULT_PT_NONE"
	end
	local bmode = sim.replaceModeFlags()
	sim.replaceModeFlags(member.bmode)
	if old_create then
		local orx, ory = tpt.brushx, tpt.brushy
		tpt.brushx, tpt.brushy = rx, ry
		sim.createBox(x1, y1, x2, y2, xtype, member.bmode)
		tpt.brushx, tpt.brushy = orx, ory
	else
		local deco
		if class == "DECOR" then
			deco = sim.decoColour()
			sim.decoColour(member.deco)
		end
		sim.toolBox(x1, y1, x2, y2, xidr.to_tool_index[xtype], str, 0, rx, ry)
		if class == "DECOR" then
			sim.decoColour(deco)
		end
	end
	sim.replaceModeFlags(bmode)
	if member.bmode ~= 0 then
		tpt.selectedreplace = selectedreplace
	end
end

local function flood_any(xidr, x, y, xtype, part_flood_hint, wall_flood_hint, member)
	if not inside_rect(0, 0, sim.XRES, sim.YRES, x, y) then
		return
	end
	if xidr.line_only[xtype] or xidr.no_create[xtype] or xidr.no_flood[xtype] then
		return
	end
	local class = xidr.xid_class[xtype]
	if class == "DECOR" or class == "TOOL" then
		return
	end
	local old_create = false
	if type(xtype) == "table" and xtype.type == "cgol" then
		-- * TODO[api]: add an api for setting gol colour
		xtype = xtype.elem
		old_create = true
	else
		local ov = xidr.create_override[xtype]
		if ov then
			rx, ry, xtype = ov(rx, ry, xtype)
			old_create = true
		end
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = xidr.to_tool[member.tool_x] or "DEFAULT_PT_NONE"
	end
	local bmode = sim.replaceModeFlags()
	sim.replaceModeFlags(member.bmode)
	if old_create then
		sim.floodParts(x, y, xtype, part_flood_hint, member.bmode)
	elseif class == "WL" then
		sim.floodWalls(x, y, sim.walls[xidr.to_tool[xtype]], wall_flood_hint)
	else
		sim.floodParts(x, y, elem[xidr.to_tool[xtype]], part_flood_hint, member.bmode)
	end
	sim.replaceModeFlags(bmode)
	if member.bmode ~= 0 then
		tpt.selectedreplace = selectedreplace
	end
end

local function clear_rect(x, y, w, h)
	if not inside_rect(0, 0, sim.XRES, sim.YRES, x + w, y + h) then
		return
	end
	sim.clearRect(x, y, w, h)
end

local function corners_to_rect(x1, y1, x2, y2)
	local xl = math.min(x1, x2)
	local yl = math.min(y1, y2)
	local xh = math.max(x1, x2)
	local yh = math.max(y1, y2)
	return xl, yl, xh - xl + 1, yh - yl + 1
end

local function escape_regex(str)
	return (str:gsub("[%$%%%(%)%*%+%-%.%?%[%^%]]", "%%%1"))
end

local function fnv1a32(data)
	local hash = 2166136261
	for i = 1, #data do
		hash = bit.bxor(hash, data:byte(i))
		hash = bit.band(bit.lshift(hash, 24), 0xFFFFFFFF) + bit.band(bit.lshift(hash, 8), 0xFFFFFFFF) + hash * 147
	end
	hash = bit.band(hash, 0xFFFFFFFF)
	return hash < 0 and (hash + 0x100000000) or hash
end

local function ambient_air_temp(temp)
	if temp then
		local set = temp / 0x400
		sim.ambientAirTemp(set)
		return set
	else
		return math.max(0x000000, math.min(0xFFFFFF, math.floor(sim.ambientAirTemp() * 0x400)))
	end
end

local function custom_gravity(x, y)
	if x then
		if x >= 0x800000 then x = x - 0x1000000 end
		if y >= 0x800000 then y = y - 0x1000000 end
		local setx, sety = x / 0x400, y / 0x400
		sim.customGravity(setx, sety)
		return setx, sety
	else
		local getx, gety = sim.customGravity()
		getx = math.max(-0x800000, math.min(0x7FFFFF, math.floor(getx * 0x400)))
		gety = math.max(-0x800000, math.min(0x7FFFFF, math.floor(gety * 0x400)))
		if getx < 0 then getx = getx + 0x1000000 end
		if gety < 0 then gety = gety + 0x1000000 end
		return getx, gety
	end
end

local function get_save_id()
	local id, hist = sim.getSaveID()
	if id and not hist then
		hist = 0
	end
	return id, hist
end

local function urlencode(str)
	return (str:gsub("[^ !'()*%-%.0-9A-Z_a-z]", function(cap)
		return ("%%%02x"):format(cap:byte())
	end))
end

local function get_name()
	local name = tpt.get_name()
	return name ~= "" and name or nil
end

local function tool_identifiers()
	local identifiers = {}
	for name in pairs(tools.index) do
		identifiers[name] = true
	end
	return identifiers
end

local function decode_rulestring(tool)
	if type(tool) == "table" and tool.type == "cgol" then
		return tool.repr
	end
end

local function tool_proper_name(tool, xidr)
	local tool_name = (tool and xidr.to_tool[tool] or decode_rulestring(tool)) or "UNKNOWN"
	if elem[tool_name] and xidr.to_tool[tool] and tool ~= 0 and tool_name ~= "UNKNOWN" then
		local real_name = elem.property(elem[tool_name], "Name")
		if real_name ~= "" then
			tool_name = real_name
		end
	end
	return tool_name
end

local function deco_unpack(deco)
	return bit.band(bit.rshift(deco, 24), 0xFF),
	       bit.band(bit.rshift(deco, 16), 0xFF),
	       bit.band(bit.rshift(deco,  8), 0xFF),
	       bit.band(           deco     , 0xFF)
end

local function deco_pack(a, r, g, b)
	return bit.bor(bit.lshift(a, 24),
	               bit.lshift(r, 16),
	               bit.lshift(g,  8),
	                          b     )
end

return {
	get_name               = get_name,
	stamp_load             = stamp_load,
	stamp_save             = stamp_save,
	binary_search_implicit = binary_search_implicit,
	inside_rect            = inside_rect,
	mouse_pos              = mouse_pos,
	brush_size             = brush_size,
	selected_tools         = selected_tools,
	wall_snap_coords       = wall_snap_coords,
	line_snap_coords       = line_snap_coords,
	rect_snap_coords       = rect_snap_coords,
	create_parts_any       = create_parts_any,
	create_line_any        = create_line_any,
	create_box_any         = create_box_any,
	flood_any              = flood_any,
	clear_rect             = clear_rect,
	xid_registry           = xid_registry,
	corners_to_rect        = corners_to_rect,
	escape_regex           = escape_regex,
	fnv1a32                = fnv1a32,
	ambient_air_temp       = ambient_air_temp,
	custom_gravity         = custom_gravity,
	get_save_id            = get_save_id,
	version_less           = common_util.version_less,
	version_equal          = common_util.version_equal,
	tpt_version            = tpt_version,
	urlencode              = urlencode,
	heat_clear             = heat_clear,
	deco_unpack            = deco_unpack,
	deco_pack              = deco_pack,
	tool_identifiers       = tool_identifiers,
	tool_proper_name       = tool_proper_name,
}
