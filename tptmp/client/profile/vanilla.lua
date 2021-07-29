local util   = require("tptmp.client.util")
local config = require("tptmp.client.config")
local sdl    = require("tptmp.client.sdl")

local profile_i = {}
local profile_m = { __index = profile_i }

local index_to_lrax = {
	[ 0 ] = "tool_l_",
	[ 1 ] = "tool_r_",
	[ 2 ] = "tool_a_",
	[ 3 ] = "tool_x_",
}
local index_to_lraxid = {
	[ 0 ] = "tool_lid_",
	[ 1 ] = "tool_rid_",
	[ 2 ] = "tool_aid_",
	[ 3 ] = "tool_xid_",
}
local toolwarn_tools = {
	[ "DEFAULT_UI_PROPERTY" ] = "prop",
	[ "DEFAULT_TOOL_MIX"    ] = "mix",
	[ "DEFAULT_PT_LIGH"     ] = "ligh",
	[ "DEFAULT_PT_STKM"     ] = "stkm",
	[ "DEFAULT_PT_STKM2"    ] = "stkm",
	[ "DEFAULT_PT_SPAWN"    ] = "stkm",
	[ "DEFAULT_PT_SPAWN2"   ] = "stkm",
	[ "DEFAULT_PT_FIGH"     ] = "stkm",
	[ "TPTMP_PT_UNKNOWN"    ] = "unknown",
}
local toolwarn_messages = {
	prop      =                      "The PROP tool does not sync, you will have to use /sync",
	mix       =                       "The MIX tool does not sync, you will have to use /sync",
	ligh      =                               "LIGH does not sync, you will have to use /sync",
	stkm      =                             "Stickmen do not sync, you will have to use /sync",
	cbrush    =                       "Custom brushes do not sync, you will have to use /sync",
	ipcirc    =               "The old circle brush does not sync, you will have to use /sync",
	unknown   =  "This custom element is not supported, please avoid using it while connected",
	cgol      = "This custom GOL type is not supported, please avoid using it while connected",
	cgolcolor =  "Custom GOL currently syncs without colours, use /sync to get colours across",
}

local log_event = print

local BRUSH_COUNT = 3
local MOUSEUP_REASON_MOUSEUP = 0
local MOUSEUP_REASON_BLUR    = 1
local MAX_SIGNS = 0
while sim.signs[MAX_SIGNS + 1] do
	MAX_SIGNS = MAX_SIGNS + 1
end

local function rulestring_bits(str)
	local bits = 0
	for i = 1, #str do
		bits = bit.bor(bits, bit.lshift(1, str:byte(i) - 48))
	end
	return bits
end

local function get_custgolinfo(identifier)
	-- * TODO[api]: add an api for this to tpt
	local pref = io.open("powder.pref")
	if not pref then
		return
	end
	local pref_data = pref:read("*a")
	pref:close()
	local types = pref_data:match([=["Types"%s*:%s*%[([^%]]+)%]]=])
	if not types then
		return
	end
	for name, ruleset, primary, secondary in types:gmatch([["(%S+)%s+(%S+)%s+(%S+)%s+(%S+)"]]) do
		if "DEFAULT_PT_LIFECUST_" .. name == identifier then
			local begin, stay, states = ruleset:match("^B([1-8]+)/S([0-8]+)/([0-9]+)$")
			if not begin then
				begin, stay = ruleset:match("^B([1-8]+)/S([0-8]+)$")
				states = "2"
			end
			states = tonumber(states)
			states = states >= 2 and states <= 17 and states
			ruleset = begin and stay and states and bit.bor(bit.lshift(rulestring_bits(begin), 8), rulestring_bits(stay), bit.lshift(states - 2, 17))
			primary = tonumber(primary)
			secondary = tonumber(secondary)
			if ruleset and primary and secondary then
				return ruleset, primary, secondary
			end
			break
		end
	end
end

local function get_sign_data()
	local sign_data = {}
	for i = 1, MAX_SIGNS do
		local text = sim.signs[i].text
		if text then
			sign_data[i] = {
				tx = text,
				ju = sim.signs[i].justification,
				px = sim.signs[i].x,
				py = sim.signs[i].y,
			}
		end
	end
	return sign_data
end

local function perfect_circle()
	return sim.brush(1, 1, 1, 1, 0)() == 0
end

local props = {}
for key, value in pairs(sim) do
	if key:find("^FIELD_") and key ~= "FIELD_TYPE" then
		table.insert(props, value)
	end
end

local function save_and_kill_zero()
	local zero = { [ sim.FIELD_TYPE ] = sim.partProperty(0, "type") }
	for _, v in ipairs(props) do
		zero[v] = sim.partProperty(0, v)
	end
	sim.partKill(0)
	return zero
end

local function restore_zero(zero)
	if sim.partCreate(-3, 0, 0, 1) ~= 0 then
		error("something is very wrong")
	end
	sim.partProperty(0, "type", zero[sim.FIELD_TYPE])
	for _, v in ipairs(props) do
		sim.partProperty(0, v, zero[v])
	end
end

local function brush_mode()
	-- * TODO[api]: add an api for this to tpt
	local id = sim.partCreate(-3, 0, 0, elem.DEFAULT_PT_ELEC)
	local zero
	local bmode = 0
	if id == -1 then
		zero = save_and_kill_zero()
		id = sim.partCreate(-3, 0, 0, elem.DEFAULT_PT_ELEC)
		if id ~= 0 then
			restore_zero(zero)
			error("something is very wrong")
		end
	end
	local selectedreplace = tpt.selectedreplace
	tpt.selectedreplace = "DEFAULT_PT_ELEC"
	sim.createParts(0, 0, 0, 0, elem.DEFAULT_PT_PROT, 0)
	local new_type = sim.partProperty(id, "type")
	if not new_type then
		bmode = 2
	elseif new_type == elem.DEFAULT_PT_PROT then
		bmode = 1
	end
	tpt.selectedreplace = selectedreplace
	if new_type then
		sim.partKill(id)
	end
	if zero then
		restore_zero(zero)
	end
	return bmode
