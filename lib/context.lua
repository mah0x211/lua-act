--
-- Copyright (C) 2021 Masatoshi Fukunaga
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
local deque_new = require('deq').new
local event_new = require('act.event').new
local runq_new = require('act.runq').new

--- @class act.context.Context
--- @field event act.event.Event
--- @field runq act.runq.RunQ
--- @field pool Deque
local Context = {}

function Context:__newindex()
    error('attempt to protected value', 2)
end

--- init
--- @return act.context.Context
--- @return string? err
function Context:init()
    local event, err = event_new()
    if err then
        return nil, err
    end

    rawset(self, 'event', event)
    rawset(self, 'runq', runq_new())
    rawset(self, 'pool', deque_new())
    return self
end

--- renew
--- @return boolean ok
--- @return string? err
function Context:renew()
    -- child process must be rebuilding event properties
    return self.event:renew()
end

--- pop removes a callee from the pool and return it
--- @return act.callee.Callee? callee
function Context:pop()
    return self.pool:pop()
end

--- pushq pushes a callee to runq
--- @param callee act.callee.Callee
--- @return boolean ok
--- @return string? err
function Context:pushq(callee)
    return self.runq:push(callee)
end

return {
    new = require('metamodule').new.Context(Context),
}

