local config = require("tptmp.client.config")

if not elem.TPTMP_PT_UNKNOWN then
	assert(elem.allocate("TPTMP", "UNKNOWN") ~= -1, "out of element IDs")
end

local jacobsmod = rawget(_G, "jacobsmod")
local from_tool = {}
local to_tool = {}
local xid_first = {}
local PMAPBITS = sim.PMAPBITS

local have_7arg_swm
local new_gol_names
do
	local old_selectedl = tpt.selectedl
	if old_selectedl == "DEFAULT_UI_PROPERTY" then
		old_selectedl = "DEFAULT_PT_DUST"
	end
	new_gol_names = pcall(function()
		tpt.selectedl = "DEFAULT_PT_LIFE_2X2"
	end)
	tpt.selectedl = old_selectedl
end

local tools = {
	-- * TODO[api]: Could do something about custom GOL; would probably need an API for it first though.
	"DEFAULT_PT_LIFE_GOL",
	"DEFAULT_PT_LIFE_HLIF",
	"DEFAULT_PT_LIFE_ASIM",
	new_gol_names and "DEFAULT_PT_LIFE_2X2" or "DEFAULT_PT_LIFE_2x2",
	"DEFAULT_PT_LIFE_DANI",
	"DEFAULT_PT_LIFE_AMOE",
	"DEFAULT_PT_LIFE_MOVE",
	"DEFAULT_PT_LIFE_PGOL",
	"DEFAULT_PT_LIFE_DMOE",
	new_gol_names and "DEFAULT_PT_LIFE_3-4" or "DEFAULT_PT_LIFE_34",
	"DEFAULT_PT_LIFE_LLIF",
	"DEFAULT_PT_LIFE_STAN",
	"DEFAULT_PT_LIFE_SEED",
	"DEFAULT_PT_LIFE_MAZE",
	"DEFAULT_PT_LIFE_COAG",
	"DEFAULT_PT_LIFE_WALL",
	"DEFAULT_PT_LIFE_GNAR",
	"DEFAULT_PT_LIFE_REPL",
	"DEFAULT_PT_LIFE_MYST",
	"DEFAULT_PT_LIFE_LOTE",
	"DEFAULT_PT_LIFE_FRG2",
	"DEFAULT_PT_LIFE_STAR",
	"DEFAULT_PT_LIFE_FROG",
	"DEFAULT_PT_LIFE_BRAN",
	"DEFAULT_WL_ERASE",
	"DEFAULT_WL_CNDTW",
	"DEFAULT_WL_EWALL",
	"DEFAULT_WL_DTECT",
	"DEFAULT_WL_STRM",
	"DEFAULT_WL_FAN",
	"DEFAULT_WL_LIQD",
	"DEFAULT_WL_ABSRB",
	"DEFAULT_WL_WALL",
	"DEFAULT_WL_AIR",
	"DEFAULT_WL_POWDR",
	"DEFAULT_WL_CNDTR",
	"DEFAULT_WL_EHOLE",
	"DEFAULT_WL_GAS",
	"DEFAULT_WL_GRVTY",
	"DEFAULT_WL_ENRGY",
	"DEFAULT_WL_NOAIR",
	"DEFAULT_WL_ERASEA",
	"DEFAULT_WL_STASIS",
	"DEFAULT_UI_SAMPLE",
	"DEFAULT_UI_SIGN",
	"DEFAULT_UI_PROPERTY",
	"DEFAULT_UI_WIND",
	"DEFAULT_TOOL_HEAT",
	"DEFAULT_TOOL_COOL",
	"DEFAULT_TOOL_AIR",
	"DEFAULT_TOOL_VAC",
	"DEFAULT_TOOL_PGRV",
	"DEFAULT_TOOL_NGRV",
	"DEFAULT_TOOL_MIX",
	"DEFAULT_DECOR_SET",
	"DEFAULT_DECOR_CLR",
	"DEFAULT_DECOR_ADD",
	"DEFAULT_DECOR_SUB",
	"DEFAULT_DECOR_MUL",
	"DEFAULT_DECOR_DIV",
	"DEFAULT_DECOR_SMDG",
	"DEFAULT_DECOR_LIGH",
	"DEFAULT_DECOR_DARK",
}
local xid_class = {}
for i = 1, #tools do
	local xtype = 0x2000 + i
	local tool = tools[i]
	from_tool[tool] = xtype
	to_tool[xtype] = tool
	local class = tool:match("^[^_]+_(.-)_[^_]+$")
	xid_class[xtype] = class
	xid_first[class] = math.min(xid_first[class] or math.huge, xtype)
