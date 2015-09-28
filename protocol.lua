require 'bit'
local lshift, rshift, band, rol, ror = bit.lshift, bit.rshift, bit.band, bit.rol, bit.ror
local insert, concat = table.insert, table.concat
protocol = {
	--Init_Connect
	[2] = {
		{name="major",size=1},
		{name="minor",size=1},
		{name="script",size=1},
		{name="nick",size=1,str=true},
	},
	--Connect_Succ
	[3] = {},
	--Disconnect , Or could be a kick
	[4] = {
		{name="reason",size=1,str=true},
	},
	-- Ping
	[8] = {},
	-- Pong
	[9] = {},
	--New_Nick -- Server->Client, The client nick was changed
	[13] = {
		{name="nick",size=1,str=true},
	},
	--Join_Chan, Try moving into new channel
	[14] = {
		{name="chan",size=1,str=true},
	},
	--Chan_Name - Current_Channel, Response of Join_Chan (or a server forced move)
	[15] = {
		{name="chan",size=1,str=true},
	},
	--Chan_Member -- Sent in response to join, One per user in channel, will fill a user list
	[16] = {
		{name="name",size=1,str=true},
	},
	--User_Join, User joins the channel
	[17] = {
		{name="name",size=1,str=true},
	},
	--User_Leave, User leaves a channel
	[18] = {},
	--User_Chat, User chat
	[19] = {
		{name="msg",size=1,str=true},
	},
	--User_Me, User emote
	[20] = {
		{name="msg",size=1,str=true},
	},
	-- User_Kick, kick a user
	[21] = {
		{name="nick",size=1,str=true},
		{name="reason",size=1,str=true},
	},
	--Server_Broadcast, Colored message sent from server
	[22] = {
		{name="msg",size=1,str=true},
		{name="R",size=1},
		{name="G",size=1},
		{name="B",size=1},
	},
	--Set_User_Mode, Set some user modes (WIP)
	[23] = {
		{name="nick",size=1,str=true},
		{name="modes",size=1,bit=true,fields={"stab","mute","op"},sizes={1,1,1}},
	},
	--Get_User_Mode, Get some user modes (WIP)
	[24] = {
		{name="nick",size=1,str=true},
	},
	--User_Mode, Response from above (WIP)
	[25] = {
		{name="nick",size=1,str=true},
		{name="modes",size=1,bit=true,fields={"stab","mute","op"},sizes={1,1,1}},
	},
	--Mouse_Pos, Client mouse location
	[32] = {
		{name="position",size=3,bit=true,fields={"x","y"},sizes={12,12}},
	},
	--Mouse_Click, Clicky at mouse location
	[33] = {
		{name="click",size=1,bit=true,fields={"button","event"},sizes={4,4}},
	},
	--Brush_Size
	[34] = {
		{name="x",size=1},
		{name="y",size=1},
	},
	--Brush_Shape,
	[35] = {
		{name="shape",size=1},
	},
	--Key_Mods, key: 0-ctrl 1-shift 2-alt
	[36] = {
		{name="key",size=1,bit=true,fields={"char","state"},sizes={4,4}},
	},
	--["Selected_Elem"] = 37,
	[37] = {
		{name="selected",size=2,bit=true,fields={"button","elem"},sizes={2,12}},
	},
	--["Replace_Mode"] = 38,
	[38] = {
		{name="replacemode",size=1},
	},
	--["Mouse_Reset"], Forced mouseup event due to zoom window or entering another interface
	[39] = {},
	--["View_Mode_Simple"] = 48,
	[48] = {
		{name="mode",size=1},
	},
	--["Pause_State"] = 49,
	[49] = {
		{name="state",size=1},
	},
	--["Frame_Step"] = 50,
	[50] = {},
	--["Deco_State"] = 51,
	[51] = {
		{name="ID",size=1},
		{name="state",size=1},
	},
	--["Ambient_State"] = 53,
	[53] = {
		{name="state",size=1},
	},
	--["NGrav_State"] = 54,
	[54] = {
		{name="state",size=1},
	},
	--["Heat_State"] = 56,
	[56] = {
		{name="state",size=1},
	},
	--["Equal_State"] = 57,
	[57] = {
		{name="state",size=1},
	},
	--["Grav_Mode"] = 58,
	[58] = {
		{name="state",size=1},
	},
	--["Air_Mode"] = 59,
	[59] = {
		{name="state",size=1},
	},
	--["Clear_Spark"] = 60,
	[60] = {},
	--["Clear_Press"] = 61,
	[61] = {},
	--["Invert_Press"] = 62,
	[62] = {},
	--["Clear_Sim"] = 63,
	[63] = {},
	--["View_Mode_Advanced"] = 64,
	[64] = {
		{name="display",size=1},
		{name="render",size=1},
		{name="color",size=1},
	},
	--["Selected_Deco"] = 65,
	[65] = {
		{name="RGBA",size=4},
	},
	--["Stamp_Data"] = 66,
	[66] = {
		{name="position",size=3,bit=true,fields={"x","y"},sizes={12,12}},
		{name="data",size=3,str=true},
	},
	--["Clear_Area"] = 67,
	[67] = {
		{name="start",size=3,bit=true,fields={"x","y"},sizes={12,12}},
		{name="stop",size=3,bit=true,fields={"x","y"},sizes={12,12}},
	},
	--["Edge_Mode"] = 68,
	[68] = {
		{name="state",size=1},
	},
	--["Load_Save"] = 69,
	[69] = {
		{name="saveID",size=3},
	},
	--["Reload_Sim"] = 70,
	[70] = {},
	-- Sign_Data = 71,
	[71] = {
		{name="signID",size=1},
		{name="position",size=3,bit=true,fields={"x","y"},sizes={12,12}},
		{name="text",size=1,str=true},
		{name="just",size=1},
	},
	--["Req_Player_Sync"] = 128,  Server->Client Only
	[128] = {
		{name="userID",size=1},
	},
	--Player_Sync, Client->Server only, packets unprocessed by the server, relayed to another client as original protocols
	[129] = {
		{name="userID",size=1},
		{name="proto",size=1},
		{name="data",size=3,str=true},
	},
}
local protoName = {
	["Init_Connect"] = 2,
	["Connect_Succ"] = 3,
	["Disconnect"] = 4,
	["Ping"] = 8,
	["Pong"] = 9,
	["New_Nick"] = 13,
	["Join_Chan"] = 14,
	["Chan_Name"] = 15,
	["Chan_Member"] = 16,
	["User_Join"] = 17,
	["User_Leave"] = 18,
	["User_Chat"] = 19,
	["User_Me"] = 20,
	["User_Kick"] = 21,
	["Server_Broadcast"] = 22,
	["Set_User_Mode"] = 23,
	["Get_User_Mode"] = 24,
	["User_Mode"] = 25,
	["Mouse_Pos"] = 32,
	["Mouse_Click"] = 33,
	["Brush_Size"] = 34,
	["Brush_Shape"] = 35,
	["Key_Mods"] = 36,
	["Selected_Elem"] = 37,
	["Replace_Mode"] = 38,
	["Mouse_Reset"] = 39,
	["View_Mode_Simple"] = 48,
	["Pause_State"] = 49,
	["Frame_Step"] = 50,
	["Deco_State"] = 51,
	["Ambient_State"] = 53,
	["NGrav_State"] = 54,
	["Heat_State"] = 56,
	["Equal_State"] = 57,
	["Grav_Mode"] = 58,
	["Air_Mode"] = 59,
	["Clear_Spark"] = 60,
	["Clear_Press"] = 61,
	["Invert_Press"] = 62,
	["Clear_Sim"] = 63,
	["View_Mode_Advanced"] = 64,
	["Selected_Deco"] = 65,
	["Stamp_Data"] = 66,
	["Clear_Area"] = 67,
	["Edge_Mode"] = 68,
	["Load_Save"] = 69,
	["Reload_Sim"] = 70,
	["Sign_Data"] = 71,
	["Req_Player_Sync"] = 128,
	["Player_Sync"] = 129,
}
--Put a reverse table in as well.
protoNames = {}
for k,v in pairs(protoName) do protoNames[k]=v protoNames[v]=k end

