local skynet = require "skynet"

skynet.start(function()
    skynet.error("local server start!")

	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",8000)

	skynet.newservice("game", "game1")
	skynet.newservice("gateway", "gate1")


	-- skynet.exit()
end)
