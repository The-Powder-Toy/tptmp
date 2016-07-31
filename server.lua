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
	local crackbotServer=socket.bind("127.0.0.1",34406,1)
	crackbot = nil
	crackbotServer:settimeout(0)
	
	if not succ then
		error("Could not bind: "..err)
	end
	server = succ
	server:settimeout(0)
	math.randomseed(os.time())
	--Protocols that edit the simulation in some way.
	local _editSim, editSim = {33,48,49,50,51,53,54,56,57,58,59,60,61,62,63,64,66,67,68,69,70,71}, {}
	--Protocols that don't send an ID to client
	local _noIDProt, noIDProt = {2,3,4,8,9,13,14,15,22,23,24,25,128,129}, {}
	for i,v in ipairs(_editSim) do editSim[v]=true end for i,v in ipairs(_noIDProt) do noIDProt[v]=true end
	local dataHooks={}
	function addHook(cmd,f,front)
		if not protoNames[cmd] then error("Invalid protocol "..cmd) end
		cmd = type(cmd)=="string" and protoNames[cmd] or cmd
		dataHooks[cmd] = dataHooks[cmd] or {}
		if front then table.insert(dataHooks[cmd],front,f)
		else table.insert(dataHooks[cmd],f) end
	end
	function dataHookCount(cmd) return dataHooks[protoNames[cmd]] and #dataHooks[protoNames[cmd]] or nil end
	bans={}
	stabbed={}
	muted={}
	clients={}
	rooms={}
	
	
	
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
	function getByte()
		return coroutine.yield():byte()
	end
	function char()
		return coroutine.yield()
	end
	
	-- nonblock read amt bytes from socket
	function getBytes(sock,amt)
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
		if not prot then print("Nil protocol "..proto:tostring()) return end
		local head = string.char(prot)..(noIDProt[prot] and "" or string.char(id))
		socket:send(head..proto:writeData())
	end
	-- send to all users on room except given one (usually self)
	function sendroomexcept(room,uid,data)
		if not rooms[room] then return end
		for _,id in ipairs(rooms[room]) do
			if id~=uid and clients[id] and clients[id].socket then
				sendProtocol(clients[id].socket,data,uid)
			end
		end
	end
	function sendroomexceptLarge(room,uid,data)
		if not rooms[room] then return end
		for _,id in ipairs(rooms[room]) do
			if id~=uid and clients[id] and clients[id].socket then
				clients[id].socket:settimeout(8)
				sendProtocol(clients[id].socket,data,uid)
				clients[id].socket:settimeout(0)
			end
		end
	end

	-- leave a room
	function leave(room,uid)
		--print((clients[uid] and clients[uid].nick or "UNKNOWN").." left "..room)
		if clients[uid] then
			sendroomexcept(room,uid,P.User_Leave)
		end
		if not rooms[room] then return end
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

		-- check for major errors that should never happen but will break the server entirely if they do
		for _,uid in ipairs(rooms[room]) do
			if not clients[uid] then
				crackbot:send("ERROR: client "..uid.." in room "..room.." doesn't exist, removing\n")
				leave(room, uid)
				if not rooms[room] then
					rooms[room]={}
					print("Re-created room '"..room.."' due to error")
				end
			end
		end

		-- Confirm the changed channel back to new user
		sendProtocol(client.socket,P.Chan_Name.chan(room))
		-- Existing users -> New user
		for _,uid in ipairs(rooms[room]) do
			sendProtocol(client.socket,P.Chan_Member.name(clients[uid].nick),uid)
			sendProtocol(client.socket,P.Brush_Shape.shape(clients[uid].brush),uid)
			sendProtocol(client.socket,P.Brush_Size.x(clients[uid].brushX).y(clients[uid].brushY),uid)
			for i=0,3 do
				sendProtocol(client.socket,P.Selected_Elem.selected.button(i).selected.elem(clients[uid].selection[i+1]),uid)
			end
			sendProtocol(client.socket,P.Replace_Mode.replacemode(clients[uid].replacemode),uid)
			sendProtocol(client.socket,P.Selected_Deco.RGBA(clients[uid].deco),uid)
		end
		table.insert(rooms[room],id)
		-- New user -> Existing users
		sendroomexcept(room,id,P.User_Join.name(client.nick))
		sendroomexcept(room,id,P.Brush_Shape.shape(client.brush))
		sendroomexcept(room,id,P.Brush_Size.x(client.brushX).y(client.brushY))
		for i=0,3 do
			sendroomexcept(room,id,P.Selected_Elem.selected.button(i).selected.elem(clients[id].selection[i+1]))
		end
		sendroomexcept(room,id,P.Replace_Mode.replacemode(client.replacemode))
		sendroomexcept(room,id,P.Selected_Deco.RGBA(client.deco))
		-- Ask for a sync from oldest user
		if #rooms[room]>1 then
			local first = rooms[room][1]
			print("asking "..first.." to provide sync for "..id)
			sendProtocol(clients[first].socket,P.Req_Player_Sync.userID(id))
			clients[first].synced = {[id]={}}
		end
	end

	function serverMsg(client, message, r, g, b)
		sendProtocol(client.socket,P.Server_Broadcast.msg(message).R(r or 127).G(g or 255).B(b or 255))
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
		local client = clients[victim]
		serverMsg(client, message, 255, 50, 50)
		print(moderator.." has kicked "..client.nick.." from "..client.room.." ("..reason..")")
		serverMsgExcept(client.room, client.nick, moderator.." has kicked "..client.nick.." from "..client.room.." ("..reason..")")
		disconnect(victim, "kicked by "..moderator..": "..reason)
	end

	function stab(victim, perpetrator, dostab)
		stabbed[clients[victim].nick] = dostab
		print(perpetrator.." has "..(dostab and "" or "un").."stabbed "..clients[victim].nick)
		serverMsgExcept(clients[victim].room, clients[victim].nick, clients[victim].nick.." has been "..(dostab and "" or "un").."stabbed by "..perpetrator)
	end

	function mute(victim, moderator, domute)
		muted[clients[victim].nick] = domute
		print(moderator.." has "..(domute and "" or "un").."muted "..clients[victim].nick)
		serverMsgExcept(clients[victim].room, clients[victim].nick, clients[victim].nick.." has been "..(domute and "" or "un").."muted by "..moderator)
	end

	function modaction(moderator, id, nick, f, ...)
		local found, fid = false, 0
		for _,uid in ipairs(rooms[moderator.room]) do
			if clients[uid].nick == nick then
				--[[if not onChat(clients[moderator], id, nick) then
					f(uid, ...)
					found, fid = true, uid
					
				end]]
			end
		end
		if not found then
			serverMsg(moderator, "User \""..nick.."\" not found")
		else
			return fid
		end
	end

	-- coroutine that handles the client
	function handler(id,client)
		local init = getByte()
		if init~=protoNames["Init_Connect"] then
			disconnect(id,"Invalid Connect")
		end
		local initial = P.Init_Connect:readData(client.socket)
		local newnick = initial.nick()
		client.nick = newnick
		if newnick == "" then
			newnick = "Guest"..math.random(10000,99999)
		end
		print("Got connect from "..newnick.." "..initial:tostring())
		for k,v in pairs(bans) do
			if client.host:match(v) then
				sendProtocol(client.socket,P.Disconnect.reason("You are banned"))
				disconnect(id,"Banned user")
			end
		end
		if initial.major() < config.versionmajormin or (initial.major() == config.versionmajormin and initial.minor() < config.versionminormin) then
			sendProtocol(client.socket,P.Disconnect.reason("Your version is out of date (requires at least "..config.versionmajormin.."."..config.versionminormin..")"))
			disconnect(id,"Bad version "..initial.major().."."..initial.minor())
			return
		end
		if initial.major() > config.versionmajormax or (initial.major() == config.versionmajormax and initial.minor() > config.versionminormax) then
			sendProtocol(client.socket,P.Disconnect.reason("Your version is too new (requires at most "..config.versionmajormax.."."..config.versionminormax..")"))
			disconnect(id,"Bad version "..initial.major().."."..initial.minor())
			return
		end
		if initial.script()~=config.scriptversion then
			sendProtocol(client.socket,P.Disconnect.reason("Your script version mismatched, try updating it"))
			disconnect(id,"Bad script version "..initial.script())
			return
		end
		if not newnick:match("^[%w%-%_]+$") then
			sendProtocol(client.socket,P.Disconnect.reason("Bad Nickname!"))
			disconnect(id,"Bad nickname")
			return
		end
		if #newnick > 32 then
			sendProtocol(client.socket,P.Disconnect.reason("Nick too long!"))
			disconnect(id,"Nick too long")
			return
		end
		for k,v in pairs(clients) do
			if k~=id and v.nick == newnick then
				sendProtocol(client.socket,P.Disconnect.reason("This nick is already on the server"))
				disconnect(id,"Duplicate nick")
				return
			end
		end
		-- Success connect!
		sendProtocol(client.socket,P.Connect_Succ)
		--Changed nick
		if newnick ~= client.nick then
			sendProtocol(client.socket,P.New_Nick.nick(newnick))
			client.nick = newnick
		end
		-- Tell client their modes
		local modes = P.User_Mode.nick(client.nick).modes.stab(stabbed[client.nick] and 1 or 0).modes.mute(muted[client.nick] and 1 or 0)
		sendProtocol(client.socket,modes) 
		
		client.brush=0
		client.brushX, client.brushY = 4,4
		client.selection={1,333,0,0}
		client.replacemode=0
		client.deco=0
		client.op=false
		client.synced = {}
		
		print(client.nick.." done identifying")
		join("null",id)
		while 1 do
			local cmd=getByte()
			
			if not protoNames[cmd] then print("Unknown Protocol! DIE") sendProtocol(client.socket,P.Disconnect.reason("Bad protocol sent")) disconnect("Bad Protocol")  break end
			local prot = protocolArray(cmd):readData(client.socket)
			
			--print("Got "..protoNames[cmd].." from "..client.nick.." "..prot:tostring())
			--We should, uhm, try calling protocol hooks here, maybe
			if dataHooks[cmd] then
				for i,v in ipairs(dataHooks[cmd]) do
					--Hooks can return true to stop future hooks
					if v(client,id,prot) then break end
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
		--TODO: Implement some kind of disconnect hook
	end
	local function runLua(msg)
		local e,err = load(msg, "crackbotcommand")
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
		sendProtocol(client.socket,P.Pong)
	end)
	addHook("Pong",function(client) end) --Who should ping? Server or client
	addHook("Join_Chan",function(client, id, data)
		local room = data.chan()
		if not room:match("^[%w%-%_]+$") or #room > 32 then
			serverMsg(client, "Invalid room name "..room)
			return true
		end
	end)
	addHook("Join_Chan",function(client, id, data)
		if client.room ~= data.chan() then
			leave(client.room,id)
			join(data.chan(),id)
		end
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
		print("* "..client.nick.." "..data.msg())
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
	addHook("Set_User_Mode",function(client, id, data)
		local nick = data.nick()
		--Fix these weird modaction functions, should be using ID, need register system first?
		local uid = modaction(client, 23, nick, stab, client.nick, data.modes.stab()==1)
		if uid then
			modaction(client, 24, nick, mute, client.nick, data.modes.mute()==1)
			clients[uid].op = data.modes.op()==1
			local packet = data.nick(), P.User_Mode
			packet.modes.stab(stabbed[nick] and 1 or 0).modes.mute(muted[nick] and 1 or 0).modes.op(client.op and 1 or 0)
			--Let everyone know
			sendroomexcept(client.room,-1,packet)
		end
	end)
	addHook("Get_User_Mode",function(client, id, data)
		local nick,packet = data.nick(), P.User_Mode
		packet.modes.stab(stabbed[nick] and 1 or 0).modes.mute(muted[nick] and 1 or 0).modes.op(client.op and 1 or 0)
		sendProtocol(client.socket,packet)
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
	addHook("Mouse_Reset",genericRelay)
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
	addHook("Sign_Data",genericRelay)
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
			print("STAMP! Loaded From "..client.nick.." size "..data:totalSize())
			sendroomexcept(client.room,id,data)
		else disconnect(id, "Failed stamp data")
		end
	end)
	addHook("Clear_Area",genericRelay)
	addHook("Edge_Mode",genericRelay)
	addHook("Load_Save",genericRelay)
	addHook("Reload_Sim",genericRelay)
	addHook("Player_Sync",function(client, id, data)
		local prot, uid = data.proto(), data.userID()
		--Confirm packet is even allowed
		if not editSim[prot] then return end
		--Confirm userID only gets 1 of each and from proper user, client.synced[id] will only exist if requested
		if not client.synced[uid] or client.synced[uid][prot] then return end
		client.synced[uid][prot]=true
		sendRawString(clients[uid].socket,string.char(prot)..string.char(id)..data.data())
	end)
	
	--Add these hooks into first slot, runs before others
	for k,v in pairs(editSim) do
		addHook(k,function(client, id, data)
			if stabbed[client.nick] then
				return true
			end
		end,1)
	end
	
	--Hooks last to ensure hook order!
	dofile("serverhooks.lua")
	
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
			-- prevent abuse with too many open connections
			local thisip = 0
			for k,v in pairs(clients) do
				if host == v.host then
					thisip = thisip + 1
				end
			end
			if thisip >= 4 then
				sendProtocol(conn,P.Disconnect.reason("There are too many connections open from this ip"))
				print("Too many connections from this ip: "..host)
				conn:close()
			else
				print("New connection: "..(host or"?")..":"..(port or"?"))

				-- look for free IDs
				local hasid
				for i=0,255 do
					if not clients[i] then
						clients[i]={socket=conn,host=host,port=port,lastping=os.time(),coro=coroutine.create(handler)}
						coret, coerr = coroutine.resume(clients[i].coro,i,clients[i])
						if not coret then
							print("ERROR! "..coerr)
							conn:close()
						end
						hasid=i
						break
					end
				end
				if hasid then
					print("Assigned ID is "..hasid)
				else
					sendProtocol(conn,P.Disconnect.reason("Server has too many users"))
					print("No user IDs left")
					conn:close()
				end
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
					if coroutine.status(client.coro) == "dead" then
						serverMsg(client, "The server errored while handling your connection")
						disconnect(id, "SERVER ERROR")
					end
					coret, coerr = coroutine.resume(client.coro,c)
					if not coret then
						print("ERROR! "..coerr)
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