end

local function in_zoom_window(x, y)
	local ax, ay = sim.adjustCoords(x, y)
	return ren.zoomEnabled() and (ax ~= x or ay ~= y)
end

function profile_i:report_loadonline_(id, hist)
	if self.client then
		self.client:send_loadonline(id, hist)
	end
end

function profile_i:report_pos_()
	if self.client then
		self.client:send_mousepos(self.pos_x_, self.pos_y_)
	end
end

function profile_i:report_size_()
	if self.client then
		self.client:send_brushsize(self.size_x_, self.size_y_)
	end
end

function profile_i:report_zoom_()
	if self.client then
		if self.zenabled_ then
			self.client:send_zoomstart(self.zcx_, self.zcy_, self.zsize_)
		else
			self.client:send_zoomend()
		end
	end
end

function profile_i:report_bmode_()
	if self.client then
		self.client:send_brushmode(self.bmode_)
	end
end

function profile_i:report_shape_()
	if self.client then
		self.client:send_brushshape(self.shape_ < BRUSH_COUNT and self.shape_ or 0)
	end
end

function profile_i:report_sparksign_(x, y)
	if self.client then
		self.client:send_sparksign(x, y)
	end
end

function profile_i:report_flood_(i, x, y)
	if self.client then
		self.client:send_flood(i, x, y)
	end
end

function profile_i:report_lineend_(x, y)
	self.lss_i_ = nil
	if self.client then
		self.client:send_lineend(x, y)
	end
end

function profile_i:report_rectend_(x, y)
	self.rss_i_ = nil
	if self.client then
		self.client:send_rectend(x, y)
	end
end

function profile_i:sync_linestart_(i, x, y)
	if self.client and self.lss_i_ then
		self.client:send_linestart(self.lss_i_, self.lss_x_, self.lss_y_)
	end
end

function profile_i:report_linestart_(i, x, y)
	self.lss_i_ = i
	self.lss_x_ = x
	self.lss_y_ = y
	if self.client then
		self.client:send_linestart(i, x, y)
	end
end

function profile_i:sync_rectstart_(i, x, y)
	if self.client and self.rss_i_ then
		self.client:send_rectstart(self.rss_i_, self.rss_x_, self.rss_y_)
	end
end

function profile_i:report_rectstart_(i, x, y)
	self.rss_i_ = i
	self.rss_x_ = x
	self.rss_y_ = y
	if self.client then
		self.client:send_rectstart(i, x, y)
	end
end

function profile_i:sync_pointsstart_()
	if self.client and self.pts_i_ then
		self.client:send_pointsstart(self.pts_i_, self.pts_x_, self.pts_y_)
	end
end

function profile_i:report_pointsstart_(i, x, y)
	self.pts_i_ = i
	self.pts_x_ = x
	self.pts_y_ = y
	if self.client then
		self.client:send_pointsstart(i, x, y)
	end
end

function profile_i:report_pointscont_(x, y, done)
	if self.client then
		self.client:send_pointscont(x, y)
	end
	self.pts_x_ = x
	self.pts_y_ = y
	if done then
		self.pts_i_ = nil
	end
end

function profile_i:report_kmod_()
	if self.client then
		self.client:send_keybdmod(self.kmod_c_, self.kmod_s_, self.kmod_a_)
	end
end

function profile_i:report_framestep_()
	if self.client then
		self.client:send_stepsim()
	end
end

function profile_i:report_airinvert_()
	if self.client then
		self.client:send_airinv()
	end
end

function profile_i:report_reset_spark_()
	if self.client then
		self.client:send_sparkclear()
	end
end

function profile_i:report_reset_air_()
	if self.client then
		self.client:send_airclear()
	end
end

function profile_i:report_reset_airtemp_()
	if self.client then
		self.client:send_heatclear()
	end
end

function profile_i:report_clearrect_(x, y, w, h)
	if self.client then
		self.client:send_clearrect(x, y, w, h)
	end
end

function profile_i:report_clearsim_()
	if self.client then
		self.client:send_clearsim()
	end
end

function profile_i:report_reloadsim_()
	if self.client then
		self.client:send_reloadsim()
	end
end

function profile_i:simstate_sync()
	if self.client then
		self.client:send_simstate(self.ss_p_, self.ss_h_, self.ss_u_, self.ss_n_, self.ss_w_, self.ss_g_, self.ss_a_, self.ss_e_, self.ss_y_, self.ss_t_)
	end
end

function profile_i:report_tool_(index)
	if self.client then
		self.client:send_selecttool(index, self[index_to_lrax[index]])
		local identifier = self[index_to_lraxid[index]]
		if identifier:find("^DEFAULT_PT_LIFECUST_") then
			local ruleset, primary, secondary = get_custgolinfo(identifier)
			if ruleset then
				self.client:send_custgolinfo(ruleset, primary, secondary)
				-- * TODO[api]: add an api for setting gol colour
				self.display_toolwarn_["cgolcolor"] = true
			else
				self.display_toolwarn_["cgol"] = true
			end
		end
	end
end

function profile_i:report_deco_()
	if self.client then
		self.client:send_brushdeco(self.deco_)
	end
end

function profile_i:sync_placestatus_()
	if self.client and self.pes_k_ ~= 0 then
		self.client:send_placestatus(self.pes_k_, self.pes_w_, self.pes_h_)
	end
end

function profile_i:report_placestatus_(k, w, h)
	self.pes_k_ = k
	self.pes_w_ = w
	self.pes_h_ = h
	if self.client then
		self.client:send_placestatus(k, w, h)
	end
end

