-- helpers
local function tptdrawtext(x,y,s,...)
	if y>=0 and y<384 and x<612 then
		while #s>0 and x<0 do
			s,x=s:sub(2),x+tpt.textwidth(s:sub(1,1))+1
		end
		pcall(tpt.drawtext,math.floor(x),math.floor(y),s,...)
	end
end
local function tptdrawrect(x,y,w,h,...)
	if x<612 and y<384 then
		if x<0 then
			x,w=0,w+x
		end
		if x+w>=612 then
			w=612-x
		end
		if y<0 then
			y,h=0,h+y
		end
		if y+h>=384 then
			y=384-h
		end
		pcall(tpt.drawrect,x,y,w,h,...)
	end
end
local function tptfillrect(x,y,w,h,...)
	if x<612 and y<384 then
		if x<-1 then
			x,w=-1,w+x+1
		end
		if x+w>=612 then
			w=612-x
		end
		if y<0 then
			y,h=-1,h+y+1
		end
		if y+h>=384 then
			h=384-y
		end
		pcall(tpt.fillrect,x,y,w,h,...)
	end
end
local function tptdrawline(a,b,c,d,...)
	a=math.max(math.min(a,611),0)
	b=math.max(math.min(b,383),0)
	c=math.max(math.min(c,611),0)
	d=math.max(math.min(d,383),0)
	pcall(tpt.drawline,a,b,c,d,...)
end
local function bevel(x,y,w,h,out)
	if out then
		tptdrawline(x,y,x+w,y,128,128,128)
		tptdrawline(x,y,x,y+h,128,128,128)
		tptdrawline(x,y+h,x+w,y+h,255,255,255)
		tptdrawline(x+w,y,x+w,y+h,255,255,255)
	else
		tptdrawline(x,y,x+w,y,255,255,255)
		tptdrawline(x,y,x,y+h,255,255,255)
		tptdrawline(x,y+h,x+w,y+h,128,128,128)
		tptdrawline(x+w,y,x+w,y+h,128,128,128)
	end
end
local function h2c(c)
	return math.floor(c/65536)%256,math.floor(c/256)%256,math.floor(c)%256
end

-- base functions
class={}
function class.INHERIT(from)
	assert(type(from)=="table","table expected")
	local o=setmetatable({},{__index=from})
	return o
end

-- base class
class.class={INHERIT=class.INHERIT}
function class.class:new(data)
	local o=setmetatable(data or{},{__index=self})
	return o
end

-- base component
class.component=class.class:INHERIT()
class.component.x=0
class.component.y=0
class.component.w=0
class.component.h=0
class.component.visible=true
function class.component:ondraw()end
function class.component:onfocus()end
function class.component:onblur()end
function class.component:onmouse()end
function class.component:onmousedown()end
function class.component:onmouseup()end
function class.component:onmousemove()end
function class.component:onscroll()end
function class.component:onkey()end
function class.component:onkeyup()end
function class.component:onkeydown()end
function class.component:dodraw(dx,dy)
	self:ondraw(dx,dy)
end
function class.component:dofocus(get)
	if get then
		self:onfocus()
	else
		self:onblur()
	end
end
function class.component:domouse(x,y,b,e,s)
	self:onmouse(x,y,b,e,s)
	if s==0 then
		if e==1 then
			self:onmousedown(x,y,b)
		elseif e==2 then
			self:onmouseup(x,y,b)
		else
			self:onmousemove(x,y,b)
		end
	else
		self:onscroll(x,y,s)
	end
	return true
end
function class.component:dokey(a,b,c,d)
	self:onkey(a,b,c,d)
	if d==1 then
		self:onkeydown(a,b,c)
	elseif d==2 then
		self:onkeyup(a,b,c)
	end
end

-- button
class.button=class.component:INHERIT()
class.button.caption=""
class.button.down=false
class.button.bgcolor=0xC0C0C0
class.button.fgcolor=0x000000
function class.button:onclick()end
function class.button:dodraw(dx,dy)
	local x,y,w,h=(dx or 0)+self.x,(dy or 0)+self.y,self.w,self.h
	bevel(x,y,w,h,self.down)
	tptfillrect(x,y,w,h,h2c(self.bgcolor))
	tptdrawtext(x+w/2-tpt.textwidth(self.caption)/2,y+h/2-3,self.caption,h2c(self.fgcolor))
	class.component.ondraw(self,dx,dy)
