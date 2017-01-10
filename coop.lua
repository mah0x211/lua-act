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

  coop.lua
  lua-coop
  Created by Masatoshi Teruya on 16/12/25.

--]]

--- file scope variables
local Deque = require('deque');
local RunQ = require('coop.runq');
local Event = require('coop.event');
local Callee = require('coop.callee');
local setmetatable = setmetatable;
local yield = coroutine.yield;


--- spawn
-- @param fn
-- @param ctx
-- @param ...
-- @param ok
-- @param err
local function spawn( coop, fn, ctx, ... )
    local callee = coop.pool:pop();

    -- use pooled callee
    if callee then
        callee:init( coop, fn, ctx, ... );
    -- create new callee
    else
        local err;

        callee, err = Callee.new( coop, fn, ctx, ... );
        if err then
            return false, err;
        end
    end

    -- push to runq
    coop.runq:push( callee );

    return true;
end


--- class Coop
local Coop = {};


--- spawn
-- @param fn
-- @param ctx
-- @param ...
-- @param ok
-- @param err
function Coop:spawn( fn, ctx, ... )
    if self.callee then
        return spawn( self, fn, ctx, ... );
    end

    error( 'cannot call spawn() from outside of vm', 2 );
end


--- exit
-- @param ...
function Coop:exit( ... )
    local callee = self.callee;

    if callee then
        callee:exit( ... );
    end

    error( 'cannot call exit() at outside of vm', 2 );
end


--- later
function Coop:later()
    local callee = self.callee;

    if callee then
        -- push to runq
        self.runq:push( callee );
        return yield();
    end

    error( 'cannot call later() from outside of vm', 2 );
end


--- atexit
-- @param fn
-- @param ...
function Coop:atexit( fn, ... )
    local callee = self.callee;

    if callee then
        if type( fn ) ~= 'function' then
            error( 'fn must be function', 2 );
        end

        callee:atexit( fn, ... );
    else
        error( 'cannot call atexit() at outside of vm', 2 );
    end
end


--- await
-- @return ok
-- @return ...
function Coop:await()
    local callee = self.callee;

    if callee then
        return callee:await();
    end

    error( 'cannot call await() at outside of vm', 2 );
end


--- sleep
-- @param deadline
-- @param status
-- @param err
function Coop:sleep( deadline )
    local callee = self.callee;

    if callee then
        return callee:sleep( deadline );
    end

    error( 'cannot call sleep() from outside of vm', 2 );
end


--- sigwait
-- @param deadline
-- @param ...
-- @param status
-- @param err
function Coop:sigwait( deadline, ... )
    local callee = self.callee;

    if callee then
        return callee:sigwait( deadline, ... );
    end

    error( 'cannot call sleep() from outside of vm', 2 );
end


--- readable
-- @param fd
-- @param deadline
-- @return status
-- @return err
function Coop:readable( fd, deadline )
    local callee = self.callee;

    if callee then
        return callee:readable( fd, deadline );
    end

    error( 'cannot call readable() from outside of vm', 2 );
end


--- writable
-- @param fd
-- @param deadline
-- @return status
-- @return err
function Coop:writable( fd, deadline )
    local callee = self.callee;

    if callee then
        return callee:writable( fd, deadline );
    end

    error( 'cannot call writable() from outside of vm', 2 );
end


--- run
-- @param fn
-- @param ctx
-- @param ok
-- @param err
local function run( fn, ctx )
    -- create event
    local event, err = Event.new();

    if event then
        local runq = RunQ.new();
        local coop = setmetatable({
            callee = false,
            event = event,
            runq = runq,
            pool = Deque.new()
        },{
            __index = Coop
        });
        local ok;

        ok, err = spawn( coop, fn, ctx );
        if ok then
            while event:len() > 0 or runq:len() > 0 do
                local sec = runq:consume() == 0 and -1 or 500;

                err = event:consume( sec );
                -- got critical error
                if err then
                    break;
                end
            end
        end
    end

    return not err, err;
end


-- exports
return {
    run = run,
    EV_ERR = Callee.EV_ERR,
    EV_HUP = Callee.EV_HUP,
    EV_OK = Callee.EV_OK,
    EV_TIMEOUT = Callee.EV_TIMEOUT
};
