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
local new_deque = require('act.deque')
local poller = require('act.poller')
local new_errno = require('errno').new
local OP_EVENT = require('act.aux').OP_EVENT

--- @class act.event.info
--- @field ev poller.event
--- @field asa string
--- @field val integer
--- @field trigger string?
---| 'oneshot' oneshot event
---| 'edge' edge-triggered event
--- @field callee act.callee?
--- @field is_ready boolean?

--- @class act.event
--- @field monitor poller
--- @field pool act.deque
--- @field used table<string, table<integer, act.event.info>>
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
    rawset(self, 'used', {
        signal = {},
        readable = {},
        writable = {},
    })

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
    for _, events in pairs(self.used) do
        for _, evinfo in pairs(events) do
            assert(evinfo.ev:renew())
        end
    end

    return true
end

local ASA2METHOD = {
    signal = 'as_signal',
    readable = 'as_read',
    writable = 'as_write',
}

--- revoke
--- @param asa string
---| 'signal' signal event
---| 'readable' readable event
---| 'writable' writable event
--- @param val integer
--- @return boolean ok
function Event:revoke(asa, val)
    assert(type(asa) == 'string' and ASA2METHOD[asa],
           'asa must be "signal", "readable" or "writable"')

    -- release reference of event explicitly
    local evinfo = self.used[asa][val]
    if evinfo then
        self.used[asa][val] = nil
        assert(evinfo.ev:revert())
        -- push to event pool
        self.pool:push(evinfo.ev)
        return true
    end
    return false
end

--- register
--- @param callee act.callee
--- @param asa
---| '"signal"' signal event
---| '"readable"' readable event
---| '"writable"' writable event
--- @param val integer
--- @param trigger?
---| '"oneshot"' oneshot event
---| '"edge"' edge-triggered event
--- @return act.event.info? evinfo
--- @return any err
--- @return boolean? is_ready
function Event:register(callee, asa, val, trigger)
    assert(type(asa) == 'string' and ASA2METHOD[asa],
           'asa must be "signal", "readable" or "writable"')
    assert(trigger == nil or trigger == 'oneshot' or trigger == 'edge',
           'trigger must be "oneshot" or "edge"')

    local evinfo = self.used[asa][val]
    if evinfo and evinfo.trigger == trigger then
        if evinfo.is_ready then
            -- event is already occurred
            evinfo.is_ready = nil
            return nil, nil, true
        end
        -- use cached event
        evinfo.callee = callee
        return evinfo
    end

    -- get pooled event
    local ev = self.pool:pop()
    if not ev then
        -- create new event
        ev = self.monitor:new_event()
    end

    if trigger then
        if trigger == 'oneshot' then
            ev:as_oneshot()
        elseif trigger == 'edge' then
            ev:as_edge()
        end
    end

    -- register new event
    local newinfo = {
        asa = asa,
        val = val,
        trigger = trigger,
        callee = callee,
    }
    local method = ASA2METHOD[asa]
    local err, errno
    ev, err, errno = ev[method](ev, val, newinfo)
    if not ev then
        return nil, new_errno(errno, err)
    end
    newinfo.ev = ev

    -- retain reference of event object in use
    self.used[asa][val] = newinfo

    return newinfo
end

--- consume
--- @param sec number
--- @return integer? nev
--- @return any err
function Event:consume(sec)
    if #self.monitor > 0 then
        local monitor = self.monitor
        -- wait events
        local nev, err, errno = monitor:wait(sec)

        if err then
            -- got critical error
            return nil, new_errno(errno, err)
        elseif nev > 0 then
            -- consuming events
            local ev, evinfo, disabled = monitor:consume()

            while ev do
                -- resume
                local callee = evinfo.callee
                if callee then
                    -- clear callee reference from event-info
                    evinfo.callee = nil
                    callee:call(OP_EVENT, evinfo.ev:ident(), disabled)
                else
                    -- set a flag to confirm that the event has already occurred
                    evinfo.is_ready = true
                end
                -- get next event
                ev, evinfo, disabled = monitor:consume()
            end
        end

        return #self.monitor
    end

    return 0
end

return {
    new = require('metamodule').new(Event),
}

