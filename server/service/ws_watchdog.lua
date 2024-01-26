local skynet = require "skynet"
local mng = require "ws_watchdog.mng" -- ws_watchdog 的逻辑操作封装
local log = require "log"
local json = require "json"

local CMD = {} -- ws_watchdog 服务操作接口
local SOCKET = {} -- ws_watchdog 的 socket 相关的操作接口
local GATE -- gate 服务地址
local AGENT -- agent 服务地址

function SOCKET.open(fd, addr)
    log.debug("New client from:", addr)
    mng.open_fd(fd)
end

function SOCKET.close(fd)
    log.debug("socket close", fd)
    mng.close_fd(fd)
end

function SOCKET.error(fd, msg)
    log.debug("socket error", fd, msg)
    mng.close_fd(fd)
end

function SOCKET.warning(fd, size)
    -- size K bytes havn't send out in fd
    log.warn("socket warning", fd, size, "K")
end

-- 客户端消息处理
function SOCKET.data(fd, msg)
    log.debug("socket data", fd, msg)
    local req = json.decode(msg)
    -- 解析客户端消息, pid 为协议 ID
    if not req.pid then
        log.error("Unknow proto. fd:", fd, ", msg:", msg)
        return
    end

    -- 判断客户端是否已通过认证
    if not mng.check_auth(fd) then
        -- 没通过认证且不是登录协议则踢下线
        if not mng.is_no_auth(req.pid) then
            log.warn("auth failed. fd:", fd, ",msg:", msg)
            mng.close_fd(fd)
            return
        end
    end

    -- 协议处理逻辑
    local res = mng.handle_proto(req, fd)
    if res then
        skynet.call(GATE, "lua", "response", fd, json.encode(res))
    end
end

function CMD.start(conf)
    -- 开启 gate 服务
    skynet.call(GATE, "lua", "open" , conf)
end

function CMD.kick(fd)
    -- 踢客户端下线
    mng.close_fd(fd)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        if cmd == "socket" then
            local f = SOCKET[subcmd]
            f(...)
            -- socket api don't need return
        else
            local f = assert(CMD[cmd])
            skynet.ret(skynet.pack(f(subcmd, ...)))
        end
    end)

    -- 启动 ws_gate 服务
    GATE = skynet.newservice("ws_gate")
    -- 启动 ws_agent 服务
    AGENT = skynet.newservice("ws_agent")
    -- 初始化 watchdog 管理器
    mng.init(GATE, AGENT)
    -- 初始化 agent 管理器
    skynet.call(AGENT, "lua", "init", GATE, skynet.self())
end)
