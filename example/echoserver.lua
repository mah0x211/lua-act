--[[

  Copyright (C) 2016 Masatoshi Teruya

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  example/echoserver.lua
  lua-act

  Created by Masatoshi Teruya on 16/12/24.

--]]
local Act = require('act')
-- you need to install the net module as follows;
--  $ luarocks install net
local InetServer = require('net.stream.inet').server


local function handler( client )
    Act.atexit( client.close, client )
    while true do
        local msg, err = client:recv()

        if err then
            print('error:', err)
            return
        end

        _, err = client:send(msg)
        if err then
            print('error:', err)
            return
        end
    end
end


local ok, err = Act.run(function()
    local server, err = InetServer.new({
        host = '127.0.0.1',
        port = 5000,
    })

    err = err or server:listen()
    if err then
        error(err)
    end

    print( 'start server: ', '127.0.0.1', 5000 )
    while true do
        local client, err = server:accept()

        if client then
            Act.spawn(handler, client)
        elseif err then
            print('failed to accept', err)
            break
        end
    end

    server:close()
    print( 'end server' )
end)

if not ok then
    error(err)
end
