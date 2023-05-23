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
-- lib/callee.lua
-- lua-act
-- Created by Masatoshi Teruya on 16/12/26.
--
--- file scope variables
local yield = coroutine.yield
local setmetatable = setmetatable
local new_coro = require('act.coro').new
local new_stack = require('act.stack')
local new_deque = require('act.deque')
local hrtimer = require('act.hrtimer')
local getnsec = hrtimer.getnsec
local getmsec = hrtimer.getmsec
local aux = require('act.aux')
local concat = aux.concat
-- constants
local OP_EVENT = aux.OP_EVENT
local OP_RUNQ = aux.OP_RUNQ
local OP_AWAIT = aux.OP_AWAIT
local OK = require('act.coro').OK
--- static variables
local SUSPENDED = setmetatable({}, {
    __mode = 'v',
})
local RWAITS = {}
local WWAITS = {}

--- unwaitfd
--- @param operators table<integer, act.callee>
--- @param fd integer
local function unwaitfd(operators, fd)
    local callee = operators[fd]

    -- found
    if callee then
        operators[fd] = nil

        local ev = callee.fdev
        callee.fdev = nil
        callee.is_cancel = true
        callee.ctx.event:revoke(ev)
        -- requeue without timeout
        callee.ctx.runq:remove(callee)
        assert(callee.ctx.runq:push(callee))
    end
end

--- unwait_readable
--- @param fd integer
local function unwait_readable(fd)
    unwaitfd(RWAITS, fd)
end

--- unwait_writable
--- @param fd integer
local function unwait_writable(fd)
    unwaitfd(WWAITS, fd)
end

--- unwait
--- @param fd integer
local function unwait(fd)
    unwaitfd(RWAITS, fd)
    unwaitfd(WWAITS, fd)
end

--- resume
--- @param cid string
--- @vararg any
--- @return boolean ok
local function resume(cid, ...)
    local callee = SUSPENDED[cid]

    -- found a suspended callee
    if callee then
        SUSPENDED[cid] = nil
        callee.argv:set(...)
        -- resume via runq
        callee.ctx.runq:remove(callee)
        callee.ctx.runq:push(callee)

        return true
    end

    return false
end

--- @class act.callee
--- @field ctx act.context
--- @field cid integer
--- @field co reco
--- @field children deque
--- @field parent? act.callee
--- @field is_await? boolean
--- @field is_cancel? boolean
--- @field is_atexit? boolean
--- @field is_exit? boolean
--- @field fdev? poller.event
--- @field sigset? deque
local Callee = {}

--- dispose
--- @param ok boolean
--- @param status integer
function Callee:dispose(ok, status)
    local runq = self.ctx.runq

    runq:remove(self)
    -- release from lockq
    self.ctx:release_locks(self)

    -- remove state properties
    self.is_exit = nil
    SUSPENDED[self.cid] = nil

    -- revoke all events currently in use
    local event = self.ctx.event
    -- revoke io event
    local ev = self.fdev
    if ev then
        self.fdev = nil
        local fd = ev:ident()
        if RWAITS[fd] == self then
            RWAITS[fd] = nil
        elseif WWAITS[fd] == self then
            WWAITS[fd] = nil
        end
        event:revoke(ev)
    end

    -- revoke signal events
    local sigset = self.sigset
    if sigset then
        self.sigset = nil
        for _ = 1, #sigset do
            event:revoke(sigset:pop())
        end
    end

    -- dispose child coroutines
    for _ = 1, #self.children do
        local child = self.children:pop()
        -- release references
        child.parent = nil
        child.ref = nil
        -- call dispose method
        child:dispose(true)
    end

    -- call parent
    local parent = self.parent
    if parent then
        local ref = self.ref

        -- release references
        self.parent = nil
        self.ref = nil
        -- detach from parent
        ref:remove()
        if parent.is_await then
            -- parent waiting for child results
            parent.is_await = nil
            local stat = {
                cid = self.cid,
            }
            if ok then
                stat.result = {
                    self.co:results(),
                }
            else
                stat.status = status
                stat.error = self.co:results()
            end
            parent:call(OP_AWAIT, stat)
        elseif parent.is_atexit then
            -- call atexit callee
            parent.is_atexit = nil
            parent:call(ok, status, self.co:results())
        elseif not ok then
            -- throws an error on failure
            error(concat({
                self.co:results(),
            }, '\n'))
        end
    elseif not ok then
        error(concat({
            self.co:results(),
        }, '\n'))
    end

    -- delete stacked values
    self.args:clear()
    self.argv:clear()

    -- add to pool for reuse
    self.ctx:pool_set(self)
