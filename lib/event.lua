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
-- lib/event.lua
-- lua-act
-- Created by Masatoshi Teruya on 16/12/25.
--
--- file scope variables
local rawset = rawset
local setmetatable = setmetatable
local deque_new = require('deque').new
local new_evm = require('evm').new
local OP_EVENT = require('act.aux').OP_EVENT

--- @class act.event
--- @field monitor evm
--- @field pool Deque
--- @field used table<evm.event, boolean>
local Event = {}

function Event:__newindex()
    error('attempt to protected value', 2)
end

--- init
--- @return act.event ev
--- @return error? err
function Event:init()
    local monitor, err = new_evm()
    if err then
        return nil, err
    end

    rawset(self, 'monitor', monitor)
    rawset(self, 'pool', deque_new())
    rawset(self, 'used', setmetatable({}, {
        __mode = 'k',
    }))

    return self
end

--- renew
--- @return boolean ok
--- @return error? err
function Event:renew()
    local ok, err = self.monitor:renew()
    if not ok then
        return false, err
    end

    -- re-create new pool (dispose pooled events)
    self.pool = deque_new()
    -- renew used events
    for ev in pairs(self.used) do
        assert(ev:renew())
    end

    return true
end

--- register
--- @param callee act.callee.Callee
--- @param asa string
--- @param val integer|number
--- @param oneshot? boolean
--- @param edge? boolean
--- @return evm.event ev
--- @return error? err
function Event:register(callee, asa, val, oneshot, edge)
    local ev = self.pool:pop()

    -- create new event
    if not ev then
        ev = self.monitor:newevent()
    end

    -- register event as a asa
    local ok, err = ev[asa](ev, val, callee, oneshot, edge)
    if not ok then
        return nil, err
    end

    -- retain reference of event object in use
    self.used[ev] = true

    return ev
end

--- revoke
--- @param ev evm.event
function Event:revoke(ev)
    -- release reference of event explicitly
    self.used[ev] = nil
    ev:revert()
    -- push to event pool
    self.pool:push(ev)
end

--- signal
--- @param callee act.callee.Callee
--- @param signo integer
--- @param oneshot boolean
--- @return evm.signal ev
--- @return error? err
function Event:signal(callee, signo, oneshot)
    return self:register(callee, 'assignal', signo, oneshot)
end

--- timer
--- @param callee act.callee.Callee
--- @param ival number
--- @param oneshot boolean
--- @return evm.timer ev
--- @return error? err
function Event:timer(callee, ival, oneshot)
    return self:register(callee, 'astimer', ival, oneshot)
end

--- writable
--- @param callee act.callee.Callee
--- @param fd integer
--- @param oneshot boolean
--- @return evm.writable ev
--- @return error? err
function Event:writable(callee, fd, oneshot)
    return self:register(callee, 'aswritable', fd, oneshot)
end

--- readable
--- @param callee act.callee.Callee
--- @param fd integer
--- @param oneshot boolean
--- @return evm.readable ev
--- @return error? err
function Event:readable(callee, fd, oneshot)
    return self:register(callee, 'asreadable', fd, oneshot)
end

--- consume
--- @param msec integer
--- @return integer nev
--- @return string? err
function Event:consume(msec)
    if #self.monitor > 0 then
        local monitor = self.monitor
        -- wait events
        local nev, err = monitor:wait(msec)

        if err then
            -- got critical error
            return nil, err
        elseif nev > 0 then
            -- consuming events
            local ev, callee, disabled = monitor:getevent()

            while ev do
                -- resume
                callee:call(OP_EVENT, ev:ident(), disabled)
                -- get next event
                ev, callee, disabled = monitor:getevent()
            end
        end

        return #self.monitor
    end

    return 0
end

return {
    new = require('metamodule').new(Event),
}

