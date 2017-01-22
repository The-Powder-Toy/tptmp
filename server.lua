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
	local succ,err=socket.bind(config.bindhost,config.bindport,10)
	local crackbotServer=socket.bind("localhost",34404,1)--socket.tcp()
	crackbot = nil
	crackbotServer:settimeout(0)
	
	if not succ then
		error("Could not bind: "..err)
	end
	server = succ
	server:settimeout(0)
	
	bans={}

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
	function bytes(socket,amt)
		local final = ""
		local timeout,rec = os.time(),0
		while rec<amt do
			local s,r,e = socket:receive(amt-rec)
			if not s then 
				if r~="timeout" then
					return false,"Error while getting stamp"
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
			if os.time()-timeout>15 then return false,"Stamp took too long" end
		end
		return true,final
	end
	
	-- send to all users on room except given one (usually self)
	function sendroomexcept(room,uid,data)
		if not rooms[room] then return end
		for _,id in ipairs(rooms[room]) do
			if id~=uid and clients[id] and clients[id].socket then
				clients[id].socket:send(data)
			end
		end
	end
	function sendroomexceptLarge(room,uid,data)
		if not rooms[room] then return end
		for _,id in ipairs(rooms[room]) do
			if id~=uid and clients[id] and clients[id].socket then
				clients[id].socket:settimeout(8)
				local s,r,e = clients[id].socket:send(data)
				clients[id].socket:settimeout(0)
			end
		end
	end

	-- leave a room
	function leave(room,uid)
		print((clients[uid] and clients[uid].nick or "UNKNOWN").." left "..room)
		if clients[uid] then
			sendroomexcept(room,uid,"\18"..string.char(uid))
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
			print("Deleted room '"..room.."'")
		end
		if clients[uid] then
			onChat(clients[uid],-2,room)
		end
	end

	-- join a room
	function join(room,id)
		local client=clients[id]
		print(client.nick.." joined "..room)
		if not rooms[room] then
			rooms[room]={}
			print("Created room '"..room.."'")
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
			--print("asking "..rooms[room][1].." to provide sync")
			--clients[rooms[room][1]].socket:send("\128"..string.char(id))
			for i,v in ipairs(rooms[room]) do
				if clients[v].nick and clients[v].nick:find("*") ~= 1 then
					print("asking "..clients[v].nick.." to provide sync")
					clients[v].socket:send("\128"..string.char(id))
					return
				end
			end
		end
	end

	function serverMsg(client, message, r, g, b)
		client.socket:send("\22"..message.."\0"..string.char(r or 127)..string.char(g or 255)..string.char(b or 255))
	end

	function kick(client, who, reason)
		for uid, v in pairs(clients) do
			if v == client then
				local message = "You were kicked by "..who
				if #reason > 0 then
					message = message..": "..reason
				end
				serverMsg(client, message, 255, 50, 50)
				print(who.." kicked "..client.nick.." from "..client.room.." ("..reason..")")
				disconnect(uid, "kicked by "..who..": "..reason)
			end
		end
	end

	-- coroutine that handles the client
	function handler(id,client)
		local major,minor,scriptver=byte(),byte(),byte()
		client.nick=nullstr()
		for k,v in pairs(bans) do
			if client.host:match(v) then
				client.socket:send("\0You are banned\0")
				disconnect(id,"Banned user")
			end
		end
		if major < config.versionmajormin or (major == config.versionmajormin and minor < config.versionminormin) then
			client.socket:send("\0Your version is out of date (requires at least "..config.versionmajormin.."."..config.versionminormin..")\0")
			disconnect(id,"Bad version "..major.."."..minor)
			return
		end
		if major > config.versionmajormax or (major == config.versionmajormax and minor > config.versionminormax) then
			client.socket:send("\0Your version is too new (requires at most "..config.versionmajormax.."."..config.versionminormax..")\0")
			disconnect(id,"Bad version "..major.."."..minor)
			return
		end
		if scriptver~=config.scriptversion then
			client.socket:send("\0Your script version mismatched, try updating it\0")
			disconnect(id,"Bad script version "..scriptver)
			return
		end
		if not client.nick:match("^%*?[%w%-%_]+$") then
			client.socket:send("\0Bad Nickname!\0")
			disconnect(id,"Bad nickname")
			return
		end
		if #client.nick > 32 then
			client.socket:send("\0Nick too long!\0")
			disconnect(id,"Nick too long")
			return
		end
		for k,v in pairs(clients) do
			if k~=id and v.nick == client.nick then
				client.socket:send("\0This nick is already on the server\0")
				disconnect(id,"Duplicate nick")
				return
			end
		end
		client.brush=0
		client.size="\4\4"
		client.selection={"\0\1","\64\0","\128\0","\192\0"}
		client.replacemode="0"
		client.deco="\0\0\0\0"
		print(client.nick.." done identifying")
		client.socket:send"\1"
		join("null",id)
		while 1 do
			local cmd=byte()
			--if cmd~=32 and cmd~=33 and cmd~=34 then
			--	print("Got ["..cmd.."] from "..client.nick)
			--end
			if cmd~=16 and cmd~=19 and cmd~=20 and cmd~=21 then --handled separately with more info
				if onChat(client,cmd) then --allow any events to be canceled with hooks
					cmd=0 --hack
				end 
			end

			-- JOIN
			if cmd==16 then
				local room=nullstr():lower()
				if not room:match("^[%w%-%_]+$") or #room > 32 then
					serverMsg(client, "Invalid room name")
				else
					leave(client.room,id)
					if not onChat(client,16,room) then
						join(room,id)
					end
				end
			-- MSG
			elseif cmd==19 then
				local msg=nullstr()
				if not msg:match("^[ -~]*$") then
					serverMsg(client, "Invalid characters detected in message, not sent")
				elseif #msg > 200 then
					serverMsg(client, "Message too long, not sent")
				else
					print("<"..client.nick.."> "..msg)
					if not onChat(client,19,msg) then
						sendroomexcept(client.room,id,"\19"..string.char(id)..msg.."\0")
					end
				end
			elseif cmd==20 then
				local msg=nullstr()
				if not msg:match("^[ -~]*$") then
					serverMsg(client, "Invalid characters detected in message, not sent")
				elseif #msg > 200 then
					serverMsg(client, "Message too long, not sent")
				else
					print("* "..client.nick.." "..msg)
					if not onChat(client,20,msg) then
						sendroomexcept(client.room,id,"\20"..string.char(id)..msg.."\0")
					end
				end
			elseif cmd==21 then
				local nick,reason = nullstr(), nullstr()
				if not reason:match("^[ -~]*$") then
					serverMsg(client, "Invalid characters detected in kick reason")
				elseif #reason > 200 then
					serverMsg(client, "Kick reason too long, not sent")
				elseif client.room == "null" then
					serverMsg(client, "You can't kick people from the lobby")
				elseif rooms[client.room][1] ~= id then
					serverMsg(client, "You can't kick people from here")
				else
					local found=false
					for _,uid in ipairs(rooms[client.room]) do
						if clients[uid].nick == nick then
							if not onChat(client, 21, nick.." "..reason) then
								kick(clients[uid], client.nick, reason)
							end
							found = true
						end
					end
					if not found then
						serverMsg(client, "User \""..nick.."\" not found")
					end
				end
			elseif cmd==2 then
				client.lastping=os.time()
			elseif cmd==32 then
				local data=char()..char()..char()
				sendroomexcept(client.room,id,"\32"..string.char(id)..data)
			elseif cmd==33 then
				local data=char()
				sendroomexcept(client.room,id,"\33"..string.char(id)..data)
			elseif cmd==34 then
				local data=char()..char()
				client.size=data
				sendroomexcept(client.room,id,"\34"..string.char(id)..data)
			elseif cmd==35 then
				client.brush=client.brush%3+1
				sendroomexcept(client.room,id,"\35"..string.char(id))
			elseif cmd==36 then
				local data=char()
				sendroomexcept(client.room,id,"\36"..string.char(id)..data)
			elseif cmd==37 then
				local byte1 = char()
				local byte2 = char()
				local data = byte1..byte2
				local btn=math.floor(data:byte(1)/64)
				--if client.nick == "jacob1" or client.nick == "jacob2" then
				--	crackbot:send("test: "..string.byte(byte1)..", "..string.byte(byte2).."\n")
				--end
				if string.byte(byte1) ~= 194 and string.byte(byte1) ~= 195 then
					client.selection[btn+1]=data
					sendroomexcept(client.room,id,"\37"..string.char(id)..data)
				else
					client.ischat = true
				end
			elseif cmd==38 then
				local data=char()
				client.replacemode = data
				sendroomexcept(client.room,id,"\38"..string.char(id)..data)
			elseif cmd==48 then
				local data=char()
				sendroomexcept(client.room,id,"\48"..string.char(id)..data)
			elseif cmd==49 then
				local data=char()
				sendroomexcept(client.room,id,"\49"..string.char(id)..data)
			elseif cmd==50 then
				sendroomexcept(client.room,id,"\50"..string.char(id))
			elseif cmd==51 then
				local data=char()
				sendroomexcept(client.room,id,"\51"..string.char(id)..data)
			elseif cmd==52 then
				local data=char()
				sendroomexcept(client.room,id,"\52"..string.char(id)..data)
			elseif cmd==53 then
				local data=char()
				sendroomexcept(client.room,id,"\53"..string.char(id)..data)
			elseif cmd==54 then
				local data=char()
				sendroomexcept(client.room,id,"\54"..string.char(id)..data)
			elseif cmd==55 then
				local data=char()
				sendroomexcept(client.room,id,"\55"..string.char(id)..data)
			elseif cmd==56 then
				local data=char()
				sendroomexcept(client.room,id,"\56"..string.char(id)..data)
			elseif cmd==57 then
				local data=char()
				sendroomexcept(client.room,id,"\57"..string.char(id)..data)
			elseif cmd==58 then
				local data=char()
				sendroomexcept(client.room,id,"\58"..string.char(id)..data)
			elseif cmd==59 then
				local data=char()
				sendroomexcept(client.room,id,"\59"..string.char(id)..data)
			elseif cmd==60 then
				sendroomexcept(client.room,id,"\60"..string.char(id))
			elseif cmd==61 then
				sendroomexcept(client.room,id,"\61"..string.char(id))
			elseif cmd==62 then
				sendroomexcept(client.room,id,"\62"..string.char(id))
			elseif cmd==63 then
				sendroomexcept(client.room,id,"\63"..string.char(id))
			elseif cmd==64 then
				local data=char()..char()..char()
				sendroomexcept(client.room,id,"\64"..string.char(id)..data)
			elseif cmd==65 then
				local data=char()..char()..char()..char()
				client.deco=data
				sendroomexcept(client.room,id,"\65"..string.char(id)..data)
			elseif cmd==66 then
				local loc=char()..char()..char()
				local b1,b2,b3=byte(),byte(),byte()
				local sz=b1*65536+b2*256+b3
				print("STAMP! Loading From "..client.nick.." size "..sz )
				local s,stm = bytes(client.socket,sz)
				if s then
					sendroomexceptLarge(client.room,id,"\66"..string.char(id)..loc..string.char(b1,b2,b3)..stm)
				else
					disconnect(id,stm)
				end
			elseif cmd==67 then
				local data=char()..char()..char()..char()..char()..char()
				sendroomexcept(client.room,id,"\67"..string.char(id)..data)
			elseif cmd==68 then
				local data=char()
				sendroomexcept(client.room,id,"\68"..string.char(id)..data)
			elseif cmd==69 then
				local data=char()..char()..char()
				sendroomexcept(client.room,id,"\69"..string.char(id)..data)
			elseif cmd==70 then
				sendroomexcept(client.room,id,"\70"..string.char(id))
			elseif cmd==128 then
				local i=byte()
				local b1,b2,b3=byte(),byte(),byte()
				local sz=b1*65536+b2*256+b3
				print(client.nick.." provided sync for "..(clients[i] and clients[i].nick or "UNKOWN")..", it was "..sz.." bytes")
				local s,stm = bytes(client.socket,sz)
				if s then
					clients[i].socket:settimeout(8)
					clients[i].socket:send("\129"..string.char(b1,b2,b3)..stm)
					clients[i].socket:settimeout(0)
				else
					disconnect(id,stm)
				end				
			--special mode sync sent to specific user (called from 128)
			elseif cmd==130 then
				local i=byte()
				if clients[i] then
					clients[i].socket:send(char()..string.char(id)..char())
				end
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
				conn:send("\0There are too many connections open from this ip\0")
				print("Too many connections from this ip: "..host)
				conn:close()
			elseif host == "58.30.71.10" then
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
						end
						hasid=i
						break
					end
				end
				if hasid then
					print("Assigned ID is "..hasid)
				else
					conn:send("\0Server has too many users\0")
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