-- Protocol code --
local function schar(s) if type(s)=="number" then return string.char(s) else return tostring(s) end end
local function compValue(self)
	local size,res = self.max,0
	for i=1,size do
		res = res + lshift(self[i],lshift(size-i,3))
	end
	return res
end
local function compValueStr(self)
	return self[self.max+1] or ""
end
local function compValueBit(self,offset,bits)
	local val = self.p()
	val = rol(val,offset)
	return rshift(val,32-bits)
end
local function setValue(self,data)
	local size = self.max
	for i=size,1,-1 do
		self[i] = band(data,0xff)
		data = rshift(data,8)
	end
end
local function setValueStr(self,data)
	self.strsize = #data
	self[self.max+1] = data:sub(1,self.strsize)
	setValue(self,self.strsize)
end
local function setValueBit(self,data,rot,bits)
	local val = self.p()
	val = ror(val,rot)
	val = lshift(rshift(val,bits),bits)
	self.p(rol(val+data,rot))
	return self.p.p --Main Protocol is one farther on bits
end
local function makeMeta(typ,p,offset,bits)
	local Value, sValue, rot  = compValue, setValue, nil
	if typ==1 then Value, sValue = compValueStr, setValueStr end
	if typ==2 then local size=p.max*8 Value, sValue, rot, offset = compValueBit, setValueBit, size-offset-bits, offset+(32-size)  end
	return {
	__call = function(t,data)
		if not data then --A call on a value will GET the value, byteArrays return a table
			return Value(t,offset,bits)
		else -- A call with data will SET the value, byteArrays use a table
			p._writeCache = nil
			return sValue(t,data,rot,bits) or p
		end
	end,}