function profile_i:sync_selectstatus_()
	if self.client and self.sts_k_ ~= 0 then
		self.client:send_selectstatus(self.sts_k_, self.sts_x_, self.sts_y_)
	end
end

function profile_i:report_selectstatus_(k, x, y)
	self.sts_k_ = k
	self.sts_x_ = x
	self.sts_y_ = y
	if self.client then
		self.client:send_selectstatus(k, x, y)
	end
end

function profile_i:report_pastestamp_(x, y, w, h)
	if self.client then
		self.client:send_pastestamp(x, y, w, h)
	end
end

function profile_i:report_canceldraw_()
	if self.client then
		self.client:send_canceldraw()
	end
end

function profile_i:get_stamp_size_()
	local stampsdef = io.open("stamps/stamps.def", "rb")
	if not stampsdef then
		return
	end
	local name = stampsdef:read(10)
	stampsdef:close()
	if type(name) ~= "string" or #name ~= 10 then
		return
	end
	local stamp = io.open("stamps/" .. name .. ".stm", "rb")
	if not stamp then
		return
	end
	local header = stamp:read(12)
	stamp:close()
	if type(header) ~= "string" or #header ~= 12 then
		return
	end
	local bw, bh = header:byte(7, 8) -- * Works for OPS and PSv too.
	return bw * 4, bh * 4
end

function profile_i:user_sync()
	self:report_size_()
	self:report_tool_(0)
	self:report_tool_(1)
	self:report_tool_(2)
	self:report_tool_(3)
	self:report_deco_()
	self:report_bmode_()
	self:report_shape_()
	self:report_kmod_()
	self:report_pos_()
	self:sync_pointsstart_()
	self:sync_placestatus_()
	self:sync_selectstatus_()
	self:sync_linestart_()
	self:sync_rectstart_()
	self:report_zoom_()
end

function profile_i:post_event_check_()
	if self.placesave_size_ then
		local x1, y1, x2, y2 = self:end_placesave_size_()
		if x1 then
			local x, y, w, h = util.corners_to_rect(x1, y1, x2, y2)
			self.simstate_invalid_ = true
			if self.placesave_open_ then
				local id, hist = util.get_save_id()
				self.set_id_func_(id, hist)
				if id then
					self:report_loadonline_(id, hist)
				else
					self:report_pastestamp_(x, y, w, h)
				end
			elseif self.placesave_reload_ then
				if not self.get_id_func_() then
					self:report_pastestamp_(x, y, w, h)
				end
				self:report_reloadsim_()
			elseif self.placesave_clear_ then
				self.set_id_func_(nil, nil)
				self:report_clearsim_()
			else
				self:report_pastestamp_(x, y, w, h)
			end
		end
		self.placesave_open_ = nil
		self.placesave_reload_ = nil
		self.placesave_clear_ = nil
	end
	if self.zoom_invalid_ then
		self.zoom_invalid_ = nil
		self:update_zoom_()
	end
	if self.simstate_invalid_ then
		self.simstate_invalid_ = nil
		self:check_simstate()
	end
	if self.bmode_invalid_ then
		self.bmode_invalid_ = nil
		self:update_bmode_()
	end
	self:update_size_()
	self:update_shape_()
	self:update_tools_()
	self:update_deco_()
end

function profile_i:sample_simstate()
	local ss_p = tpt.set_pause()
	local ss_h = tpt.heat()
	local ss_u = tpt.ambient_heat()
	local ss_n = tpt.newtonian_gravity()
	local ss_w = sim.waterEqualisation()
	local ss_g = sim.gravityMode()
	local ss_a = sim.airMode()
	local ss_e = sim.edgeMode()
	local ss_y = sim.prettyPowders()
	local ss_t = util.ambient_air_temp()
	if self.ss_p_ ~= ss_p or
	   self.ss_h_ ~= ss_h or
	   self.ss_u_ ~= ss_u or
	   self.ss_n_ ~= ss_n or
	   self.ss_w_ ~= ss_w or
	   self.ss_g_ ~= ss_g or
	   self.ss_a_ ~= ss_a or
	   self.ss_e_ ~= ss_e or
	   self.ss_y_ ~= ss_y or
	   self.ss_t_ ~= ss_t then
		self.ss_p_ = ss_p
		self.ss_h_ = ss_h
		self.ss_u_ = ss_u
		self.ss_n_ = ss_n
		self.ss_w_ = ss_w
		self.ss_g_ = ss_g
		self.ss_a_ = ss_a
		self.ss_e_ = ss_e
		self.ss_y_ = ss_y
		self.ss_t_ = ss_t
		return true
	end
	return false
end

function profile_i:check_signs(old_data)
	local new_data = get_sign_data()
	local bw = sim.XRES / 4
	local to_send = {}
	local function key(x, y)
		return math.floor(x / 4) + math.floor(y / 4) * bw
	end
	for i = 1, MAX_SIGNS do
		if old_data[i] and new_data[i] then
			if old_data[i].ju ~= new_data[i].ju or
			   old_data[i].tx ~= new_data[i].tx or
			   old_data[i].px ~= new_data[i].px or
			   old_data[i].py ~= new_data[i].py then
				to_send[key(old_data[i].px, old_data[i].py)] = true
				to_send[key(new_data[i].px, new_data[i].py)] = true
			end
		elseif old_data[i] then
			to_send[key(old_data[i].px, old_data[i].py)] = true
		elseif new_data[i] then
			to_send[key(new_data[i].px, new_data[i].py)] = true
		end
	end
	for k in pairs(to_send) do
		local x, y, w, h = k % bw * 4, math.floor(k / bw) * 4, 4, 4
		self:report_clearrect_(x, y, w, h)
		self:report_pastestamp_(x, y, w, h)
	end
end

function profile_i:check_simstate()
	if self:sample_simstate() then
		self:simstate_sync()
	end
