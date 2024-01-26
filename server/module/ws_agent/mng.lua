local skynet = require "skynet"
local log = require "log"
local json = require "json"

local M = {} -- 模块接口
local RPC = {} -- 协议绑定处理函数

local WATCHDOG -- watchdog 服务地址
local GATE -- gate 服务地址
local fd2uid = {} -- fd 和 uid 绑定
local online_users = {} -- {[uid] = user} -- 在线玩家

function M.init(gate, watchdog)
    GATE = gate
    WATCHDOG = watchdog
end

-- 返回协议给客户端
function M.send_res(fd, res)
    local msg = json.encode(res)
    skynet.call(GATE, "lua", "response", fd, msg)
end

-- 登录成功逻辑
function M.login(acc, fd)
    assert(not fd2uid[fd], string.format("Already Logined. acc:%s, fd:%s", acc, fd))

    -- TODO: 从数据库加载数据
    local uid = tonumber(acc) -- 现在假设 uid 就是 acc
    local user = {
        fd = fd,
        acc = acc,
    }
    online_users[uid] = user
    fd2uid[fd] = uid

    -- 通知 gate 以后消息由 agent 接管
    skynet.call(GATE, "lua", "forward", fd)

    log.info("Login Success. acc:", acc, ", fd:", fd)
    local res = {
        pid = "s2c_login",
        uid = uid,
        msg = "Login Success",
    }
    return res
end

function M.disconnect(fd)
    local uid = fd2uid[fd]
    if uid then
        online_users[uid] = nil
        fd2uid[fd] = nil
    end
end

function M.close_fd(fd)
    skynet.send(GATE, "lua", "kick", fd)
    M.disconnect(fd)
end

function M.get_uid(fd)
    return fd2uid[fd]
end

-- 测试消息
function RPC.c2s_echo(req, fd, uid)
    local res = {
        pid = "s2c_echo",
        msg = req.msg,
        uid = uid,
    }
    return res
end

-- 协议处理逻辑
function M.handle_proto(req, fd, uid)
    -- 根据协议 ID 找到对应的处理函数
    local func = RPC[req.pid]
    local res = func(req, fd, uid)
    return res
end

return M
