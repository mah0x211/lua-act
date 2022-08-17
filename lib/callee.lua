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
-- lib/callee.lua
-- lua-act
-- Created by Masatoshi Teruya on 16/12/26.
--
--- file scope variables
local yield = coroutine.yield
local setmetatable = setmetatable
local new_argv = require('argv').new
local new_deque = require('deque').new
local reco = require('reco')
local new_reco = reco.new
local hrtimer = require('act.hrtimer')
local getnsec = hrtimer.getnsec
local getmsec = hrtimer.getmsec
local aux = require('act.aux')
local concat = aux.concat
-- constants
local OP_EVENT = aux.OP_EVENT
local OP_RUNQ = aux.OP_RUNQ
local OP_AWAIT = aux.OP_AWAIT
local OK = reco.OK
-- local CO_YIELD = reco.YIELD
-- local ERRRUN = reco.ERRRUN
-- local ERRSYNTAX = reco.ERRSYNTAX
-- local ERRMEM = reco.ERRMEM
-- local ERRERR = reco.ERRERR
--- static variables
local SUSPENDED = setmetatable({}, {
    __mode = 'v',
})
local RLOCKS = {}
local WLOCKS = {}
local RWAITS = {}
local WWAITS = {}
local RWWAITS = {
    readable = RWAITS,
    writable = WWAITS,
}

--- @type act.pool
local POOL = require('act.pool').new()

--- @type act.callee
local CURRENT_CALLEE

--- acquire
--- @return act.callee callee
local function acquire()
    return CURRENT_CALLEE
end

--- unwaitfd
--- @param operators table<integer, act.callee>
--- @param fd integer
local function unwaitfd(operators, fd)
    local callee = operators[fd]

    -- found
    if callee then
        operators[fd] = nil
        callee.act.runq:remove(callee)
        callee.act.event:revoke(callee.ev)
        -- reset event properties
        callee.ev = nil
        callee.evfd = -1
        -- currently in-use
        if callee.evuse then
            callee.evuse = false
            callee.evasa = 'unwaitfd'
            -- requeue without timeout
            assert(callee.act.runq:push(callee))
        else
            callee.evasa = ''
        end
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
        callee.argv:set(0, ...)
        -- resume via runq
        callee.act.runq:remove(callee)
        callee.act.runq:push(callee)

        return true
    end

    return false
end

--- @class act.callee
local Callee = {}

--- revoke
function Callee:revoke()
    local event = self.act.event

    -- revoke signal events
    if self.sigset then
        local sigset = self.sigset

        for _ = 1, #sigset do
            event:revoke(sigset:pop())
        end
        self.sigset = nil
    end

    -- revoke io event
    if self.evfd ~= -1 then
        local ev = self.ev

        RWWAITS[self.evasa][self.evfd] = nil
        self.ev = nil
        self.evfd = -1
        self.evasa = ''
        self.evuse = false
        event:revoke(ev)
    end
end

