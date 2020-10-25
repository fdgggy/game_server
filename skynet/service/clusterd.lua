local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster.core"

local config_name = skynet.getenv "cluster"
local node_address = {}
local node_sender = {}
local command = {}
local config = {}
local nodename = cluster.nodename()

local connecting = {}
--cluster.reload 也可以接收一个 table 来更新配置，如果你传入了 table，那么 table 内的数据优先级高于配置文件（配置文件被忽略）。
--如果一开始就没有配置文件，那么必须在使用 cluster 之前用 cluster.reload 传入最初的配置数据。
--在线上产品中如何向集群中的每个节点分发新的配置文件，skynet 并没有提供方案。但这个方案一般比较容易实现。例如，你可以自己设计一个中心节点用来管理它。
--或者让系统管理员编写好同步脚本，并给程序加上控制指令来重载这些配置。或不依赖配置文件，而全部用 cluster.reload 来初始化。

local function open_channel(t, key)
	local ct = connecting[key]
	if ct then
		local co = coroutine.running()
		table.insert(ct, co)
		skynet.wait(co)
		return assert(ct.channel)
	end
	ct = {}
	connecting[key] = ct
	local address = node_address[key]
	-- 当一个名字没有配置在配置表中时，如果你向这个未命名节点发送一个请求，skynet 的默认行为是挂起，
	-- 一直等到这个名字对应项的配置被更新。你可以通过配置节点名字对应的地址为 false 来明确指出这个节点已经下线。
	-- 另外，可以通过在配置表中插入 __nowaiting = true 来关闭这种挂起行为。
	if address == nil and not config.nowaiting then
		local co = coroutine.running()
		assert(ct.namequery == nil)
		ct.namequery = co
		skynet.error("Waiting for cluster node [".. key.."]")
		skynet.wait(co)
		address = node_address[key]
	end
	local succ, err, c
	if address then
		local host, port = string.match(address, "([^:]+):(.*)$")
		c = node_sender[key]
		if c == nil then
			c = skynet.newservice("clustersender", key, nodename, host, port)
			if node_sender[key] then
				-- double check
				skynet.kill(c)
				c = node_sender[key]
			else
				node_sender[key] = c
			end
		end

		succ = pcall(skynet.call, c, "lua", "changenode", host, port)

		if succ then
			t[key] = c
			ct.channel = c
		else
			err = string.format("changenode [%s] (%s:%s) failed", key, host, port)
		end
	else
		err = string.format("cluster node [%s] is %s.", key,  address == false and "down" or "absent")
	end
	connecting[key] = nil
	for _, co in ipairs(ct) do
		skynet.wakeup(co)
	end
	assert(succ, err)
	if node_address[key] ~= address then
		return open_channel(t,key)
	end
	return c
end

local node_channel = setmetatable({}, { __index = open_channel })

--第一次加载时，对集群中节点不会主动建立通道，第一次发送消息时才会建立
local function loadconfig(tmp)
	if tmp == nil then
		tmp = {}
		if config_name then
			local f = assert(io.open(config_name))
			local source = f:read "*a"
			f:close()
			assert(load(source, "@"..config_name, "t", tmp))()  --load的本质就是在Lua代码中运行一段存储在字符串中的代码
		end
	end
	local reload = {}
	for name,address in pairs(tmp) do
		if name:sub(1,2) == "__" then
			name = name:sub(3)
			config[name] = address
			skynet.error(string.format("Config %s = %s", name, address))
		else
			assert(address == false or type(address) == "string")
			if node_address[name] ~= address then
				-- address changed
				if rawget(node_channel, name) then  --不会访问元表
					node_channel[name] = nil	-- reset connection
					table.insert(reload, name)
				end
				node_address[name] = address
			end
			local ct = connecting[name]
			if ct and ct.namequery and not config.nowaiting then
				skynet.error(string.format("Cluster node [%s] resloved : %s", name, address))
				skynet.wakeup(ct.namequery)
			end
		end
	end
	if config.nowaiting then
		-- wakeup all connecting request
		for name, ct in pairs(connecting) do
			if ct.namequery then
				skynet.wakeup(ct.namequery)
			end
		end
	end
	for _, name in ipairs(reload) do
		-- open_channel would block
		skynet.fork(open_channel, node_channel, name)
	end
end

function command.reload(source, config)
	loadconfig(config)
	skynet.ret(skynet.pack(nil))
end

function command.listen(source, addr, port)
	local gate = skynet.newservice("gate")
	if port == nil then
		local address = assert(node_address[addr], addr .. " is down")
		addr, port = string.match(address, "([^:]+):(.*)$")
	end
	skynet.call(gate, "lua", "open", { address = addr, port = port })
	skynet.ret(skynet.pack(nil))
end

function command.sender(source, node)
	skynet.ret(skynet.pack(node_channel[node]))
end

function command.senders(source)
	skynet.retpack(node_sender)
end

local proxy = {}

function command.proxy(source, node, name)
	if name == nil then
		node, name = node:match "^([^@.]+)([@.].+)"
		if name == nil then
			error ("Invalid name " .. tostring(node))
		end
	end
	local fullname = node .. "." .. name
	local p = proxy[fullname]
	if p == nil then
		p = skynet.newservice("clusterproxy", node, name)
		-- double check
		if proxy[fullname] then
			skynet.kill(p)
			p = proxy[fullname]
		else
			proxy[fullname] = p
		end
	end
	skynet.ret(skynet.pack(p))
end

local cluster_agent = {}	-- fd:service
local register_name = {}

local function clearnamecache()
	for fd, service in pairs(cluster_agent) do
		if type(service) == "number" then
			skynet.send(service, "lua", "namechange")
		end
	end
end

function command.register(source, name, addr)
	assert(register_name[name] == nil)
	addr = addr or source
	local old_name = register_name[addr]
	if old_name then
		register_name[old_name] = nil
		clearnamecache()
	end
	register_name[addr] = name
	register_name[name] = addr
	skynet.ret(nil)
	skynet.error(string.format("Register [%s] :%08x", name, addr))
end

function command.queryname(source, name)
	skynet.ret(skynet.pack(register_name[name]))
end

function command.socket(source, subcmd, fd, msg)
	if subcmd == "open" then
		skynet.error(string.format("socket accept from %s", msg))
		-- new cluster agent
		cluster_agent[fd] = false
		local agent = skynet.newservice("clusteragent", skynet.self(), source, fd)
		local closed = cluster_agent[fd]
		cluster_agent[fd] = agent
		if closed then
			skynet.send(agent, "lua", "exit")
			cluster_agent[fd] = nil
		end
	else
		if subcmd == "close" or subcmd == "error" then
			-- close cluster agent
			local agent = cluster_agent[fd]
			if type(agent) == "boolean" then
				cluster_agent[fd] = true
			elseif agent then
				skynet.send(agent, "lua", "exit")
				cluster_agent[fd] = nil
			end
		else
			skynet.error(string.format("socket %s %d %s", subcmd, fd, msg or ""))
		end
	end
end

skynet.start(function()
	loadconfig()
	skynet.dispatch("lua", function(session , source, cmd, ...)
		local f = assert(command[cmd])
		f(source, ...)
	end)
end)
