local skynet = require "skynet"
local config = require "config"
local timer = require "timer"
local md5 = require "md5"

local M = {} -- 模块接口
local RPC = {} -- 协议绑定处理函数

local GATE -- gate 服务地址
local AGENT -- agent 服务地址
local TIMEOUT_AUTH = 10 -- 认证超时 10 秒
local noauth_fds = {} -- 未通过认证的客户端

-- 标记哪些协议不需要登录就能访问
local no_auth_proto_list = {
    c2s_login = true,
}
function M.is_no_auth(pid)
    return no_auth_proto_list[pid]
end

function M.init(gate, agent)
    GATE = gate
    AGENT = agent
end

-- 超时踢掉没有通过认证的客户端
local function timeout_auth(fd)
    local ti = noauth_fds[fd]
    if not ti then return end

    local now = skynet.time()
    if now - ti < TIMEOUT_AUTH then
        return
    end

    M.close_fd(fd)
end

function M.open_fd(fd)
    noauth_fds[fd] = skynet.time()
    timer.timeout(TIMEOUT_AUTH + 1, timeout_auth, fd)
end

-- 关闭链接
function M.close_fd(fd)
    skynet.send(GATE, "lua", "kick", fd)
    skynet.send(AGENT, "lua", "disconnect", fd)
    noauth_fds[fd] = nil
end

function M.check_auth(fd)
    if noauth_fds[fd] then
        return false
    end
    return true
end

local function check_sign(token, acc, sign)
    local checkstr = token .. acc
    local checksum = md5.sumhexa(checkstr)
    if checksum == sign then
        return true
    end
    return false
end

-- 登录协议处理
function RPC.c2s_login(req, fd)
    -- token 验证
    if not check_sign(req.token, req.acc, req.sign) then
        log.debug("login failed. token:", req.token, ", acc:", req.acc, ", sign:", req.sign)
        M.close_fd(fd)
        return
    end
    -- 登录成功逻辑处理
    -- 分配 agent
    local res = skynet.call(AGENT, "lua", "login", req.acc, fd)
    -- 从超时队列中移除
    noauth_fds[fd] = nil
    -- 返回登录成功
    return res
end

-- 协议处理逻辑
function M.handle_proto(req, fd)
    -- 根据协议 ID 找到对应的处理函数
    local func = RPC[req.pid]
    local res = func(req, fd)
    return res
end

return M
