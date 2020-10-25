local skynet = require "skynet"
local cluster = require "skynet.cluster"

local nodename = ...

skynet.start(function()
	skynet.error("gate server start!")

	local proto = skynet.uniqueservice "protoloader"
	skynet.call(proto, "lua", "load", {
		"proto.c2s",
		"proto.s2c",
	})

	local watchdog = skynet.newservice("watchdog")
	skynet.call(watchdog, "lua", "start", {
		address = skynet.getenv "gateway_host",
		port = skynet.getenv "gateway_port",
		maxclient = 5000,
		nodelay = true,
	})

	cluster.open(nodename or skynet.getenv "nodename")

	skynet.exit()
end)
