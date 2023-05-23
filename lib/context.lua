--
-- Copyright (C) 2021-present Masatoshi Fukunaga
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
--- file scope variables
local rawset = rawset
local new_event = require('act.event').new
local new_runq = require('act.runq').new
local new_lockq = require('act.lockq').new
local new_pool = require('act.pool').new

--- @class act.context
--- @field event act.event
--- @field runq act.runq
--- @field lockq act.lockq
--- @field pool act.pool
local Context = {}

function Context:__newindex()
    error('attempt to protected value', 2)
end

--- init
--- @return act.context? ctx
--- @return any err
function Context:init()
    local event, err = new_event()
    if err then
        return nil, err
    end

    rawset(self, 'event', event)
    rawset(self, 'runq', new_runq())
    rawset(self, 'lockq', new_lockq(self.runq))
    rawset(self, 'pool', new_pool())
    return self
end

--- renew
--- @return boolean ok
--- @return any err
function Context:renew()
    -- child process must be rebuilding event properties
    return self.event:renew()
end

--- pushq pushes a callee to runq
--- @param callee act.callee
--- @param msec? integer
--- @return boolean ok
--- @return any err
function Context:pushq(callee, msec)
    return self.runq:push(callee, msec)
end

--- removeq remove a callee from runq
--- @param callee act.callee
function Context:removeq(callee)
    self.runq:remove(callee)
end

--- read_lock
--- @param callee act.callee
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Context:read_lock(callee, fd, msec)
    return self.lockq:read_lock(callee, fd, msec)
end

--- read_unlock
--- @param callee act.callee
--- @param fd integer
--- @return boolean ok
function Context:read_unlock(callee, fd)
    return self.lockq:read_unlock(callee, fd)
end

--- write_lock
--- @param callee act.callee
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Context:write_lock(callee, fd, msec)
    return self.lockq:write_lock(callee, fd, msec)
end

--- write_unlock
--- @param callee act.callee
--- @param fd integer
--- @return boolean ok
function Context:write_unlock(callee, fd)
    return self.lockq:write_unlock(callee, fd)
end

--- release_locks release the callee from the lockq
--- @param callee act.callee
--- @return integer nrelease
function Context:release_locks(callee)
    return self.lockq:release(callee)
end

--- pool_get
--- @return act.callee
function Context:pool_get()
    return self.pool:pop()
end

--- pool_set
--- @param callee act.callee
function Context:pool_set(callee)
    self.pool:push(callee)
end

return {
    new = require('metamodule').new(Context),
}