end

function profile_i:update_draw_mode_()
	if self.kmod_c_ and self.kmod_s_ then
		if util.xid_class[self[index_to_lrax[self.last_toolslot_]]] == "TOOL" then
			self.draw_mode_ = "points"
		else
			self.draw_mode_ = "flood"
		end
	elseif self.kmod_c_ then
		self.draw_mode_ = "rect"
	elseif self.kmod_s_ then
		self.draw_mode_ = "line"
	else
		self.draw_mode_ = "points"
	end
end

function profile_i:enable_shift_()
	self.kmod_changed_ = true
	self.kmod_s_ = true
	if not self.dragging_mouse_ or self.select_mode_ ~= "none" then
		self:update_draw_mode_()
	end
end

function profile_i:enable_ctrl_()
	self.kmod_changed_ = true
	self.kmod_c_ = true
	if not self.dragging_mouse_ or self.select_mode_ ~= "none" then
		self:update_draw_mode_()
	end
end

function profile_i:enable_alt_()
	self.kmod_changed_ = true
	self.kmod_a_ = true
end

function profile_i:disable_shift_()
	self.kmod_changed_ = true
	self.kmod_s_ = false
	if not self.dragging_mouse_ or self.select_mode_ ~= "none" then
		self:update_draw_mode_()
	end
end

function profile_i:disable_ctrl_()
	self.kmod_changed_ = true
	self.kmod_c_ = false
	if not self.dragging_mouse_ or self.select_mode_ ~= "none" then
		self:update_draw_mode_()
	end
end

function profile_i:disable_alt_()
	self.kmod_changed_ = true
	self.kmod_a_ = false
end

function profile_i:update_pos_(x, y)
	x, y = sim.adjustCoords(x, y)
	if x < 0         then x = 0            end
	if x >= sim.XRES then x = sim.XRES - 1 end
	if y < 0         then y = 0            end
	if y >= sim.YRES then y = sim.YRES - 1 end
	if self.pos_x_ ~= x or self.pos_y_ ~= y then
		self.pos_x_ = x
		self.pos_y_ = y
		self:report_pos_(self.pos_x_, self.pos_y_)
	end
end

function profile_i:update_size_()
	local x, y = tpt.brushx, tpt.brushy
	if x < 0   then x = 0   end
	if x > 255 then x = 255 end
	if y < 0   then y = 0   end
	if y > 255 then y = 255 end
	if self.size_x_ ~= x or self.size_y_ ~= y then
		self.size_x_ = x
		self.size_y_ = y
		self:report_size_(self.size_x_, self.size_y_)
	end
end

function profile_i:update_zoom_()
	local zenabled = ren.zoomEnabled()
	local zcx, zcy, zsize = ren.zoomScope()
	if self.zenabled_ ~= zenabled or self.zcx_ ~= zcx or self.zcy_ ~= zcy or self.zsize_ ~= zsize then
		self.zenabled_ = zenabled
		self.zcx_ = zcx
		self.zcy_ = zcy
		self.zsize_ = zsize
		self:report_zoom_()
	end
end

function profile_i:update_bmode_()
	local bmode = brush_mode()
	if self.bmode_ ~= bmode then
		self.bmode_ = bmode
		self:report_bmode_()
	end
end

function profile_i:update_shape_()
	local pcirc = self.perfect_circle_
	if self.perfect_circle_invalid_ then
		pcirc = perfect_circle()
	end
	local shape = tpt.brushID
	if self.shape_ ~= shape or self.perfect_circle_ ~= pcirc then
		local old_cbrush = self.cbrush_
		self.cbrush_ = shape >= BRUSH_COUNT or nil
		if not old_cbrush and self.cbrush_ then
			self.display_toolwarn_["cbrush"] = true
		end
		local old_ipcirc = self.ipcirc_
		self.ipcirc_ = shape == 0 and not pcirc
		if not old_ipcirc and self.ipcirc_ then
			self.display_toolwarn_["ipcirc"] = true
		end
		self.shape_ = shape
		self.perfect_circle_ = pcirc
		self:report_shape_()
	end
end

function profile_i:update_tools_()
	local tlid = tpt.selectedl
	local trid = tpt.selectedr
	local taid = tpt.selecteda
	local txid = tpt.selectedreplace
	if self.tool_lid_ ~= tlid then
		self.tool_l_ = util.from_tool[tlid] or util.from_tool.TPTMP_PT_UNKNOWN
		self.tool_lid_ = tlid
		self:report_tool_(0)
	end
	if self.tool_rid_ ~= trid then
		self.tool_r_ = util.from_tool[trid] or util.from_tool.TPTMP_PT_UNKNOWN
		self.tool_rid_ = trid
		self:report_tool_(1)
	end
	if self.tool_aid_ ~= taid then
		self.tool_a_ = util.from_tool[taid] or util.from_tool.TPTMP_PT_UNKNOWN
		self.tool_aid_ = taid
		self:report_tool_(2)
	end
	if self.tool_xid_ ~= txid then
		self.tool_x_ = util.from_tool[txid] or util.from_tool.TPTMP_PT_UNKNOWN
		self.tool_xid_ = txid
		self:report_tool_(3)
	end
	local new_tool = util.to_tool[self[index_to_lrax[self.last_toolslot_]]]
	local new_tool_id = self[index_to_lraxid[self.last_toolslot_]]
	if self.last_tool_ ~= new_tool then
		if not new_tool_id:find("^DEFAULT_PT_LIFECUST_") then
			if toolwarn_tools[new_tool] then
				self.display_toolwarn_[toolwarn_tools[new_tool]] = true
			end
		end
		self.last_tool_ = new_tool
	end
end

function profile_i:update_kmod_()
	if self.kmod_changed_ then
		self.kmod_changed_ = nil
		self:report_kmod_()
	end
end

