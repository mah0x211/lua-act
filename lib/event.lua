--
-- Copyright (C) 2016-present Masatoshi Fukunaga
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
-- lib/event.lua
-- lua-act
-- Created by Masatoshi Teruya on 16/12/25.
--
--- file scope variables
local rawset = rawset
local setmetatable = setmetatable
local new_deque = require('act.deque')
local poller = require('act.poller')
local new_errno = require('errno').new
local OP_EVENT = require('act.aux').OP_EVENT

--- @class act.event
--- @field monitor poller
--- @field pool act.deque
--- @field used table<poller.event, boolean>
local Event = {}

function Event:__newindex()
    error('attempt to protected value', 2)
end

--- init
--- @return act.event? ev
--- @return any err
function Event:init()
    -- create event monitor
    local monitor, err, errno = poller()
    if err then
        return nil, new_errno(errno, err)
    end

    rawset(self, 'monitor', monitor)
    rawset(self, 'pool', new_deque())
    rawset(self, 'used', setmetatable({}, {
        __mode = 'k',
    }))

    return self
end

--- renew
--- @return boolean ok
--- @return any err
function Event:renew()
    local ok, err, errno = self.monitor:renew()
    if not ok then
        return false, new_errno(errno, err)
    end

    -- re-create new pool (dispose pooled events)
    self.pool = new_deque()
    -- renew used events
    for ev in pairs(self.used) do
        assert(ev:renew())
    end

    return true
end

--- revoke
--- @param ev poller.event
function Event:revoke(ev)
    -- release reference of event explicitly
    self.used[ev] = nil
    assert(ev:revert())
    -- push to event pool
    self.pool:push(ev)
end

--- register
--- @param callee act.callee
--- @param asa string
--- @param val integer|number
--- @param trigger string?
---| 'oneshot' oneshot event
---| 'edge' edge-triggered event
--- @return poller.event? ev
--- @return any err
function Event:register(callee, asa, val, trigger)
    assert(trigger == nil or trigger == 'oneshot' or trigger == 'edge',
           'trigger must be "oneshot" or "edge"')

    local ev = self.pool:pop()

    -- create new event
    if not ev then
        ev = self.monitor:new_event()
    end

    if trigger then
        if trigger == 'oneshot' then
            ev:as_oneshot()
        elseif trigger == 'edge' then
            ev:as_edge()
        end
    end

    -- register event as a asa
    local err, errno
    ev, err, errno = ev[asa](ev, val, callee)
    if not ev then
        return nil, new_errno(errno, err)
    end

    -- retain reference of event object in use
    self.used[ev] = true

    return ev
end

--- signal
--- @param callee act.callee
--- @param signo integer
--- @param trigger string?
--- @return poller.event? ev
--- @return any err
function Event:signal(callee, signo, trigger)
    return self:register(callee, 'as_signal', signo, trigger)
end

--- writable
--- @param callee act.callee
--- @param fd integer
--- @param trigger string?
--- @return poller.event? ev
--- @return any err
function Event:writable(callee, fd, trigger)
    return self:register(callee, 'as_write', fd, trigger)
end

--- readable
--- @param callee act.callee
--- @param fd integer
--- @param trigger string?
--- @return poller.event? ev
--- @return any err
function Event:readable(callee, fd, trigger)
    return self:register(callee, 'as_read', fd, trigger)
end

--- consume
--- @param msec integer
--- @return integer? nev
--- @return any err
function Event:consume(msec)
    if #self.monitor > 0 then
        local monitor = self.monitor
        -- wait events
        local nev, err, errno = monitor:wait(msec)

        if err then
            -- got critical error
            return nil, new_errno(errno, err)
        elseif nev > 0 then
            -- consuming events
            local ev, callee, disabled = monitor:consume()

            while ev do
                -- resume
                callee:call(OP_EVENT, ev:ident(), disabled)
                -- get next event
                ev, callee, disabled = monitor:consume()
            end
        end

        return #self.monitor
    end

    return 0
end

return {
    new = require('metamodule').new(Event),
}

