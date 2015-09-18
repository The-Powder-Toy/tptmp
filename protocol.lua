require 'bit'
no_ID_protocols = {[2]=true,[3]=true,[4]=true,[13]=true,[14]=true,[15]=true,[22]=true,[23]=true,[24]=true,[25]=true,[128]=true,[129]=true,}
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
	--["Zoom_State"], Mouse changed zoom state
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
		{name="ID",size=1},
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
		{name="end",size=3,bit=true,fields={"x","y"},sizes={12,12}},
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
	["New_Nick"] = 14,
	["Join_Chan"] = 15,
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
	["Zoom_State"] = 39,
	["View_Mode_Simple"] = 48,
	["Pause_State"] = 49,
	["Frame_Step"] = 50,
	["Deco_State"] = 51,
	["Ambient_State"] = 53,
	["NGrav_State"] = 54,
	["Heat_State"] = 56,
	["Equal_State"] = 57,
	["Grave_Mode"] = 58,
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
		res = res + bit.lshift(self[i],bit.lshift(size-i,3))
	end
	return res
end
local function compValueStr(self)
	return self[self.max+1] or ""
end
local function compValueBit(self,offset,bits)
	local val,size = self.p(),self.p.max*8
	val = bit.rol(val,offset+(32-size))
	return bit.rshift(val,32-bits)
end
local function setValue(self,data)
	local size = self.max
	for i=size,1,-1 do
		self[i] = bit.band(data,0xff)
		data = bit.rshift(data,8)
	end
	return self.p --Main Protocol
end
local function setValueStr(self,data)
	self.strsize = #data
	self[self.max+1] = data:sub(1,self.strsize)
	setValue(self,self.strsize)
	return self.p
end
local function setValueBit(self,data,offset,bits)
	local val,size = self.p(),self.p.max*8
	local rot = size-offset-bits
	val = bit.ror(val,rot)
	val = bit.lshift(bit.rshift(val,bits),bits)
	self.p(bit.rol(val+data,rot))
	return self.p.p --Main Protocol is one farther on bits
end
local function makeMeta(typ,offset,bits)
	local Value, sValue = compValue, setValue
	if typ==1 then Value, sValue = compValueStr, setValueStr end
	if typ==2 then Value, sValue = compValueBit, setValueBit end
	return {
	__call = function(t,data)
		if not data then --A call on a value will GET the value, byteArrays return a table
			return Value(t,offset,bits)
		else -- A call with data will SET the value, byteArrays use a table
			return sValue(t,data,offset,bits)
		end
	end,}
end
local function dataType()
	return {
	["read"] = function(self,socket)
		for i,v in ipairs(self) do
			self[i] = byte()
		end
		if self.str then
			self.strsize = self()
			if self.strsize>0 then self[self.max+1] = bytes(socket,self.strsize) end
		end
	end,
	["write"] = function(self)
		local t={}
		for i,v in ipairs(self) do
			table.insert(res,schar(v))
		end
		return table.concat(t,"")
	end,
	["string"] = function(self)
		return self.nam..":"..self()
	end,
}end
local function dataTypeBit()
	local t=dataType()
	t.string = function(self)
		local more={}
		for k,v in ipairs(self.fields) do
			table.insert(more,v..":"..self[v]())
		end
		return self.nam..":{"..table.concat(more,",").."}"
	end
	return t
end
function protocolArray(proto)
	local t = {}
	local prot = protocol[proto]
	if prot then
		local initialSize = 0
		for i,v in ipairs(prot) do
			local temp = v.bit and dataTypeBit() or dataType()
			for ii=1,v.size do table.insert(temp,0) end
			temp.max, temp.str, temp.bit, temp.nam, temp.fields, temp.p = v.size, v.str, v.bit, v.name, v.fields, t
			if v.bit then local off=0 for ind,field in ipairs(v.fields) do temp[field]={p=temp} setmetatable(temp[field],makeMeta(2,off,v.sizes[ind])) off=off+v.sizes[ind] end end
			t[v.name] = temp
			t[i] = temp
			setmetatable(temp,makeMeta(v.str and 1 or 0))
		end
		t["protoID"] = proto
		t["totalSize"] = function(self)
			local tsize = 0
			for i,v in ipairs(self) do
				tsize = tsize + v.max + (v.str and v.strsize or 0)
			end
			return tsize
		end
		t["writeData"] = function(self)
			local res = {}
			for i,v in ipairs(self) do
				table.insert(res,self:write())
			end
			return table.concat(res,"")
		end
		t["readData"] = function(self,socket)
			for i,v in ipairs(self) do
				self:read(str)
			end
		end
		t["tostring"] = function(self)
			local temp = {}
			for i,v in ipairs(self) do
				table.insert(temp,v:string())
			end
			return "{"..table.concat(temp,",").."}"
		end
	else
		error("Bad protocol "..proto)
	end
	return t
end
P = {}
setmetatable(P,{__index = function(t,cmd) return protocolArray(protoNames[cmd]) end})