function profile_i:update_deco_()
	local deco = sim.decoColour()
	if self.deco_ ~= deco then
		self.deco_ = deco
		self:report_deco_()
	end
end

local preshack_prof
local preshack_elem
local preshack_zero
local function preshack_graphics(i)
	preshack_prof:post_event_check_()
	sim.partKill(i)
	if preshack_zero then
		restore_zero(preshack_zero)
		preshack_zero = nil
	end
	return 0, 0
end

function profile_i:begin_placesave_size_(x, y, defer)
	local id = sim.partCreate(-3, 0, 0, preshack_elem)
	if id == -1 then
		preshack_zero = save_and_kill_zero()
		id = sim.partCreate(-3, 0, 0, preshack_elem)
		if id ~= 0 then
			restore_zero(preshack_zero)
			error("something is very wrong")
		end
	end
	local bx, by = math.floor(x / 4), math.floor(y / 4)
	local p = 0
	local pres = {}
	local function push(x, y)
		p = p + 2
		local pr = sim.pressure(x, y)
		if pr >  256 then pr =  256 end
		if pr < -256 then pr = -256 end
		local st = (math.floor(pr * 0x10) * 0x1000 + math.random(0x000, 0xFFF)) / 0x10000
		pres[p - 1] = pr
		pres[p] = st
		sim.pressure(x, y, st)
	end
	for x = 0, sim.XRES / 4 - 1 do
		push(x, by)
	end
	for y = 0, sim.YRES / 4 - 1 do
		if y ~= by then
			push(bx, y)
		end
	end
	local pss = {
		pres = pres,
		bx = bx,
		by = by,
		airmode = sim.airMode(),
	}
	if defer then
		self.placesave_size_next_ = pss
	else
		self.placesave_size_ = pss
	end
	sim.airMode(4)
end

function profile_i:end_placesave_size_()
	local bx, by = self.placesave_size_.bx, self.placesave_size_.by
	local pres = self.placesave_size_.pres
	local p = 0
	local lx, ly, hx, hy = math.huge, math.huge, -math.huge, -math.huge
	local function pop(x, y)
		p = p + 2
		if sim.pressure(x, y) == pres[p] then
			sim.pressure(x, y, pres[p - 1])
		else
			lx = math.min(lx, x)
			ly = math.min(ly, y)
			hx = math.max(hx, x)
			hy = math.max(hy, y)
		end
	end
	for x = 0, sim.XRES / 4 - 1 do
		pop(x, by)
	end
	for y = 0, sim.YRES / 4 - 1 do
		if y ~= by then
			pop(bx, y)
		end
	end
	local partcount = self.placesave_size_.partcount
	sim.airMode(self.placesave_size_.airmode)
	self.placesave_size_ = nil
	if lx == math.huge then
		self.placesave_postmsg_ = {
			message = "If you just pasted something, you will have to use /sync",
		}
	else
		return math.max((lx - 2) * 4, 0),
		       math.max((ly - 2) * 4, 0),
		       math.min((hx + 2) * 4, sim.XRES) - 1,
		       math.min((hy + 2) * 4, sim.YRES) - 1
	end
end

function profile_i:handle_tick()
	self:post_event_check_()
	if self.want_stamp_size_ then
		self.want_stamp_size_ = nil
		local w, h = self:get_stamp_size_()
		if w then
			self.place_x_, self.place_y_ = w, h
		end
	end
	if self.signs_invalid_ then
		local sign_data = self.signs_invalid_
		self.signs_invalid_ = nil
		self:check_signs(sign_data)
	end
	self:update_pos_(tpt.mousex, tpt.mousey)
	-- * Here the assumption is made that no Lua hook cancels the tick event.
	if self.placing_zoom_ then
		self.zoom_invalid_ = true
	end
	if self.skip_draw_ then
		self.skip_draw_ = nil
	else
		if self.select_mode_ == "none" and self.dragging_mouse_ then
			if self.draw_mode_ == "flood" then
				self:report_flood_(self.last_toolslot_, self.pos_x_, self.pos_y_)
			end
			if self.draw_mode_ == "points" then
				self:report_pointscont_(self.pos_x_, self.pos_y_)
			end
		end
	end
	if self.simstate_invalid_next_ then
		self.simstate_invalid_next_ = nil
		self.simstate_invalid_ = true
	end
	if self.placesave_size_next_ then
		self.placesave_size_ = self.placesave_size_next_
		self.placesave_size_next_ = nil
	end
	local complete_select_mode = self.select_x_ and self.select_mode_
	if self.prev_select_mode_ ~= complete_select_mode then
		self.prev_select_mode_ = complete_select_mode
		if self.select_mode_ == "copy"
		or self.select_mode_ == "cut"
		or self.select_mode_ == "stamp" then
			if self.select_mode_ == "copy" then
				self:report_selectstatus_(1, self.select_x_, self.select_y_)
			elseif self.select_mode_ == "cut" then
				self:report_selectstatus_(2, self.select_x_, self.select_y_)
			elseif self.select_mode_ == "stamp" then
				self:report_selectstatus_(3, self.select_x_, self.select_y_)
			end
		else
			self.select_x_, self.select_y_ = nil, nil
			self:report_selectstatus_(0, 0, 0)
		end
	end
	local complete_place_mode = self.place_x_ and self.select_mode_
	if self.prev_place_mode_ ~= complete_place_mode then
		self.prev_place_mode_ = complete_place_mode
		if self.select_mode_ == "place" then
			self:report_placestatus_(1, self.place_x_, self.place_y_)
		else
			self.place_x_, self.place_y_ = nil, nil
			self:report_placestatus_(0, 0, 0)
		end
	end
end

