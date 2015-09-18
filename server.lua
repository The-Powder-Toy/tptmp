#!/usr/bin/lua
local server
WINDOWS = package.config:sub(1,1) == "\\"
local succ,err=pcall(function()
	if not WINDOWS then
		local f=io.open".tptmp.pid"
		if f then
			local n=f:read"*n"
			os.execute("kill -2 "..n)
			f:close()
		end
		f=io.open(".tptmp.pid","w")
		local p=io.popen"echo $PPID"
		f:write(p:read"*a")
		p:close()
		f:close()
	end

-------- SERVER BODY

	-- init server socket
	local socket=require"socket"
	local config=dofile"config.lua"
	dofile"protocol.lua"
	local succ,err=socket.bind(config.bindhost,config.bindport,10)
	local crackbotServer=socket.bind("localhost",34404,1)--socket.tcp()
	crackbot = nil
	crackbotServer:settimeout(0)
	
	if not succ then
		error("Could not bind: "..err)
	end
	server = succ
	server:settimeout(0)
	
	local dataHooks={}
	function addHook(cmd,f,front)
		cmd = type(cmd)=="string" and protoNames[cmd] or cmd
		dataHooks[cmd] = dataHooks[cmd] or {}
		table.insert(dataHooks,f,front)
	end
	bans={}
	stabbed={}
	muted={}

	clients={}
	rooms={}
	
	dofile("serverhooks.lua")
	
	-- nonblockingly read a null-terminated string
	function nullstr()
		local t={}
		local d=coroutine.yield()
		while d~="\0" do
			table.insert(t,d)
			d=coroutine.yield()
		end
		return table.concat(t)
	end

	-- nonblockingly read a byte
	function byte()
		return coroutine.yield():byte()
	end
	function char()
		return coroutine.yield()
	end
	
	-- nonblock read amt bytes from socket
	function bytes(sock,amt)
		local final = ""
		local timeout,rec = socket.gettime(),0
		while rec<amt do
			local s,r,e = sock:receive(amt-rec)
			if not s then 
				if r~="timeout" then
					return false,"Error while getting bytes"
				end
				rec = rec + #e
				if rec < amt then
					e = e .. coroutine.yield()
					rec = rec+1
				end
				final = final..e
			else
				final = final..s
				break
			end
			if socket.gettime()-timeout>15 then return false,"Byte send took too long" end
		end
		--print("Received "..amt.." bytes in "..(socket.gettime()-timeout))
		return true,final
	end
	function sendRawString(socket,data)
		socket:send(data)
	end
	function sendProtocol(socket,proto,id)
		local prot = proto.protoID
		local head = string.char(prot)..(no_ID_protocols[prot] and "" or string.char(id))
		socket:send(head..proto:writeData())
	end
	-- send to all users on room except given one (usually self)
	function sendroomexcept(room,uid,data)
		for _,id in ipairs(rooms[room]) do
			if id~=uid then
				sendProtocol(clients[id].socket,data,uid)
				--clients[id].socket:send(data)
			end
		end
	end
	function sendroomexceptLarge(room,uid,data)
		for _,id in ipairs(rooms[room]) do
			if id~=uid then
				clients[id].socket:settimeout(8)
				sendProtocol(clients[id].socket,data,uid)
				--local s,r,e = clients[id].socket:send(data)
				clients[id].socket:settimeout(0)
			end
		end
	end

	-- leave a room
	function leave(room,uid)
		--print(clients[uid].nick.." left "..room)
		sendroomexcept(room,uid,"\18"..string.char(uid))
		for i,id in ipairs(rooms[room]) do
			if id==uid then
				table.remove(rooms[room],i)
				break
			end
		end
		if #rooms[room]==0 then
			rooms[room]=nil
			--print("Deleted room '"..room.."'")
		end
		onChat(clients[uid],-2,room)
	end

	-- join a room
	function join(room,id)
		local client=clients[id]
		--print(client.nick.." joined "..room)
		if not rooms[room] then
			rooms[room]={}
			--print("Created room '"..room.."'")
		end
		client.room=room

		--hook system (check if user is allowed)
		if onChat(client, 1, room) then
			if room ~= "null" then
				join('null', id)
			else
				disconnect(id, 'Banned from lobby')
			end
			return
		end

		-- send who's in room
		client.socket:send("\16"..string.char(#rooms[room]))
		for _,uid in ipairs(rooms[room]) do
			client.socket:send(string.char(uid)..clients[uid].nick.."\0")
		end
		for _,uid in ipairs(rooms[room]) do
			client.socket:send(("\35"..string.char(uid)):rep(clients[uid].brush).."\34"..string.char(uid)..clients[uid].size)
			for i=1,4 do
				client.socket:send("\37"..string.char(uid)..clients[uid].selection[i])
			end
			client.socket:send("\38"..string.char(uid)..clients[uid].replacemode)
			client.socket:send("\65"..string.char(uid)..clients[uid].deco)
		end
		table.insert(rooms[room],id)
		sendroomexcept(room,id,"\17"..string.char(id)..client.nick.."\0")
		if #rooms[room]>1 then
			print("asking "..rooms[room][1].." to provide sync")
			clients[rooms[room][1]].socket:send("\128"..string.char(id))
		end
	end

	function serverMsg(client, message, r, g, b)
		client.socket:send("\22"..message.."\0"..string.char(r or 127)..string.char(g or 255)..string.char(b or 255))
	end

	function serverMsgExcept(room, except, message, r, g, b)
		for _,uid in ipairs(rooms[room]) do
			if clients[uid].nick ~= except then
				serverMsg(clients[uid], message, r, g, b)
			end
		end
	end

	function kick(victim, moderator, reason)
		local message = "You were kicked by "..moderator
		if #reason > 0 then
			message = message..": "..reason
		end
		serverMsg(clients[victim], message, 255, 50, 50)
		print(moderator.." has kicked "..clients[victim].nick.." from "..clients[victim].room.." ("..reason..")")
		serverMsgExcept(clients[victim].room, clients[victim].nick, moderator.." has kicked "..clients[victim].nick.." from "..clients[victim].room.." ("..reason..")")
		disconnect(victim, "kicked by "..moderator..": "..reason)
	end

	function stab(victim, perpetrator, dostab)
		stabbed[clients[victim].nick] = dostab
		clients[victim].socket:send("\23"..(dostab and '\1' or '\0'))
		print(perpetrator.." has "..(dostab and "" or "un").."stabbed "..clients[victim].nick)
		serverMsgExcept(clients[victim].room, clients[victim].nick, clients[victim].nick.." has been "..(dostab and "" or "un").."stabbed by "..perpetrator)
	end

	function mute(victim, moderator, domute)
		muted[clients[victim].nick] = domute
		clients[victim].socket:send("\24"..(domute and '\1' or '\0'))
		print(moderator.." has "..(domute and "" or "un").."muted "..clients[victim].nick)
		serverMsgExcept(clients[victim].room, clients[victim].nick, clients[victim].nick.." has been "..(domute and "" or "un").."muted by "..moderator)
	end

	function modaction(moderator, id, nick, f, ...)
		local found = false
		for _,uid in ipairs(rooms[moderator.room]) do
			if clients[uid].nick == nick then
				if not onChat(clients[moderator], id, nick) then
					f(uid, ...)
					found = true
				end
			end
		end
		if not found then
			serverMsg(moderator, "User \""..nick.."\" not found")
		end
	end

	-- coroutine that handles the client
	function handler(id,client)
		--local major,minor,scriptver=byte(),byte(),byte()
		--client.nick=nullstr()
		local initial = protocolArray(protoNames["Init_Connect"]):readData(client.socket)
		client.nick = initial.nick
		for k,v in pairs(bans) do
			if client.host:match(v) then
				client.socket:send("\0You are banned\0")
				disconnect(id,"Banned user")
			end
		end
		if initial.minor~=config.versionminor or initial.major~=config.versionmajor then
			sendProtocol(client.socket,protocolArray(protoNames["Disconnect"]).reason("Your version mismatched (requires "..config.versionmajor.."."..config.versionminor..")"))
			disconnect(id,"Bad version "..initial.major.."."..initial.minor)
			return
		end
		if initial.script~=config.scriptversion then
			sendProtocol(client.socket,protocolArray(protoNames["Disconnect"]).reason("Your script version mismatched, try updating it"))
			disconnect(id,"Bad script version "..initial.script)
			return
		end
		if not client.nick:match("^[%w%-%_]+$") then
			sendProtocol(client.socket,protocolArray(protoNames["Disconnect"]).reason("Bad Nickname!"))
			disconnect(id,"Bad nickname")
			return
		end
		if #client.nick > 32 then
			sendProtocol(client.socket,protocolArray(protoNames["Disconnect"]).reason("Nick too long!"))
			disconnect(id,"Nick too long")
			return
		end
		for k,v in pairs(clients) do
			if k~=id and v.nick == client.nick then
				sendProtocol(client.socket,protocolArray(protoNames["Disconnect"]).reason("This nick is already on the server"))
				disconnect(id,"Duplicate nick")
				return
			end
		end
		local modes = protocolArray(protoNames["User_Mode"]).userID(id).stab(stabbed[client.nick] and 1 or 0)
		modes.mute(muted[client.nick] and 1 or 0)
		sendProtocol(socket.client,modes) -- tell client their modes
		
		client.brush=0
		client.brushX, client.brushY = 4,4
		client.selection={"\0\1","\64\0","\128\0"}
		client.replacemode=0
		client.deco=0
		client.op=false
		
		print(client.nick.." done identifying")
		sendProtocol(client.socket,protocolArray(protoNames["Connect_Succ"]))
		join("null",id)
		while 1 do
			local cmd=byte()
			
			if not protoNames[cmd] then print("Unknown Protocol! DIE") sendProtocol(client.socket,protocolArray(protoNames["Disconnect"]).reason("Bad protocol sent")) disconnect("Bad Protocol")  break end
			local prot = protocolArray(cmd):readData(client.socket)
			
			print("Got "..protoNames[cmd].." from "..client.nick.." "..prot:tostring())
			--We should, uhm, try calling protocol hooks here, maybe
			if dataHooks[cmd] then
				for i,v in ipairs(dataHooks) do
					--Hooks can return true to stop future hooks
					if v() then break end
				end
			else
				print("No hooks for "..protoNames[cmd])
			end
		end
	end

	-- disconnects a client
	function disconnect(id,err)
		local client=clients[id]
		if not client then return end
		client.socket:close()
		print((client.nick or id)..": Connection to "..(client.host or"?")..":"..(client.port or"?").." closed: "..err)
		if client.room then
			leave(client.room,id)
		else
			print"nothing to leave"
		end
		clients[id]=nil
		onChat(client,-1,err)
	end
	local function runLua(msg)
		local e,err = loadstring(msg)
		if e then
			--debug.sethook(infhook,"l")
			local s,r = pcall(e)
			--debug.sethook()
			--stepcount=0
			if s then
				local str = tostring(r):gsub("[\r\n]"," ")
				return str
			else
				return "ERROR: " .. r
			end
			return
		end
		return "ERROR: " .. err
	end
	function readCrackbot()
		local s,r = crackbot:receive("*l")
		if not s then
			if r~= "timeout" then
				crackbot=nil
			end
			return
		end
		crackbot:send(runLua(s).."\n")
	end
	--[=[
			What were these for? can these checks use the new hooks?
			if cmd~=16 and cmd~=19 and cmd~=20 and cmd~=21 and cmd~=23 and cmd~=24 then --handled separately with more info
				if onChat(client,cmd) then --allow any events to be canceled with hooks
					cmd=0 --hack
				end 
			end
	--]=]
	local function genericRelay(client, id, data)
		sendroomexcept(client.room,id,data)
	end
	addHook("Ping",function(client) 
		client.lastping=os.time() 
		sendProtocol(client,protocolArray(protoNames["Pong"]))
	end)
	addHook("Pong",function(client) end) --Who should ping? Server or client
	addHook("Join_Channel",function(client, id, data)
		local room = data.channel()
		if not room:match("^[%w%-%_]+$") or #room > 32 then
			serverMsg(client, "Invalid room name "..room)
			return true
		end
	end)
	addHook("Join_Channel",function(client, id, data)
		leave(client.room,id)
		join(data.channel(),id)
	end)
	addHook("User_Chat",function(client, id, data)
		local msg=data.msg()
		if muted[client.nick] then
			serverMsg(client, "You have been muted and cannot chat")
		elseif not msg:match("^[ -~]*$") then
			serverMsg(client, "Invalid characters detected in message, not sent")
		elseif #msg > 200 then
			serverMsg(client, "Message too long, not sent")
		else return end
		return true
	end)
	addHook("User_Chat",function(client, id, data)
		print("<"..client.nick.."> "..data.msg())
		sendroomexcept(client.room,id,data)
	end)
	addHook("User_Me",function(client, id, data)
		local msg=data.msg()
		if muted[client.nick] then
			serverMsg(client, "You have been muted and cannot chat")
		elseif not msg:match("^[ -~]*$") then
			serverMsg(client, "Invalid characters detected in message, not sent")
		elseif #msg > 200 then
			serverMsg(client, "Message too long, not sent")
		else return end
		return true
	end)
	addHook("User_Me",function(client, id, data)
		print("* "..client.nick.." "..msg)
		sendroomexcept(client.room,id,data)
	end)
	addHook("User_Kick",function(client, id, data)
		local reason = data.reason()
		if not reason:match("^[ -~]*$") then
			serverMsg(client, "Invalid characters detected in kick reason")
		elseif #reason > 200 then
			serverMsg(client, "Kick reason too long, not sent")
		elseif not client.op and client.room == "null" then
			serverMsg(client, "You can't kick people from the lobby")
		elseif not client.op and rooms[client.room][1] ~= id then
			serverMsg(client, "You can't kick people from here")
		else return end
		return true
	end)
	addHook("User_Kick",function(client, id, data)
		modaction(client, 21, data.nick(), kick, client.nick, data.reason())
	end)
	addHook("Set_User_Mode",function(client, id, data)
		local doStab, doMute = data.modes.stab()==1, data.modes.mute()==1
		if not client.op then
			serverMsg(client, "You aren't an op!")
		elseif data.nick() == client.nick then
			serverMsg(client, "You can't do that to yourself!")
		else return end
		return true
	end)
	addHook("Set_User_Mode",function(client, id, data
		local nick = data.nick()
		modaction(client, 23, nick, stab, client.nick, data.modes.stab()==1)
		modaction(client, 24, nick, mute, client.nick, data.modes.mute()==1)
		client.op = data.modes.op()==1
	end)
	addHook("Get_User_Mode",function(client, id, data)
		local nick,packet = data.nick(), protocolArray(protoNames["User_Mode"])
		packet.modes.stab(stabbed[nick] and 1 or 0)
		packet.modes.mute(muted[nick] and 1 or 0)
		packet.modes.op(client.op and 1 or 0)
	end)
	addHook("Mouse_Pos",genericRelay)
	addHook("Mouse_Click",genericRelay)
	addHook("Brush_Size",function(client, id, data)
		client.brushX, client.brushY = data.x(), data.y()
		--This was client.size before, check it
		sendroomexcept(client.room,id,data)
	end)
	addHook("Brush_Shape",function(client, id, data)
		client.brush = data.shape()
		sendroomexcept(client.room,id,data)
	end)
	addHook("Key_Mods",genericRelay)
	addHook("Selected_Elem",function(client, id, data)
		client.selection[data.selected.button()+1] = data.selected.elem()
		sendroomexcept(client.room,id,data)
	end)
	addHook("Replace_Mode",function(client, id, data)
		client.replacemode = data.replacemode()
		sendroomexcept(client.room,id,data)
	end)
	addHook("Zoom_State",genericRelay)
	addHook("View_Mode_Simple",genericRelay)
	addHook("Pause_State",genericRelay)
	addHook("Frame_Step",genericRelay)
	addHook("Deco_State",genericRelay)
	addHook("Ambient_State",genericRelay)
	addHook("NGrav_State",genericRelay)
	addHook("Heat_State",genericRelay)
	addHook("Equal_State",genericRelay)
	addHook("Grav_Mode",genericRelay)
	addHook("Air_Mode",genericRelay)
	addHook("Clear_Spark",genericRelay)
	addHook("Clear_Press",genericRelay)
	addHook("Invert_Press",genericRelay)
	addHook("Clear_Sim",genericRelay)
	addHook("View_Mode_Advanced",genericRelay)
	addHook("Selected_Deco",function(client, id, data)
		client.deco = data.RGBA()
		sendroomexcept(client.room,id,data)
	end)
	addHook("Stamp_Data",function(client, id, data)
		if client.ignore then
			serverMsg(client, "You aren't allowed to place stamps!")
			return true
		end
	end)
	addHook("Stamp_Data",function(client, id, data)
		if data.data() then
			print("STAMP! Loaded From "..client.nick.." size "..data.totalSize())
			sendroomexcept(client.room,id,data)'
		else disconnect(id, "Failed stamp data")
		end
	end)
	addHook("Clear_Area",genericRelay)
	addHook("Edge_Mode",genericRelay)
	addHook("Load_Save",genericRelay)
	addHook("Reload_Sim",genericRelay)
	addHook("Player_Sync",function(client, id, data)
		--Need to confirm that userID is actually expecting specific packets
		sendRawString(clients[data.userID()].socket,string.char(data.proto()..string.char(id)..data.data())
		sendroomexcept(client.room,id,data)
	end)
	--Add these hooks into first slot, runs before others
	local stabBlock = {33,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,66,67,68,69,70}
	for k,v in pairs(stabBlock) do
		addHook(stabBlock,function(client, id, data)
			if stabbed[client.nick] then
				return true
			end
		end,1)
	end
-------- MAIN LOOP
	while 1 do
		-- has anything happened on this iteration
		local anything
		-- check connections
		if not crackbot then
			crackbot = crackbotServer:accept()
			if crackbot then crackbot:settimeout(0) end
		else
			readCrackbot()
		end
		local conn,err=server:accept()
		if err and err~="timeout" then
			io.stderr:write("!!! Failed to accept client: "..err)
		elseif conn then
			conn:settimeout(0)
			local host,port=conn:getpeername()
			print("New connection: "..(host or"?")..":"..(port or"?"))
			-- look for free IDs
			local hasid
			for i=0,255 do
				if not clients[i] then
					clients[i]={socket=conn,host=host,port=port,lastping=os.time(),coro=coroutine.create(handler)}
					ret, err = coroutine.resume(clients[i].coro,i,clients[i])
					if not ret then
						print(err)
						conn:close()
					end
					hasid=i
					break
				end
			end
			if hasid then
				print("Assigned ID is "..hasid)
			else
				conn:send"\0Server has too many users\0"
				print"No user IDs left"
				conn:close()
			end
			anything=true
		end
		-- update states of each client
		for id,client in pairs(clients) do
			-- ping timeout?
			if client.lastping+config.pingtimeout<os.time() then
				disconnect(id,"ping timeout")
			else
				local c,err=client.socket:receive(1)
				while c do
					anything=true
					ret, err = coroutine.resume(client.coro,c)
					if not ret then
						print(err)
						disconnect(id,"server error")
					end
					if not clients[id] then
						err=nil
						break
					end
					c,err=client.socket:receive(1)
				end
				if err and err~="timeout" then
					disconnect(id,err)
					anything=true
				end
			end
		end
		-- to prevent 100% cpu usage, sleep if been doing nothing
		if not anything then
			socket.sleep(0.01)
		end
	end
-------- END OF SERVER BODY
end)
os.remove".tptmp.pid"
if not succ and not err:match"interrupted!$" then
	io.stderr:write("*** CRASH! "..err,"\n")
	io.stderr:write(debug.traceback(),"\n")
end
