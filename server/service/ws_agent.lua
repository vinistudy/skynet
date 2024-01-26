local skynet = require "skynet"
local socket = require "skynet.socket"
local log = require "log"
local mng = require "ws_agent.mng"
local json = require "json"

local WATCHDOG -- watchdog 服务地址
local GATE -- gate 服务地址

local CMD = {}

function CMD.init(gate, watchdog)
    GATE = gate
    WATCHDOG = watchdog
    mng.init(GATE, WATCHDOG)
end

-- 登录
function CMD.login(acc, fd)
    return mng.login(acc, fd)
end

-- 断线
function CMD.disconnect(fd)
    mng.disconnect(fd)
end

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
    unpack = skynet.tostring,
    dispatch = function(fd, address, msg)
        skynet.ignoreret()  -- session is fd, don't call skynet.ret

        log.debug("socket data", fd, msg)
        -- 解析客户端消息, pid 为协议 ID
        local req = json.decode(msg)
        if not req.pid then
            log.error("Unknow proto. fd:", fd, ", msg:", msg)
            return
        end

        -- 登录成功后就会 fd 和 uid 绑定
        local uid = mng.get_uid(fd)
        if not uid then
            log.warn("no uid. fd:", fd, ",msg:", msg)
            mng.close_fd(fd)
            return
        end

        -- 协议处理逻辑
        local res = mng.handle_proto(req, fd, uid)
        if res then
            skynet.call(GATE, "lua", "response", fd, json.encode(res))
        end
    end
}

skynet.start(function()
    skynet.dispatch("lua", function(_,_, command, ...)
        --skynet.trace()
        local f = CMD[command]
        skynet.ret(skynet.pack(f(...)))
    end)
end)
