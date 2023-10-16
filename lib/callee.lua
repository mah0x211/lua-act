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
local select = select
local EALREADY = require('errno').EALREADY
local ECANCELED = require('errno').ECANCELED
local gettime = require('time.clock').gettime
local new_coro = require('act.coro').new
local new_stack = require('act.stack')
local new_deque = require('act.deque')
local aux = require('act.aux')
local is_uint = aux.is_uint
local concat = aux.concat
-- constants
local OP_EVENT = aux.OP_EVENT
local OP_RUNQ = aux.OP_RUNQ

--- @class act.callee
--- @field ctx act.context
--- @field cid integer
--- @field co reco
--- @field children act.deque
--- @field yieldq act.deque
--- @field awaitq act.deque
--- @field awaitq_max integer
--- @field op? integer
--- @field parent? act.callee
--- @field is_await? boolean
--- @field is_cancel? boolean
--- @field is_atexit? boolean
--- @field is_exit? boolean
--- @field ioevents? table<integer, act.event.info>
--- @field sigset? act.deque
local Callee = {}

--- exit
--- @param ... any
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
--- @return table? stat
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
--- @param sec? number
--- @param ... any
--- @return boolean ok
function Callee:yield(sec, ...)
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

    if sec ~= nil then
        self.ctx:pushq(self, sec)
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
        assert(sec ~= nil, 'invalid implements')
        return false
    end

    if sec then
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
--- @param sec? number
--- @return table? res
--- @return boolean? timeout
function Callee:await(sec)
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

        if sec ~= nil then
            self.ctx:pushq(self, sec)
        end

        self.is_await = true
        assert(yield() == nil, 'invalid implements')
        assert(self.op == OP_RUNQ, 'invalid implements')

        -- timeout
        if self.is_await then
            self.is_await = nil
            assert(sec ~= nil, 'invalid implements')
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
--- @param sec number
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Callee:read_lock(fd, sec)
    return self.ctx:read_lock(self, fd, sec)
end

--- read_unlock
--- @param fd integer
--- @return boolean ok
function Callee:read_unlock(fd)
    return self.ctx:read_unlock(self, fd)
end

--- write_lock
--- @param fd integer
--- @param sec number
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Callee:write_lock(fd, sec)
    return self.ctx:write_lock(self, fd, sec)
end

--- write_unlock
--- @param fd integer
--- @return boolean ok
function Callee:write_unlock(fd)
    return self.ctx:write_unlock(self, fd)
end

--- sigwait
--- @param sec number
--- @param ... integer signal numbers
--- @return integer? signo
--- @return any err
--- @return boolean? timeout
function Callee:sigwait(sec, ...)
    -- register to runq with sec
    if sec ~= nil then
        self.ctx:pushq(self, sec)
    end

    local event = self.ctx.event
    local sigset = new_deque()
    local sigmap = {}
    -- register signal events
    for _, signo in pairs({
        ...,
    }) do
        local evinfo, err = event:register(self, 'signal', signo, 'oneshot')

        if err then
            if sec then
                self.ctx:removeq(self)
            end

            -- revoke signal events
            for _ = 1, #sigset do
                evinfo = sigset:pop()
                event:revoke(evinfo.asa, evinfo.val)
            end
            return nil, err
        end

        -- maintain registered event
        sigset:push(evinfo)
        sigmap[signo] = true
    end

    -- no need to wait signal if empty
    if #sigset == 0 then
        if sec then
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
        local evinfo = sigset:pop()
        event:revoke(evinfo.asa, evinfo.val)
    end

    -- timeout
    if self.op == OP_RUNQ then
        assert(sec ~= nil, 'invalid implements')
        return nil, nil, true
    end

    if sec then
        self.ctx:removeq(self)
    end

    assert(self.op == OP_EVENT and sigmap[signo], 'invalid implements')
    -- got signal event
    return signo
end

--- iowait restrict the fd from being used in multiple coroutines
--- @class iowait
--- @field readable table<integer, act.callee>
--- @field writable table<integer, act.callee>
local IOWAIT = {
    readable = {},
    writable = {},
}