end
function class.button:domouse(x,y,b,e,s)
	if s==0 then
		if b==1 then
			if e==1 then
				self.down=true
			elseif e==2 then
				self.down=false
				self:onclick(x,y)
			end
		end
		return true
	end
end

-- container
class.container=class.component:INHERIT()
class.container.children={}
class.container.childorder={}
class.container.focus=0
function class.container:dodrawself(dx,dy)end
function class.container:dodraw(dx,dy)
	self:dodrawself(dx,dy)
	class.component.dodraw(self,dx,dy)
	self.childorder=rawget(self,"childorder")or{}
	local i=1
	while i<=#self.childorder do
		local found
		for _,child in pairs(self.children) do
			if self.childorder[i]==child then
				found=true
				break
			end
		end
		if found then
			i=i+1
		else
			table.remove(self.childorder,i)
		end
	end
	for _,child in pairs(self.children) do
		local found
		for _,entry in ipairs(self.childorder) do
			if entry==child then
				found=true
				break
			end
		end
		if not found then
			table.insert(self.childorder,child)
		end
	end
	for _,child in ipairs(self.childorder) do
		if child.visible and child~=self.focus then
			child:dodraw(self.x+(dx or 0),self.y+(dy or 0))
		end
	end
	if type(self.focus)~="number" and self.focus~=self then
		self.focus:dodraw(self.x+(dx or 0),self.y+(dy or 0))
	end
end
function class.container:dofocus(get)
	if not get and type(self.focus)~="number" and self.focus~=self then
		self.focus:dofocus(get)
		self.focus=0
	end
	class.component:dofocus(get)
end
function class.container:domouseself(x,y,b,e,s)end
function class.container:domouse(x,y,b,e,s)
	if e==1 then
		local sent
		for i=#self.childorder,1,-1 do
			local child=self.childorder[i]
			if child.visible and child.x<=x and child.y<=y and child.x+child.w>=x and child.y+child.h>y then
				child:domouse(x-child.x,y-child.y,b,e,s)
				if self.focus~=child then
					if type(self.focus)~="number" then
						self.focus:dofocus(false)
					end
					self.focus=child
					table.remove(self.childorder,i)
					table.insert(self.childorder,child)
					self.focus:dofocus(true)
				end
				sent=true
				break
			end
		end
		if not sent then
			if type(self.focus)~="number" and self.focus~=self then
				self.focus:dofocus(false)
			end
			self.focus=self
			self:domouseself(x,y,b,e,s)
			class.component.domouse(self,x,y,b,e,s)
			return true
		end
		return false
	else
		if self.focus==self then
			self:domouseself(x,y,b,e,s)
			return true
		elseif type(self.focus)~="number" then
			self.focus:domouse(x-self.focus.x,y-self.focus.y,b,e,s)
			return false
		end
		return true
	end
end
function class.container:dokey(x,y,b,e,s)
	if type(self.focus)~="number" and self.focus~=self then
		return self.focus:dokey(x,y,b,e,s)
	else
		return class.component.dokey(self,x,y,b,e,s)
	end
end

-- global
global=class.container:new{x=0,y=0,w=611,h=383}
tpt.register_step(function()global:dodraw(0,0)end)
tpt.register_mouseclick(function(...)return global:domouse(...)end)
tpt.register_keypress(function(...)return global:dokey(...)end)

-- window
class.window=class.container:INHERIT()
class.window.caption=""
class.window.dragx=""
class.window.dragy=""
class.window.headcolor=0x000080
class.window.fgcolor=0xFFFFFF
class.window.bgcolor=0xC0C0C0
function class.window:dodrawself(dx,dy)
	local x,y,w,h=(dx or 0)+self.x,(y or 0)+self.y,self.w,self.h
	bevel(x,y,w,h,false)
	tptfillrect(x,y,w,h,h2c(self.bgcolor))
	bevel(x,y,w,12,false)
	tptfillrect(x,y,w,12,h2c(self.headcolor))
	tptdrawtext(x+2,y+3,self.caption,h2c(self.fgcolor))
