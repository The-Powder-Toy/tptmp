serverHooks = {}
commandHooks = {}

--Load all hooks in hooks/ here (copied from Crackbot)
function loadhook(name)
	local succ,err = pcall(dofile, "hooks/"..name)
	local ret = ""
	if not succ then
		ret = "Error loading hooks/"..name..": "..err
	else
		ret = "Loaded hooks/"..name
	end
	print(ret)
	return ret
end

function loadallhooks()
	local listcmd = WINDOWS and "dir /b" or "ls"
	local pluginList = io.popen(listcmd.." \"hooks\"")
	serverHooks = {}
	commandHooks = {}
	for file in pluginList:lines() do
		if file:sub(#file-3,#file) == ".lua" then
			loadhook(file)
		end
	end
end
loadallhooks()

--function used in some hooks
function countTable(t)
	local t2 = {}
	for k,v in pairs(t) do
		table.insert(t2,v)
	end
	return #t2
end

--split a string into words
function getArgs(msg)
	if not msg then
		return {}
	end
	local args = {}
	for word in msg:gmatch("([^%s%c]+)") do
		table.insert(args,word)
	end
	return args
end

local function callHook(hook, ...)
	local succ,err = pcall(hook, unpack(arg))
	if not succ then
		if crackbot then
			crackbot:send("Hook error: "..err.."\n")
		else
			print("Hook error: "..err)
		end
	elseif err then
		return true
	end
end

function onChat(client, cmd, msg)
	for k, v in pairs(serverHooks) do
		if type(v) == "function" and callHook(v, client, cmd, msg) then
			return true
		end
	end
	if cmd == 19 then
		local split = getArgs(msg)
		if #split > 0 and split[1]:sub(1,1) == "/" then
			local command = split[1]:sub(2)
			local msg = msg:sub(#command+3)
			table.remove(split, 1)
			if commandHooks[command] and type(commandHooks[command]) == "function" and callHook(commandHooks[command], client, msg, split) then
				return true
			end
		end
	end
end