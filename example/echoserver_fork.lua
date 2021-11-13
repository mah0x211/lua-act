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
local Act = require('act')
require('net.poll').set_poller(Act)
-- you need to install the net and signal modules as follows;
--  $ luarocks install net signal
local inet = require('net.stream.inet')
local signal = require('signal')

local function handler(client)
    Act.atexit(function(...)
        client:close()
    end)

    while true do
        local msg, err = client:recv()

        if not msg then
            return
        end

        _, err = client:send(msg)
        if err then
            print('error:', err)
            return
        end
    end
end

local function waitWorkerExit(nworker)
    -- wait 10 msec
    Act.sleep(10)

    local status = Act.waitpid(-1)

    while status do
        if status then
            if status.pid == -1 then
                break
            end
            print('worker-process exit', status.pid)
            nworker = nworker - 1
        end

        status = Act.waitpid(-1)
    end

    return nworker
end

local function handleSignal(nworker)
    while nworker > 0 do
        local signo = Act.sigwait(nil, signal.SIGINT, signal.SIGCHLD)

        -- stop workers
        if signo == signal.SIGINT then
            -- send SIGUSR1 signal
            signal.killpg(signal.SIGUSR1)
            nworker = waitWorkerExit(nworker)
            -- send SIGKILL if worker still exists
            if nworker > 0 then
                signal.killpg(signal.SIGKILL)
                nworker = waitWorkerExit(nworker)
            end
            break
            -- worker exited
        elseif signo == signal.SIGCHLD then
            nworker = waitWorkerExit(nworker)
        end
    end
end

local ok, err = Act.run(function()
    local server = assert(inet.server.new('127.0.0.1', 5000))
    local nworker = 0

    assert(server:listen())
    signal.blockAll()
    print('start server: ', '127.0.0.1', 5000)
    -- handle by 5 worker process
    for i = 1, 5 do
        local pid, err = Act.fork()

        if err then
            print(err)
            -- worker process
        elseif pid == 0 then
            print('worker start')
            Act.spawn(function()
                while true do
                    local client, err = server:accept()

                    if client then
                        Act.spawn(handler, client)
                    elseif err then
                        print('failed to accept', err)
                        break
                    end
                end
            end)

            -- worker wait a SIGUSR1
            Act.sigwait(nil, signal.SIGUSR1)
            print('worker end')
            os.exit()
        end

        nworker = nworker + 1
    end

    handleSignal(nworker)
    server:close()
    print('end server')
end)

if not ok then
    print(err)
end