end
local function T_read(self,socket)
	for i,v in ipairs(self) do
		self[i] = getByte()
	end
	--String data is held in the table just after size
	if self.str then
		self.strsize = compValue(self)
		if self.strsize>0 then _,self[self.max+1] = getBytes(socket,self.strsize) end
	end
end
local function T_write(self)
	local t={}
	for i,v in ipairs(self) do
		insert(t,schar(v))
	end
	return concat(t,"")
end
local function T_string(self)
	return self.nam..":"..self()
end
local function T_string_bit(self)
	local more={}
	for k,v in ipairs(self.fields) do
		insert(more,v..":"..self[v]())
	end
	return self.nam..":{"..concat(more,",").."}"
end
local function dataType()
	return {
	["read"] = T_read,
	["write"] = T_write,
	["string"] = T_string}
end
local function dataTypeBit()
	return {
	["read"] = T_read,
	["write"] = T_write,
	["string"] = T_string_bit}
end
local function P_totalSize(self)
	local tsize = 0
	for i,v in ipairs(self) do
		tsize = tsize + v.max + (v.str and v.strsize or 0)
	end
	return tsize
end
local function P_writeData(self)
	if not self._writeCache then
		local res = {}
		for i,v in ipairs(self) do
			insert(res,v:write())
		end
		self._writeCache = concat(res,"")
	end
	return self._writeCache
end
local function P_readData(self,socket)
	for i,v in ipairs(self) do
		v:read(socket)
	end
	self._writeCache = nil
	return self
end
local function P_toString(self)
	local temp = {}
	for i,v in ipairs(self) do
		insert(temp,v:string())
	end
	return "{"..concat(temp,",").."}"
end
function protocolArray(proto)
	local t = {}
	local prot = protocol[proto]
	if prot then
		for i,v in ipairs(prot) do
			local temp = v.bit and dataTypeBit() or dataType()
			for ii=1,v.size do insert(temp,0) end
			temp.max, temp.str, temp.bit, temp.nam, temp.fields, temp.p = v.size, v.str, v.bit, v.name, v.fields, t
			if v.bit then local off=0 for ind,field in ipairs(v.fields) do temp[field]={p=temp} setmetatable(temp[field],makeMeta(2,temp,off,v.sizes[ind])) off=off+v.sizes[ind] end end
			t[v.name] = temp
			t[i] = temp
			setmetatable(temp,makeMeta(v.str and 1 or 0, t))
		end
		t.protoID = proto
		t.totalSize = P_totalSize
		t.writeData = P_writeData
		t.readData = P_readData
		t.tostring = P_toString
	else
		error("Bad protocol "..(proto or "??"))
	end
	return t
end
--P is shortcut for creating a new packet, P_C is the same but caches the new protocol, only one per type is ever made
P, P_C = {}, {}
setmetatable(P,{__index = function(t,cmd) if not protoNames[cmd] then error(cmd.." is invalid") end return protocolArray(protoNames[cmd]) end})
setmetatable(P_C,{__index = function(t,cmd) if not protoNames[cmd] then error(cmd.." is invalid") end t[cmd]=protocolArray(protoNames[cmd]) return t[cmd] end})
