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
--- @return boolean ok
--- @return any err
function Context:pushq(callee)
    return self.runq:push(callee)
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