function profile_i:handle_mousedown(px, py, button)
	self:post_event_check_()
	if self.placesave_postmsg_ then
		self.placesave_postmsg_.partcount = sim.NUM_PARTS
	end
	self:update_pos_(px, py)
	self.last_in_zoom_window_ = in_zoom_window(px, py)
	-- * Here the assumption is made that no Lua hook cancels the mousedown event.
	if not self.kmod_c_ and not self.kmod_s_ and self.kmod_a_ and button == sdl.SDL_BUTTON_LEFT then
		button = 2
	end
	for _, btn in pairs(self.buttons_) do
		if util.inside_rect(btn.x, btn.y, btn.w, btn.h, tpt.mousex, tpt.mousey) then
			btn.active = true
		end
	end
	if not self.placing_zoom_ then
		if self.select_mode_ ~= "none" then
			self.sel_x1_ = self.pos_x_
			self.sel_y1_ = self.pos_y_
			self.sel_x2_ = self.pos_x_
			self.sel_y2_ = self.pos_y_
			self.dragging_mouse_ = true
			self.select_x_, self.select_y_ = self.pos_x_, self.pos_y_
			return
		end
		if px < sim.XRES and py < sim.YRES then
			if button == sdl.SDL_BUTTON_LEFT then
				self.last_toolslot_ = 0
			elseif button == sdl.SDL_BUTTON_MIDDLE then
				self.last_toolslot_ = 2
			elseif button == sdl.SDL_BUTTON_RIGHT then
				self.last_toolslot_ = 1
			else
				return
			end
			self:update_tools_()
			if next(self.display_toolwarn_) then
				if self.registered_func_() then
					for key in pairs(self.display_toolwarn_) do
						log_event(config.print_prefix .. toolwarn_messages[key])
					end
				end
				self.display_toolwarn_ = {}
			end
			self:update_draw_mode_()
			self.dragging_mouse_ = true
			if self.draw_mode_ == "rect" then
				self:report_rectstart_(self.last_toolslot_, self.pos_x_, self.pos_y_)
			end
			if self.draw_mode_ == "line" then
				self:report_linestart_(self.last_toolslot_, self.pos_x_, self.pos_y_)
			end
			if self.draw_mode_ == "flood" then
				if util.xid_class[self[index_to_lrax[self.last_toolslot_]]] == "DECOR" and self.registered_func_() then
					log_event(config.print_prefix .. "Decoration flooding does not sync, you will have to use /sync")
				end
				self:report_flood_(self.last_toolslot_, self.pos_x_, self.pos_y_)
			end
			if self.draw_mode_ == "points" then
				self:report_pointsstart_(self.last_toolslot_, self.pos_x_, self.pos_y_)
			end
		end
	end
end

function profile_i:cancel_drawing_()
	if self.dragging_mouse_ then
		self:report_canceldraw_()
		self.dragging_mouse_ = false
	end
end

function profile_i:handle_mousemove(px, py, delta_x, delta_y)
	self:post_event_check_()
	if self.placesave_postmsg_ then
		self.placesave_postmsg_.partcount = sim.NUM_PARTS
	end
	self:update_pos_(px, py)
	for _, btn in pairs(self.buttons_) do
		if not util.inside_rect(btn.x, btn.y, btn.w, btn.h, tpt.mousex, tpt.mousey) then
			btn.active = false
		end
	end
	-- * Here the assumption is made that no Lua hook cancels the mousemove event.
	if self.select_mode_ ~= "none" then
		if self.select_mode_ == "place" then
			self.sel_x1_ = self.pos_x_
			self.sel_y1_ = self.pos_y_
		end
		if self.sel_x1_ then
			self.sel_x2_ = self.pos_x_
			self.sel_y2_ = self.pos_y_
		end
	elseif self.dragging_mouse_ then
		local last = self.last_in_zoom_window_
		self.last_in_zoom_window_ = in_zoom_window(px, py)
		if last ~= self.last_in_zoom_window_ and (self.draw_mode_ == "flood" or self.draw_mode_ == "points") then
			self:cancel_drawing_()
			return
		end
		if self.draw_mode_ == "flood" then
			self:report_flood_(self.last_toolslot_, self.pos_x_, self.pos_y_)
			self.skip_draw_ = true
		end
		if self.draw_mode_ == "points" then
			self:report_pointscont_(self.pos_x_, self.pos_y_)
			self.skip_draw_ = true
		end
	end
end