end

--- exit
--- @vararg any
function Callee:exit(...)
    self.is_exit = true
    yield(...)
    -- normally unreachable
    error('invalid implements')
end

--- await until the child thread to exit while the specified number of seconds.
--- @param msec integer
--- @return table? res
--- @return boolean? timeout
function Callee:await(msec)
    if #self.children > 0 then
        if msec ~= nil then
            assert(self.ctx.runq:push(self, msec))
        end

        self.is_await = true
        local op, res = yield()
        if op == OP_AWAIT then
            if msec then
                self.ctx.runq:remove(self)
            end
            return res
        end
        -- timeout
        self.is_await = nil
        assert(op == OP_RUNQ, 'invalid implements')
        assert(msec ~= nil, 'invalid implements')
        return nil, true
    end
end

--- suspend
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return ...
function Callee:suspend(msec)
    if msec ~= nil then
        assert(self.ctx.runq:push(self, msec))
    end

    -- wait until resumed by resume method
    local cid = self.cid
    SUSPENDED[cid] = self
    local op = yield()
    assert(op == OP_RUNQ, 'invalid implements')

    -- resumed by time-out
    if SUSPENDED[cid] then
        assert(msec ~= nil, 'invalid implements')
        self.ctx.runq:remove(self)
        SUSPENDED[cid] = nil
        return false
    end

    -- resumed
    return true, self.argv:clear()
end

--- later
function Callee:later()
    assert(self.ctx.runq:push(self))
    assert(yield() == OP_RUNQ, 'invalid implements')
end

--- read_lock
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Callee:read_lock(fd, msec)
    return self.ctx:read_lock(self, fd, msec)
end

--- read_unlock
--- @param fd integer
--- @return boolean ok
function Callee:read_unlock(fd)
    return self.ctx:read_unlock(self, fd)
end

--- write_lock
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Callee:write_lock(fd, msec)
    return self.ctx:write_lock(self, fd, msec)
end

--- write_unlock
--- @param fd integer
--- @return boolean ok
function Callee:write_unlock(fd)
    return self.ctx:write_unlock(self, fd)
end

--- waitable
--- @param self act.callee
--- @param operators table
--- @param asa string
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
local function waitable(self, operators, asa, fd, msec)
    -- register to runq with msec
    if msec ~= nil then
        assert(self.ctx.runq:push(self, msec))
    end

    -- operation already in progress in another callee
    if operators[fd] then
        if msec then
            self.ctx.runq:remove(self)
        end
        return false, 'operation already in progress'
    end

    -- register io(readable or writable) event as oneshot event
    local event = self.ctx.event
    local ev, err = event[asa](event, self, fd, true)
    if err then
        if msec then
            self.ctx.runq:remove(self)
        end
        return false, err
    end

    -- retain ev and related info
    self.is_cancel = nil
    self.fdev = ev
    operators[fd] = self
    -- wait until event fired
    local op, fdno = yield()
    operators[fd] = nil
    self.fdev = nil
    self.fd = nil

    -- canceled by cancel method
    if self.is_cancel then
        self.is_cancel = nil
        return false
    end
    event:revoke(ev)

    if op == OP_RUNQ then
        assert(msec ~= nil, 'invalid implements')
        self.ctx.runq:remove(self)
        -- timed out
        return false, nil, true
    end

    -- opertion type must be OP_EVENT
    assert(op == OP_EVENT, 'invalid implements')
    assert(fdno == fd, 'invalid implements')
    return true
end

--- wait_readable
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Callee:wait_readable(fd, msec)
    return waitable(self, RWAITS, 'readable', fd, msec)
end

--- wait_writable
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Callee:wait_writable(fd, msec)
    return waitable(self, WWAITS, 'writable', fd, msec)
end

--- sleep
--- @param msec integer
--- @return integer rem
--- @return any err
function Callee:sleep(msec)
    assert(self.ctx.runq:push(self, msec))

    local cid = self.cid
    local deadline = getmsec() + msec
    -- wait until wake-up or resume by resume method
    SUSPENDED[cid] = self
    local op = yield()
    SUSPENDED[cid] = nil
    assert(op == OP_RUNQ)
    local rem = deadline - getmsec()
    return rem > 0 and rem or 0
