local config      = require("tptmp.client.config")
local common_util = require("tptmp.common.util")

local jacobsmod = rawget(_G, "jacobsmod")
local from_tool = {}
local to_tool = {}
local xid_first = {}
local PMAPBITS = sim.PMAPBITS

local tpt_version = { tpt.version.major, tpt.version.minor }
local has_ambient_heat_tools
do
	local old_selectedl = tpt.selectedl
	if old_selectedl == "DEFAULT_UI_PROPERTY" or old_selectedl == "DEFAULT_UI_ADDLIFE" then
		old_selectedl = "DEFAULT_PT_DUST"
	end
	has_ambient_heat_tools = pcall(function() tpt.selectedl = "DEFAULT_TOOL_AMBM" end)
	tpt.selectedl = old_selectedl
end

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

local function array_keyify(arr)
	local tbl = {}
	for i = 1, #arr do
		tbl[arr[i]] = true
	end
	return tbl
end

local tools = array_concat({
	"DEFAULT_PT_LIFE_GOL",
	"DEFAULT_PT_LIFE_HLIF",
	"DEFAULT_PT_LIFE_ASIM",
	"DEFAULT_PT_LIFE_2X2",
	"DEFAULT_PT_LIFE_DANI",
	"DEFAULT_PT_LIFE_AMOE",
	"DEFAULT_PT_LIFE_MOVE",
	"DEFAULT_PT_LIFE_PGOL",
	"DEFAULT_PT_LIFE_DMOE",
	"DEFAULT_PT_LIFE_3-4",
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
}, {
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
}, {
	"DEFAULT_UI_SAMPLE",
	"DEFAULT_UI_SIGN",
	"DEFAULT_UI_PROPERTY",
	"DEFAULT_UI_WIND",
	"DEFAULT_UI_ADDLIFE",
}, {
	"DEFAULT_TOOL_HEAT",
	"DEFAULT_TOOL_COOL",
	"DEFAULT_TOOL_AIR",
	"DEFAULT_TOOL_VAC",
	"DEFAULT_TOOL_PGRV",
	"DEFAULT_TOOL_NGRV",
	"DEFAULT_TOOL_MIX",
	"DEFAULT_TOOL_CYCL",
	has_ambient_heat_tools and "DEFAULT_TOOL_AMBM" or nil,
	has_ambient_heat_tools and "DEFAULT_TOOL_AMBP" or nil,
}, {
	"DEFAULT_DECOR_SET",
	"DEFAULT_DECOR_CLR",
	"DEFAULT_DECOR_ADD",
	"DEFAULT_DECOR_SUB",
	"DEFAULT_DECOR_MUL",
	"DEFAULT_DECOR_DIV",
	"DEFAULT_DECOR_SMDG",
})
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
-- * TODO[opt]: support custom elements
local known_elements = array_keyify({
	"DEFAULT_PT_NONE",
	"DEFAULT_PT_DUST",
	"DEFAULT_PT_WATR",
	"DEFAULT_PT_OIL",
	"DEFAULT_PT_FIRE",
	"DEFAULT_PT_STNE",
	"DEFAULT_PT_LAVA",
	"DEFAULT_PT_GUN",
	"DEFAULT_PT_GUNP",
	"DEFAULT_PT_NITR",
	"DEFAULT_PT_CLNE",
	"DEFAULT_PT_GAS",
	"DEFAULT_PT_C-4",
	"DEFAULT_PT_PLEX",
	"DEFAULT_PT_GOO",
	"DEFAULT_PT_ICE",
	"DEFAULT_PT_ICEI",
	"DEFAULT_PT_METL",
	"DEFAULT_PT_SPRK",
	"DEFAULT_PT_SNOW",
	"DEFAULT_PT_WOOD",
	"DEFAULT_PT_NEUT",
	"DEFAULT_PT_PLUT",
	"DEFAULT_PT_PLNT",
	"DEFAULT_PT_ACID",
	"DEFAULT_PT_VOID",
	"DEFAULT_PT_WTRV",
	"DEFAULT_PT_CNCT",
	"DEFAULT_PT_DSTW",
	"DEFAULT_PT_SALT",
	"DEFAULT_PT_SLTW",
	"DEFAULT_PT_DMND",
	"DEFAULT_PT_BMTL",
	"DEFAULT_PT_BRMT",
	"DEFAULT_PT_PHOT",
	"DEFAULT_PT_URAN",
	"DEFAULT_PT_WAX",
	"DEFAULT_PT_MWAX",
	"DEFAULT_PT_PSCN",
	"DEFAULT_PT_NSCN",
	"DEFAULT_PT_LNTG",
	"DEFAULT_PT_LN2",
	"DEFAULT_PT_INSL",
	"DEFAULT_PT_BHOL",
	"DEFAULT_PT_VACU",
	"DEFAULT_PT_WHOL",
	"DEFAULT_PT_VENT",
	"DEFAULT_PT_RBDM",
	"DEFAULT_PT_LRBD",
	"DEFAULT_PT_NTCT",
	"DEFAULT_PT_SAND",
	"DEFAULT_PT_GLAS",
	"DEFAULT_PT_PTCT",
	"DEFAULT_PT_BGLA",
	"DEFAULT_PT_THDR",
	"DEFAULT_PT_PLSM",
	"DEFAULT_PT_ETRD",
	"DEFAULT_PT_NICE",
	"DEFAULT_PT_NBLE",
	"DEFAULT_PT_BTRY",
	"DEFAULT_PT_LCRY",
	"DEFAULT_PT_STKM",
	"DEFAULT_PT_SWCH",
	"DEFAULT_PT_SMKE",
	"DEFAULT_PT_DESL",
	"DEFAULT_PT_COAL",
	"DEFAULT_PT_LO2",
	"DEFAULT_PT_LOXY",
	"DEFAULT_PT_O2",
	"DEFAULT_PT_OXYG",
	"DEFAULT_PT_INWR",
	"DEFAULT_PT_YEST",
	"DEFAULT_PT_DYST",
	"DEFAULT_PT_THRM",
	"DEFAULT_PT_GLOW",
	"DEFAULT_PT_BRCK",
	"DEFAULT_PT_HFLM",
	"DEFAULT_PT_CFLM",
	"DEFAULT_PT_FIRW",
	"DEFAULT_PT_FUSE",
	"DEFAULT_PT_FSEP",
	"DEFAULT_PT_AMTR",
	"DEFAULT_PT_BCOL",
	"DEFAULT_PT_PCLN",
	"DEFAULT_PT_HSWC",
	"DEFAULT_PT_IRON",
	"DEFAULT_PT_MORT",
	"DEFAULT_PT_LIFE",
	"DEFAULT_PT_DLAY",
	"DEFAULT_PT_CO2",
	"DEFAULT_PT_DRIC",
	"DEFAULT_PT_BUBW",
	"DEFAULT_PT_CBNW",
	"DEFAULT_PT_STOR",
	"DEFAULT_PT_PVOD",
	"DEFAULT_PT_CONV",
	"DEFAULT_PT_CAUS",
	"DEFAULT_PT_LIGH",
	"DEFAULT_PT_TESC",
	"DEFAULT_PT_DEST",
	"DEFAULT_PT_SPNG",
	"DEFAULT_PT_RIME",
	"DEFAULT_PT_FOG",
	"DEFAULT_PT_BCLN",
	"DEFAULT_PT_LOVE",
	"DEFAULT_PT_DEUT",
	"DEFAULT_PT_WARP",
	"DEFAULT_PT_PUMP",
	"DEFAULT_PT_FWRK",
	"DEFAULT_PT_PIPE",
	"DEFAULT_PT_FRZZ",
	"DEFAULT_PT_FRZW",
	"DEFAULT_PT_GRAV",
	"DEFAULT_PT_BIZR",
	"DEFAULT_PT_BIZG",
	"DEFAULT_PT_BIZRG",
	"DEFAULT_PT_BIZRS",
	"DEFAULT_PT_BIZS",
	"DEFAULT_PT_INST",
	"DEFAULT_PT_ISOZ",
	"DEFAULT_PT_ISZS",
	"DEFAULT_PT_PRTI",
	"DEFAULT_PT_PRTO",
	"DEFAULT_PT_PSTE",
	"DEFAULT_PT_PSTS",
	"DEFAULT_PT_ANAR",
	"DEFAULT_PT_VINE",
	"DEFAULT_PT_INVIS",
	"DEFAULT_PT_INVS",
	"DEFAULT_PT_116",
	"DEFAULT_PT_EQVE",
	"DEFAULT_PT_SPAWN2",
	"DEFAULT_PT_SPWN2",
	"DEFAULT_PT_SPWN",
	"DEFAULT_PT_SPAWN",
	"DEFAULT_PT_SHLD",
	"DEFAULT_PT_SHLD1",
	"DEFAULT_PT_SHLD2",
	"DEFAULT_PT_SHD2",
	"DEFAULT_PT_SHD3",
	"DEFAULT_PT_SHLD3",
	"DEFAULT_PT_SHLD4",
	"DEFAULT_PT_SHD4",
	"DEFAULT_PT_LOLZ",
	"DEFAULT_PT_WIFI",
	"DEFAULT_PT_FILT",
	"DEFAULT_PT_ARAY",
	"DEFAULT_PT_BRAY",
	"DEFAULT_PT_STKM2",
	"DEFAULT_PT_STK2",
	"DEFAULT_PT_BOMB",
	"DEFAULT_PT_C5",
	"DEFAULT_PT_C-5",
	"DEFAULT_PT_SING",
	"DEFAULT_PT_QRTZ",
	"DEFAULT_PT_PQRT",
	"DEFAULT_PT_EMP",
	"DEFAULT_PT_BREC",
	"DEFAULT_PT_BREL",
	"DEFAULT_PT_ELEC",
	"DEFAULT_PT_ACEL",
	"DEFAULT_PT_DCEL",
	"DEFAULT_PT_TNT",
	"DEFAULT_PT_BANG",
	"DEFAULT_PT_IGNT",
	"DEFAULT_PT_IGNC",
	"DEFAULT_PT_BOYL",
	"DEFAULT_PT_GEL",
	"DEFAULT_PT_TRON",
	"DEFAULT_PT_TTAN",
	"DEFAULT_PT_EXOT",
	"DEFAULT_PT_EMBR",
	"DEFAULT_PT_HYGN",
	"DEFAULT_PT_H2",
	"DEFAULT_PT_SOAP",
	"DEFAULT_PT_NBHL",
	"DEFAULT_PT_NWHL",
	"DEFAULT_PT_MERC",
	"DEFAULT_PT_PBCN",
	"DEFAULT_PT_GPMP",
	"DEFAULT_PT_CLST",
	"DEFAULT_PT_WWLD",
	"DEFAULT_PT_WIRE",
	"DEFAULT_PT_GBMB",
	"DEFAULT_PT_FIGH",
	"DEFAULT_PT_FRAY",
	"DEFAULT_PT_RPEL",
	"DEFAULT_PT_PPIP",
	"DEFAULT_PT_DTEC",
	"DEFAULT_PT_DMG",
	"DEFAULT_PT_TSNS",
	"DEFAULT_PT_VIBR",
	"DEFAULT_PT_BVBR",
	"DEFAULT_PT_CRAY",
	"DEFAULT_PT_PSTN",
	"DEFAULT_PT_FRME",
	"DEFAULT_PT_GOLD",
	"DEFAULT_PT_TUNG",
	"DEFAULT_PT_PSNS",
	"DEFAULT_PT_PROT",
	"DEFAULT_PT_VIRS",
	"DEFAULT_PT_VRSS",
	"DEFAULT_PT_VRSG",
	"DEFAULT_PT_GRVT",
	"DEFAULT_PT_DRAY",
	"DEFAULT_PT_CRMC",
	"DEFAULT_PT_HEAC",
	"DEFAULT_PT_SAWD",
	"DEFAULT_PT_POLO",
	"DEFAULT_PT_RFRG",
	"DEFAULT_PT_RFGL",
	"DEFAULT_PT_LSNS",
	"DEFAULT_PT_LDTC",
	"DEFAULT_PT_SLCN",
	"DEFAULT_PT_PTNM",
	"DEFAULT_PT_VSNS",
	"DEFAULT_PT_ROCK",
	"DEFAULT_PT_LITH",
})
for key, value in pairs(elem) do
	if known_elements[key] then
		from_tool[key] = value
		to_tool[value] = key
	end
