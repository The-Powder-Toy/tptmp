--Cracker64's Powder Toy Multiplayer
--I highly recommend to use my Autorun Script Manager

--TODO's
--Channel UserList UI
--Config UI
--Config Options {sync_view_modes ; sync_debug_mode ; chat_width ; chat_height ; sync_frames ; auto_connect}
--PROP Tool
--! commands in chat

local versionStr, version = "1.0", 3

--If this script detects itself
if TPTMP then if TPTMP.version <= version then TPTMP.disableMultiplayer() else error("A newer version of TPTMP already running") end end 
--TPT version compatibility check
if not sim.clearRect then error("Tpt version not supported") end
-- Our local script version, protocol version
TPTMP = {version = version, proto = 1, versionStr = versionStr}
local socket = require "socket"

--Load / update protocol data
pcall(dofile,"scripts/tptmp.protocol")
local function updateprotocol()
	-- can't check for tpt.getscript directly, since it the older version existed since a long time ago
	if tpt.version.major >= 91 or tpt.version.jacob1s_mod >= 32 then
		if tpt.confirm("Install TPTMP", "The TPTMP protocol must be downloaded and installed to scripts/tptmp.protocol") then
			fs.makeDirectory("scripts")
			tpt.getscript(69, "scripts/tptmp.protocol", 1, 0)
		end
	end
	if not P_Ver then
		error("Protocol not found")
	elseif P_Ver < TPTMP.proto then
		error("Protocol is out of date, needs version "..TPTMP.proto.." but is version "..P_Ver)
	end
end
if not P_Ver or P_Ver < TPTMP.proto then
	updateprotocol()
end
local P,P_O=P_C,P

--If this is running with script manager
local using_manager, _print = false, print
if MANAGER or MANAGER_EXISTS then
	using_manager = true
	_print = MANAGER and MANAGER.print or MANAGER_PRINT
end

local get_name = tpt.get_name
local hooks_enabled = false
--only change KEYBOARD if you have issues. Only other option right now is 2(finnish).
local KEYBOARD = 1
--Local player vars we need to keep
local L = {mousex=0, mousey=0, brushx=0, brushy=0, select={1,333,0,0}, replacemode = 0, mButt=0, mEvent=0, dcolour=0, stick2=false, chatHidden=true, flashChat=false,
shift=false, alt=false, ctrl=false, tabs = false, skipClick=false, pauseNextFrame=false,
copying=false, stamp=false, placeStamp=false, lastStamp=nil, lastCopy=nil, smoved=false, rotate=false, sendScreen=false,
mouseInZoom=false, stabbed=false, muted=false, signs={}}
--Protocols that edit the simulation in some way.
local _editSim, editSim = {33,48,49,50,51,53,54,56,57,58,59,60,61,62,63,64,66,67,68,69,70,71}, {}
--Protocols that don't send an ID to client
local _noIDProt, noIDProt = {2,3,4,8,9,13,14,15,22,23,24,25,128,129}, {}
for i,v in ipairs(_editSim) do editSim[v]=true end for i,v in ipairs(_noIDProt) do noIDProt[v]=true end

--Detect jacob's mod
local jacobsmod = tpt.version.jacob1s_mod~=nil
math.randomseed(os.time())
local username = get_name()
local chatwindow, hideChat
local con = {connected = false,
		 socket = nil,
		 members = nil,
		 pingTime = os.time()+5}
local function disconnected(reason)
	if con.socket then
		con.socket:close()
	end
	reason = reason or "Connection was closed"
	chatwindow:addline(reason,255,50,50)
	con.connected = false
	con.members = {}
	L.stabbed, L.muted = false, false
end
local function sendProtocol(proto)
	if not con.connected then return false,"Not connected" end
	local prot = proto.protoID
	if L.stabbed and editSim[prot] then return false,"No Permission" end
	con.socket:settimeout(5)
	--_print("Sending "..proto:tostring())
	con.socket:send(string.char(prot)..proto:writeData())
	con.socket:settimeout(0)
end
local function sendSync(sync,proto)
	sendProtocol(sync.proto(proto.protoID).data(proto:writeData()))
end
local function joinChannel(chan)
	sendProtocol(P.Join_Chan.chan(chan))
end
function connectToServer(ip,port,nick)
	if con.connected then return false,"Already connected" end
	ip = ip or "cracker.starcatcher.us"
	port = port or 34404
	nick = nick or username
	local sock = socket.tcp()
	sock:settimeout(5)
	local s,r = sock:connect(ip,port)
	if not s then return false,r end
	sock:settimeout(0)
	sock:setoption("keepalive",true)
	con.connected = true
	con.socket = sock
	sendProtocol(P.Init_Connect.major(tpt.version.major).minor(tpt.version.minor).script(TPTMP.version).nick(nick))
	local c,r
	while not c do
		c,r = sock:receive(1)
		if not c and r~="timeout" then break end
	end
	if not c and r~="timeout" then con.connected = false return false,r end
	local prot = string.byte(c)
	--Only a few packets are allowed during connection
	if prot == protoNames["Disconnect"] then
		con.connected = false
		local data = P.Disconnect:readData(sock)
		local reason = data.reason()
		if reason=="This nick is already on the server" then
			nick = nick:gsub("(.)$",function(s) local n=tonumber(s) if n and n+1 <= 9 then return n+1 else return nick:sub(-1)..'0' end end)
			return connectToServer(ip,port,nick)
		end
		return false,reason
	end
	--Possibly receive changed username here? or later
	if prot ~= protoNames["Connect_Succ"] then
		con.connected = false
		return false,"Server Error, got proto "..prot
	end
	--Connection was good, continue
	username = nick
	sendProtocol(P.Brush_Shape.shape(tpt.brushID))
	sendProtocol(P.Brush_Size.x(L.brushx).y(L.brushy))
	sendProtocol(P.Selected_Elem.selected.button(0).selected.elem(L.select[1]))
	sendProtocol(P.Selected_Elem.selected.button(1).selected.elem(L.select[2]))
	sendProtocol(P.Selected_Elem.selected.button(2).selected.elem(L.select[3]))
	sendProtocol(P.Selected_Elem.selected.button(3).selected.elem(L.select[4]))
	sendProtocol(P.Replace_Mode.replacemode(L.replacemode))
	sendProtocol(P.Selected_Deco.RGBA(L.dcolour))
	sendProtocol(P.Join_Chan.chan("null"))
	return true
end
--get next char/byte
local function cChar()
	con.socket:settimeout(0)
	local c,r = con.socket:receive(1)
	con.socket:settimeout(0)
	if not c and r~="timeout" then disconnected("In cChar: "..r) return nil,r end
	return c,r
end
function getByte()
	local byte, r = cChar()
	if byte then return byte:byte() end
	return nil, r
end
function getBytes(_,amt)
	local final, rec = "", 0
	local timeout = socket.gettime()
	while rec<amt do
		local s,r,e = con.socket:receive(amt-rec)
		if not s then 
			if r~="timeout" then
				return false,"Error while getting bytes"
			end
			rec = rec + #e
			final = final..e
		else
			final = final..s
			break
		end
		if socket.gettime()-timeout>4 then return false,"Byte send took too long" end
	end
	--print("Received "..amt.." bytes in "..(socket.gettime()-timeout))
	return true,final
end
--return table of arguments
local function getArgs(msg)
	if not msg then return {} end
	local args = {}
	for word in msg:gmatch("([^%s%c]+)") do
		table.insert(args,word)
	end
	return args
end

--get different lists for other language keyboards
local keyboardshift = { {before=" qwertyuiopasdfghjklzxcvbnm1234567890-=.,/`|;'[]\\",after=" QWERTYUIOPASDFGHJKLZXCVBNM!@#$%^&*()_+><?~\\:\"{}|",},{before=" qwertyuiopasdfghjklzxcvbnm1234567890+,.-'߿߿߿߿߿߿߿<",after=" QWERTYUIOPASDFGHJKLZXCVBNM!\"#߿߿߿ߥ&/()=?;:_*`^>",}  }
local keyboardaltgr = { {nil},{before=" qwertyuiopasdfghjklzxcvbnm1234567890+,.-'߿߿߿߼",after=" qwertyuiopasdfghjklzxcvbnm1@߿߿߿ߤ߶{[]}\\,.-'~|",},}
local function shift(c, keyb)
	return keyb and keyb.after:sub(keyb.before:find(c,1,true)) or c
end

local function unpackDeco(dcolour)
	local b = bit.band(dcolour,0x000000FF)
	local g = bit.rshift(bit.band(dcolour,0x0000FF00),8)
	local r = bit.rshift(bit.band(dcolour,0x00FF0000),16)
	local a = bit.rshift(bit.band(dcolour,0xFF000000),24)
	return r,g,b,a
end
--Sync local sign cache
local function localSigns()
	for i=1,16 do
		local sign = sim.signs[i]
		--Signs have x, y, text, justification, all default to nil
		L.signs[i] = {x = sign.x, y = sign.y, text = sign.text, ju = sign.justification}
	end
end
localSigns()

