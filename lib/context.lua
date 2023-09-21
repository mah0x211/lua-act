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

--- @class act.bitset
--- @field get fun(self:act.bitset, pos:integer):(ok:boolean?, err:any)
--- @field set fun(self:act.bitset, pos:integer):(ok:boolean?, err:any)
--- @field unset fun(self:act.bitset, pos:integer):(ok:boolean?, err:any)
--- @field ffz fun(self:act.bitset):(pos:integer?, err:any)
--- @field add fun(self:act.bitset):(pos:integer?, err:any)

--- @type fun():act.bitset
local new_bitset = require('act.bitset')

--- @class act.context
--- @field event act.event
--- @field runq act.runq
--- @field lockq act.lockq
--- @field pool act.pool
--- @field cidset act.bitset
--- @field active_callees table<act.callee, boolean>
local Context = {}

function Context:__newindex()
    error('attempt to protected value', 2)
end

--- init
--- @param event_cache_enabled boolean
--- @return act.context? ctx
--- @return any err
function Context:init(event_cache_enabled)
    local event, err = new_event(event_cache_enabled)
    if err then
        return nil, err
    end

    local cidset
    cidset, err = new_bitset()
    if err then
        return nil, err
    end

    rawset(self, 'event', event)
    rawset(self, 'runq', new_runq())
    rawset(self, 'lockq', new_lockq(self.runq))
    rawset(self, 'pool', new_pool())
    rawset(self, 'cidset', cidset)
    rawset(self, 'active_callees', {})
    return self
end

--- add_active_callees
--- @param callee act.callee
function Context:add_active_callees(callee)
    if self.active_callees[callee] then
        error('callee is already active')
    end
    self.active_callees[callee] = true
end

--- del_active_callees
--- @param callee act.callee
function Context:del_active_callees(callee)
    if not self.active_callees[callee] then
        error('callee is not active')
    end
    self.active_callees[callee] = nil
end

--- has_active_callees
--- @return boolean
function Context:has_active_callees()
    return next(self.active_callees) ~= nil
end

--- getinfo_active_callees
--- @return table[] infos
function Context:getinfo_active_callees()
    local infos = {}
    for callee in pairs(self.active_callees) do
        infos[#infos + 1] = callee.co:getinfo(2, 'Sl')
    end
    return infos
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
--- @param sec? number
function Context:pushq(callee, sec)
    self.runq:push(callee, sec)
end

--- removeq remove a callee from runq
--- @param callee act.callee
function Context:removeq(callee)
    self.runq:remove(callee)
end

--- read_lock
--- @param callee act.callee
--- @param fd integer
--- @param sec number
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Context:read_lock(callee, fd, sec)
    return self.lockq:read_lock(callee, fd, sec)
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
--- @param sec number
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Context:write_lock(callee, fd, sec)
    return self.lockq:write_lock(callee, fd, sec)
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

--- cid_alloc
--- @return integer cid
--- @return any err
function Context:cid_alloc()
    return self.cidset:add()
end

--- cid_free
--- @param cid integer
--- @return boolean ok
--- @return any err
function Context:cid_free(cid)
    return self.cidset:unset(cid)
end

return {
    new = require('metamodule').new(Context),
}

