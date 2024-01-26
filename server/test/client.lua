local skynet = require "skynet"
require "skynet.manager"
local config = require "config"
local websocket = require "http.websocket"
local socket = require "skynet.socket"
local util_file = require "util.file"
local util_string = require "util.string"
local dns = require "skynet.dns"
local json = require "json"

local ws_id
local cmds = {}

local function fetch_cmds()
    local ttt = util_file.scandir("test/cmds")
    for k,v in pairs(ttt) do
        local cmd = util_string.split(v, ".")[1]
        local cmd_mod = "test.cmds."..cmd
        cmds[cmd] = require(cmd_mod)
    end
end
fetch_cmds()

local function run_command(cmd, ...)
    print("run_command:", cmd, ...)
    print("ws_id:", ws_id)
    local cmd_mod = cmds[cmd]
    if cmd_mod then
        cmd_mod.run_command(ws_id, ...)
    end
end

local function handle_resp(ws_id, res)
    for _, cmd_mod in pairs(cmds) do
        if cmd_mod.handle_res then
            cmd_mod.handle_res(ws_id, res)
        end
    end
end

local function websocket_main_loop()
    local ws_protocol = config.get("ws_protocol")
    local ws_port = config.get("ws_port")
    local server_host = config.get("server_host")
    local url = string.format("%s://%s:%s/client", ws_protocol, server_host, ws_port)
    ws_id = websocket.connect(url)

    print("websocket connected. ws_id:", ws_id)
	while true do
        local res, close_reason = websocket.read(ws_id)
        if not res then
            print("disconnect.")
            break
        end
        print("res:", ws_id, res)
        local ok, err = xpcall(handle_resp, debug.traceback, ws_id, json.decode(res))
        if not ok then
            print(err)
        end
        websocket.ping(ws_id)
	end
end

local function split_cmdline(cmdline)
	local split = {}
	for i in string.gmatch(cmdline, "%S+") do
		table.insert(split,i)
	end
	return split
end

local function console_main_loop()
	local stdin = socket.stdin()
	while true do
		local cmdline = socket.readline(stdin, "\n")
		if cmdline ~= "" then
            local split = split_cmdline(cmdline)
            local cmd = split[1]
            local ok, err = xpcall(run_command, debug.traceback, cmd, select(2, table.unpack(split)))
            if not ok then
                print(err)
            end
        end
	end
end

skynet.start(function()
	dns.server()
	skynet.fork(websocket_main_loop)
	skynet.fork(console_main_loop)
end)

