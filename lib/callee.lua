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
local pairs = pairs
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

--- @class act.callee
--- @field ctx act.context
--- @field cid integer
--- @field co reco
--- @field children deque
--- @field yieldq deque
--- @field awaitq deque
--- @field awaitq_max integer
--- @field op? integer
--- @field parent? act.callee
--- @field is_await? boolean
--- @field is_cancel? boolean
--- @field is_atexit? boolean
--- @field is_exit? boolean
--- @field fdev? poller.event
--- @field sigset? deque
local Callee = {}

--- exit
--- @vararg any
function Callee:exit(...)
    self.is_exit = true
    yield(...)
    -- normally unreachable
    error('invalid implements')
end

--- later
function Callee:later()
    self.ctx:pushq(self)
    assert(yield() == nil, 'invalid implements')
    assert(self.op == OP_RUNQ, 'invalid implements')
end

--- @type table<integer, act.callee>
local YIELDED = setmetatable({}, {
    __mode = 'v',
})

--- consume_yieldq
--- @return table stat
function Callee:consume_yieldq()
    local stat = self.yieldq:shift()

    if stat then
        -- resume yielded child
        local callee = assert(YIELDED[stat.cid], 'invalid implements')
        YIELDED[stat.cid] = nil
        self.ctx:removeq(callee)
        self.ctx:pushq(callee)
        return stat
    end
end

--- yield
--- @param msec? integer
--- @param ... any
--- @return boolean ok
function Callee:yield(msec, ...)
    -- check parent is exists except atexit callee
    local parent = self.parent
    while parent and parent.is_atexit do
        parent = parent.parent
    end
    assert(parent, 'parent is not exists')

    -- resume parent via runq if parent is await
    if parent.is_await then
        -- NOTE: parent must be pushed to runq before push a child to runq
        parent.is_await = nil
        parent.ctx:removeq(parent)
        parent.ctx:pushq(parent)
    end

    if msec ~= nil then
        self.ctx:pushq(self, msec)
    end

    local elm = parent.yieldq:push({
        cid = self.cid,
        status = 'yield',
        result = {
            ...,
        },
    })

    YIELDED[self.cid] = self
    assert(yield() == nil, 'invalid implements')
    assert(self.op == OP_RUNQ, 'invalid implements')
    -- timeout
    if YIELDED[self.cid] then
        YIELDED[self.cid] = nil
        elm:remove()
        assert(msec ~= nil, 'invalid implements')
        return false
    end

    if msec then
        self.ctx:removeq(self)
    end

    return true
end

local HUGE = math.huge

--- awaitq_size get or set the maximum await queueing size.
--- @param qsize? integer 0 not queueing, >0 queueing size, <0 unlimited
--- @return integer qlen
function Callee:awaitq_size(qsize)
    if qsize ~= nil then
        local qlen = #self.awaitq

        if qsize == 0 then
            -- remove all child stats
            if qlen > 0 then
                self.awaitq = new_deque()
            end
        elseif qsize < 0 then
            -- unlimited
            qsize = HUGE
        elseif qlen > qsize then
            -- remove exceeded child stats
            for _ = 1, qlen - qsize do
                self.awaitq:shift()
            end
        end
        self.awaitq_max = qsize
    end

    return self.awaitq_max == HUGE and -1 or self.awaitq_max
end

--- await until the child thread to exit while the specified number of seconds.
--- @param msec? integer
--- @return table? res
--- @return boolean? timeout
function Callee:await(msec)
    -- consume awaitq
    local stat = self.awaitq:shift()

    if not stat then
        if #self.children == 0 then
            -- no child
            return
        end

        stat = self:consume_yieldq()
        if stat then
            return stat
        end

        if msec ~= nil then
            self.ctx:pushq(self, msec)
        end

        self.is_await = true
        assert(yield() == nil, 'invalid implements')
        assert(self.op == OP_RUNQ, 'invalid implements')

        -- timeout
        if self.is_await then
            self.is_await = nil
            assert(msec ~= nil, 'invalid implements')
            return nil, true
        end

        -- consume awaitq
        stat = self.awaitq:shift()
        if not stat then
            -- consume yieldq
            stat = assert(self:consume_yieldq(), 'invalid implements')
        end
    end

    return stat
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

--- sigwait
--- @param msec integer
--- @vararg integer signo
--- @return integer? signo
--- @return any err
--- @return boolean? timeout
function Callee:sigwait(msec, ...)
    -- register to runq with msec
    if msec ~= nil then
        self.ctx:pushq(self, msec)
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
                self.ctx:removeq(self)
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
            self.ctx:removeq(self)
        end
        return nil
    end

    -- wait registered signals
    self.sigset = sigset
    local signo = yield()
    self.sigset = nil

    -- revoke signal events
    for _ = 1, #sigset do
        event:revoke(sigset:pop())
    end

    -- timeout
    if self.op == OP_RUNQ then
        assert(msec ~= nil, 'invalid implements')
        return nil, nil, true
    end

    if msec then
        self.ctx:removeq(self)
    end

    assert(self.op == OP_EVENT and sigmap[signo], 'invalid implements')
    -- got signal event
    return signo
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
        self.ctx:pushq(self, msec)
    end

    -- operation already in progress in another callee
    if operators[fd] then
        if msec then
            self.ctx:removeq(self)
        end
        return false, 'operation already in progress'
    end

    -- register io(readable or writable) event as oneshot event
    local event = self.ctx.event
    local ev, err = event[asa](event, self, fd, true)
    if err then
        if msec then
            self.ctx:removeq(self)
        end
        return false, err
    end

    -- retain ev and related info
    self.is_cancel = nil
    self.fdev = ev
    operators[fd] = self
    -- wait until event fired
    local fdno = yield()
    operators[fd] = nil
    self.fdev = nil
    self.fd = nil

    -- canceled by cancel method
    if self.is_cancel then
        self.is_cancel = nil
        return false
    end
    event:revoke(ev)

    -- timed out
    if self.op == OP_RUNQ then
        assert(msec ~= nil, 'invalid implements')
        return false, nil, true
    end

    if msec then
        self.ctx:removeq(self)
    end

    -- opertion type must be OP_EVENT
    assert(self.op == OP_EVENT, 'invalid implements')
    assert(fdno == fd, 'invalid implements')
    return true
