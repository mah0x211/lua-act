--
-- Copyright (C) 2018 Masatoshi Teruya
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- example/echoserver_fork.lua
-- lua-act
--
-- Created by Masatoshi Teruya on 18/04/11.
--
-- you need to install the following modules:
--  dump
--  signal
--  act
--  net
--
local dump = require('dump')
local signal = require('signal')
local new_server = require('net.stream.inet').server.new

-- NOTE: The net module performs asynchronous processing implicitly using the
-- gpoll module.
-- Therefore, by registering a group of functions of the act module in the
-- gpoll module, concurrent processing is automatically performed without
-- changing the synchronous code.
local act = require('act')
require('gpoll').set_poller(act)
local getcpus = require('act.getcpus')

local function handle_client(client)
    local msg, err, timeout = client:recv()
    while msg do
        local _
        _, err = client:send(msg)
        if err then
            break
        end
        msg, err, timeout = client:recv()
    end

    if err then
        print('error:', err)
    elseif timeout then
        print('timeout')
    end
    client:close()
end

local function handle_server(server)
    while true do
        local client, err = server:accept()
        if client then
            act.spawn(handle_client, client)
        elseif err then
            print('failed to accept', err)
            break
        end
    end
end

local function handle_signal()
    local signo = act.sigwait(nil, signal.SIGUSR1)
    return 'got signal:' .. tostring(signo)
end

local function handle_worker(pid, server)
    print('start worker', pid)
    assert(server:listen())
    local cid = act.spawn(handle_server, server)
    act.spawn(handle_signal)
    -- await end of signal handler or server handler
    local stat = act.await()
    if stat.cid == cid then
        print('handle_server failed:', dump(stat))
    end
    server:close()
end

local function kill_workers(workers)
    print('send SIGUSR1 to all worker-processes')
    for _, proc in pairs(workers) do
        local res, err = proc:kill(signal.SIGUSR1, 'nohang')
        if res then
            print('worker-process exit', res.pid)
            workers[res.pid] = nil
        elseif err then
            print('failed to proc:kill():', err)
        end
    end
end

local function wait_worker_exit(workers)
    if next(workers) then
        print('wait all worker-processes exit')
        repeat
            local res, err = act.waitpid(200)
            if res then
                print('worker-process exit', res.pid)
                workers[res.pid] = nil
            elseif err then
                print('got error:', err, dump(workers))
                break
            else
                kill_workers(workers)
            end
        until not next(workers)
        print('done')
    end
end

local function main()
    local server = assert(new_server('127.0.0.1', 5000))
    local workers = {}
    signal.blockAll()

    -- register exit handler
    act.atexit(function()
        server:close()
        wait_worker_exit(workers)
        print('end server')
    end)

    print('start server: ', '127.0.0.1', 5000)
    -- create worker-processes
    for _ = 1, getcpus() do
        local proc, err = act.fork()
        if not proc then
            print('failed to act.fork():', err)
            return
        end

        -- handle worker-process
        if proc:is_child() then
            handle_worker(proc:pid(), server)
            os.exit()
        end

        workers[proc:pid()] = proc
    end

    -- handle signal
    while next(workers) do
        -- wait SIGINT and SIGCHLD signals
        local signo = act.sigwait(nil, signal.SIGINT, signal.SIGCHLD)

        -- stop server by Ctrl-C
        if signo == signal.SIGINT then
            break
        end

        -- wait worker-process exit
        local res, err = act.waitpid(100)
        if res then
            print('worker-process exit', res.pid)
            workers[res.pid] = nil
        elseif err then
            print('got error:', err)
            return
        end
    end
end

local ok, err = act.run(main)
if not ok then
    print(err)
end