--- waitable
--- @param self act.callee
--- @param asa string
--- @param fd integer
--- @param sec number
--- @param ... integer additional fds
--- @return integer? fd
--- @return any err
--- @return boolean? timeout
local function waitable(self, asa, fd, sec, ...)
    local event = self.ctx.event
    local nfd = select('#', ...) + 1
    local fds = {
        fd,
        ...,
    }
    local revoke_events = function(n)
        for i = 1, n or nfd do
            fd = fds[i]
            self.ioevents[fd] = nil
            IOWAIT[asa][fd] = nil
            event:revoke(asa, fd)
        end
    end
    local revoke_events_if_cache_not_enabled = function(n)
        for i = 1, n or nfd do
            fd = fds[i]
            self.ioevents[fd] = nil
            IOWAIT[asa][fd] = nil
            event:revoke_if_cache_not_enabled(asa, fd)
        end
    end

    for i = 1, nfd do
        fd = fds[i]
        if not is_uint(fd) then
            revoke_events_if_cache_not_enabled(i - 1)
            error('invalid fd#' .. i .. ' must be unsigned integer', 2)
        end

        if IOWAIT[asa][fd] then
            -- other callee is already waiting for the fd
            revoke_events_if_cache_not_enabled(i - 1)
            return nil, EALREADY:new()
        end

        local evinfo, err, is_ready = event:register(self, asa, fd, 'edge')
        if is_ready then
            -- fd is ready to read or write
            revoke_events_if_cache_not_enabled(i - 1)
            return fd
        elseif not evinfo then
            -- failed to create io-event
            revoke_events_if_cache_not_enabled(i - 1)
            return nil, err
        end

        -- cache act.event.info
        self.ioevents[fd] = evinfo
        IOWAIT[asa][fd] = self
    end

    -- register to runq with sec
    if sec ~= nil then
        self.ctx:pushq(self, sec)
    end

    -- clear cancel flag
    self.is_cancel = nil

    -- wait event until event fired, timeout or canceled
    local fdno = yield()

    -- canceled by unwaitfd method
    if self.is_cancel then
        revoke_events()
        self.is_cancel = nil
        return nil, ECANCELED:new()
    end

    -- timed out
    if self.op == OP_RUNQ then
        revoke_events()
        assert(sec ~= nil, 'invalid implements')
        return nil, nil, true
    end

    -- event occurred
    if sec then
        self.ctx:removeq(self)
    end

    -- opertion type must be OP_EVENT and fdno must be fd
    if self.op == OP_EVENT and self.ioevents[fdno] then
        revoke_events_if_cache_not_enabled()
        return fdno
    end
    revoke_events()
    error('invalid implements')
end

--- wait_readable
--- @param fd integer
--- @param sec number
--- @param ... integer additional fds
--- @return integer fd
--- @return any err
--- @return boolean? timeout
function Callee:wait_readable(fd, sec, ...)
    return waitable(self, 'readable', fd, sec, ...)
end

--- wait_writable
--- @param fd integer
--- @param sec number
--- @param ... integer additional fds
--- @return integer? fd
--- @return any err
--- @return boolean? timeout
function Callee:wait_writable(fd, sec, ...)
    return waitable(self, 'writable', fd, sec, ...)
end

--- unwaitfd
--- @param ctx act.context
--- @param asa string
--- @param fd integer
local function unwaitfd(ctx, asa, fd)
    local callee = IOWAIT[asa][fd]

    if callee then
        callee.is_cancel = true
        -- re-queue without timeout
        callee.ctx:removeq(callee)
        callee.ctx:pushq(callee)
        return true
    end

    -- revoke cached event
    return ctx.event:revoke(asa, fd)
end

--- unwait_readable
--- @param ctx act.context
--- @param fd integer
--- @return boolean ok
local function unwait_readable(ctx, fd)
    return unwaitfd(ctx, 'readable', fd)
end