end
for key, value in pairs(elem) do
	if key:find("^[^_]+_PT_") then
		from_tool[key] = value
		to_tool[value] = key
	end
end

local WL_FAN = from_tool.DEFAULT_WL_FAN - xid_first.WL

local create_override = {
	[ from_tool.DEFAULT_PT_STKM ] = function(rx, ry, c)
		return 0, 0, c
	end,
	[ from_tool.DEFAULT_PT_LIGH ] = function(rx, ry, c)
		local tmp = rx + ry
		if tmp > 55 then
			tmp = 55
		end
		return 0, 0, c + bit.lshift(tmp, PMAPBITS)
	end,
	[ from_tool.DEFAULT_PT_TESC ] = function(rx, ry, c)
		local tmp = rx * 4 + ry * 4 + 7
		if tmp > 300 then
			tmp = 300
		end
		return rx, ry, c + bit.lshift(tmp, PMAPBITS)
	end,
	[ from_tool.DEFAULT_PT_STKM2 ] = function(rx, ry, c)
		return 0, 0, c
	end,
	[ from_tool.DEFAULT_PT_FIGH ] = function(rx, ry, c)
		return 0, 0, c
	end,
}
local no_flood = {
	[ from_tool.DEFAULT_PT_SPRK  ] = true,
	[ from_tool.DEFAULT_PT_STKM  ] = true,
	[ from_tool.DEFAULT_PT_LIGH  ] = true,
	[ from_tool.DEFAULT_PT_STKM2 ] = true,
	[ from_tool.DEFAULT_PT_FIGH  ] = true,
}
local no_shape = {
	[ from_tool.DEFAULT_PT_STKM  ] = true,
	[ from_tool.DEFAULT_PT_LIGH  ] = true,
	[ from_tool.DEFAULT_PT_STKM2 ] = true,
	[ from_tool.DEFAULT_PT_FIGH  ] = true,
}
local no_create = {
	[ from_tool.DEFAULT_UI_PROPERTY   ] = true,
	[ from_tool.DEFAULT_UI_SAMPLE     ] = true,
	[ from_tool.DEFAULT_UI_SIGN       ] = true,
	[ from_tool.TPTMP_PT_UNKNOWN      ] = true,
}
local line_only = {
	[ from_tool.DEFAULT_UI_WIND ] = true,
}

local function stamp_load(x, y, data, reset)
	if data == "" then -- * Is this check needed at all?
		return nil, "no stamp data"
	end
	local handle = io.open(config.stamp_temp, "wb")
	if not handle then
		return nil, "cannot write stamp data"
	end
	handle:write(data)
	handle:close()
	if reset then
		sim.clearSim()
	end
	if not sim.loadStamp(config.stamp_temp, x, y) then
		os.remove(config.stamp_temp)
		return nil, "cannot load stamp data"
	end
	os.remove(config.stamp_temp)
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

