local skynet = require "skynet"
local cluster = require "skynet.cluster"

local nodename = ...

skynet.start(function()
	skynet.error("game server start!")

	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	-- skynet.newservice("debug_console",8000)
	local proto = skynet.uniqueservice "protoloader"
	skynet.call(proto, "lua", "load", {
		"proto.c2s",
		"proto.s2c",
	})

	local sdb = skynet.newservice("simpledb")
	cluster.register("sdb", sdb)
	cluster.open(nodename or skynet.getenv "nodename")

	skynet.exit()
end)