--- unwait_writable
--- @param ctx act.context
--- @param fd integer
--- @return boolean ok
local function unwait_writable(ctx, fd)
    return unwaitfd(ctx, 'writable', fd)
end

--- unwait
--- @param ctx act.context
--- @param fd integer
--- @return boolean ok
local function unwait(ctx, fd)
    local ok1 = unwaitfd(ctx, 'readable', fd)
    local ok2 = unwaitfd(ctx, 'writable', fd)
    return ok1 and ok2
end

--- @type table<any, act.callee>
local SUSPENDED = setmetatable({}, {
    __mode = 'v',
})

--- resume
--- @param cid string
--- @param ... any
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
--- @param sec number
--- @return boolean ok
--- @return string? err
--- @return ...
function Callee:suspend(sec)
    if sec ~= nil then
        self.ctx:pushq(self, sec)
    end

    -- wait until resumed by resume method
    local cid = self.cid
    SUSPENDED[cid] = self
    assert(yield() == nil, 'invalid implements')
    assert(self.op == OP_RUNQ, 'invalid implements')

    -- timeout
    if SUSPENDED[cid] then
        SUSPENDED[cid] = nil
        assert(sec ~= nil, 'invalid implements')
        return false
    end

    -- resumed
    return true, self.argv:clear()
end

--- sleep
--- @param sec number
--- @return number rem
--- @return any err
function Callee:sleep(sec)
    self.ctx:pushq(self, sec)

    local cid = self.cid
    local deadline = gettime() + sec
    -- wait until wake-up or resume by resume method
    SUSPENDED[cid] = self
    assert(yield() == nil, 'invalid implements')
    assert(self.op == OP_RUNQ)

    -- timeout
    if SUSPENDED[cid] then
        SUSPENDED[cid] = nil
        assert(sec ~= nil, 'invalid implements')
    end

    local rem = deadline - gettime()
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
    -- delete reference to active callee
    self.ctx:del_active_callees(self)

    local status_text = assert(STATUS_TEXT[status], 'unknown status code')
    local cid = self.cid
    -- remove cid
    self.ctx:cid_free(cid)
    -- remove from runq
    self.ctx:removeq(self)
    -- release locks
    self.ctx:release_locks(self)

    -- remove state properties
    self.is_exit = nil
    YIELDED[cid] = nil
    SUSPENDED[cid] = nil

    -- revoke all events currently in use
    local event = self.ctx.event
    -- revoke self-managed io events
    for _, evinfo in pairs(self.ioevents) do
        IOWAIT[evinfo.asa][evinfo.val] = nil
        event:revoke(evinfo.asa, evinfo.val)
    end
    self.ioevents = nil

    -- revoke signal events
    local sigset = self.sigset
    if sigset then
        self.sigset = nil
        for _ = 1, #sigset do
            local evinfo = sigset:pop()
            event:revoke(evinfo.asa, evinfo.val)
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
            cid = cid,
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
--- @param ... any
function Callee:renew(ctx, is_atexit, fn, ...)
    self.ctx = ctx
    self.cid = ctx:cid_alloc()
    self.is_atexit = is_atexit
    self.co:reset(fn)
    self.args:set(...)
    self.awaitq = new_deque()
    self.awaitq_max = 0
    self.yieldq = new_deque()
    self.ioevents = {}
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
    self.cid = ctx:cid_alloc()
    self.is_atexit = is_atexit
    self.co = new_coro(fn)
    self.args = new_stack(...)
    self.argv = new_stack()
    self.children = new_deque()
    self.awaitq = new_deque()
    self.awaitq_max = 0
    self.yieldq = new_deque()
    self.ioevents = {}
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
    else
        callee = Callee(ctx, is_atexit, fn, ...)
    end

    -- add reference to active callee
    ctx:add_active_callees(callee)
    if not is_atexit then
        -- push to runq if not atexit
        ctx:pushq(callee)
    end

    return callee
end

return {
    new = new,
    acquire = acquire,
    resume = resume,
    unwait = unwait,
    unwait_readable = unwait_readable,
    unwait_writable = unwait_writable,
}