local function get_user()
	local pref = io.open("powder.pref")
	if not pref then
		return
	end
	local pref_data = pref:read("*a")
	pref:close()
	local user = pref_data:match([["User"%s*:%s*(%b{})]])
	if not user then
		return
	end
	local uid = user:match([["ID"%s*:%s*(%d+)]])
	local sess = user:match([["SessionID"%s*:%s*"([^"]+)"]])
	local name = user:match([["Username"%s*:%s*"([^"]+)"]])
	if not uid or not sess or not name then
		return
	end
	if name ~= tpt.get_name() then
		return
	end
	return uid, sess, name
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

local function create_parts_any(x, y, rx, ry, xtype, brush, member)
	if line_only[xtype] or no_create[xtype] then
		return
	end
	local class = xid_class[xtype]
	if class == "WL" then
		if xtype == from_tool.DEFAULT_WL_STRM then
			rx, ry = 0, 0
		end
		sim.createWalls(x, y, rx, ry, xtype - xid_first.WL, brush)
		return
	elseif class == "TOOL" then
		local str = 1
		if member.kmod_s then
			str = 10
		elseif member.kmod_c then
			str = 0.1
		end
		sim.toolBrush(x, y, rx, ry, xtype - xid_first.TOOL, brush, str)
		return
	elseif class == "DECOR" then
		sim.decoBrush(x, y, rx, ry, member.deco_r, member.deco_g, member.deco_b, member.deco_a, xtype - xid_first.DECOR, brush)
		return
	elseif class == "PT_LIFE" then
		xtype = elem.DEFAULT_PT_LIFE + bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS)
	end
	local ov = create_override[xtype]
	if ov then
		rx, ry, xtype = ov(rx, ry, xtype)
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = to_tool[member.tool_x] or "TPTMP_PT_UNKNOWN"
	end
	sim.createParts(x, y, rx, ry, xtype, brush, member.bmode)
	if member.bmode ~= 0 then
		tpt.selectedreplace = selectedreplace
	end
end

local function create_line_any(x1, y1, x2, y2, rx, ry, xtype, brush, member, cont)
	if no_create[xtype] or no_shape[xtype] or (jacobsmod and xtype == tpt.element("ball") and not member.kmod_s) then
		return
	end
	local class = xid_class[xtype]
	if class == "WL" then
		local str = 1
		if cont then
			if member.kmod_s then
				str = 10
			elseif member.kmod_c then
				str = 0.1
			end
			str = str * 5
		end
		if not cont and xtype == from_tool.DEFAULT_WL_FAN and tpt.get_wallmap(math.floor(x1 / 4), math.floor(y1 / 4)) == WL_FAN then
			local fvx = (x2 - x1) * 0.005
			local fvy = (y2 - y1) * 0.005
			local bw = sim.XRES / 4
			local bh = sim.YRES / 4
			local visit = {}
			local mark = {}
			local last = 0
			local function enqueue(x, y)
				if x >= 0 and y >= 0 and x < bw and y < bh and tpt.get_wallmap(x, y) == WL_FAN then
					local k = x + y * bw
					if not mark[k] then
						last = last + 1
						visit[last] = k
						mark[k] = true
					end
				end
			end
			enqueue(math.floor(x1 / 4), math.floor(y1 / 4))
			local curr = 1
			while visit[curr] do
				local k = visit[curr]
				local x, y = k % bw, math.floor(k / bw)
				if have_7arg_swm == nil then
					tpt.set_wallmap(x, y, 1, 1, 1, 1, WL_FAN)
					have_7arg_swm = tpt.get_wallmap(x, y) == WL_FAN
				end
				if have_7arg_swm then
					tpt.set_wallmap(x, y, 1, 1, fvx, fvy, WL_FAN)
				else
					tpt.set_wallmap(x, y, 1, 1, WL_FAN)
				end
				enqueue(x - 1, y)
				enqueue(x, y - 1)
				enqueue(x + 1, y)
				enqueue(x, y + 1)
				curr = curr + 1
			end
			return
		end
		if xtype == from_tool.DEFAULT_WL_STRM then
			rx, ry = 0, 0
		end
		sim.createWallLine(x1, y1, x2, y2, rx, ry, xtype - xid_first.WL, brush)
		return
	elseif xtype == from_tool.DEFAULT_UI_WIND then
		local str = 1
		if cont then
			if member.kmod_s then
				str = 10
			elseif member.kmod_c then
				str = 0.1
			end
			str = str * 5
		end
		sim.toolLine(x1, y1, x2, y2, rx, ry, sim.TOOL_WIND, brush, str)
		return
	elseif class == "TOOL" then
		local str = 1
		if cont then
			if member.kmod_s then
				str = 10
			elseif member.kmod_c then
				str = 0.1
			end
		end
		sim.toolLine(x1, y1, x2, y2, rx, ry, xtype - xid_first.TOOL, brush, str)
		return
	elseif class == "DECOR" then
		sim.decoLine(x1, y1, x2, y2, rx, ry, member.deco_r, member.deco_g, member.deco_b, member.deco_a, xtype - xid_first.DECOR, brush)
		return
	elseif class == "PT_LIFE" then
		xtype = elem.DEFAULT_PT_LIFE + bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS)
	end
	local ov = create_override[xtype]
	if ov then
		rx, ry, xtype = ov(rx, ry, xtype)
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = to_tool[member.tool_x]
	end
	sim.createLine(x1, y1, x2, y2, rx, ry, xtype, brush, member.bmode)
	if member.bmode ~= 0 then
		tpt.selectedreplace = selectedreplace
	end