end
function class.window:dodraw(dx,dy)
	class.container.dodraw(self,dx,(dy or 0)+12)
end
function class.window:domouse(x,y,b,e,s)
	if (e~=1 and self.dragx~="" and self.dragy~="")or(e==1 and y<12) then
		if b==1 then
			if e==1 then
				self.dragx,self.dragy=x,y
			elseif e==3 then
				self.x=self.x+x-self.dragx
				self.y=self.y+y-self.dragy
			else
				self.x,self.dragx=self.x+x-self.dragx,""
				self.y,self.dragy=self.y+y-self.dragy,""
			end
		end
		return true
	else
		return class.container.domouse(self,x,y-12,b,e,s)
	end
end

-- label
class.label=class.component:INHERIT()
class.label.caption=""
class.label.color=0xFFFFFF
function class.label:dodraw(dx,dy)
	local x,y,w,h=(dx or 0)+self.x,(dy or 0)+self.y,self.w,self.h
	local s=self.caption
	while #s>0 and tpt.textwidth(s)>w do
		s=s:sub(1,-2)
	end
	tptdrawtext(x,y+h/2-3,s,h2c(self.color))
end

-- edit
class.edit=class.component:INHERIT()
class.edit.text=""
class.edit.cursor=0
class.edit.focus=false
class.edit.scroll=1
class.edit.bgcolor=0xFFFFFF
class.edit.fgcolor=0x000000
function class.edit:onenter()end
function class.edit:dodraw(dx,dy)
	local x,y,w,h=(dx or 0)+self.x,(dy or 0)+self.y,self.w,self.h
	bevel(x,y,w,h,true)
	class.component.dodraw(self,dx,dy)
	tptfillrect(x,y,w,h,h2c(self.bgcolor))
	local s=self.text
	s=s:sub(self.scroll)
	while #s>1 and tpt.textwidth(s)>w-4 do
		s=s:sub(1,-2)
	end
	tptdrawtext(x+2,y+h/2-3,s,h2c(self.fgcolor))
	if self.focus then
		if self.cursor~=0 and self.cursor<self.scroll then
			self.scroll=self.cursor
		else
			while tpt.textwidth(self.text:sub(self.scroll,self.cursor))>self.w-4 do
				self.scroll=self.scroll+1
			end
		end
		local d=tpt.textwidth(s:sub(1,self.cursor-self.scroll+1))
		tptdrawline(x+d+2,y+h/2-5,x+d+2,y+h/2+5,h2c(self.fgcolor))
	end
end
function class.edit:dofocus(get)
	self.focus=get
	class.component.dofocus(self,get)
end
function class.edit:domouse(x,y,b,e,s)
	if s==0 and b==1 and e==1 then
		local s=self.text:sub(self.scroll)
		x=x-tpt.textwidth(s:sub(1,1))/2-2
		self.cursor=self.scroll-1
		while #s>0 and x>0 do
			x=x-tpt.textwidth(s:sub(1,2))/2-0.5
			s=s:sub(2)
			self.cursor=self.cursor+1
		end
	end
	class.component.domouse(self,x,y,b,e,s)