end

--- static variables
local RWAITS = {}
local WWAITS = {}

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
        callee.ctx:removeq(callee)
        callee.ctx:pushq(callee)
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

local SUSPENDED = setmetatable({}, {
    __mode = 'v',
})

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
        callee.ctx:removeq(callee)
        callee.ctx:pushq(callee)

        return true
    end

    return false
end

--- suspend
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return ...
function Callee:suspend(msec)
    if msec ~= nil then
        self.ctx:pushq(self, msec)
    end

    -- wait until resumed by resume method
    local cid = self.cid
    SUSPENDED[cid] = self
    assert(yield() == nil, 'invalid implements')
    assert(self.op == OP_RUNQ, 'invalid implements')

    -- timeout
    if SUSPENDED[cid] then
        SUSPENDED[cid] = nil
        assert(msec ~= nil, 'invalid implements')
        return false
    end

    -- resumed
    return true, self.argv:clear()
end

--- sleep
--- @param msec integer
--- @return integer rem
--- @return any err
function Callee:sleep(msec)
    self.ctx:pushq(self, msec)

    local cid = self.cid
    local deadline = getmsec() + msec
    -- wait until wake-up or resume by resume method
    SUSPENDED[cid] = self
    assert(yield() == nil, 'invalid implements')
    assert(self.op == OP_RUNQ)

    -- timeout
    if SUSPENDED[cid] then
        SUSPENDED[cid] = nil
        assert(msec ~= nil, 'invalid implements')
    end

    local rem = deadline - getmsec()
    return rem > 0 and rem or 0
end

local coro = require('act.coro')
local OK = coro.OK
local YIELD = coro.YIELD
local ERRRUN = coro.ERRRUN
local ERRSYNTAX = coro.ERRSYNTAX
local ERRMEM = coro.ERRMEM
local ERRERR = coro.ERRERR
local STATUS_TEXT = {
    [OK] = 'ok',
    [YIELD] = 'yield',
    [ERRRUN] = 'errrun',
    [ERRSYNTAX] = 'errsyntax',
    [ERRMEM] = 'errmem',
    [ERRERR] = 'errerr',
}

--- dispose
--- @param status integer
function Callee:dispose(status)
    local status_text = assert(STATUS_TEXT[status], 'unknown status code')

    -- remove from runq
    self.ctx:removeq(self)
    -- release locks
    self.ctx:release_locks(self)

    -- remove state properties
    self.is_exit = nil
    YIELDED[self.cid] = nil
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

    -- dispose awaitq and yieldq
    self.awaitq = nil
    self.yieldq = nil

    -- dispose child coroutines
    for _ = 1, #self.children do
        local child = self.children:pop()
        -- release references
        child.parent = nil
        child.ref = nil
        -- call dispose method
        child:dispose(OK)
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

        local stat = {
            cid = self.cid,
            status = status_text,
        }
        if status == OK then
            stat.result = {
                self.co:results(),
            }
        else
            stat.error = self.co:results()
        end

        if parent.is_atexit then
            -- call atexit callee via runq
            parent.is_atexit = nil
            parent.args:insert(1, stat)
            parent.ctx:removeq(parent)
            parent.ctx:pushq(parent)
        elseif parent.is_await then
            parent.awaitq:push(stat)
            -- resume await callee via runq
            parent.is_await = nil
            parent.ctx:removeq(parent)
            parent.ctx:pushq(parent)
        elseif parent.awaitq_max > #parent.awaitq then
            parent.awaitq:push(stat)
        end
    elseif status ~= OK then
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

--- @type act.callee?
local CURRENT_CALLEE

--- call
--- @param op integer
--- @param ... any
function Callee:call(op, ...)
    CURRENT_CALLEE = self
    -- call with passed arguments
    self.op = op
    local done, status = self.co(self.args:clear(...)) --- @type boolean,integer
    self.op = nil
    CURRENT_CALLEE = nil

    if done then
        self:dispose(status)
    elseif self.is_exit then
        self:dispose(OK)
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
    self.cid = getnsec()
    self.is_atexit = is_atexit
    self.co:reset(fn)
    self.args:set(...)
    self.awaitq = new_deque()
    self.awaitq_max = 0
    self.yieldq = new_deque()
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
    self.cid = getnsec()
    self.is_atexit = is_atexit
    self.co = new_coro(fn)
    self.args = new_stack(...)
    self.argv = new_stack()
    self.children = new_deque()
    self.awaitq = new_deque()
    self.awaitq_max = 0
    self.yieldq = new_deque()
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