--- call
function Callee:call(...)
    CURRENT_CALLEE = self
    -- call with passed arguments
    local done, status = self.co(self.args:select(#self.args, ...))
    CURRENT_CALLEE = nil

    if done then
        self:dispose(status == OK, status)
    elseif self.term then
        self:dispose(true, OK)
    end
end

--- dispose
--- @param ok boolean
--- @param status integer
function Callee:dispose(ok, status)
    local runq = self.act.runq

    runq:remove(self)
    -- remove state properties
    self.term = nil
    SUSPENDED[self.cid] = nil

    -- read_unlock
    for fd in pairs(self.rlock) do
        self:read_unlock(fd)
    end
    self.rlock = {}

    -- write_unlock
    for fd in pairs(self.wlock) do
        self:write_unlock(fd)
    end
    self.wlock = {}

    -- revoke all events currently in use
    self:revoke()

    -- dispose child coroutines
    for _ = 1, #self.node do
        local child = self.node:pop()

        -- remove from runq
        runq:remove(child)
        -- release references
        child.parent = nil
        child.ref = nil
        -- call dispose method
        child:dispose(true)
    end

    -- call parent node
    if self.parent then
        local root = self.parent
        local ref = self.ref

        -- release references
        self.parent = nil
        self.ref = nil
        -- detouch from from root node
        root.node:remove(ref)
        if root.wait then
            -- root node waiting for child results
            root.wait = nil
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
            root:call(OP_AWAIT, stat)
        elseif root.atexit then
            -- call atexit node
            root.atexit = nil
            root:call(ok, status, self.co:results())
        elseif not ok then
            error(concat({
                self.co:results(),
            }, '\n'))
        end
    elseif not ok then
        error(concat({
            self.co:results(),
        }, '\n'))
    end

    -- add to pool for reuse
    POOL:push(self)
end

--- exit
--- @vararg any
function Callee:exit(...)
    self.term = true
    yield(...)

    -- normally unreachable
    error('invalid implements')
end

--- await until the child thread to exit while the specified number of seconds.
--- @param msec integer
--- @return table res
--- @return string err
--- @return boolean timeout
function Callee:await(msec)
    if #self.node > 0 then
        if msec ~= nil then
            -- register to resume after msec seconds
            local ok, err = self.act.runq:push(self, msec)
            if not ok then
                return nil, err
            end
        end

        -- revoke all events currently in use
        self:revoke()
        self.wait = true
        local op, res = yield()
        if op == OP_AWAIT then
            return res
        elseif op == OP_RUNQ then
            return nil, nil, true
        end

        -- normally unreachable
        error('invalid implements')
    end
end

--- suspend
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return ...
--- @return boolean timeout
function Callee:suspend(msec)
    if msec ~= nil then
        -- suspend until reached to msec
        local ok, err = self.act.runq:push(self, msec)
        if not ok then
            return false, err
        end
    end

    -- revoke all events currently in use
    self:revoke()
    -- wait until resumed by resume method
    local cid = self.cid
    SUSPENDED[cid] = self
    if yield() == OP_RUNQ then
        -- resumed by time-out if self exists in suspend list
        if SUSPENDED[cid] then
            SUSPENDED[cid] = nil
            self.act.runq:remove(self)
            return false, nil, true
        end

        -- resumed
        return true, self.argv:select()
    end

    -- normally unreachable
    error('invalid implements')
end

--- later
--- @return boolean ok
--- @return string? err
function Callee:later()
    local ok, err = self.act.runq:push(self)
    if not ok then
        return false, err
    end

    -- revoke all events currently in use
    self:revoke()
    if yield() == OP_RUNQ then
        return true
    end

    -- normally unreachable
    error('invalid implements')
end

--- rwunlock
--- @param callee act.callee
--- @param locks table
--- @param asa string
--- @param fd integer
local function rwunlock(callee, locks, asa, fd)
    local waitq = callee[asa][fd]

    if waitq then
        callee[asa][fd] = nil

        for i = 1, #waitq do
            local cid = waitq[i]

            callee = SUSPENDED[cid]
            if callee then
                waitq[i] = false
                SUSPENDED[cid] = nil
                -- resume suspended callee via runq
                local runq = callee.act.runq
                runq:remove(callee)
                runq:push(callee)
                return
            end
        end
        -- waitq has been consumed
        locks[fd] = nil
    end
end

--- read_unlock
--- @param fd integer
function Callee:read_unlock(fd)
    rwunlock(self, RLOCKS, 'rlock', fd)
end

--- write_unlock
--- @param fd integer
function Callee:write_unlock(fd)
    rwunlock(self, WLOCKS, 'wlock', fd)
end

--- rwlock
--- @param callee act.callee
--- @param locks table
--- @param asa string
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function rwlock(callee, locks, asa, fd, msec)
    if not callee[asa][fd] then
        local waitq = locks[fd]

        -- other callee is waiting
        if waitq then
            local idx = #waitq + 1

            waitq[idx] = callee.cid
            local ok, err, timeout = callee:suspend(msec)
            waitq[idx] = false
            if ok then
                -- other callee unlocked
                callee[asa][fd] = waitq
            end

            return ok, err, timeout
        end

        -- create read or write lock wait queue
        waitq = {}
        locks[fd] = waitq
        callee[asa][fd] = waitq
    end

    return true
end

--- read_lock
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
function Callee:read_lock(fd, msec)
    return rwlock(self, RLOCKS, 'rlock', fd, msec)
end

--- write_lock
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
function Callee:write_lock(fd, msec)
    return rwlock(self, WLOCKS, 'wlock', fd, msec)
end

--- waitable
--- @param self act.callee
--- @param operators table
--- @param asa string
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function waitable(self, operators, asa, fd, msec)
    local event = self.act.event

    -- fd is not watching yet
    if self.evfd ~= fd or self.evasa ~= asa then
        -- revoke retained event
        self:revoke()

        local callee = operators[fd]
        -- another callee has an 'asa' event of fd
        if callee then
            -- currently in-use
            if callee.evuse then
                return false, 'operation already in progress'
            end

            -- retain ev and related info
            self.ev = callee.ev
            self.evfd = fd
            self.evasa = asa
            operators[fd] = self
            self.ev:context(self)

            -- remove ev and related info
            callee.ev = nil
            callee.evfd = -1
            callee.evasa = ''
        end

        -- register io(readable or writable) event
        if not self.ev then
            local ev, err = event[asa](event, self, fd)

            if err then
                return false, err
            end

            -- retain ev and related info
            self.ev = ev
            self.evfd = fd
            self.evasa = asa
            operators[fd] = self
        end
    end

    -- register to runq
    if msec then
        local ok, err = self.act.runq:push(self, msec)

        if not ok then
            local ev = self.ev
            -- revoke io event
            self.ev = nil
            self.evfd = -1
            self.evasa = ''
            operators[fd] = nil
            event:revoke(ev)
            return false, err
        end
    end

    self.evuse = true
    -- wait until event fired
    local op, fdno, disabled = yield()
    self.evuse = false

    -- got io event
    if op == OP_EVENT then
        if fdno == fd then
            -- remove from runq
            if msec then
                self.act.runq:remove(self)
            end

            if disabled then
                self:revoke()
            end

            return true
        end
    elseif op == OP_RUNQ then
        if self.evasa == 'unwaitfd' then
            -- revoked by unwaitfd
            self.evasa = ''
            return false
        elseif msec then
            -- timed out
            return false, nil, true
        end
    end

    -- remove from runq
    if msec then
        self.act.runq:remove(self)
    end

    -- revoke event
    self:revoke()

    -- normally unreachable
    error('invalid implements')
end

--- wait_readable
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
function Callee:wait_readable(fd, msec)
    return waitable(self, RWAITS, 'readable', fd, msec)
end

--- wait_writable
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
function Callee:wait_writable(fd, msec)
    return waitable(self, WWAITS, 'writable', fd, msec)
end

--- sleep
--- @param msec integer
--- @return integer rem
--- @return string? err
function Callee:sleep(msec)
    local ok, err = self.act.runq:push(self, msec)
    if not ok then
        return false, err
    end

    -- revoke all events currently in use
    self:revoke()
    local deadline = getmsec() + msec
    if yield() == OP_RUNQ then
        local rem = deadline - getmsec()
        return rem > 0 and rem or 0
    end

    -- normally unreachable
    error('invalid implements')
end

--- sigwait
--- @param msec integer
--- @vararg integer signo
--- @return integer signo
--- @return string? err
--- @return boolean? timeout
function Callee:sigwait(msec, ...)
    -- register to runq with msec
    if msec then
        local ok, err = self.act.runq:push(self, msec)
        if not ok then
            return nil, err
        end
    end

    local event = self.act.event
    local sigset = new_deque()
    local sigmap = {}
    -- register signal events
    for _, signo in pairs({
        ...,
    }) do
        local ev, err = event:signal(self, signo, true)

        if err then
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
        return nil
    end

    -- revoke all events currently in use
    self:revoke()
    -- wait registered signals
    self.sigset = sigset
    local op, signo = yield()
    self.sigset = nil
    -- remove from runq if registered
    if msec then
        self.act.runq:remove(self)
    end

    -- revoke signal events
    for _ = 1, #sigset do
        event:revoke(sigset:pop())
    end

    if op == OP_EVENT and sigmap[signo] then
        -- got signal event
        return signo
    elseif op == OP_RUNQ then
        -- timed out
        return nil, nil, true
    end

    -- normally unreachable
    error('invalid implements')
end

--- attach2caller
--- @param caller act.callee
--- @param callee act.callee
--- @param atexit boolean
local function attach2caller(caller, callee, atexit)
    if caller then
        -- set as a child: caller -> callee
        if not atexit then
            callee.parent = caller
            callee.ref = caller.node:push(callee)
            return
        end

        -- atexit node always await child node
        callee.atexit = true
        -- set as a parent of caller: callee -> caller
        local parent = caller.parent
        if not parent then
            caller.parent = callee
            caller.ref = callee.node:push(caller)
            return
        end

        -- change parent of caller: caller_parent -> callee -> caller
        parent.node:remove(caller.ref)
        caller.parent = callee
        caller.ref = callee.node:push(caller)
        callee.parent = parent
        callee.ref = parent.node:push(callee)

    elseif atexit then
        error('root callee cannot be run at exit')
    end
end

--- renew
--- @param act act.context
--- @param atexit boolean
--- @param fn function
--- @vararg any
function Callee:renew(act, atexit, fn, ...)
    self.act = act
    self.atexit = atexit
    self.args:set(0, ...)
    self.co:reset(fn)
    self.cid = getnsec()
    -- set relationship
    attach2caller(CURRENT_CALLEE, self, atexit)
end

--- init
--- @param act act.context
--- @param atexit boolean
--- @param fn function
--- @vararg any
--- @return act.callee callee
function Callee:init(act, atexit, fn, ...)
    local args = new_argv()
    args:set(0, ...)

    self.act = act
    self.atexit = atexit
    self.co = new_reco(fn)
    self.args = args
    self.argv = new_argv()
    self.node = new_deque()
    self.rlock = {}
    self.wlock = {}
    -- ev = [event object]
    self.evfd = -1
    self.evasa = '' -- '', 'readable' or 'writable'
    self.evuse = false -- true or false

    -- set callee-id
    self.cid = getnsec()
    -- set relationship
    attach2caller(CURRENT_CALLEE, self, atexit)

    return self
end

Callee = require('metamodule').new(Callee)

--- new create new act.callee
--- @param ... any
local function new(...)
    local callee = POOL:pop()

    -- use pooled callee
    if callee then
        callee:renew(...)
        return callee
    end

    return Callee(...)
end

return {
    new = new,
    acquire = acquire,
    unwait = unwait,
    unwait_readable = unwait_readable,
    unwait_writable = unwait_writable,
    resume = resume,
}

