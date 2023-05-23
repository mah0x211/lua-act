--
-- Copyright (C) 2023-present Masatoshi Fukunaga
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
local yield = coroutine.yield
local find = string.find
-- constants
local OP_RUNQ = require('act.aux').OP_RUNQ

--- @class act.lockq
--- @field runq act.runq
--- @field rlockq table<integer, table>
--- @field wlockq table<integer, table>
local LockQ = {}

function LockQ:__newindex()
    error('attempt to protected value', 2)
end

--- init
--- @param runq act.runq
--- @vararg any
--- @return act.lockq
function LockQ:init(runq)
    if find(tostring(runq), 'act.runq') ~= 1 then
        error('runq must be instance of act.runq', 2)
    end
    rawset(self, 'runq', runq)
    rawset(self, 'rlockq', {})
    rawset(self, 'wlockq', {})
    return self
end

--- release the callee from the lockq
--- @param callee act.callee
--- @return integer nrelease
function LockQ:release(callee)
    local runq = self.runq
    local nrelease = 0

    -- unlock or remove from lockq if callee is registered in lockq
    for lockq, unlockfn in pairs({
        [self.rlockq] = self.read_unlock,
        [self.wlockq] = self.write_unlock,
    }) do
        for fd, waitq in pairs(lockq) do
            local idx = waitq[callee]

            -- unlock if callee is holding the lock
            if unlockfn(self, callee, fd) then
                nrelease = nrelease + 1
            elseif idx then
                -- release callee from waitq if callee is waiting for the lock
                waitq[idx] = false
                waitq[callee] = nil
                runq:remove(callee)
                nrelease = nrelease + 1
            end
        end
    end

    return nrelease
end

--- unlock release the lock of the specified file descriptor.
--- @param runq act.runq
--- @param lockq table<integer, table>
--- @param callee act.callee
--- @param fd integer
--- @return boolean ok
local function unlock(runq, lockq, callee, fd)
    local waitq = lockq[fd]
    if not waitq or waitq.locker ~= callee then
        -- callee is not holding the lock
        return false
    end

    -- release the callee reference
    waitq.locker = nil
    -- resume next callee
    for i = 1, #waitq do
        local next_callee = waitq[i]
        -- resume next callee
        if next_callee then
            waitq[next_callee] = nil
            waitq[i] = false
            waitq.locker = next_callee
            -- remove from runq and push to runq
            runq:remove(next_callee)
            runq:push(next_callee)
            return true
        end
    end

    lockq[fd] = nil
    return true
end

--- read_unlock
--- @param callee act.callee
--- @param fd integer
--- @return boolean ok
function LockQ:read_unlock(callee, fd)
    return unlock(self.runq, self.rlockq, callee, fd)
end

--- write_unlock
--- @param fd integer
--- @return boolean ok
function LockQ:write_unlock(callee, fd)
    return unlock(self.runq, self.wlockq, callee, fd)
end

--- lock lock a fd
--- @param runq act.runq
--- @param lockq table<integer, table>
--- @param callee act.callee
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
local function lock(runq, lockq, callee, fd, msec)
    local waitq = lockq[fd]
    if not waitq then
        -- create a new lock-waitq and keep the waitq reference
        lockq[fd] = {
            locker = callee,
        }
        return true
    elseif waitq.locker == callee then
        -- already locked
        return true
    end

    if msec ~= nil then
        -- suspend until reached to msec
        assert(runq:push(callee, msec))
    end

    -- other callee is locking the fd
    local idx = #waitq + 1
    waitq[idx] = callee
    waitq[callee] = idx
    -- wait until resumed by resume method
    local op = yield()
    waitq[callee] = nil
    waitq[idx] = false

    assert(op == OP_RUNQ, 'invalid implements')

    -- resumed by time-out if locker is not callee
    if waitq.locker ~= callee then
        if msec then
            runq:remove(callee)
        end
        return false, nil, true
    end

    -- got the lock
    return true
end

--- read_lock
--- @param callee act.callee
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function LockQ:read_lock(callee, fd, msec)
    return lock(self.runq, self.rlockq, callee, fd, msec)
end

--- write_lock
--- @param callee act.callee
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function LockQ:write_lock(callee, fd, msec)
    return lock(self.runq, self.wlockq, callee, fd, msec)
end

return {
    new = require('metamodule').new(LockQ),
}