function profile_i:handle_mouseup(px, py, button, reason)
	if self.placesave_postmsg_ then
		local partcount = self.placesave_postmsg_.partcount
		if partcount and partcount ~= sim.NUM_PARTS and self.registered_func_() then
			log_event(config.print_prefix .. self.placesave_postmsg_.message)
		end
		self.placesave_postmsg_ = nil
	end
	self:post_event_check_()
	self:update_pos_(px, py)
	for name, btn in pairs(self.buttons_) do
		if btn.active then
			self["button_" .. name .. "_"](self)
		end
		btn.active = false
	end
	-- * Here the assumption is made that no Lua hook cancels the mouseup event.
	if px >= sim.XRES or py >= sim.YRES then
		self.perfect_circle_invalid_ = true
		self.simstate_invalid_next_ = true
	end
	if reason == MOUSEUP_REASON_MOUSEUP and self[index_to_lrax[self.last_toolslot_]] ~= util.from_tool.DEFAULT_UI_SIGN or button ~= 1 then
		for i = 1, MAX_SIGNS do
			local x = sim.signs[i].screenX
			if x then
				local t = sim.signs[i].text
				local y = sim.signs[i].screenY
				local w = sim.signs[i].width + 1
				local h = sim.signs[i].height
				if util.inside_rect(x, y, w, h, self.pos_x_, self.pos_y_) and t:match("^{b|.*}$") then
					self:report_sparksign_(sim.signs[i].x, sim.signs[i].y)
				end
			end
		end
	end
	if self.placing_zoom_ then
		self.placing_zoom_ = false
		self.draw_mode_ = "points"
		self:cancel_drawing_()
	elseif self.dragging_mouse_ then
		if self.select_mode_ ~= "none" then
			if reason == MOUSEUP_REASON_MOUSEUP then
				local x, y, w, h = util.corners_to_rect(self.sel_x1_, self.sel_y1_, self.sel_x2_, self.sel_y2_)
				if self.select_mode_ == "place" then
					self:begin_placesave_size_(x, y)
				elseif self.select_mode_ == "copy" then
					self.clipsize_x_ = w
					self.clipsize_y_ = h
				elseif self.select_mode_ == "cut" then
					self.clipsize_x_ = w
					self.clipsize_y_ = h
					self:report_clearrect_(x, y, w, h)
				elseif self.select_mode_ == "stamp" then
					-- * Nothing.
				end
			end
			self.select_mode_ = "none"
			self:cancel_drawing_()
			return
		end
		if reason == MOUSEUP_REASON_MOUSEUP then
			if self.draw_mode_ == "rect" then
				self:report_rectend_(self.pos_x_, self.pos_y_)
			end
			if self.draw_mode_ == "line" then
				self:report_lineend_(self.pos_x_, self.pos_y_)
			end
			if self.draw_mode_ == "flood" then
				self:report_flood_(self.last_toolslot_, self.pos_x_, self.pos_y_)
			end
			if self.draw_mode_ == "points" then
				self:report_pointscont_(self.pos_x_, self.pos_y_, true)
			end
		end
		self:cancel_drawing_()
	elseif self.select_mode_ ~= "none" and button ~= 1 then
		if reason == MOUSEUP_REASON_MOUSEUP then
			self.select_mode_ = "none"
		end
	end
	self:update_draw_mode_()
end

function profile_i:handle_mousewheel(px, py, dir)
	self:post_event_check_()
	self:update_pos_(px, py)
	-- * Here the assumption is made that no Lua hook cancels the mousewheel event.
	if self.placing_zoom_ then
		self.zoom_invalid_ = true
	end
end

function profile_i:handle_keypress(key, scan, rep, shift, ctrl, alt)
	self:post_event_check_()
	if shift and not self.kmod_s_ then
		self:enable_shift_()
	end
	if ctrl and not self.kmod_c_ then
		self:enable_ctrl_()
	end
	if alt and not self.kmod_a_ then
		self:enable_alt_()
	end
	self:update_kmod_()
	-- * Here the assumption is made that no Lua hook cancels the keypress event.
	if not rep then
		if not self.stk2_out_ or ctrl then
			if scan == sdl.SDL_SCANCODE_W then
				self.simstate_invalid_ = true
			elseif scan == sdl.SDL_SCANCODE_S then
				self.select_mode_ = "stamp"
				self:cancel_drawing_()
			end
		end
	end
	-- * Here the assumption is made that no debug hook cancels the keypress event.
	if self.select_mode_ == "place" then
		-- * Note: Sadly, there's absolutely no way to know how these operations
		--         affect the save being placed, as it only grows if particles
		--         in it would go beyond its border.
		if key == sdl.SDLK_RIGHT then
			-- * Move. See note above.
			return
		elseif key == sdl.SDLK_LEFT then
			-- * Move. See note above.
			return
		elseif key == sdl.SDLK_DOWN then
			-- * Move. See note above.
			return
		elseif key == sdl.SDLK_UP then
			-- * Move. See note above.
			return
		elseif scan == sdl.SDL_SCANCODE_R and not rep then
			if ctrl and shift then
				-- * Rotate. See note above.
			elseif not ctrl and shift then
				-- * Rotate. See note above.
			else
				-- * Rotate. See note above.
			end
			return
		end
	end
	if rep then
		return
	end
	local did_shortcut = true
	if scan == sdl.SDL_SCANCODE_SPACE then
		self.simstate_invalid_ = true
	elseif scan == sdl.SDL_SCANCODE_GRAVE then
		if self.registered_func_() and not alt then
			log_event(config.print_prefix .. "The console is disabled because it does not sync (press the Alt key to override)")
			return true
		end
	elseif scan == sdl.SDL_SCANCODE_Z then
		if self.select_mode_ == "none" or not self.dragging_mouse_ then
			if ctrl and not self.dragging_mouse_ then
				if self.registered_func_() and not alt then
					log_event(config.print_prefix .. "Undo is disabled because it does not sync (press the Alt key to override)")
					return true
				end
			else
				self:cancel_drawing_()
				self.placing_zoom_ = true
				self.zoom_invalid_ = true
			end
		end
	elseif scan == sdl.SDL_SCANCODE_F5 or (ctrl and scan == sdl.SDL_SCANCODE_R) then
		self:button_reload_()
	elseif scan == sdl.SDL_SCANCODE_F and not ctrl then
		if ren.debugHUD() == 1 and (shift or alt) then
			if self.registered_func_() and not alt then
				log_event(config.print_prefix .. "Partial framesteps do not sync, you will have to use /sync")
			end
		end
		self:report_framestep_()
		self.simstate_invalid_ = true
	elseif scan == sdl.SDL_SCANCODE_B and not ctrl then
		self.simstate_invalid_ = true
	elseif scan == sdl.SDL_SCANCODE_Y then
		if ctrl then
			if self.registered_func_() and not alt then
				log_event(config.print_prefix .. "Redo is disabled because it does not sync (press the Alt key to override)")
				return true
			end
		else
			self.simstate_invalid_ = true
		end
	elseif scan == sdl.SDL_SCANCODE_U then
		if ctrl then
			self:report_reset_airtemp_()
		else
			self.simstate_invalid_ = true
		end
	elseif scan == sdl.SDL_SCANCODE_N then
		self.simstate_invalid_ = true
	elseif scan == sdl.SDL_SCANCODE_EQUALS then
		if ctrl then
			self:report_reset_spark_()
		else
			self:report_reset_air_()
		end
	elseif scan == sdl.SDL_SCANCODE_C and ctrl then
		self.select_mode_ = "copy"
		self:cancel_drawing_()
	elseif scan == sdl.SDL_SCANCODE_X and ctrl then
		self.select_mode_ = "cut"
		self:cancel_drawing_()
	elseif scan == sdl.SDL_SCANCODE_V and ctrl then
		if self.clipsize_x_ then
			self.select_mode_ = "place"
			self:cancel_drawing_()
			self.place_x_, self.place_y_ = self.clipsize_x_, self.clipsize_y_
		end
	elseif scan == sdl.SDL_SCANCODE_L then
		self.select_mode_ = "place"
		self:cancel_drawing_()
		self.want_stamp_size_ = true
	elseif scan == sdl.SDL_SCANCODE_K then
		self.select_mode_ = "place"
		self:cancel_drawing_()
		self.want_stamp_size_ = true
	elseif scan == sdl.SDL_SCANCODE_RIGHTBRACKET then
		if self.placing_zoom_ then
			self.zoom_invalid_ = true
		end
	elseif scan == sdl.SDL_SCANCODE_LEFTBRACKET then
		if self.placing_zoom_ then
			self.zoom_invalid_ = true
		end
	elseif scan == sdl.SDL_SCANCODE_I and not ctrl then
		self:report_airinvert_()
	elseif scan == sdl.SDL_SCANCODE_SEMICOLON then
		self.bmode_invalid_ = true
	end
	if key == sdl.SDLK_INSERT or key == sdl.SDLK_DELETE then
		self.bmode_invalid_ = true
	end
