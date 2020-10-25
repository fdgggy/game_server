local skynet = require "skynet"
require "skynet.manager"	-- import skynet.register
local cluster = require "skynet.cluster"
local sprotoloader = require "sprotoloader"

local db = {}
local host
local send_request
local session = 0

local function request(name, args)
	session = session + 1
	local str = send_request(name, args, session)
	return str
end

local command = {}

function command.GET(key)
	return db[key]
end

function command.SET(key, value)
	print("yyyyyyyyyyyyyyyy")

	local proxy = cluster.proxy("gate1","@1618")
	skynet.call(proxy, "lua", "testpush", request("common", { what = "xxxxxxx", value = 890}))
	print("xxxxxxxxxxxxxxxx")
	local last = db[key]
	db[key] = value
	return last
end



skynet.start(function()
	host = sprotoloader.load(1):host "package"
	send_request = host:attach(sprotoloader.load(2))
	
	skynet.dispatch("lua", function(session, address, cmd, ...)
		cmd = cmd:upper()
		if cmd == "PING" then
			assert(session == 0)
			local str = (...)
			if #str > 20 then
				str = str:sub(1,20) .. "...(" .. #str .. ")"
			end
			skynet.error(string.format("%s ping %s", skynet.address(address), str))
			return
		end
		local f = command[cmd]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
--	skynet.traceproto("lua", false)	-- true off tracelog
	skynet.register "SIMPLEDB"
end)
