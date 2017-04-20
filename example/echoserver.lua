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
  lua-synops

  Created by Masatoshi Teruya on 16/12/24.

--]]
local inspect = require('util').inspect;
local signal = require('signal')
local InetServer = require('net.stream.inet').server;
local Synops = require('synops');
-- constants
local HOST = '127.0.0.1';
local PORT = '5000';



local function send( sock, str, deadline )
    local len, err, again = sock:send( str );

    if not again then
        return len, err;
    else
        local fd = sock:fd();
        local total = 0;
        local ok, timeout;

        repeat
            total = total + len;

            if len > 0 then
                str = str:sub( len + 1 );
            end

            ok, err, timeout = Synops.writable( fd, deadline );
            if ok then
                len, err, again = sock:send( str );
            end
        until not again or timeout == true;

        return len and total + len, err, timeout;
    end
end


local function recv( sock )
    local msg, err, again = sock:recv();

    if not again then
        return msg, err;
    else
        local ok;

        ok, err = Synops.readable( sock:fd() );
        if ok then
            return sock:recv();
        end

        return nil, err;
    end
end


local function accept( sock )
    local client, err, again = sock:accept();

    if not again then
        return client, err;
    else
        local ok;

        repeat
            ok, err = Synops.readable( sock:fd() );
            if ok then
                client, err, again = sock:accept();
            else
                print( 'accept wait()', ok, err );
                return nil, err;
            end
        until not again;

        return client, err;
    end
end


local function handleClient( client )
    local err;

    Synops.atexit( client.close, client );

    while true do
        local msg, ok;

        msg, err = recv( client );
        if not msg then break end

        ok, err = send( client, msg );
        if err then break end
    end

    if err then
        print( err );
    end
end


local function handleServer( server )
    Synops.atexit( server.close, server );

    repeat
        local client, err = accept( server );

        -- got client
        if client then
            -- print( 'accept', client:fd() )
            assert( Synops.spawn( handleClient, client ) );
        end
    until err;
end


local function main()
    -- create server
    local server, err = InetServer.new({
        host = HOST;
        port = PORT,
        reuseaddr = true,
        nonblock = true,
    });

    if err then
        error( err );
    end

    err = server:listen( BACKLOG );
    if err then
        server:close();
        error( err );
    end

    -- start server
    print( 'start server: ', HOST, PORT, server:fd() );
    assert( Synops.spawn( handleServer, server ) );
    signal.blockAll();
    print( 'sigwait', Synops.sigwait( nil, signal.SIGINT ) );
    -- assert( c:await() )

    print( 'end server' );
end


do
    print( 'run', assert( Synops.run( main ) ) );
    print('done')
end