end
function class.edit:dokey(a,b,c,d)
	if d==1 then
		self.cursor=math.max(math.min(#self.text,self.cursor),0)
		if b>31 and b<127 then
			if math.floor(c/2)%2~=c%2 then
				local from=[[`1234567890-=qwertyuiop[]\asdfghjkl;'zxcvbnm,./]]
				local to  =[[~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:"ZXCVBNM<>?]]
				if from:find(a,1,true) then
					a=to:sub(from:find(a,1,true))
				end
			end
			if math.floor(c/8192)%2==1 then
				local from=[[qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM]]
				local to  =[[QWERTYUIOPASDFGHJKLZXCVBNMqwertyuiopasdfghjklzxcvbnm]]
				if from:find(b,1,true) then
					a=to:sub(from:find(a,1,true))
				end
			end
			self.text=self.text:sub(1,self.cursor)..a..self.text:sub(self.cursor+1)
			self.cursor=self.cursor+1
		elseif b==8 then
			self.text=self.text:sub(1,math.max(0,self.cursor-1))..self.text:sub(self.cursor+1)
			self.cursor=math.max(0,self.cursor-1)
		elseif b==13 then
			self:onenter()
		elseif b==127 then
			self.text=self.text:sub(1,self.cursor)..self.text:sub(self.cursor+2)
		elseif b==276 then
			self.cursor=math.max(0,self.cursor-1)
		elseif b==275 then
			self.cursor=math.min(#self.text,self.cursor+1)
		end
	end
	return false
end

-- textarea
class.textarea=class.edit:INHERIT()
class.textarea.vscroll=1
function class.textarea:dodraw(dx,dy)
	local x,y,w,h=(dx or 0)+self.x,(dy or 0)+self.y,self.w,self.h
	bevel(x,y,w,h,true)
	tptfillrect(x,y,w,h,h2c(self.bgcolor))
	local n=0
	local t=self.text.."\n"
	for a,s,b in t:gmatch"()([^\n]*)()\n" do
		n=n+1
		if n>=self.vscroll and n<=self.vscroll+(self.h-4)/10 then
			local p=s:sub(self.scroll)
			while #p>1 and tpt.textwidth(p)>w-4 do
				p=p:sub(1,-2)
			end
			tptdrawtext(x+2,y+2+10*(n-self.vscroll),p,h2c(self.fgcolor))
			if self.focus then
				if self.cursor>=a-1 and self.cursor<b then
					if self.cursor-a~=0 and self.cursor-a+1<self.scroll then
						self.scroll=self.cursor-a+1
					else
						while tpt.textwidth(s:sub(self.scroll,self.cursor-a+1))>self.w-4 do
							self.scroll=self.scroll+1
						end
					end
					local d=tpt.textwidth(s:sub(self.scroll,self.cursor-a+1))
					tptdrawline(x+d+2,y+1+10*(n-self.vscroll),x+d+2,y+11+10*(n-self.vscroll),h2c(self.fgcolor))
				end
			end
		elseif n<self.vscroll and self.cursor<b then
			self.vscroll=self.vscroll-1
		elseif n>=self.vscroll+(self.h-4)/10 and self.cursor>=a-1 then
			self.vscroll=self.vscroll+1
		end
	end
end
function class.edit:domouse(x,y,b,e,s)
	if s==0 and b==1 and e==1 then
		local l=math.floor((y-2)/10)+self.vscroll
		local t=self.text.."\n"
		local n=0
		self.cursor=#t-1
		for a,s in t:gmatch"()([^\n]*)\n" do
			n=n+1
			if n==l then
				local s=s:sub(self.scroll)
				x=x-tpt.textwidth(s:sub(1,1))/2-2
				self.cursor=a+self.scroll-1
				while #s>0 and x>0 do
					x=x-tpt.textwidth(s:sub(1,2))/2-0.5
					s=s:sub(2)
					self.cursor=self.cursor+1
				end
				break
			end
		end
	end
	class.component.domouse(self,x,y,b,e,s)
end
function class.textarea:dokey(a,b,c,d)
	if d==1 then
		if b==13 then
			self.text=self.text:sub(1,self.cursor).."\n"..self.text:sub(self.cursor+1)
			self.cursor=self.cursor+1
		elseif b==273 then
			if self.text:sub(1,self.cursor):find("\n",1,true) then
				local w=self.cursor-self.text:sub(1,self.cursor):match"\n()[^\n]*$"+1
				local s,f=self.text:sub(1,self.cursor):match"()[^\n]*()\n[^\n]*$"
				self.cursor=math.min(f,s+w)-1
			end
		elseif b==274 then
			if self.text:find("\n",self.cursor+1,true) then
				local w=self.cursor-self.text:sub(1,self.cursor):match"()[^\n]*$"+1
				local f,s=select(2,self.text:find("\n()[^\n]*",self.cursor+1))
				self.cursor=math.min(s+w-1,f)
			end
		else
			class.edit.dokey(self,a,b,c,d)
		end
	end
	return false
end
