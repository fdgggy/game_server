local skynet = require "skynet"
local cluster = require "skynet.cluster"

local nodename = ...

skynet.start(function()
	skynet.error("gate server start!")

	cluster.open(nodename or skynet.getenv "nodename")

	local proxy = cluster.proxy "game1@sdb"	-- cluster.proxy("db", "@sdb")
	local largekey = string.rep("X", 128*1024)
	local largevalue = string.rep("R", 100 * 1024)
	print("largevalue:"..largevalue)

	skynet.call(proxy, "lua", "SET", largekey, largevalue)
	local v = skynet.call(proxy, "lua", "GET", largekey)
	print("---v:"..v)
	skynet.exit()

end)
