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

  lib/event.lua
  lua-synops
  Created by Masatoshi Teruya on 16/12/25.

--]]

--- file scope variables
local Deque = require('deque');
local Sentry = require('sentry');
local OP_EVENT = require('synops.aux').OP_EVENT;
local setmetatable = setmetatable;


--- class Event
local Event = {};


--- register
-- @param callee
-- @param asa
-- @param val
-- @param oneshot
-- @param edge
-- @return ev
-- @return err
function Event:register( callee, asa, val, oneshot, edge )
    local ev = self.pool:pop();
    local err;

    -- create new context
    if not ev then
        ev, err = self.loop:newevent();
        if err then
            return nil, err;
        end
    end

    -- register event
    err = ev[asa]( ev, val, callee, oneshot, edge );
    if err then
        return nil, err;
    end

    -- retain reference of event object in use
    self.used[ev] = true;

    return ev;
end


--- revoke
-- @param ev
function Event:revoke( ev )
    -- release reference of event explicitly
    self.used[ev] = nil;
    ev:revert();
    -- push to event pool
    self.pool:push( ev );
end


--- signal
-- @param callee
-- @param signo
-- @param oneshot
-- @return id
-- @return err
function Event:signal( callee, signo, oneshot )
    return self:register( callee, 'assignal', signo, oneshot );
end


--- timer
-- @param callee
-- @param ival
-- @param oneshot
-- @return id
-- @return err
function Event:timer( callee, ival, oneshot )
    return self:register( callee, 'astimer', ival, oneshot );
end


--- writable
-- @param callee
-- @param fd
-- @param oneshot
-- @return id
-- @return err
function Event:writable( callee, fd, oneshot )
    return self:register( callee, 'aswritable', fd, oneshot );
end


--- readable
-- @param callee
-- @param fd
-- @param oneshot
-- @return id
-- @return err
function Event:readable( callee, fd, oneshot )
    return self:register( callee, 'asreadable', fd, oneshot );
end


--- consume
-- @param msec
-- @return nev
-- @return err
function Event:consume( msec )
    if #self.loop > 0 then
        local loop = self.loop;
        -- wait events
        local nev, err = loop:wait( msec );

        -- got critical error
        if err then
            return nil, err;
        -- consuming events
        elseif nev > 0 then
            local ev, callee, disabled = loop:getevent();

            while ev do
                -- resume
                callee:call( OP_EVENT, ev:ident(), disabled );
                -- get next event
                ev, callee, disabled = loop:getevent();
            end
        end

        return #self.loop;
    end

    return 0;
end


--- renew
-- @return ok
-- @return err
function Event:renew()
    local ok, err = self.loop:renew();

    if not ok then
        return false, err;
    end

    -- re-create new pool (dispose pooled events)
    self.pool = Deque.new();
    -- renew used events
    for ev in pairs( self.used ) do
        assert( ev:renew() )
    end

    return true
end


--- new
-- @return events
-- @return err
local function new()
    local loop, err = Sentry.new();

    if err then
        return nil, err;
    end

    return setmetatable({
        loop = loop,
        pool = Deque.new(),
        used = setmetatable({},{
            __mode = 'k'
        })
    },{
        __index = Event
    });
end


return {
    new = new
};

