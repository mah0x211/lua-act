--
-- Copyright (C) 2016 Masatoshi Teruya
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
-- example/echoserver.lua
-- lua-act
--
-- Created by Masatoshi Teruya on 16/12/24.
--
-- you need to install the following modules:
--  act
--  net
--
local new_server = require('net.stream.inet').server.new

-- NOTE: The net module performs asynchronous processing implicitly using the
-- gpoll module.
-- Therefore, by registering a group of functions of the act module in the
-- gpoll module, concurrent processing is automatically performed without
-- changing the synchronous code.
local act = require('act')
require('gpoll').set_poller(act)

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

local function main()
    local server = assert(new_server('127.0.0.1', 5000))
    assert(server:listen())

    print('start server: ', '127.0.0.1', 5000)
    while true do
        local client, err = server:accept()
        if client then
            -- create coroutine
            act.spawn(handle_client, client)
        elseif err then
            print('failed to accept', err)
            break
        end
    end
    print('end server')

    server:close()
end

local ok, err = act.run(main)
if not ok then
    error(err)
end