end

function profile_i:handle_keyrelease(key, scan, rep, shift, ctrl, alt)
	self:post_event_check_()
	if not shift and self.kmod_s_ then
		self:disable_shift_()
	end
	if not ctrl and self.kmod_c_ then
		self:disable_ctrl_()
	end
	if not alt and self.kmod_a_ then
		self:disable_alt_()
	end
	self:update_kmod_()
	-- * Here the assumption is made that no Lua hook cancels the keyrelease event.
	-- * Here the assumption is made that no debug hook cancels the keyrelease event.
	if rep then
		return
	end
	if scan == sdl.SDL_SCANCODE_Z then
		if self.placing_zoom_ and not alt then
			self.placing_zoom_ = false
			self.zoom_invalid_ = true
		end
	end
end

function profile_i:handle_textinput(text)
	self:post_event_check_()
end

function profile_i:handle_textediting(text)
	self:post_event_check_()
end

function profile_i:handle_blur()
	self:post_event_check_()
	for _, btn in pairs(self.buttons_) do
		btn.active = false
	end
	if self[index_to_lrax[self.last_toolslot_]] == util.from_tool.DEFAULT_UI_SIGN then
		self.signs_invalid_ = get_sign_data()
	end
	self:disable_shift_()
	self:disable_ctrl_()
	self:disable_alt_()
	self:update_kmod_()
	self:cancel_drawing_()
	self.draw_mode_ = "points"
end

function profile_i:placing_zoom()
	return self.placing_zoom_
end

function profile_i:button_open_()
	self.placesave_open_ = true
	self:begin_placesave_size_(100, 100, true)
end

function profile_i:button_reload_()
	self.placesave_reload_ = true
	self:begin_placesave_size_(100, 100, true)
end

function profile_i:button_clear_()
	self.placesave_clear_ = true
	self:begin_placesave_size_(100, 100, true)
end

local function new(params)
	local prof = setmetatable({
		placing_zoom_ = false,
		kmod_c_ = false,
		kmod_s_ = false,
		kmod_a_ = false,
		bmode_ = 0,
		dragging_mouse_ = false,
		select_mode_ = "none",
		prev_select_mode_ = false,
		prev_place_mode_ = false,
		draw_mode_ = "points",
		last_toolslot_ = 0,
		shape_ = 0,
		stk2_out_ = false,
		perfect_circle_invalid_ = true,
		registered_func_ = params.registered_func,
		set_id_func_ = params.set_id_func,
		get_id_func_ = params.get_id_func,
		display_toolwarn_ = {},
		buttons_ = {
			open   = { x =               1, y = gfx.HEIGHT - 16, w = 17, h = 15 },
			reload = { x =              19, y = gfx.HEIGHT - 16, w = 17, h = 15 },
			clear  = { x = gfx.WIDTH - 159, y = gfx.HEIGHT - 16, w = 17, h = 15 },
		},
	}, profile_m)
	prof.tool_l_ = util.from_tool.TPTMP_PT_UNKNOWN
	prof.tool_r_ = util.from_tool.TPTMP_PT_UNKNOWN
	prof.tool_a_ = util.from_tool.TPTMP_PT_UNKNOWN
	prof.tool_x_ = util.from_tool.TPTMP_PT_UNKNOWN
	prof.last_tool_ = prof.tool_l_
	prof.deco_ = sim.decoColour()
	prof:update_pos_(tpt.mousex, tpt.mousey)
	prof:update_size_()
	prof:update_tools_()
	prof:update_deco_()
	prof:check_simstate()
	prof:update_kmod_()
	prof:update_bmode_()
	prof:update_shape_()
	prof:update_zoom_()
	prof:check_signs({})
	if not elem.TPTMP_PT_VANILLAPRESHACK then
		assert(elem.allocate("TPTMP", "VANILLAPRESHACK") ~= -1, "out of element IDs")
	end
	preshack_elem = elem.TPTMP_PT_VANILLAPRESHACK
	elem.property(preshack_elem, "Graphics", preshack_graphics)
	preshack_prof = prof
	return prof
end

return {
	new = new,
	brand = "vanilla",
	profile_i = profile_i,
	log_event = log_event,
}
