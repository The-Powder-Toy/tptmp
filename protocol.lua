if bit32 then
	bit=bit32 bit.rol=bit.lrotate bit.ror=bit.rrotate
elseif not bit then
	bit = require 'bit'
end
local lshift, rshift, band, rol, ror = bit.lshift, bit.rshift, bit.band, bit.rol, bit.ror
local insert, concat = table.insert, table.concat
protocol = { --The name of the protocol is removed later
	[2] = {
		"Init_Connect",
		{name="major",size=1},
		{name="minor",size=1},
		{name="script",size=1},
		{name="nick",size=1,str=true},
	},
	[3] = {"Connect_Succ"},
	[4] = {
		"Disconnect",
		{name="reason",size=1,str=true},
	},
	[8] = {"Ping"},
	[9] = {"Pong"},
	[13] = {
		"New_Nick", -- Server->Client, The client nick was changed
		{name="nick",size=1,str=true},
	},
	[14] = {
		"Join_Chan", -- Try moving into new channel
		{name="chan",size=1,str=true},
	},
	[15] = {
		"Chan_Name", -- Current_Channel, Response of Join_Chan (or a server forced move)
		{name="chan",size=1,str=true},
	},
	[16] = {
		"Chan_Member",-- Sent in response to join, One per user in channel, will fill a user list
		{name="name",size=1,str=true},
	},
	[17] = {
		"User_Join", -- User joins the channel
		{name="name",size=1,str=true},
	},
	[18] = {"User_Leave"}, -- User leaves a channel
	[19] = {
		"User_Chat",
		{name="msg",size=1,str=true},
	},
	[20] = {
		"User_Me",
		{name="msg",size=1,str=true},
	},
	[21] = {
		"User_Kick",
		{name="nick",size=1,str=true},
		{name="reason",size=1,str=true},
	},
	[22] = {
		"Server_Broadcast",
		{name="msg",size=1,str=true},
		{name="R",size=1},
		{name="G",size=1},
		{name="B",size=1},
	},
	[23] = {
		"Set_User_Mode",
		{name="nick",size=1,str=true},
		{name="modes",size=1,bit=true,fields={"stab","mute","op"},sizes={1,1,1}},
	},
	[24] = {
		"Get_User_Mode", -- Client->Server
		{name="nick",size=1,str=true},
	},
	[25] = {
		"User_Mode", -- Server->Client
		{name="nick",size=1,str=true},
		{name="modes",size=1,bit=true,fields={"stab","mute","op"},sizes={1,1,1}},
	},
	[32] = {
		"Mouse_Pos",
		{name="position",size=3,bit=true,fields={"x","y"},sizes={12,12}},
	},
	[33] = {
		"Mouse_Click",
		{name="click",size=1,bit=true,fields={"button","event"},sizes={4,4}},
	},
	[34] = {
		"Brush_Size",
		{name="x",size=1},
		{name="y",size=1},
	},
	[35] = {
		"Brush_Shape",
		{name="shape",size=1},
	},
	[36] = {
		"Key_Mods", -- key: 0-ctrl 1-shift 2-alt
		{name="key",size=1,bit=true,fields={"char","state"},sizes={4,4}},
	},
	[37] = {
		"Selected_Elem",
		{name="selected",size=2,bit=true,fields={"button","elem"},sizes={2,12}},
	},
	[38] = {
		"Replace_Mode",
		{name="replacemode",size=1},
	},
	[39] = {"Mouse_Reset"}, -- Forced mouseup event due to zoom window or entering another interface
	[48] = {
		"View_Mode_Simple",
		{name="mode",size=1},
	},
	[49] = {
		"Pause_State",
		{name="state",size=1},
	},
	[50] = {"Frame_Step"},
	[51] = {
		"Deco_State",
		{name="ID",size=1},
		{name="state",size=1},
	},
	[53] = {
		"Ambient_State",
		{name="state",size=1},
	},
	[54] = {
		"NGrav_State",
		{name="state",size=1},
	},
	[56] = {
		"Heat_State",
		{name="state",size=1},
	},
	[57] = {
		"Equal_State",
		{name="state",size=1},
	},
	[58] = {
		"Grav_Mode",
		{name="state",size=1},
	},
	[59] = {
		"Air_Mode",
		{name="state",size=1},
	},
	[60] = {"Clear_Spark"},
	[61] = {"Clear_Press"},
	[62] = {"Invert_Press"},
	[63] = {"Clear_Sim"},
	[64] = {
		"View_Mode_Advanced",
		{name="display",size=1},
		{name="render",size=1},
		{name="color",size=1},
	},
	[65] = {
		"Selected_Deco",
		{name="RGBA",size=4},
	},
	[66] = {
		"Stamp_Data",
		{name="position",size=3,bit=true,fields={"x","y"},sizes={12,12}},
		{name="data",size=3,str=true},
	},
	[67] = {
		"Clear_Area",
		{name="start",size=3,bit=true,fields={"x","y"},sizes={12,12}},
		{name="stop",size=3,bit=true,fields={"x","y"},sizes={12,12}},
	},
	[68] = {
		"Edge_Mode",
		{name="state",size=1},
	},
	[69] = {
		"Load_Save",
		{name="saveID",size=3},
	},
	[70] = {"Reload_Sim"},
	[71] = {
		"Sign_Data",
		{name="signID",size=1},
		{name="position",size=3,bit=true,fields={"x","y"},sizes={12,12}},
		{name="text",size=1,str=true},
		{name="just",size=1},
	},
	[128] = {
		"Req_Player_Sync", -- Server->Client Only
		{name="userID",size=1},
	},
	[129] = {
		"Player_Sync", -- Client->Server only, packets unprocessed by the server, relayed to another client as original protocols
		{name="userID",size=1},
		{name="proto",size=1},
		{name="data",size=3,str=true},
	},
}
protoNames = {}
--Create Name table and reverse table as well.
for k,v in pairs(protocol) do local name=table.remove(v,1) protoNames[k]=name protoNames[name]=k end

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
	if self.strsize >= 256^self.max then self.strsize = 256^self.max-1 end
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
		if i <= self.max then
			self[i] = getByte()
		end
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
P_Ver = 1
P, P_C = {}, {}
setmetatable(P,{__index = function(t,cmd) if not protoNames[cmd] then error(cmd.." is invalid") end return protocolArray(protoNames[cmd]) end})
setmetatable(P_C,{__index = function(t,cmd) if not protoNames[cmd] then error(cmd.." is invalid") end t[cmd]=protocolArray(protoNames[cmd]) return t[cmd] end})
