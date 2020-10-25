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
	-- register name "sdb" for simpledb, you can use cluster.query() later.
	-- See cluster2.lua
	cluster.register("sdb", sdb)

	print(skynet.call(sdb, "lua", "SET", "a", "foobar"))
	print(skynet.call(sdb, "lua", "SET", "b", "foobar2"))
	print(skynet.call(sdb, "lua", "GET", "a"))
	print(skynet.call(sdb, "lua", "GET", "b"))

	cluster.open(nodename or skynet.getenv "nodename")

	skynet.exit()
end)