end
local unknown_xid = 0x3FFF
assert(not to_tool[unknown_xid])
from_tool["UNKNOWN"] = unknown_xid
to_tool[unknown_xid] = "UNKNOWN"

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
	[ from_tool.DEFAULT_UI_PROPERTY ] = true,
	[ from_tool.DEFAULT_UI_SAMPLE   ] = true,
	[ from_tool.DEFAULT_UI_SIGN     ] = true,
	[ from_tool.UNKNOWN             ] = true,
}
local line_only = {
	[ from_tool.DEFAULT_UI_WIND ] = true,
}

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
	local handle = io.open(config.stamp_temp, "wb")
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
	local ok, err = sim.loadStamp(config.stamp_temp, x, y)
	if not ok then
		os.remove(config.stamp_temp)
		if err then
			return nil, "cannot load stamp data: " .. err
		else
			return nil, "cannot load stamp data"
		end
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
		xtype = bit.bor(elem.DEFAULT_PT_LIFE, bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS))
	elseif type(xtype) == "table" and xtype.type == "cgol" then
		-- * TODO[api]: add an api for setting gol colour
		xtype = xtype.elem
	end
	local ov = create_override[xtype]
	if ov then
		rx, ry, xtype = ov(rx, ry, xtype)
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = to_tool[member.tool_x] or "DEFAULT_PT_NONE"
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
				tpt.set_wallmap(x, y, 1, 1, fvx, fvy, WL_FAN)
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
		xtype = bit.bor(elem.DEFAULT_PT_LIFE, bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS))
	elseif type(xtype) == "table" and xtype.type == "cgol" then
		-- * TODO[api]: add an api for setting gol colour
		xtype = xtype.elem
	end
	local ov = create_override[xtype]
	if ov then
		rx, ry, xtype = ov(rx, ry, xtype)
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = to_tool[member.tool_x] or "DEFAULT_PT_NONE"
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
		xtype = bit.bor(elem.DEFAULT_PT_LIFE, bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS))
	elseif type(xtype) == "table" and xtype.type == "cgol" then
		-- * TODO[api]: add an api for setting gol colour
		xtype = xtype.elem
	end
	local _
	local ov = create_override[xtype]
	if ov then
		_, _, xtype = ov(member.size_x, member.size_y, xtype)
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = to_tool[member.tool_x] or "DEFAULT_PT_NONE"
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
		xtype = bit.bor(elem.DEFAULT_PT_LIFE, bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS))
	elseif type(xtype) == "table" and xtype.type == "cgol" then
		-- * TODO[api]: add an api for setting gol colour
		xtype = xtype.elem
	end
	local _
	local ov = create_override[xtype]
	if ov then
		_, _, xtype = ov(member.size_x, member.size_y, xtype)
	end
	local selectedreplace
	if member.bmode ~= 0 then
		selectedreplace = tpt.selectedreplace
		tpt.selectedreplace = to_tool[member.tool_x] or "DEFAULT_PT_NONE"
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
		return math.floor(sim.ambientAirTemp() * 0x400)
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
	fnv1a32 = fnv1a32,
	ambient_air_temp = ambient_air_temp,
	get_save_id = get_save_id,
	version_less = common_util.version_less,
	version_equal = common_util.version_equal,
	tpt_version = tpt_version,
	urlencode = urlencode,
	heat_clear = heat_clear,
	unknown_xid = unknown_xid,
}
