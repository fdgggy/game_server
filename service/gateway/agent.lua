local skynet = require "skynet"
local socket = require "skynet.socket"
local sproto = require "sproto"
local sprotoloader = require "sprotoloader"
local cluster = require "skynet.cluster"

local WATCHDOG
local host
local send_request

local CMD = {}
local REQUEST = {}
local client_fd

function REQUEST:get()
	print("get", self.what)
	return { result = "hhhhhhh" }
end

function REQUEST:set()
	local proxy = cluster.proxy "game1@sdb"	-- cluster.proxy("db", "@sdb")
	local largekey = "hello"
	local largevalue = "world"
	print("largevalue:"..largevalue)

	skynet.call(proxy, "lua", "SET", largekey, largevalue)
	local v = skynet.call(proxy, "lua", "GET", largekey)
	print("---v:"..v)
	print("set", self.what, self.value)
end

function REQUEST:handshake()
	return { msg = "Welcome to skynet, I will send heartbeat every 5 sec." }
end

function REQUEST:quit()
	skynet.call(WATCHDOG, "lua", "close", client_fd)
end

local function request(name, args, response)
	local f = assert(REQUEST[name])
	local r = f(args)
	if response then
		return response(r)
	end
end

local function send_package(pack)
	local package = string.pack(">s2", pack)
	socket.write(client_fd, package)
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		--host用于处理接收的消息,返回2种情况。 
		--第一个返回值REQUEST，表示远程请求。若没有session,则代表不需要回应。
		--第2个参数为消息类型名，第3个参数为消息内容，为一个table。
		--如果请求包中有session,第4个参数生成一个用于生成回应包的函数。
		--第一个返回值RESPONSE,第 2 和 第 3 个返回值分别为 session 和消息内容。
		--消息内容通常是一个 table ，但也可能不存在内容（仅仅是一个回应确认）。
		return host:dispatch(msg, sz) 
	end,
	dispatch = function (fd, _, type, ...)
		assert(fd == client_fd)	-- You can use fd to reply message
		-- skynet.ignoreret()	-- session is fd, don't call skynet.ret
		-- skynet.trace()
		if type == "REQUEST" then
			local ok, result  = pcall(request, ...)
			if ok then
				if result then
					send_package(result)
				end
			else
				skynet.error(result)
			end
		else
			assert(type == "RESPONSE")
			error "This example doesn't support request client"
		end
	end
}

function CMD.start(conf)
	local fd = conf.client
	local gate = conf.gate
	WATCHDOG = conf.watchdog
	-- slot 1,2 set at main.lua
	host = sprotoloader.load(1):host "package" --构造sproto rpc消息处理器host,package应与协议定制的头名字一样
	send_request = host:attach(sprotoloader.load(2)) --构造一个发送函数，用来将对外请求打包编码成可以被 dispatch 正确解码的数据包。
	--send_request 函数接受三个参数（name, args, session）。name 是消息的字符串名、args 是一张保存用消息内容的 table ，而 session 是你提供的唯一识别号，用于让对方正确的回应。 当你的协议不规定需要回应时，session 可以不给出。同样，args 也可以为空。
	skynet.fork(function()
		while true do
			send_package(send_request "heartbeat")
			skynet.sleep(500)
		end
	end)

	client_fd = fd
	skynet.call(gate, "lua", "forward", fd)

	cluster.register("1618", skynet.self())
end

function CMD.disconnect()
	-- todo: do something before exit
	skynet.exit()
end

function CMD.testpush(a)
	print("hhhello:a:"..type(a).." a:"..a)
	send_package(a)
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		skynet.trace()
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
end)
