local skynet = require "skynet"
local config = require "config"

-- 所有服务的启动入口
skynet.start(function()
    skynet.error("Server start")
    if not config.get("daemon") then
        -- 如果不是 daemon 模式启动则开启 console 服务
        skynet.newservice("console")
    end
    -- 开启 debug console 服务
    skynet.newservice("debug_console",8000)

    -- 开启 ws_watchdog 服务
    local ws_watchdog = skynet.newservice("ws_watchdog")

    -- 从配置中读取 websocket 协议和端口
    local ws_protocol = config.get("ws_protocol")
    local ws_port = config.get("ws_port")
    -- 从配置中读取最大链接数
    local max_online_client = config.get("max_online_client")

    -- 通知 ws_watchdog 启动服务
    skynet.call(ws_watchdog, "lua", "start", {
        port = ws_port,
        maxclient = max_online_client,
        nodelay = true,
        protocol = ws_protocol,
    })
    skynet.error("websocket watchdog listen on", ws_port)

    -- main 服务只作为入口，启动完所需的服务后就完成了使命，可以自己退出了
    skynet.exit()
end)