end

--- sigwait
--- @param msec integer
--- @vararg integer signo
--- @return integer? signo
--- @return any err
--- @return boolean? timeout
function Callee:sigwait(msec, ...)
    -- register to runq with msec
    if msec ~= nil then
        assert(self.ctx.runq:push(self, msec))
    end

    local event = self.ctx.event
    local sigset = new_deque()
    local sigmap = {}
    -- register signal events
    for _, signo in pairs({
        ...,
    }) do
        local ev, err = event:signal(self, signo, true)

        if err then
            if msec then
                self.ctx.runq:remove(self)
            end

            -- revoke signal events
            for _ = 1, #sigset do
                event:revoke(sigset:pop())
            end
            return nil, err
        end

        -- maintain registered event
        sigset:push(ev)
        sigmap[signo] = true
    end

    -- no need to wait signal if empty
    if #sigset == 0 then
        if msec then
            self.ctx.runq:remove(self)
        end
        return nil
    end

    -- wait registered signals
    self.sigset = sigset
    local op, signo = yield()
    self.sigset = nil

    -- revoke signal events
    for _ = 1, #sigset do
        event:revoke(sigset:pop())
    end

    if op == OP_RUNQ then
        -- timed out
        assert(msec ~= nil, 'invalid implements')
        self.ctx.runq:remove(self)
        return nil, nil, true
    end

    assert(op == OP_EVENT and sigmap[signo], 'invalid implements')
    -- got signal event
    return signo
end

--- @type act.callee?
local CURRENT_CALLEE

--- call
function Callee:call(...)
    CURRENT_CALLEE = self
    -- call with passed arguments
    local done, status = self.co(self.args:clear(...)) --- @type boolean,integer
    CURRENT_CALLEE = nil

    if done then
        self:dispose(status == OK, status)
    elseif self.is_exit then
        self:dispose(true, OK)
    end
end

--- attach
--- @param callee act.callee
local function attach(callee)
    if not CURRENT_CALLEE then
        assert(not callee.is_atexit, 'root callee cannot be run at exit')
        return
    end

    -- set as a child of the current callee
    if not callee.is_atexit then
        callee.parent = CURRENT_CALLEE
        callee.ref = CURRENT_CALLEE.children:push(callee)
        return
    end

    -- set as a child of the parent of the current callee
    local parent = CURRENT_CALLEE.parent
    if parent then
        CURRENT_CALLEE.ref:remove()
        callee.parent = parent
        callee.ref = parent.children:push(callee)
    end

    -- set as a parent of the current callee
    CURRENT_CALLEE.parent = callee
    CURRENT_CALLEE.ref = callee.children:push(CURRENT_CALLEE)
end

--- renew
--- @param ctx act.context
--- @param is_atexit boolean
--- @param fn function
--- @vararg any
function Callee:renew(ctx, is_atexit, fn, ...)
    self.ctx = ctx
    self.is_atexit = is_atexit
    self.args:set(...)
    self.co:reset(fn)
    self.cid = getnsec()
    -- attach to the current callee
    attach(self)
end

--- init
--- @param ctx act.context
--- @param is_atexit boolean
--- @param fn function
--- @param ... any
--- @return act.callee callee
function Callee:init(ctx, is_atexit, fn, ...)
    self.ctx = ctx
    self.is_atexit = is_atexit
    self.co = new_coro(fn)
    self.args = new_stack(...)
    self.argv = new_stack()
    self.children = new_deque()
    self.cid = getnsec()
    -- attach to the current callee
    attach(self)
    return self
end

--- acquire
--- @return act.callee? callee
local function acquire()
    return CURRENT_CALLEE
end

Callee = require('metamodule').new(Callee)

--- new create new act.callee
--- @param ctx act.context
--- @param is_atexit boolean
--- @param fn function
--- @param ... any
--- @return act.callee
local function new(ctx, is_atexit, fn, ...)
    local callee = ctx:pool_get()
    if callee then
        -- use pooled callee
        callee:renew(ctx, is_atexit, fn, ...)
        return callee
    end

    return Callee(ctx, is_atexit, fn, ...)
end

return {
    new = new,
    acquire = acquire,
    unwait = unwait,
    unwait_readable = unwait_readable,
    unwait_writable = unwait_writable,
    resume = resume,
}

