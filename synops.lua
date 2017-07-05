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

  synops.lua
  lua-synops
  Created by Masatoshi Teruya on 16/12/25.

--]]

--- file scope variables
local Deque = require('deque');
local fork = require('process').fork;
local HRTimer = require('synops.hrtimer');
local RunQ = require('synops.runq');
local Event = require('synops.event');
local Callee = require('synops.callee');
local setmetatable = setmetatable;
--- constants
local SYNOPS_CTX;


--- spawn
-- @param atexit
-- @param fn
-- @param ...
-- @return ok
-- @return err
local function spawn( atexit, fn, ... )
    local callee = SYNOPS_CTX.pool:pop();
    local ok, err;

    -- use pooled callee
    if callee then
        callee:init( atexit, fn, ... );
    -- create new callee
    else
        callee, err = Callee.new( SYNOPS_CTX, atexit, fn, ... );
        if err then
            return false, err;
        end
    end

    -- push to runq if not atexit
    if not atexit then
        ok, err = SYNOPS_CTX.runq:push( callee );
        if not ok then
            return false, err;
        end
    end

    return true;
end


--- class Synops
local Synops = {};


--- fork
-- @return pid
-- @return err
-- @return again
function Synops.fork()
    if Callee.acquire() then
        local pid, err, again = fork();

        if not pid then
            return nil, err, again;
        -- child process must be rebuilding event properties
        elseif pid == 0 then
            SYNOPS_CTX.event:renew();
        end

        return pid;
    end

    error( 'cannot call fork() from outside of execution context', 2 );
end


--- spawn
-- @param fn
-- @param ...
-- @return ok
-- @return err
function Synops.spawn( fn, ... )
    if Callee.acquire() then
        return spawn( false, fn, ... );
    end

    error( 'cannot call spawn() from outside of execution context', 2 );
end


--- exit
-- @param ...
function Synops.exit( ... )
    local callee = Callee.acquire();

    if callee then
        callee:exit( ... );
    end

    error( 'cannot call exit() at outside of execution context', 2 );
end


--- later
-- @return ok
-- @return err
function Synops.later()
    local callee = Callee.acquire();

    if callee then
        return callee:later();
    end

    error( 'cannot call later() from outside of execution context', 2 );
end


--- atexit
-- @param fn
-- @param ...
-- @return ok
-- @return err
function Synops.atexit( fn, ... )
    if Callee.acquire() then
        return spawn( true, fn, ... );
    end

    error( 'cannot call atexit() at outside of execution context', 2 );
end


--- await
-- @return ok
-- @return ...
function Synops.await()
    local callee = Callee.acquire();

    if callee then
        return callee:await();
    end

    error( 'cannot call await() at outside of execution context', 2 );
end


--- sleep
-- @param deadline
-- @return ok
-- @return err
function Synops.sleep( deadline )
    local callee = Callee.acquire();

    if callee then
        return callee:sleep( deadline );
    end

    error( 'cannot call sleep() from outside of execution context', 2 );
end


--- sigwait
-- @param deadline
-- @param ...
-- @return signo
-- @return err
-- @return timeout
function Synops.sigwait( deadline, ... )
    local callee = Callee.acquire();

    if callee then
        return callee:sigwait( deadline, ... );
    end

    error( 'cannot call sleep() from outside of execution context', 2 );
end


--- readable
-- @param fd
-- @param deadline
-- @return ok
-- @return err
-- @return timeout
function Synops.readable( fd, deadline )
    local callee = Callee.acquire();

    if callee then
        return callee:readable( fd, deadline );
    end

    error( 'cannot call readable() from outside of execution context', 2 );
end


--- writable
-- @param fd
-- @param deadline
-- @return ok
-- @return err
-- @return timeout
function Synops.writable( fd, deadline )
    local callee = Callee.acquire();

    if callee then
        return callee:writable( fd, deadline );
    end

    error( 'cannot call writable() from outside of execution context', 2 );
end


--- runloop
-- @param fn
-- @param ...
-- @return ok
-- @return err
local function runloop( fn, ... )
    local event, runq, hrtimer, ok, err;

    -- check first argument
    assert( type( fn ) == 'function', 'fn must be function' );

    if SYNOPS_CTX then
        return false, 'synops run already';
    end

    -- create event
    event, err = Event.new();
    if err then
        return false, err;
    end

    -- create synops context
    runq = RunQ.new();
    SYNOPS_CTX = setmetatable({
        event = event,
        runq = runq,
        pool = Deque.new()
    },{
        __newindex = function()
            error( 'attempt to protected value', 2 );
        end
    });

    -- create main coroutine
    ok, err = spawn( false, fn, ... );
    if not ok then
        return false, err;
    end

    -- run synops scheduler
    hrtimer = HRTimer.new();
    while true do
        local msec = -1;

        if runq:len() > 0 and hrtimer:remain() < 0 then
            msec = runq:consume(-1);
            if msec > 0 then
                hrtimer:init( msec );
            end
        end

        if event:len() > 0 then
            err = event:consume( msec );
            -- got critical error
            if err then
                return false, err;
            end
        elseif runq:len() > 0 then
            hrtimer:sleep();
        else
            return true;
        end
    end
end


--- run
-- @param fn
-- @param ...
-- @return ok
-- @return err
function Synops.run( fn, ... )
    local ok, rv, err = pcall( runloop, fn, ... );

    SYNOPS_CTX = nil;
    if ok then
        return rv, err;
    end

    return false, rv;
end


-- exports
return Synops;