local ui_base local ui_box local ui_text local ui_button local ui_scrollbar local ui_inputbox local ui_chatbox
ui_base = {
new = function()
	local b={}
	b.drawlist = {}
	function b:drawadd(f)
		table.insert(self.drawlist,f)
	end
	function b:draw(...)
		for _,f in ipairs(self.drawlist) do
			if type(f)=="function" then
				f(self,...)
			end
		end
	end
	b.movelist = {}
	function b:moveadd(f)
		table.insert(self.movelist,f)
	end
	function b:onmove(x,y)
		for _,f in ipairs(self.movelist) do
			if type(f)=="function" then
				f(self,x,y)
			end
		end
	end
	return b
end
}
ui_box = {
new = function(x,y,w,h,r,g,b)
	local box=ui_base.new()
	box.x=x box.y=y box.w=w box.h=h box.x2=x+w box.y2=y+h
	box.r=r or 255 box.g=g or 255 box.b=b or 255
	function box:setcolor(r,g,b) self.r=r self.g=g self.b=b end
	function box:setbackground(r,g,b,a) self.br=r self.bg=g self.bb=b self.ba=a end
	box.drawbox=true
	box.drawbackground=false
	box:drawadd(function(self) if self.drawbackground then tpt.fillrect(self.x,self.y,self.w,self.h,self.br,self.bg,self.bb,self.ba) end
								if self.drawbox then tpt.drawrect(self.x,self.y,self.w,self.h,self.r,self.g,self.b) end end)
	box:moveadd(function(self,x,y)
		if x then self.x=self.x+x self.x2=self.x2+x end
		if y then self.y=self.y+y self.y2=self.y2+y end
	end)
	return box
end
}
ui_text = {
new = function(text,x,y,r,g,b)
	local txt = ui_base.new()
	txt.text = text
	txt.x=x or 0 txt.y=y or 0 txt.r=r or 255 txt.g=g or 255 txt.b=b or 255
	function txt:setcolor(r,g,b) self.r=r self.g=g self.b=b end
	txt:drawadd(function(self,x,y) tpt.drawtext(x or self.x,y or self.y,self.text,self.r,self.g,self.b) end)
	txt:moveadd(function(self,x,y)
		if x then self.x=self.x+x end
		if y then self.y=self.y+y end
	end)
	function txt:process() return false end
	return txt
end,
--Scrolls while holding mouse over
newscroll = function(text,x,y,vis,force,r,g,b)
	local txt = ui_text.new(text,x,y,r,g,b)
	if not force and tpt.textwidth(text)<vis then return txt end
	txt.visible=vis
	txt.length=string.len(text)
	txt.start=1
	local last=2
	while tpt.textwidth(text:sub(1,last))<vis and last<=txt.length do
		last=last+1
	end
	txt.last=last-1
	txt.minlast=last-1
	txt.ppl=((txt.visible-6)/(txt.length-txt.minlast+1))
	function txt:update(text,pos)
		if text then
			self.text=text
			self.length=string.len(text)
			local last=2
			while tpt.textwidth(text:sub(1,last))<self.visible and last<=self.length do
				last=last+1
			end
			self.minlast=last-1
			self.ppl=((self.visible-6)/(self.length-self.minlast+1))
			if not pos then self.last=self.minlast end
		end
		if pos then
			if pos>=self.last and pos<=self.length then --more than current visible
				local newlast = pos
				local newstart=1
				while tpt.textwidth(self.text:sub(newstart,newlast))>= self.visible do
					newstart=newstart+1
				end
				self.start=newstart self.last=newlast
			elseif pos<self.start and pos>0 then --position less than current visible
				local newstart=pos
				local newlast=pos+1
				while tpt.textwidth(self.text:sub(newstart,newlast))<self.visible and newlast<self.length do
					newlast=newlast+1
				end
				self.start=newstart self.last=newlast-1
			end
			--keep strings as long as possible (pulls from left)
			local newlast=self.last
			if newlast<self.minlast then newlast=self.minlast end
			local newstart=1
			while tpt.textwidth(self.text:sub(newstart,newlast))>= self.visible do
				newstart=newstart+1
			end
			self.start=newstart self.last=newlast
		end
	end
	txt.drawlist={} --reset draw
	txt:drawadd(function(self,x,y)
		tpt.drawtext(x or self.x,y or self.y, self.text:sub(self.start,self.last) ,self.r,self.g,self.b)
	end)
	function txt:process(mx,my,button,event,wheel)
		if event==3 then
			local newlast = math.floor((mx-self.x)/self.ppl)+self.minlast
			if newlast<self.minlast then newlast=self.minlast end
			if newlast>0 and newlast~=self.last then
				local newstart=1
				while tpt.textwidth(self.text:sub(newstart,newlast))>= self.visible do
					newstart=newstart+1
				end
				self.start=newstart self.last=newlast
			end
		end
	end
	return txt
end
}
ui_inputbox = {
new=function(x,y,w,h)
	local intext=ui_box.new(x,y,w,h)
	intext.cursor=0
	intext.line=1
	intext.currentline = ""
	intext.focus=false
	intext.t=ui_text.newscroll("",x+2,y+2,w-2,true)
	intext.history={}
	intext.max_history=200
	intext.ratelimit = 0
	intext:drawadd(function(self)
		local cursoradjust=tpt.textwidth(self.t.text:sub(self.t.start,self.cursor))+2
		tpt.drawline(self.x+cursoradjust,self.y,self.x+cursoradjust,self.y+10,255,255,255)
		self.t:draw()
	end)
	intext:moveadd(function(self,x,y) self.t:onmove(x,y) end)
	function intext:setfocus(focus)
		self.focus=focus
		if focus then tpt.set_shortcuts(0) self:setcolor(255,255,0)
		else tpt.set_shortcuts(1) self:setcolor(255,255,255) end
	end
	function intext:movecursor(amt)
		self.cursor = self.cursor+amt
		if self.cursor>self.t.length then self.cursor = self.t.length end
		if self.cursor<0 then self.cursor = 0 return end
	end
	function intext:addhistory(str)
		self.history[#self.history+1] = str
		if #self.history >= self.max_history then
			table.remove(self.history, 1)
		end
	end
	function intext:moveline(amt)
		self.line = self.line+amt
		local max = #self.currentline and #self.history+2 or #self.history+1
		if self.line>max then self.line=max
		elseif self.line<1 then self.line=1 end
		local history = self.history[self.line] or ""
		if self.line == #self.history+1 then history = self.currentline end
		self.cursor = string.len(history)
		self.t:update(history, self.cursor)
	end
	function intext:textprocess(key,nkey,modifier,event)
		if event~=1 then return end
		if not self.focus then
			if nkey==13 or nkey==271 then self:setfocus(true) return true end
			return
		end
		if nkey==27 then self:setfocus(false) return true end
		if nkey==13 or nkey==271 then if socket.gettime() < self.ratelimit then return true end local text=self.t.text if text == "" then self:setfocus(false) return true else self.cursor=0 self.t.text="" self:addhistory(text) self.line=#self.history+1 self.currentline = "" self.ratelimit=socket.gettime()+1 return text end end --enter
		if nkey==267 then key="/" nkey=47 end
		if nkey==273 then if socket.gettime() < self.ratelimit then return true end self:moveline(-1) return true end --up
		if nkey==274 then self:moveline(1) return true end --down
		if nkey==275 then self:movecursor(1) self.t:update(nil,self.cursor) return true end --right
		if nkey==276 then self:movecursor(-1) self.t:update(nil,self.cursor) return true end --left
		local modi = (modifier%1024)
		local newstr
		if nkey==8 and self.cursor > 0 then newstr=self.t.text:sub(1,self.cursor-1) .. self.t.text:sub(self.cursor+1) self:movecursor(-1) --back
		elseif nkey==127 then newstr=self.t.text:sub(1,self.cursor) .. self.t.text:sub(self.cursor+2) --delete
		elseif nkey==9 then --tab complete
			local nickstart,nickend,nick = self.t.text:sub(1,self.cursor+1):find("([^%s%c]+)"..(self.cursor == #self.t.text and "" or " ").."$")
			if con.members and nick then
				for k,v in pairs(con.members) do
					if v.name:sub(1,#nick) == nick then
						nick = v.name if nickstart == 1 then nick = nick..":" end newstr = self.t.text:sub(1,nickstart-1)..nick.." "..self.t.text:sub(nickend+1,#self.t.text) self.cursor = nickstart+#nick
					end
				end
			end
		else
			if nkey<32 or nkey>=127 then return true end --normal key
			local shiftkey = (modi==1 or modi==2)
			if math.floor((modifier%16384)/8192)==1 and key >= 'a' and key <= 'z' then shiftkey = not shiftkey end
			local addkey = shiftkey and shift(key,keyboardshift[KEYBOARD]) or key
			if (math.floor(modi/512))==1 then addkey=shift(key,keyboardaltgr[KEYBOARD]) end
			newstr = self.t.text:sub(1,self.cursor) .. addkey .. self.t.text:sub(self.cursor+1)
			self.currentline = newstr
			self.t:update(newstr,self.cursor+1)
			self:movecursor(1)
			return true
		end
		if newstr then
			self.t:update(newstr,self.cursor)
			return true
		end
		--some actual text processing, lol
	end
	return intext
end
}
ui_scrollbar = {
new = function(x,y,h,t,m)
	local bar = ui_base.new() --use line object as base?
	bar.x=x bar.y=y bar.h=h
	bar.total=t
	bar.numshown=m
	bar.pos=0
	bar.length=math.floor((1/math.ceil(bar.total-bar.numshown+1))*bar.h)
	bar.soffset=math.floor(bar.pos*((bar.h-bar.length)/(bar.total-bar.numshown)))
	function bar:update(total,shown,pos)
		self.pos=pos or 0
		if self.pos<0 then self.pos=0 end
		self.total=total
		self.numshown=shown
		self.length= math.floor((1/math.ceil(self.total-self.numshown+1))*self.h)
		self.soffset= math.floor(self.pos*((self.h-self.length)/(self.total-self.numshown)))
	end
	function bar:move(wheel)
		self.pos = self.pos-wheel
		if self.pos < 0 then self.pos=0 end
		if self.pos > (self.total-self.numshown) then self.pos=(self.total-self.numshown) end
		self.soffset= math.floor(self.pos*((self.h-self.length)/(self.total-self.numshown)))
	end
	bar:drawadd(function(self)
		if self.total > self.numshown then
			tpt.drawline(self.x,self.y+self.soffset,self.x,self.y+self.soffset+self.length)
		end
	end)
	bar:moveadd(function(self,x,y)
		if x then self.x=self.x+x end
		if y then self.y=self.y+y end
	end)
	function bar:process(mx,my,button,event,wheel)
		if wheel~=0 and not hidden_mode then
			if self.total > self.numshown then
				local previous = self.pos
				self:move(wheel)
				if self.pos~=previous then
					return wheel
				end
			end
		end
		--possibly click the bar and drag?
		return false
	end
	return bar
end
}
ui_button = {
new = function(x,y,w,h,f,text)
	local b = ui_box.new(x,y,w,h)
	b.f=f
	b.t=ui_text.new(text,x+2,y+2)
	b.drawbox=false
	b.almostselected=false
	b.invert=false
	b.wasinside, b.mouseover, b.onLeave, b.onEnter = false, false, function() end, function() end
	b:drawadd(function(self)
		if self.invert or self.almostselected then
			self.almostselected = false
			tpt.fillrect(self.x,self.y,self.w,self.h)
			local tr=self.t.r local tg=self.t.g local tb=self.t.b
			b.t:setcolor(0,0,0)
			b.t:draw()
			b.t:setcolor(tr,tg,tb)
		else
			if self.mouseover then tpt.fillrect(self.x,self.y,self.w,self.h, 150, 150, 150) end
			b.t:draw()
		end
	end)
	b:moveadd(function(self,x,y)
		self.t:onmove(x,y)
	end)
	function b:process(mx,my,button,event,wheel)
		local inside = mx>=self.x and mx<=self.x2 and my>=self.y and my<=self.y2
		if not inside then
			if event == 0 and self.wasinside then self:onLeave() end
			self.mouseover=false
			self.wasinside=false
			return false
		end
		if event == 0 and not self.wasinside then self:onEnter() self.mouseover=true end
		if event==1 then self.wasinside = true end
		if event==3 and self.wasinside then self.almostselected=true end
		if event==2 and self.wasinside then self:f() end
		return true
	end
	return b
end
}
ui_chatbox = {
new=function(x,y,w,h)
	local chat=ui_box.new(x,y,w,h)
	chat.moving=false
	chat.lastx=0
	chat.lasty=0
	chat.relx=0
	chat.rely=0
	chat.shown_lines=math.floor(chat.h/10)-2 --one line for top, one for chat
	chat.max_width=chat.w-4
	chat.max_lines=200
	chat.lines = {}
	chat.scrollbar = ui_scrollbar.new(chat.x2-2,chat.y+11,chat.h-22,0,chat.shown_lines)
	chat.inputbox = ui_inputbox.new(x,chat.y2-10,w,10)
	chat.minimize = ui_button.new(chat.x2-15,chat.y,15,10,function() chat.moving=false chat.inputbox:setfocus(false) hideChat() end,">>")
	chat.conquit = ui_button.new(chat.x,chat.y,37,10,
		function(self)
			if con.connected then
				disconnected("Disconnected")
				self.t.text="Connect"
			else
				local s,r = connectToServer()
				if not s then
					chat:addline(r,255,50,50)
				else
					self.t.text="Disconn"
				end
			end
		end, "Connect")
	chat:drawadd(function(self)
		if self.w > 175 and jacobsmod then
			tpt.drawtext(self.x+self.w/2-72,self.y+2,"TPT Multiplayer, by cracker64") --72 tpt.textwidth("TPT Multiplayer, by cracker64")/2
		elseif self.w > 100 then
			tpt.drawtext(self.x+self.w/2-37.5,self.y+2,"TPT Multiplayer") -- 37.5 tpt.textwidth("TPT Multiplayer")/2
		end
		tpt.drawline(self.x+1,self.y+10,self.x2-1,self.y+10,120,120,120)
		self.scrollbar:draw()
		local count=0
		for i,line in ipairs(self.lines) do
			if i>self.scrollbar.pos and i<= self.scrollbar.pos+self.shown_lines then
				line:draw(self.x+3,self.y+12+(count*10))
				count = count+1
			end
		end
		self.inputbox:draw()
		self.minimize:draw()
		self.conquit:draw()
	end)
	chat:moveadd(function(self,x,y)
		for i,line in ipairs(self.lines) do
			line:onmove(x,y)
		end
		self.scrollbar:onmove(x,y)
		self.inputbox:onmove(x,y)
		self.minimize:onmove(x,y)
		self.conquit:onmove(x,y)
	end)
	function chat:addline(line,r,g,b,noflash)
		if not line or line=="" then return end --No blank lines
		local linebreak,lastspace = 0,nil
		for i=0,#line do
			local width = tpt.textwidth(line:sub(linebreak,i+1))
			if width > self.max_width/2 and line:sub(i,i):match("[%s,_%.%-?!]") then
				lastspace = i
			end
			if width > self.max_width or i==#line then
				local pos = (i==#line or not lastspace) and i or lastspace
				table.insert(self.lines,ui_text.new(line:sub(linebreak,pos),self.x,0,r,g,b))
				linebreak = pos+1
				lastspace = nil
			end
		end
		while #self.lines>self.max_lines do table.remove(self.lines,1) end
		self.scrollbar:update(#self.lines,self.shown_lines,#self.lines-self.shown_lines)
		if L.chatHidden and not noflash then L.flashChat=true end
	end
	chat:addline("TPTMP v"..versionStr..": Click [Connect] to join server, or type /list for all commands.",200,200,200,true)
	function chat:process(mx,my,button,event,wheel)
		if L.chatHidden then return false end
		local canMove = true
		if self.minimize:process(mx,my,button,event,wheel) then canMove = false end
		if self.conquit:process(mx,my,button,event,wheel) then canMove = false end
		if self.moving and event==3 then
			local newx,newy = mx-self.relx,my-self.rely
			local ax,ay = 0,0
			if newx<0 then ax = newx end
			if newy<0 then ay = newy end
			if (newx+self.w)>=sim.XRES then ax = newx+self.w-sim.XRES end
			if (newy+self.h)>=sim.YRES then ay = newy+self.h-sim.YRES end
			self:onmove(mx-self.lastx-ax,my-self.lasty-ay)
			self.lastx=mx-ax
			self.lasty=my-ay
			return true
		end
		local which = math.floor((my-self.y)/10)
		if self.moving and event==2 then self.moving=false return true end
		if mx<self.x or mx>self.x2 or my<self.y or my>self.y2 then if button == 0 then return false end self.inputbox:setfocus(false) return false elseif event==1 and which ~= 0 and not self.inputbox.focus then self.inputbox:setfocus(true) end
		self.scrollbar:process(mx,my,button,event,wheel)
		if event==1 and which==0 and canMove then self.moving=true self.lastx=mx self.lasty=my self.relx=mx-self.x self.rely=my-self.y return true end
		if event==1 and which==self.shown_lines+1 then self.inputbox:setfocus(true) return true elseif self.inputbox.focus then return true end --trigger input_box
		if which>0 and which<self.shown_lines+1 and self.lines[which+self.scrollbar.pos] then self.lines[which+self.scrollbar.pos]:process(mx,my,button,event,wheel) end
		return event==1
	end
	--commands for chat window
	chatcommands = {
	connect = function(self,msg,args)
		local newname = pcall(string.dump, get_name) and "Gue".."st"..math["random"](1111,9888) or get_name()
		local s,r = connectToServer(args[1],tonumber(args[2]) or 34404, newname~="" and newname or username)
		if not s then self:addline(r,255,50,50) end
		pressedKeys = nil
	end,
	--send = function(self,msg,args)
	--	if tonumber(args[1]) and args[2] then
	--	local withNull=false
	--	if args[2]=="true" then withNull=true end
	--	msg = msg:sub(#args[1]+1+(withNull and #args[2]+2 or 0))
	--	conSend(tonumber(args[1]),msg,withNull)
	--	end
	--end,
	quit = function(self,msg,args)
		disconnected("Disconnected")
	end,
	disconnect = function(self,msg,args)
		disconnected("Disconnected")
	end,
	join = function(self,msg,args)
		if args[1] then
			joinChannel(args[1])
			self:addline("joined channel "..args[1],50,255,50)
		end
	end,
	sync = function(self,msg,args)
		if L.stabbed then return end
		if con.connected then L.sendScreen=true end --need to send 67 clear screen
		self:addline("Synced screen to server",255,255,50)
	end,
	help = function(self,msg,args)
		if not args[1] then self:addline("/help <command>, type /list for a list of commands") end
		if args[1] == "connect" then self:addline("(/connect [ip] [port]) -- connect to a TPT multiplayer server, or no args to connect to the default one")
		--elseif args[1] == "send" then self:addline("(/send <something> <somethingelse>) -- send raw data to the server") -- send a raw command
		elseif args[1] == "quit" or args[1] == "disconnect" then self:addline("(/quit, no arguments) -- quit the game")
		elseif args[1] == "join" then self:addline("(/join <channel> -- joins a room on the server")
		elseif args[1] == "sync" then self:addline("(/sync, no arguments) -- syncs your screen to everyone else in the room")
		elseif args[1] == "me" then self:addline("(/me <message>) -- say something in 3rd person")
		elseif args[1] == "kick" then self:addline("(/kick <nick> <reason>) -- kick a user, only works if you have been in a channel the longest")
		elseif args[1] == "size" then self:addline("(/size <width> <height>) -- sets the size of the chat window")
		elseif args[1] == "stab" then self:addline("(/stab <nick>) -- stabs a user, preventing them from drawing or modifying the simulation at all")
		elseif args[1] == "unstab" then self:addline("(/unstab <nick>) -- unstabs a user, allowing them to draw on or modify the simulation again")
		elseif args[1] == "mute" then self:addline("(/mute <nick>) -- mutes a user, preventing them chatting")
		elseif args[1] == "unmute" then self:addline("(/unmute <nick>) -- mutes a user, allowing them to speak again")
		end
	end,
	list = function(self,msg,args)
		local list = ""
		for name in pairs(chatcommands) do
			list=list..name..", "
		end
		self:addline("Commands: "..list:sub(1,#list-2))
	end,
	me = function(self, msg, args)
		if not con.connected then return end
		self:addline("* " .. username .. " ".. table.concat(args, " "),200,200,200)
		sendProtocol(P.User_Me.msg(table.concat(args, " ")))
	end,
	kick = function(self, msg, args)
		if not con.connected then return end
		if not args[1] then self:addline("Need a nick! '/kick <nick> [reason]'") return end
		sendProtocol(P.User_Kick.nick(args[1]).reason(table.concat(args, " ", 2)))
	end,
	size = function(self, msg, args)
		if args[2] then
			local w, h = tonumber(args[1]), tonumber(args[2])
			if w < 75 or h < 50 then self:addline("size too small") return
			elseif w > sim.XRES-100 or h > sim.YRES-100 then self:addline("size too large") return
			end
			chatwindow = ui_chatbox.new(100,100,w,h)
			chatwindow:setbackground(10,10,10,235) chatwindow.drawbackground=true
			if using_manager then
				MANAGER.savesetting("tptmp", "width", w)
				MANAGER.savesetting("tptmp", "height", h)
			end
		end
	end,
	stab = function(self, msg, args)
		if not con.connected then return end
		if not args[1] then self:addline("Need a nick! '/stab <nick>") return end
		--sendProtocol(members[args[1]].M.modes.stab(1))
		--Fix me
	end,
	unstab = function(self, msg, args)
		if not con.connected then return end
		if not args[1] then self:addline("Need a nick! '/unstab <nick>") return end
		--sendProtocol(members[args[1]].M.modes.stab(0))
		--Fix me
	end,
	mute = function(self, msg, args)
		if not con.connected then return end
		if not args[1] then self:addline("Need a nick! '/mute <nick>") return end
		--sendProtocol(members[args[1]].M.modes.mute(1))
		--Fix me
	end,
	unmute = function(self, msg, args)
		if not con.connected then return end
		if not args[1] then self:addline("Need a nick! '/unmute <nick>") return end
		--sendProtocol(members[args[1]].M.modes.mute(0))
		--Fix me
	end,
	}
	function chat:textprocess(key,nkey,modifier,event)
		if L.chatHidden then return nil end
		local text = self.inputbox:textprocess(key,nkey,modifier,event)
		if type(text)=="boolean" then return text end
		if text and text~="" then

			local cmd = text:match("^/([^%s]+)")
			if cmd then
				local msg=text:sub(#cmd+3)
				local args = getArgs(msg)
				if chatcommands[cmd] then
					chatcommands[cmd](self,msg,args)
					--self:addline("Executed "..cmd.." "..rest)
					return
				end
			end
			--normal chat
			if con.connected then
				sendProtocol(P.User_Chat.msg(text))
				self:addline(username .. ": ".. text,200,200,200)
			else
				self:addline("Not connected to server!",255,50,50)
			end
		end
	end
	return chat
end
}
local fadeText = {}
--A little text that fades away, (align text (left/center/right)?)
local function newFadeText(text,frames,x,y,r,g,b,noremove)
	local t = {ticks=frames,max=frames,text=text,x=x,y=y,r=r,g=g,b=b,keep=noremove}
	t.reset = function(self,text) self.ticks=self.max if text then self.text=text end end
	table.insert(fadeText,t)
	return t
end
--Some text locations for repeated usage
local infoText = newFadeText("",150,245,370,255,255,255,true)
local cmodeText = newFadeText("",120,250,180,255,255,255,true)

local showbutton = ui_button.new(613,using_manager and 119 or 136,14,14,function(self) 
	if using_manager and not MANAGER.hidden then _print("minimize the manager before opening TPTMP") return end 
	if not hooks_enabled then TPTMP.enableMultiplayer() end 
	L.chatHidden=(not TPTMP.chatHidden) TPTMP.chatHidden=L.chatHidden L.flashChat=false
	self.t.text = (L.chatHidden and "<<" or ">>")
	end,"<<")
hideChat = function()
	L.chatHidden=true TPTMP.chatHidden=true
	showbutton.t.text = "<<"
end
showbutton.onEnter = function(self)
	if not con.connected then return end
	L.chatHidden, L.flashChat = false, false
	chatwindow.inputbox:setfocus(true)
end
showbutton.onLeave = function(self)
	if not TPTMP.chatHidden then return end
	L.chatHidden = true
	chatwindow.inputbox:setfocus(false)
end
if jacobsmod and tpt.oldmenu()~=0 then
	showbutton:onmove(0, 256)
end
showbutton.drawbox = true

if using_manager then
	local loadsettings = function() chatwindow = ui_chatbox.new(100, 100, tonumber(MANAGER.getsetting("tptmp", "width")), tonumber(MANAGER.getsetting("tptmp", "height"))) end
	if not pcall(loadsettings) then chatwindow = ui_chatbox.new(100, 100, 225, 150) end
else
	chatwindow = ui_chatbox.new(100, 100, 225, 150)
end
chatwindow:setbackground(10,10,10,235) chatwindow.drawbackground=true

local eleNameTable = {
["DEFAULT_PT_LIFE_GOL"] = 256,["DEFAULT_PT_LIFE_HLIF"] = 257,["DEFAULT_PT_LIFE_ASIM"] = 258,["DEFAULT_PT_LIFE_2x2"] = 259,["DEFAULT_PT_LIFE_DANI"] = 260,
["DEFAULT_PT_LIFE_AMOE"] = 261,["DEFAULT_PT_LIFE_MOVE"] = 262,["DEFAULT_PT_LIFE_PGOL"] = 263,["DEFAULT_PT_LIFE_DMOE"] = 264,["DEFAULT_PT_LIFE_34"] = 265,
["DEFAULT_PT_LIFE_LLIF"] = 276,["DEFAULT_PT_LIFE_STAN"] = 267,["DEFAULT_PT_LIFE_SEED"] = 268,["DEFAULT_PT_LIFE_MAZE"] = 269,["DEFAULT_PT_LIFE_COAG"] = 270,
["DEFAULT_PT_LIFE_WALL"] = 271,["DEFAULT_PT_LIFE_GNAR"] = 272,["DEFAULT_PT_LIFE_REPL"] = 273,["DEFAULT_PT_LIFE_MYST"] = 274,["DEFAULT_PT_LIFE_LOTE"] = 275,
["DEFAULT_PT_LIFE_FRG2"] = 276,["DEFAULT_PT_LIFE_STAR"] = 277,["DEFAULT_PT_LIFE_FROG"] = 278,["DEFAULT_PT_LIFE_BRAN"] = 279,
["DEFAULT_WL_ERASE"] = 280,["DEFAULT_WL_CNDTW"] = 281,["DEFAULT_WL_EWALL"] = 282,["DEFAULT_WL_DTECT"] = 283,["DEFAULT_WL_STRM"] = 284,
["DEFAULT_WL_FAN"] = 285,["DEFAULT_WL_LIQD"] = 286,["DEFAULT_WL_ABSRB"] = 287,["DEFAULT_WL_WALL"] = 288,["DEFAULT_WL_AIR"] = 289,["DEFAULT_WL_POWDR"] = 290,
["DEFAULT_WL_CNDTR"] = 291,["DEFAULT_WL_EHOLE"] = 292,["DEFAULT_WL_GAS"] = 293,["DEFAULT_WL_GRVTY"] = 294,["DEFAULT_WL_ENRGY"] = 295,
["DEFAULT_WL_NOAIR"] = 296,["DEFAULT_WL_ERASEA"] = 297,
["DEFAULT_TOOL_HEAT"] = 300,["DEFAULT_TOOL_COOL"] = 301,["DEFAULT_TOOL_AIR"] = 302,["DEFAULT_TOOL_VAC"] = 303,["DEFAULT_TOOL_PGRV"] = 304,["DEFAULT_TOOL_NGRV"] = 305,["DEFAULT_UI_WIND"] = 306,
["DEFAULT_DECOR_SET"] = 307,["DEFAULT_DECOR_ADD"] = 308,["DEFAULT_DECOR_SUB"] = 309,["DEFAULT_DECOR_MUL"] = 310,["DEFAULT_DECOR_DIV"] = 311,["DEFAULT_DECOR_SMDG"] = 312,["DEFAULT_DECOR_CLR"] = 313,["DEFAULT_DECOR_LIGH"] = 314, ["DEFAULT_DECOR_DARK"] = 315,
["DEFAULT_UI_SAMPLE"] = 333,["DEFAULT_UI_SIGN"] = 334,["DEFAULT_UI_PROPERTY"] = 335,
}
local golStart,golEnd=256,279
local wallStart,wallEnd=280,297
local toolStart,toolEnd=300,306
local decoStart,decoEnd=307,315
local function convertDecoTool(c)
	return c
end
if jacobsmod then
	convertDecoTool = function(c)
		if c > decoStart and c <= decoStart+6 then
			c =  decoStart + 1 + (c-decoStart)%6
		end
		return c
	end
end
local gravList= {[0]="Vertical",[1]="Off",[2]="Radial"}
local airList= {[0]="On",[1]="Pressure Off",[2]="Velocity Off",[3]="Off",[4]="No Update"}
local noFlood = {[15]=true,[55]=true,[87]=true,[128]=true,[158]=true,[284]=true}
local noShape = {[55]=true,[87]=true,[128]=true,[158]=true}
local createOverride = {
	[55] = function(rx,ry,c) return 0,0,c end, --STKM
	[87] = function(rx,ry,c) local tmp=rx+ry if tmp>55 then tmp=55 end return 0,0,c+bit.lshift(tmp,8) end, --LIGH
	[88] = function(rx,ry,c) local tmp=rx*4+ry*4+7 if tmp>300 then tmp=300 end return rx,ry,c+bit.lshift(tmp,8) end, --TESC
	[128] = function(rx,ry,c) return 0,0,c end, --STKM2
	[158] = function(rx,ry,c) return 0,0,c end, -- FIGH
	[284] = function(rx,ry,c) return 0,0,c end, -- Streamline
	}

--Functions that do stuff in powdertoy
local function createPartsAny(x,y,rx,ry,c,brush,user)
	if createOverride[c] then
		rx,ry,c = createOverride[c](rx,ry,c)
		if c<0 then return end
	end
	if c>=wallStart then
		if c<= wallEnd then
			sim.createWalls(x,y,rx,ry,c-wallStart,brush)
		elseif c<=toolEnd then
			if c>=toolStart then sim.toolBrush(x,y,rx,ry,c-toolStart,brush) end
		elseif c<= decoEnd then
			local r,g,b,a = unpackDeco(user.dcolour)
			sim.decoBrush(x,y,rx,ry,r,g,b,a,convertDecoTool(c)-decoStart,brush)
		end
		return
	elseif c>=golStart then
		c = 78+(c-golStart)*256
	end
	sim.createParts(x,y,rx,ry,c,brush,user.replacemode)
end
local function createLineAny(x1,y1,x2,y2,rx,ry,c,brush,user)
	if noShape[c] then return end
	if jacobsmod and c == tpt.element("ball") and not user.shift then return end
	if createOverride[c] then
		rx,ry,c = createOverride[c](rx,ry,c)
		if c<0 then return end
	end
	if c>=wallStart then
		if c<= wallEnd then
			sim.createWallLine(x1,y1,x2,y2,rx,ry,c-wallStart,brush)
		elseif c<=toolEnd then
			if c>=toolStart then local str=1.0 if user.drawtype==4 then if user.shift then str=10.0 elseif user.alt then str=0.1 end end sim.toolLine(x1,y1,x2,y2,rx,ry,c-toolStart,brush,str) end
		elseif c<= decoEnd then
			local r,g,b,a = unpackDeco(user.dcolour)
			sim.decoLine(x1,y1,x2,y2,rx,ry,r,g,b,a,convertDecoTool(c)-decoStart,brush)
		end
		return
	elseif c>=golStart then
		c = 78+(c-golStart)*256
	end
	sim.createLine(x1,y1,x2,y2,rx,ry,c,brush,user.replacemode)
end
local function createBoxAny(x1,y1,x2,y2,c,user)
	if noShape[c] then return end
	if createOverride[c] then
		_,_,c = createOverride[c](user.brushx,user.brushy,c)
		if c<0 then return end
	end
	if c>=wallStart then
		if c<= wallEnd then
			sim.createWallBox(x1,y1,x2,y2,c-wallStart)
		elseif c<=toolEnd then
			if c>=toolStart then sim.toolBox(x1,y1,x2,y2,c-toolStart) end
		elseif c<= decoEnd then
			local r,g,b,a = unpackDeco(user.dcolour)
			sim.decoBox(x1,y1,x2,y2,r,g,b,a,convertDecoTool(c)-decoStart)
		end
		return
	elseif c>=golStart then
		c = 78+(c-golStart)*256
	end
	sim.createBox(x1,y1,x2,y2,c,user and user.replacemode)
end
local function floodAny(x,y,c,cm,bm,user)
	if noFlood[c] then return end
	if createOverride[c] then
		_,_,c = createOverride[c](user.brushx,user.brushy,c)
		if c<0 then return end
	end
	if c>=wallStart then
		if c<= wallEnd then
			sim.floodWalls(x,y,c-wallStart,bm)
		end
		--other tools shouldn't flood
		return
	elseif c>=golStart then --GoL adjust
		c = 78+(c-golStart)*256
	end
	sim.floodParts(x,y,c,cm,user.replacemode)
end

local function lineSnapCoords(x1,y1,x2,y2)
	local snapAngle = math.floor(math.atan2(y2-y1, x2-x1)/(math.pi*0.25)+0.5)*math.pi*0.25;
	local lineMag = math.sqrt(math.pow(x2-x1,2)+math.pow(y2-y1,2));
	local nx = math.floor(lineMag*math.cos(snapAngle)+x1+0.5);
	local ny = math.floor(lineMag*math.sin(snapAngle)+y1+0.5);
	return nx,ny
end
local function rectSnapCoords(x1,y1,x2,y2)
	local snapAngle = math.floor((math.atan2(y2-y1, x2-x1)+math.pi*0.25)/(math.pi*0.5)+0.5)*math.pi*0.5 - math.pi*0.25;
	local lineMag = math.sqrt(math.pow(x2-x1,2)+math.pow(y2-y1,2));
	local nx = math.floor(lineMag*math.cos(snapAngle)+x1+0.5);
	local ny = math.floor(lineMag*math.sin(snapAngle)+y1+0.5);
	return nx,ny
end
local renModes = {[0xff00f270]=1,[-16715152]=1,[0x0400f381]=2,[0xf382]=4,[0xf388]=8,[0xf384]=16,[0xfff380]=32,[1]=0xff00f270,[2]=0x0400f381,[4]=0xf382,[8]=0xf388,[16]=0xf384,[32]=0xfff380}
local function getViewModes()
	local t={0,0,0}
	for k,v in pairs(ren.displayModes()) do
		t[1] = t[1]+v
	end
	for k,v in pairs(ren.renderModes()) do
		t[2] = t[2]+(renModes[v] or 0)
	end
	t[3] = ren.colorMode()
	return t
end

--clicky click
local function playerMouseClick(id,btn,ev)
	local user = con.members[id]
	--_print(tostring(btn)..tostring(ev))
	if ev==0 then return end
	
	--btn: 1-left 2-middle 4-right
	user.btn[btn] = ev
	if ev==1 then
		--Outside clicks are ignored
		if user.mousex>=sim.XRES then return end
		if user.mousey>=sim.YRES then return end
		user.pmx,user.pmy = user.mousex,user.mousey
		user.lastbtn = btn
		if not user.drawtype then
			--left box
			if user.ctrl and not user.shift then user.drawtype = 2 return end
			--left line
			if user.shift and not user.ctrl then user.drawtype = 1 return end
			--floodfill
			if user.ctrl and user.shift then floodAny(user.mousex,user.mousey,user.select[btn],-1,-1,user) user.drawtype = 3 return end
			--an alt click
			if user.alt then return end
			user.drawtype=4 --normal hold
			createPartsAny(user.mousex,user.mousey,user.brushx,user.brushy,user.select[btn],user.brush,user)
		elseif user.drawtype==3 then
			floodAny(user.mousex,user.mousey,user.select[btn],-1,-1,user)
		end
	elseif ev==2 and user.drawtype then
		if user.mousex>=sim.XRES then user.mousex=sim.XRES-1 end
		if user.mousey>=sim.YRES then user.mousey=sim.YRES-1 end
		if user.drawtype==2 then
			if user.alt then user.mousex,user.mousey = rectSnapCoords(user.pmx,user.pmy,user.mousex,user.mousey) end
			createBoxAny(user.mousex,user.mousey,user.pmx,user.pmy,user.select[user.lastbtn],user)
		elseif user.drawtype~=3 then
			if user.alt then user.mousex,user.mousey = lineSnapCoords(user.pmx,user.pmy,user.mousex,user.mousey) end
			createLineAny(user.mousex,user.mousey,user.pmx,user.pmy,user.brushx,user.brushy,user.select[user.lastbtn],user.brush,user)
		end
		user.lastbtn=nil --Nothing should use lastbtn without a 1 event first
		user.drawtype=false
		user.pmx,user.pmy = user.mousex,user.mousey
	end
end
--To draw continued lines
local function playerMouseMove(id)
	local user = con.members[id]
	if user.drawtype==3 then
		floodAny(user.mousex,user.mousey,user.select[user.lastbtn],-1,-1,user)
	elseif user.drawtype==1 and user.select[user.lastbtn]==306 then --Wind continuous draw
		if user.mousex>=sim.XRES then user.mousex=sim.XRES-1 end
		if user.mousey>=sim.YRES then user.mousey=sim.YRES-1 end
		createLineAny(user.pmx,user.pmy,user.mousex,user.mousey,user.brushx,user.brushy,user.select[user.lastbtn],user.brush,user)
	elseif user.drawtype==4 and user.btn[user.lastbtn]==3 then
		if user.mousex>=sim.XRES then user.mousex=sim.XRES-1 end
		if user.mousey>=sim.YRES then user.mousey=sim.YRES-1 end
		createLineAny(user.mousex,user.mousey,user.pmx,user.pmy,user.brushx,user.brushy,user.select[user.lastbtn],user.brush,user)
		user.pmx,user.pmy = user.mousex,user.mousey
	end
end
local function loadStamp(data,x,y,reset)
	if data then
		local f = io.open(".tmp.stm","wb")
		f:write(data)
		f:close()
		if reset then sim.clearSim() end
		if not sim.loadStamp(".tmp.stm",x,y) then
			infoText:reset("Error loading stamp")
		end
		os.remove".tmp.stm"
	else
		infoText:reset("Error loading empty stamp")
	end
end
local function saveStamp(x, y, w, h)
	local stampName = sim.saveStamp(x, y, w, h) or "errorsavingstamp"
	local fullName = "stamps/"..stampName..".stm"
	return stampName, fullName
end
local function deleteStamp(name)
	if sim.deleteStamp then
		sim.deleteStamp(name)
	else
		os.remove("stamps/"..name..".stm")
	end
end
local dataHooks={}
function addHook(cmd,f,front)
	if not protoNames[cmd] then error("Invalid protocol "..cmd) end
	cmd = type(cmd)=="string" and protoNames[cmd] or cmd
	dataHooks[cmd] = dataHooks[cmd] or {}
	if front then table.insert(dataHooks[cmd],front,f)
	else table.insert(dataHooks[cmd],f) end
end
addHook("New_Nick",function(data, uid)
	username = data.nick()
	chatwindow:addline("You were assigned the name "..username,255,255,50)
end)
addHook("Chan_Name",function(data, uid)
	con.members = {}
	chatwindow:addline("Moved to channel "..data.chan(),255,255,50)
end)
addHook("Chan_Member",function(data, uid)
	--Basic user table, will be receiving the full data shortly
	con.members[uid] = {name=data.name(),mousex=0,mousey=0,brushx=4,brushy=4,brush=0,select={1,333,0,0},dcolour={0,0,0,0},btn={[1]=nil,[2]=nil,[4]=nil},ctrl=false,shift=false,alt=false,skipDraw=false}
end)
addHook("User_Join",function(data, uid)
	local name = data.name()
	con.members[uid] = {name=name,mousex=0,mousey=0,brushx=4,brushy=4,brush=0,select={1,333,0,0},dcolour={0,0,0,0},btn={[1]=nil,[2]=nil,[4]=nil},ctrl=false,shift=false,alt=false,skipDraw=false}
	local line = name.." has joined"
	chatwindow:addline(line,255,255,50)
	if L.chatHidden then print(line) end
end)
addHook("User_Leave",function(data, uid)
	local line = con.members[uid].name.." has left"
	chatwindow:addline(line,255,255,50)
	if L.chatHidden then print(line) end
	con.members[uid] = nil
end)
addHook("User_Chat",function(data, uid)
	local line = con.members[uid].name .. ": " .. data.msg()
	chatwindow:addline(line)
	if L.chatHidden then print(line) end
end)
addHook("User_Me",function(data, uid)
	local line = "* " .. con.members[uid].name .. " " .. data.msg()
	chatwindow:addline(line)
	if L.chatHidden then print(line) end
end)
addHook("Server_Broadcast",function(data, uid)
	chatwindow:addline(data.msg(),data.R(),data.G(),data.B())
end)
addHook("User_Mode",function(data, uid)
	if username == data.nick() then
		L.stabbed = data.modes.stab()==1
		L.muted = data.modes.mute()==1
		--L.op = data.modes.op()==1
	else
		--Save other people data for use with /mute and /stab
	end
end)
addHook("Mouse_Pos",function(data, uid)
	local user = con.members[uid]
	user.mousex, user.mousey = data.position.x(), data.position.y()
	playerMouseMove(uid)
	user.skipDraw=true
end)
addHook("Mouse_Click",function(data, uid)
	local btn, ev = data.click.button(), data.click.event()
	playerMouseClick(uid,btn,ev)
end)
addHook("Brush_Size",function(data, uid)
	con.members[uid].brushx, con.members[uid].brushy = data.x(), data.y()
end)
addHook("Brush_Shape",function(data, uid)
	con.members[uid].brush = data.shape()
end)
addHook("Key_Mods",function(data, uid)
	local mod, state = data.key.char(), data.key.state()==1
	if mod==0 then
		con.members[uid].ctrl=state
	elseif mod==1 then
		con.members[uid].shift=state
	elseif mod==2 then
		con.members[uid].alt=state
	end
end)
addHook("Selected_Elem",function(data, uid)
	local btn, el = data.selected.button(), data.selected.elem()
	con.members[uid].select[btn+1] = el
	if btn==2 then
		--sync replace mode element between all players since apparently you have to set tpt.selectedreplace to use replace mode ...
		tpt.selectedreplace = elem.property(el, "Identifier")
	end
end)
addHook("Replace_Mode",function(data, uid)
	con.members[uid].replacemode = data.replacemode()
end)
addHook("Mouse_Reset",function(data, uid)
	con.members[uid].drawtype = false
	con.members[uid].btn = {}
end)
addHook("View_Mode_Simple",function(data, uid)
	tpt.display_mode(data.mode())
	cmodeText:reset(con.members[uid].name.." set:")
end)
addHook("Pause_State",function(data, uid)
	local p = data.state()
	tpt.set_pause(p)
	local str = (p==1) and "Pause" or "Unpause"
	infoText:reset(str.." from "..con.members[uid].name)
end)
addHook("Frame_Step",function(data, uid)
	tpt.set_pause(0)
	L.pauseNextFrame=true
end)
addHook("Deco_State",function(data, uid)
	tpt.decorations_enable(data.state())
	cmodeText:reset(con.members[uid].name.." set:")
end)
addHook("Ambient_State",function(data, uid)
	tpt.ambient_heat(data.state())
end)
addHook("NGrav_State",function(data, uid)
	tpt.newtonian_gravity(data.state())
end)
addHook("Heat_State",function(data, uid)
	tpt.heat(data.state())
end)
addHook("Equal_State",function(data, uid)
	sim.waterEqualisation(data.state())
end)
addHook("Grav_Mode",function(data, uid)
	local mode = data.state()
	sim.gravityMode(mode)
	cmodeText:reset(con.members[uid].name.." set: Gravity: "..gravList[mode])
end)
addHook("Air_Mode",function(data, uid)
	local mode = data.state()
	sim.airMode(mode)
	cmodeText:reset(con.members[uid].name.." set: Air: "..airList[mode])
end)
addHook("Clear_Spark",function(data, uid)
	tpt.reset_spark()
end)
addHook("Clear_Press",function(data, uid)
	tpt.reset_velocity()
	tpt.set_pressure()
end)
addHook("Invert_Press",function(data, uid)
	for x=0,152 do
		for y=0,95 do
			sim.pressure(x,y,-sim.pressure(x,y))
		end
	end
end)
addHook("Clear_Sim",function(data, uid)
	sim.clearSim()
	L.lastSave=nil
	infoText:reset(con.members[uid].name.." cleared the screen")
end)
addHook("View_Mode_Advanced",function(data, uid)
	local disM,renM,colM = data.display(), data.render(), data.color()
	ren.displayModes({disM})
	local t,i={},1
	while i<=32 do
		if bit.band(renM,i)>0 then table.insert(t,renModes[i]) end
		i=i*2
	end
	ren.renderModes(t)
	ren.colorMode(colM)
end)
addHook("Selected_Deco",function(data, uid)
	con.members[uid].dcolour = data.RGBA()
end)
addHook("Stamp_Data",function(data, uid)
	local x, y = data.position.x(), data.position.y()
	loadStamp(data.data(),x,y,false)
	infoText:reset("Stamp from "..con.members[uid].name)
end)
addHook("Clear_Area",function(data, uid)
	local x1, y1 = data.start.x(), data.start.y()
	local x2, y2 = data.stop.x(), data.stop.y()
	sim.clearRect(x1, y1, x2-x1+1, y2-y1+1)
end)
addHook("Edge_Mode",function(data, uid)
	sim.edgeMode(data.state())
end)
addHook("Load_Save",function(data, uid)
	local saveID = data.saveID()
	L.lastSave=saveID
	sim.loadSave(saveID,1)
	L.browseMode=3
end)
addHook("Reload_Sim",function(data, uid)
	sim.clearSim()
	if not sim.loadStamp("stamps/tmp.stm",0,0) then
		infoText:reset("Error reloading save from "..con.members[uid].name)
	end
end)
addHook("Sign_Data",function(data, uid)
	local sID = data.signID()
	local x, y, text, ju = data.position.x(), data.position.y(), data.text(), data.just()
	local sign, lsign = sim.signs[sID], L.signs[sID]
	if sign and sign.x then
		--Existing sign
		sign.x, sign.y, sign.text, sign.justification = x, y, text, ju
	else
		--New sign! Use the new ID incase they were somehow out of sync
		sID = sim.signs.new(text, x, y, ju)
		lsign = L.signs[sID]
	end
	--Update locals
	lsign.x, lsign.y, lsign.text, lsign.ju = x, y, text, ju
end)
addHook("Req_Player_Sync",function(data, uid)
	--Create a single sync packet and change it over and over
	local sync = P.Player_Sync.userID(data.userID())
	sendSync(sync,P.Pause_State.state(tpt.set_pause()))
	local stampName,fullName = saveStamp(0,0,sim.XRES-1,sim.YRES-1)
	local f = assert(io.open(fullName,"rb"))
	local s = f:read"*a"
	f:close()
	deleteStamp(stampName)
	sendSync(sync,P.Clear_Area.start.x(0).start.y(0).stop.x(sim.XRES-1).stop.y(sim.YRES-1))
	sendSync(sync,P.Stamp_Data.position.x(0).position.y(0).data(s))
	sendSync(sync,P.Ambient_State.state(tpt.ambient_heat()))
	sendSync(sync,P.NGrav_State.state(tpt.newtonian_gravity()))
	sendSync(sync,P.Heat_State.state(tpt.heat()))
	sendSync(sync,P.Equal_State.state(sim.waterEqualisation()))
	sendSync(sync,P.Grav_Mode.state(sim.gravityMode()))
	sendSync(sync,P.Air_Mode.state(sim.airMode()))
	sendSync(sync,P.Edge_Mode.state(sim.edgeMode()))
	local t = getViewModes()
	sendSync(sync,P.View_Mode_Advanced.display(t[1]).render(t[2]).color(t[3]))
end)

local function connectThink()
	if not con.connected then return end
	if not con.socket then disconnected("No Socket") return end
	--read all messages
	while 1 do
		local cmd,r = getByte()
		if cmd then
			if not protoNames[cmd] then _print("Unknown Protocol "..cmd) disconnected("Unknown Proto") break end
			local uid
			if not noIDProt[cmd] then uid = getByte() end
			--_print("Trying to get protocol "..cmd)
			local prot = protocolArray(cmd):readData(con.socket)
			--_print("Got "..protoNames[cmd].." from "..(uid or "server").." "..prot:tostring())
			if dataHooks[cmd] then
				for i,v in ipairs(dataHooks[cmd]) do
					--Hooks can return true to stop future hooks
					if v(prot,uid) then break end
				end
			end
		else
			if r ~= "timeout" then disconnected("In connectThink: "..r) end
			break
		end
	end

	--ping every minute
	if os.time()>con.pingTime then sendProtocol(P.Ping) con.pingTime=os.time()+60 end
end
--Track if we have STKM2 out, for WASD key changes
elements.property(128,"Update",function() L.stick2=true end)

local function drawStuff()
	if con.members then
		for i,user in pairs(con.members) do
			local x,y = user.mousex,user.mousey
			local brx,bry=user.brushx,user.brushy
			local brush,drawBrush=user.brush,true
			gfx.drawText(x,y,("%s %dx%d"):format(user.name,brx,bry),0,255,0,192)
			if user.drawtype then
				if user.drawtype==1 then
					if user.alt then x,y = lineSnapCoords(user.pmx,user.pmy,x,y) end
					tpt.drawline(user.pmx,user.pmy,x,y,0,255,0,128)
				elseif user.drawtype==2 then
					if user.alt then x,y = rectSnapCoords(user.pmx,user.pmy,x,y) end
					local tpmx,tpmy = user.pmx,user.pmy
					if tpmx>x then tpmx,x=x,tpmx end
					if tpmy>y then tpmy,y=y,tpmy end
					tpt.drawrect(tpmx,tpmy,x-tpmx,y-tpmy,0,255,0,128)
					drawBrush=false
				elseif user.drawtype==3 then
					tpt.drawline(x,y,x+5,y,0,255,0,128)
					tpt.drawline(x,y,x-5,y,0,255,0,128)
					tpt.drawline(x,y,x,y+5,0,255,0,128)
					tpt.drawline(x,y,x,y-5,0,255,0,128)
					drawBrush=false
				end
			end
			if drawBrush then
				if brush==0 then
					gfx.drawCircle(x,y,brx,bry,0,255,0,128)
				elseif brush==1 then
					gfx.drawRect(x-brx,y-bry,brx*2+1,bry*2+1,0,255,0,128)
				elseif brush==2 then
					gfx.drawLine(x-brx,y+bry,x,y-bry,0,255,0,128)
					gfx.drawLine(x-brx,y+bry,x+brx,y+bry,0,255,0,128)
					gfx.drawLine(x,y-bry,x+brx,y+bry,0,255,0,128)
				end
			end
		end
	end
	for k,v in pairs(fadeText) do
		if v.ticks > 0 then
			local a = math.floor(255*(v.ticks/v.max))
			tpt.drawtext(v.x,v.y,v.text,v.r,v.g,v.b,a)
			v.ticks = v.ticks-1
		else if not v.keep then table.remove(fadeText,k) end
		end
	end
end
local function updateBrush()
	if tpt.brushx > 255 then tpt.brushx = 255 end
	if tpt.brushy > 255 then tpt.brushy = 255 end
	local nbx,nby = tpt.brushx,tpt.brushy
	if L.brushx~=nbx or L.brushy~=nby then
		L.brushx,L.brushy = nbx,nby
		sendProtocol(P.Brush_Size.x(L.brushx).y(L.brushy))
	end
end

local function sendStuff()
	if not con.connected then return end
	--mouse position every step, slightly different from 1 and 2  click events.
	updateBrush()
	local nmx,nmy = tpt.mousex,tpt.mousey
	if nmx<sim.XRES and nmy<sim.YRES then nmx,nmy = sim.adjustCoords(nmx,nmy) end
	if L.mousex~= nmx or L.mousey~= nmy and L.mEvent~=3 then
		L.mousex,L.mousey = nmx,nmy
		sendProtocol(P.Mouse_Pos.position.x(L.mousex).position.y(L.mousey))
	end
	--check selected elements
	local nsell,nsela,nselr,nselrep = elements[tpt.selectedl] or eleNameTable[tpt.selectedl],elements[tpt.selecteda] or eleNameTable[tpt.selecteda],elements[tpt.selectedr] or eleNameTable[tpt.selectedr],elements[tpt.selectedreplace] or eleNameTable[tpt.selectedreplace]
	if L.select[1]~=nsell then
		L.select[1]=nsell
		sendProtocol(P.Selected_Elem.selected.button(0).selected.elem(nsell))
	elseif L.select[2]~=nsela then
		L.select[2]=nsela
		sendProtocol(P.Selected_Elem.selected.button(1).selected.elem(nsela))
	elseif L.select[4]~=nselr then
		L.select[4]=nselr
		sendProtocol(P.Selected_Elem.selected.button(3).selected.elem(nselr))
	elseif L.select[3]~=nselrep then
		L.select[3]=nselrep
		sendProtocol(P.Selected_Elem.selected.button(2).selected.elem(nselrep))
	end
	local ncol = sim.decoColour()
	if L.dcolour~=ncol then
		L.dcolour=ncol
		sendProtocol(P.Selected_Deco.RGBA(ncol))
	end

	if L.stabbed then return end -- stabbed players can't modify anything

	--Tell others to open this save ID, or send screen if opened local browser
	if jacobsmod and L.browseMode and L.browseMode > 3 then
		--hacky hack
		L.browseMode = L.browseMode - 3
	elseif L.browseMode==1 then
		--loaded online save
		local id=sim.getSaveID()
		if L.lastSave~=id then
			L.lastSave=id
			--save a backup for the reload button
			local stampName,fullName = saveStamp(0,0,sim.XRES-1,sim.YRES-1)
			os.remove("stamps/tmp.stm") os.rename(fullName,"stamps/tmp.stm")
			sendProtocol(P.Load_Save.saveID(id))
			deleteStamp(stampName)
		end
		L.browseMode=nil
	elseif L.browseMode==2 then
		--loaded local save (should probably clear sim first instead?)
		L.sendScreen=true
		L.browseMode=nil
	elseif L.browseMode==3 and L.lastSave==sim.getSaveID() then
		L.browseMode=nil
		--save this as a stamp for reloading (unless an api function exists to do this)
		local stampName,fullName = saveStamp(0,0,sim.XRES-1,sim.YRES-1)
		os.remove("stamps/tmp.stm") os.rename(fullName,"stamps/tmp.stm")
		deleteStamp(stampName)
	end

	--Send screen (or an area for known size) for stamps
	if jacobsmod and L.sendScreen == 2 then
		L.sendScreen = true
	elseif L.sendScreen then
		local x,y,w,h = 0,0,sim.XRES-1,sim.YRES-1
		if L.smoved then
			local stm
			if L.copying then stm=L.lastCopy else stm=L.lastStamp end
			if L.rotate then stm.w,stm.h=stm.h,stm.w end
			x,y,w,h = math.floor((L.mousex-stm.w/2)/4)*4,math.floor((L.mousey-stm.h/2)/4)*4,stm.w,stm.h
			L.smoved=false
			L.copying=false
		end
		L.sendScreen=false
		local stampName,fullName = saveStamp(x,y,w,h)
		local f = assert(io.open(fullName,"rb"))
		local s = f:read"*a"
		f:close()
		deleteStamp(stampName)
		sendProtocol(P.Clear_Area.start.x(x).start.y(y).stop.x(x+w).stop.y(y+h))
		sendProtocol(P.Stamp_Data.position.x(x).position.y(y).data(s))
	end

	--Check if custom modes were changed
	if jacobsmod and L.checkRen == 2 then
		L.checkRen = true
	elseif L.checkRen then
		L.checkRen=false
		local t,send=getViewModes(),false
		for k,v in pairs(t) do
			if v~=L.pModes[k] then
				send=true break
			end
		end
		if send then sendProtocol(P.View_Mode_Advanced.display(t[1]).render(t[2]).color(t[3])) end
	end

	--Send option menu settings
	if L.checkOpt then
		L.checkOpt=false
		sendProtocol(P.Ambient_State.state(tpt.ambient_heat()))
		sendProtocol(P.NGrav_State.state(tpt.newtonian_gravity()))
		sendProtocol(P.Heat_State.state(tpt.heat()))
		sendProtocol(P.Equal_State.state(sim.waterEqualisation()))
		sendProtocol(P.Grav_Mode.state(sim.gravityMode()))
		sendProtocol(P.Air_Mode.state(sim.airMode()))
		sendProtocol(P.Edge_Mode.state(sim.edgeMode()))
	end
	if L.checkSigns then
		L.checkSigns=false
		for i=1,16 do
			local lsign,sign = L.signs[i], sim.signs[i]
			if sign.x ~= lsign.x or sign.y ~= lsign.y or sign.text ~= lsign.text or sign.justification ~= lsign.ju then
				lsign.x, lsign.y, lsign.text, lsign.ju = sign.x, sign.y, sign.text, sign.justification
				sendProtocol(P.Sign_Data.signID(i).position.x(lsign.x or 0).position.y(lsign.y or 0).text(lsign.text or "").just(lsign.ju or 0))
			end
		end
	end
end
local function updatePlayers()
	if con.members then
		for k,v in pairs(con.members) do
			--If the mouse_pos was updated this frame we don't need to try again
			if not v.skipDraw then 
				playerMouseMove(k)
			else v.skipDraw=nil
			end
		end
	end
	--Keep last frame of stick2
	L.lastStick2=L.stick2
	L.stick2=false
end

local pressedKeys, tickHooks, ticker = nil, {}, 0
local function step()
	local mx, my = tpt.mousex, tpt.mousey
	if not L.chatHidden then chatwindow:process(mx, my,0,0,0) chatwindow:draw() end
	showbutton:process(mx, my,0,0,0)
	showbutton:draw()
	if hooks_enabled then
		if pressedKeys and pressedKeys["repeat"] < socket.gettime() then
			if pressedKeys["repeat"] < socket.gettime()-.05 then
				pressedKeys = nil
			else
				chatwindow:textprocess(pressedKeys["key"],pressedKeys["nkey"],pressedKeys["modifier"],pressedKeys["event"])
				pressedKeys["repeat"] = socket.gettime()+.065
			end
		end
		drawStuff()
		sendStuff()
		if L.pauseNextFrame then L.pauseNextFrame=false tpt.set_pause(1) end
		connectThink()
		updatePlayers()
	end
	ticker = ticker+1
	for i,v in pairs(tickHooks) do
		if (ticker%v.tick) == 0 then
			v.f()
		end
	end
end
local pc, cq = nil, chatwindow.conquit -- Previous color, connect button
table.insert(tickHooks,{tick=40,f=function() if not con.connected then cq.drawbox=true if pc then cq:setcolor(pc[1],pc[2],pc[3]) pc=nil else pc = {cq.r,cq.g,cq.b} cq:setcolor(130,255,130) end else cq.drawbox=false end end})
table.insert(tickHooks,{tick=25,f=function() if L.flashChat then showbutton.invert=not showbutton.invert else showbutton.invert=false end end})
--some button locations that emulate tpt, return false will disable button
local tpt_buttons = {
	["open"] = {x1=1, y1=408, x2=17, y2=422, f=function() if not L.ctrl then L.browseMode=1 else L.browseMode=2 end L.lastSave=sim.getSaveID() end},
	["rload"] = {x1=19, y1=408, x2=35, y2=422, f=function() if L.lastSave then if L.ctrl then infoText:reset("If you re-opened the save, please type /sync") else sendProtocol(P.Reload_Sim) end else infoText:reset("Reloading local saves is not synced currently. Type /sync") end end},
	["clear"] = {x1=470, y1=408, x2=486, y2=422, f=function() sendProtocol(P.Clear_Sim) L.lastSave=nil end},
	["opts"] = {x1=581, y1=408, x2=595, y2=422, f=function() L.checkOpt=true end},
	["disp"] = {x1=597, y1=408, x2=611, y2=422, f=function() L.checkRen=true L.pModes=getViewModes() end},
	["pause"] = {x1=613, y1=408, x2=627, y2=422, f=function() sendProtocol(P.Pause_State.state(bit.bxor(tpt.set_pause(),1))) end},
	["deco"] = {x1=613, y1=33, x2=627, y2=47, f=function() if jacobsmod and (L.tabs or L.ctrl) then return end sendProtocol(P.Deco_State.state(bit.bxor(tpt.decorations_enable(),1))) end},
	["newt"] = {x1=613, y1=49, x2=627, y2=63, f=function() if jacobsmod and (L.tabs or L.ctrl) then return end sendProtocol(P.NGrav_State.state(bit.bxor(tpt.newtonian_gravity(),1))) end},
	["ambh"] = {x1=613, y1=65, x2=627, y2=79, f=function() if jacobsmod and (L.tabs or L.ctrl) then return end sendProtocol(P.Ambient_State.state(bit.bxor(tpt.ambient_heat(),1))) end},
}
if jacobsmod then
	tpt_buttons["tab"] = {x1=613, y1=1, x2=627, y2=15, f=function() L.tabs = not L.tabs end}
	tpt_buttons["tabs"] = {x1=613, y1=17, x2=627, y2=147, f=function() if L.tabs or L.ctrl then L.sendScreen = true end end}
	tpt_buttons["opts"] = {x1=465, y1=408, x2=479, y2=422, f=function() L.checkOpt=true end}
	tpt_buttons["clear"] = {x1=481, y1=408, x2=497, y2=422, f=function() sendProtocol(P.Clear_Sim) L.lastSave=nil end}
	tpt_buttons["disp"] = {x1=595, y1=408, x2=611, y2=422,f=function() L.checkRen=2 L.pModes=getViewModes() end}
	tpt_buttons["open"] = {x1=1, y1=408, x2=17, y2=422, f=function() if not L.ctrl then L.browseMode=4 else L.browseMode=5 end L.lastSave=sim.getSaveID() end}
end

local function mouseclicky(mousex,mousey,button,event,wheel)
	if event == 4 or event == 5 then
		-- mouse reset from various changes, UI, zoom
		sendProtocol(P.Mouse_Reset)
		return true
	end

	if button > 4 then return end -- in case mouse wheel ever sends 8 or 16 event
	showbutton:process(mousex,mousey,button,event,wheel)
	if not hooks_enabled then return true end
	if L.stabbed and mousex < sim.XRES and mousey < sim.YRES and not L.stamp and not L.placeStamp then if chatwindow:process(mousex,mousey,button,event,wheel) then return false end return false end

	local oldx, oldy = mousex, mousey
	if mousex<sim.XRES and mousey<sim.YRES then
		mousex,mousey = sim.adjustCoords(mousex,mousey)
	end
	if L.stamp and button>0 and button~=2 then
		if event==1 and button==1 and L.stampx == -1 then
			--initial stamp coords
			L.stampx,L.stampy = mousex,mousey
		elseif event==2 then
			if L.skipClick then L.skipClick=false return true end
			--stamp has been saved, make our own copy
			if button==1 then
				--save stamp ourself for data, delete it
				local sx,sy = mousex,mousey
				if sx<L.stampx then L.stampx,sx=sx,L.stampx end
				if sy<L.stampy then L.stampy,sy=sy,L.stampy end
				--cheap cut hook to send a clear
				if L.copying==1 then
					--maybe this is ctrl+x? 67 is clear area
					sendProtocol(P.Clear_Area.start.x(L.stampx).start.y(L.stampy).stop.x(sx).stop.y(sy))
				end
				local w,h = sx-L.stampx,sy-L.stampy
				local stampName,fullName = saveStamp(L.stampx,L.stampy,w,h)
				sx,sy,L.stampx,L.stampy = math.ceil((sx+1)/4)*4,math.ceil((sy+1)/4)*4,math.floor(L.stampx/4)*4,math.floor(L.stampy/4)*4
				w,h = sx-L.stampx, sy-L.stampy
				local f = assert(io.open(fullName,"rb"))
				if L.copying then L.lastCopy = {data=f:read"*a",w=w,h=h} else L.lastStamp = {data=f:read"*a",w=w,h=h} end
				f:close()
				deleteStamp(stampName)
			end
			L.stamp=false
			L.copying=false
		end
		return true
	elseif L.placeStamp and button>0 and button~=2 then
		if event==2 then
			if L.skipClick then L.skipClick=false return true end
			if button==1 then
				local stm
				if L.copying then stm=L.lastCopy else stm=L.lastStamp end
				if stm then
					if not stm.data then
						--unknown stamp, send full screen on next step, how can we read last created stamp, timestamps on files?
						L.sendScreen = (jacobsmod and 2 or true)
					else
						--send the stamp
						if L.smoved then
							--moved from arrows or rotate, send area next frame
							L.placeStamp=false
							L.sendScreen=true
							return true
						end
						local sx,sy = mousex-math.floor(stm.w/2),mousey-math.floor((stm.h)/2)
						if sx<0 then sx=0 end
						if sy<0 then sy=0 end
						if sx+stm.w>sim.XRES-1 then sx=sim.XRES-stm.w end
						if sy+stm.h>sim.YRES-1 then sy=sim.YRES-stm.h end
						sendProtocol(P.Stamp_Data.position.x(sx).position.y(sy).data(stm.data))
					end
				end
			end
			L.placeStamp=false
			L.copying=false
		end
		return true
	end

	if button > 0 and L.skipClick then L.skipClick=false return true end
	if chatwindow:process(oldx,oldy,button,event,wheel) then return false end

	local obut,oevnt,t  = L.mButt,L.mEvent,{}
	L.mButt,L.mEvent = button,event
	
	local btnDiff = button~=obut
	if btnDiff or event~=oevnt then
		updateBrush()
		table.insert(t,P.Mouse_Click.click.button(button).click.event(event))
		if L.mousex ~= mousex or L.mousey ~= mousey then
			L.mousex,L.mousey = mousex,mousey
			if event==3 then
				table.insert(t,P.Mouse_Pos.position.x(mousex).position.y(mousey))
			else
				table.insert(t,1,P.Mouse_Pos.position.x(mousex).position.y(mousey))
			end
			if btnDiff and event==1 and oevnt==3 then
				table.insert(t,1,P.Mouse_Reset)
			end
		end
		for i,v in ipairs(t) do sendProtocol(v) end
	elseif event==3 then
		updateBrush()
		if L.mousex ~= mousex or L.mousey ~= mousey then
			L.mousex,L.mousey = mousex,mousey
			sendProtocol(P.Mouse_Pos.position.x(mousex).position.y(mousey))
		end
	end
	--Possible sign event just happened
	if event==2 and L.select[button]==334 then
		L.checkSigns = true
	end

	--Click inside button first
	if button==1 or jacobsmod then
		if event==1 then
			for k,v in pairs(tpt_buttons) do
				if mousex>=v.x1 and mousex<=v.x2 and mousey>=v.y1 and mousey<=v.y2 then
					v.downInside = true
				end
			end
		--Up inside the button we started with
		elseif event==2 then
			local ret = true
			for k,v in pairs(tpt_buttons) do
				if v.downInside and (mousex>=v.x1 and mousex<=v.x2 and mousey>=v.y1 and mousey<=v.y2) then
					if L.stabbed then chatwindow:addline("You are stabbed and can't modify the simulation",255,50,50) return false end
					if v.f() == false then ret = false end
				end
				v.downInside = nil
			end
			return ret
		--Mouse hold, we MUST stay inside button or don't trigger on up
		elseif event==3 then
			for k,v in pairs(tpt_buttons) do
				if v.downInside and (mousex<v.x1 or mousex>v.x2 or mousey<v.y1 or mousey>v.y2) then
					v.downInside = nil
				end
			end
		end
	end
end
local _skb, stabKeyBlocks = {32,48,49,50,51,52,53,54,55,56,57,59,61,96,98,102,104,105,107,108,110,114,117,118,119,120,121,127,277,286},{}
for i,v in ipairs(_skb) do stabKeyBlocks[v]=true end
local keypressfuncs = {
	--TAB, Override brush changes, disables custom brushes
	[9] = function() if not jacobsmod or not L.ctrl then tpt.brushID = (tpt.brushID+1)%3 sendProtocol(P.Brush_Shape.shape(tpt.brushID)) return false end end,

	--ESC
	[27] = function() if not L.chatHidden then hideChat() return false end end,

	--space, pause toggle
	[32] = function() sendProtocol(P.Pause_State.state(bit.bxor(tpt.set_pause(),1))) end,

	--View modes 0-9
	[48] = function() sendProtocol(P.View_Mode_Simple.mode(10)) end,
	[49] = function() if L.shift then sendProtocol(P.View_Mode_Simple.mode(9)) tpt.display_mode(9)--[[force local display mode, screw debug check for now]] return false end sendProtocol(P.View_Mode_Simple.mode(0)) end,
	[50] = function() sendProtocol(P.View_Mode_Simple.mode(1)) end,
	[51] = function() sendProtocol(P.View_Mode_Simple.mode(2)) end,
	[52] = function() sendProtocol(P.View_Mode_Simple.mode(3)) end,
	[53] = function() sendProtocol(P.View_Mode_Simple.mode(4)) end,
	[54] = function() sendProtocol(P.View_Mode_Simple.mode(5)) end,
	[55] = function() sendProtocol(P.View_Mode_Simple.mode(6)) end,
	[56] = function() sendProtocol(P.View_Mode_Simple.mode(7)) end,
	[57] = function() sendProtocol(P.View_Mode_Simple.mode(8)) end,

	--semicolon / ins / del for replace mode
	[59] = function() if L.ctrl then  L.replacemode = bit.bxor(L.replacemode, 2) else  L.replacemode = bit.bxor(L.replacemode, 1) end sendProtocol(P.Replace_Mode.replacemode(L.replacemode)) end,
	[277] = function() L.replacemode = bit.bxor(L.replacemode, 1) sendProtocol(P.Replace_Mode.replacemode(L.replacemode)) end,
	[127] = function() L.replacemode = bit.bxor(L.replacemode, 2) sendProtocol(P.Replace_Mode.replacemode(L.replacemode)) end,

	--= key, pressure/spark reset
	[61] = function() if L.ctrl then sendProtocol(P.Clear_Spark) else sendProtocol(P.Clear_Press) end end,

	--`, console
	[96] = function() if not L.shift and con.connected then infoText:reset("Console does not sync, use shift+` to open instead") return false end end,

	--b , deco, pauses sim
	[98] = function() if L.ctrl then sendProtocol(P.Deco_State.state(bit.bxor(tpt.decorations_enable(),1))) else sendProtocol(P.Pause_State.state(1)) sendProtocol(P.Deco_State.state(1)) end end,

	--c , copy
	[99] = function() if L.ctrl then L.stamp=true L.copying=true L.placeStamp=false L.stampx = -1 L.stampy = -1 end end,

	--d key, debug, api broken right now
	--[100] = function() conSend(55) end,

	--F , frame step
	[102] = function() if not jacobsmod or not L.ctrl then sendProtocol(P.Frame_Step) end end,

	--H , HUD and intro text
	[104] = function() if L.ctrl and jacobsmod then return false end end,

	--I , invert pressure
	[105] = function() sendProtocol(P.Invert_Press) end,

	--K , stamp menu, abort our known stamp, who knows what they picked, send full screen?
	[107] = function() L.lastStamp={data=nil,w=0,h=0} L.placeStamp=true L.copying=false L.stamp=false end,

	--L , last Stamp
	[108] = function() L.copying=false L.stamp=false if L.lastStamp then L.placeStamp=true end end,

	--N , newtonian gravity or new save
	[110] = function() if jacobsmod and L.ctrl then L.sendScreen=2 L.lastSave=nil else sendProtocol(P.Deco_State.state(bit.bxor(tpt.newtonian_gravity(),1))) end end,

	--O, old menu in jacobs mod
	[111] = function() if jacobsmod and not L.ctrl then if tpt.oldmenu()==0 and showbutton.y < 150 then return false elseif showbutton.y > 150 then showbutton:onmove(0, -256) end end end,

	--R , for stamp rotate, Reload
	[114] = function() if L.placeStamp then L.smoved=true if L.shift then return end L.rotate=not L.rotate elseif L.ctrl then sendProtocol(P.Reload_Sim) end end,

	--S, stamp
	[115] = function() if (L.lastStick2 and not L.ctrl) or (jacobsmod and L.ctrl) then return end L.stamp=true L.copying=false L.placeStamp=false L.stampx = -1 L.stampy = -1 end,

	--T, tabs
	[116] = function() if jacobsmod then L.tabs = not L.tabs end end,

	--U, ambient heat toggle
	[117] = function() sendProtocol(P.Ambient_State.state(bit.bxor(tpt.ambient_heat(),1))) end,

	--V, paste the copystamp
	[118] = function() if L.ctrl and L.lastCopy then L.stamp=false L.placeStamp=true L.copying=true end end,

	--X, cut a copystamp and clear
	[120] = function() if L.ctrl then L.stamp=true L.placeStamp=false L.copying=1 L.stampx = -1 L.stampy = -1 end end,

	--W,Y (grav mode, air mode)
	[119] = function() if L.lastStick2 and not L.ctrl then return end sendProtocol(P.Grav_Mode.state((sim.gravityMode()+1)%3))  return true end,
	[121] = function() sendProtocol(P.Air_Mode.state((sim.airMode()+1)%5)) return true end,
	--Z
	[122] = function() L.skipClick=true sendProtocol(P.Mouse_Reset) end,

	--Arrows for stamp adjust
	[273] = function() if L.placeStamp then L.smoved=true end end,
	[274] = function() if L.placeStamp then L.smoved=true end end,
	[275] = function() if L.placeStamp then L.smoved=true end end,
	[276] = function() if L.placeStamp then L.smoved=true end end,

	--F1 , intro text
	[282] = function() if jacobsmod then return false end end,

	--F5 , save reload
	[286] = function() sendProtocol(P.Reload_Sim) end,

	--SHIFT,CTRL,ALT
	[303] = function() L.shift=true sendProtocol(P.Key_Mods.key.char(1).key.state(1)) end,
	[304] = function() L.shift=true sendProtocol(P.Key_Mods.key.char(1).key.state(1)) end,
	[305] = function() L.ctrl=true sendProtocol(P.Key_Mods.key.char(0).key.state(1)) end,
	[306] = function() L.ctrl=true sendProtocol(P.Key_Mods.key.char(0).key.state(1)) end,
	[307] = function() L.alt=true sendProtocol(P.Key_Mods.key.char(2).key.state(1)) end,
	[308] = function() L.alt=true sendProtocol(P.Key_Mods.key.char(2).key.state(1)) end,
}
local keyunpressfuncs = {
	--Fake key to reset modifiers
	[0] = function() 
		if L.ctrl then
			L.ctrl=false sendProtocol(P.Key_Mods.key.char(0).key.state(0))
		end
		if L.shift then
			L.shift=false sendProtocol(P.Key_Mods.key.char(1).key.state(0))
		end
		if L.alt then
			L.alt=false sendProtocol(P.Key_Mods.key.char(2).key.state(0))
		end end,
	--Z
	[122] = function() L.skipClick=false if L.alt then L.skipClick=true end end,
	--SHIFT,CTRL,ALT
	[303] = function() L.shift=false sendProtocol(P.Key_Mods.key.char(1).key.state(0)) end,
	[304] = function() L.shift=false sendProtocol(P.Key_Mods.key.char(1).key.state(0)) end,
	[305] = function() L.ctrl=false sendProtocol(P.Key_Mods.key.char(0).key.state(0)) end,
	[306] = function() L.ctrl=false sendProtocol(P.Key_Mods.key.char(0).key.state(0)) end,
	[307] = function() L.alt=false sendProtocol(P.Key_Mods.key.char(2).key.state(0)) end,
	[308] = function() L.alt=false sendProtocol(P.Key_Mods.key.char(2).key.state(0)) end,
}
local function keyclicky(key,nkey,modifier,event)
	if not hooks_enabled then
		if jacobsmod and bit.band(modifier, 0xC0) == 0 and key == 'o' and event == 1 then if tpt.oldmenu()==0 and showbutton.y < 150 then showbutton:onmove(0, 256) elseif showbutton.y > 150 then showbutton:onmove(0, -256) end end
		return
	end
	if chatwindow.inputbox.focus then
		if event == 1 and nkey~=13 and nkey~=27 and nkey~=271 then
			pressedKeys = {["repeat"] = socket.gettime()+.6, ["key"] = key, ["nkey"] = nkey, ["modifier"] = modifier, ["event"] = event}
		elseif event == 2 and pressedKeys and nkey == pressedKeys["nkey"] then
			pressedKeys = nil
		end
	end
	local check = chatwindow:textprocess(key,nkey,modifier,event)
	if type(check)=="boolean" then return not check end
	--_print(nkey, key)
	if L.stabbed and stabKeyBlocks[nkey] then return false end
	local ret
	if event==1 then
		if keypressfuncs[nkey] then
			ret = keypressfuncs[nkey]()
		end
	elseif event==2 then
		if keyunpressfuncs[nkey] then
			ret = keyunpressfuncs[nkey]()
		end
	end
	if ret~= nil then return ret end
end

function TPTMP.disableMultiplayer()
	tpt.unregister_step(step)
	tpt.unregister_mouseclick(mouseclicky)
	tpt.unregister_keypress(keyclicky)
	TPTMP = nil
	disconnected("TPTMP unloaded")
end

function TPTMP.enableMultiplayer()
	hooks_enabled = true
	TPTMP.enableMultiplayer = nil
	debug.sethook(nil,"",0)
	if jacobsmod then
		--clear intro text tooltip
		gfx.toolTip("", 0, 0, 0, 4)
	end
end
TPTMP.con = con
hideChat()
tpt.register_step(step)
tpt.register_mouseclick(mouseclicky)
tpt.register_keypress(keyclicky)