end

local function create_box_any(x1, y1, x2, y2, xtype, member)
	if line_only[xtype] or no_create[xtype] or no_shape[xtype] then
		return
	end
	local class = xid_class[xtype]
	if class == "WL" then
		sim.createWallBox(x1, y1, x2, y2, xtype - xid_first.WL)
		return
	elseif class == "TOOL" then
		sim.toolBox(x1, y1, x2, y2, xtype - xid_first.TOOL)
		return
	elseif class == "DECOR" then
		sim.decoBox(x1, y1, x2, y2, member.deco_r, member.deco_g, member.deco_b, member.deco_a, xtype - xid_first.DECOR)
		return
	elseif class == "PT_LIFE" then
		xtype = elem.DEFAULT_PT_LIFE + bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS)
	end
	local _
	local ov = create_override[xtype]
	if ov then
		_, _, xtype = ov(member.size_x, member.size_y, xtype)
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = to_tool[member.tool_x]
	end
	sim.createBox(x1, y1, x2, y2, xtype, member and member.bmode)
	if member.bmode ~= 0 then
		tpt.selectedreplace = selectedreplace
	end
end

local function flood_any(x, y, xtype, part_flood_hint, wall_flood_hint, member)
	if line_only[xtype] or no_create[xtype] or no_flood[xtype] then
		return
	end
	local class = xid_class[xtype]
	if class == "WL" then
		sim.floodWalls(x, y, xtype - xid_first.WL, wall_flood_hint)
		return
	elseif class == "DECOR" or class == "TOOL" then
		return
	elseif class == "PT_LIFE" then
		xtype = elem.DEFAULT_PT_LIFE + bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS)
	end
	local _
	local ov = create_override[xtype]
	if ov then
		_, _, xtype = ov(member.size_x, member.size_y, xtype)
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = to_tool[member.tool_x]
	end
	sim.floodParts(x, y, xtype, part_flood_hint, member.bmode)
	if member.bmode ~= 0 then
		tpt.selectedreplace = selectedreplace
	end
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

return {
	get_user = get_user,
	stamp_load = stamp_load,
	stamp_save = stamp_save,
	binary_search_implicit = binary_search_implicit,
	inside_rect = inside_rect,
	mouse_pos = mouse_pos,
	brush_size = brush_size,
	selected_tools = selected_tools,
	wall_snap_coords = wall_snap_coords,
	line_snap_coords = line_snap_coords,
	rect_snap_coords = rect_snap_coords,
	create_parts_any = create_parts_any,
	create_line_any = create_line_any,
	create_box_any = create_box_any,
	flood_any = flood_any,
	from_tool = from_tool,
	to_tool = to_tool,
	create_override = create_override,
	no_flood = no_flood,
	no_shape = no_shape,
	xid_class = xid_class,
	corners_to_rect = corners_to_rect,
	escape_regex = escape_regex,
}
