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
local tostring = tostring
local strsub = string.sub
local argv_new = require('argv').new
local deque_new = require('deque').new
local reco = require('reco')
local reco_new = reco.new
local aux = require('act.aux')
local concat = aux.concat
local is_uint = aux.is_uint
-- constants
local OP_EVENT = aux.OP_EVENT
local OP_RUNQ = aux.OP_RUNQ
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
local OPERATORS = {
    readable = {},
    writable = {},
}

--- @type act.callee
local CURRENT_CALLEE

--- acquire
--- @return act.callee callee
local function acquire()
    return CURRENT_CALLEE
end

--- unwaitfd
-- @param operators
-- @param fd
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
-- @param fd
local function unwait_readable(fd)
    unwaitfd(OPERATORS.readable, fd)
end

--- unwait_writable
-- @param fd
local function unwait_writable(fd)
    unwaitfd(OPERATORS.writable, fd)
end

--- unwait
-- @param fd
local function unwait(fd)
    unwaitfd(OPERATORS.readable, fd)
    unwaitfd(OPERATORS.writable, fd)
end

--- resume
-- @param cid
-- @param ...
-- @return ok
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

--- resumeq
-- @param runq
-- @param cidq
local function resumeq(runq, cidq)
    -- first index is used for holding a fd
    for i = 1, #cidq do
        local cid = cidq[i]
        local callee = SUSPENDED[cid]

        -- found a suspended callee
        if callee then
            SUSPENDED[cid] = nil
            -- resume via runq
            runq:remove(callee)
            runq:push(callee)
        end
    end
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

        OPERATORS[self.evasa][self.evfd] = nil
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
        self:dispose(status == OK)
    elseif self.term then
        self:dispose(true)
    end
end

--- dispose
--- @param ok boolean
function Callee:dispose(ok)
    local runq = self.act.runq

    runq:remove(self)
    -- remove state properties
    self.term = nil
    SUSPENDED[self.cid] = nil

    -- resume all suspended callee
    for fd, cidq in pairs(self.rlock) do
        -- remove cidq maintained by fd
        RLOCKS[fd] = nil
        resumeq(runq, cidq)
    end
    self.rlock = {}

    -- resume all suspended callee
    for fd, cidq in pairs(self.wlock) do
        -- remove cidq maintained by fd
        WLOCKS[fd] = nil
        resumeq(runq, cidq)
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
        -- root node waiting for child results
        if root.wait then
            root.wait = nil
            -- should not return ok value if atexit function
            if root.atexit then
                root.atexit = nil
                root:call(self.co:results())
            else
                root:call(ok, self.co:results())
            end
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
    self.act.pool:push(self)
end

--- exit
--- @vararg any
function Callee:exit(...)
    self.term = true
    yield(...)

    -- normally unreachable
    error('invalid implements')
end

--- await
--- @return boolean ok
--- @return ...
function Callee:await()
    if #self.node > 0 then
        -- revoke all events currently in use
        self:revoke()
        self.wait = true
        return yield()
    end

    return true
end

--- suspend
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return ...
--- @return boolean timeout
function Callee:suspend(msec)
    local cid = self.cid

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
    local cidq = callee[asa][fd]

    -- resume all suspended callee
    if cidq then
        callee[asa][fd] = nil
        -- remove cidq maintained by fd
        locks[fd] = nil
        resumeq(callee.act.runq, cidq)
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
    assert(is_uint(fd), 'fd must be unsigned integer')
    if not callee[asa][fd] then
        local cidq = locks[fd]

        -- other callee is waiting
        if cidq then
            local idx = #cidq + 1
            local ok, err, timeout

            cidq[idx] = callee.cid
            ok, err, timeout = callee:suspend(msec)
            cidq[idx] = false

            return ok, err, timeout
        end

        -- create read or write queue
        locks[fd] = {}
        callee[asa][fd] = locks[fd]
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
    local runq = self.act.runq
    local event = self.act.event
    local op, fdno, disabled

    -- fd is not watching yet
    if self.evfd ~= fd or self.evasa ~= asa then
        local callee = operators[fd]

        -- revoke retained event
        self:revoke()

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
        local ok, err = runq:push(self, msec)

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
    op, fdno, disabled = yield()
    self.evuse = false

    -- got io event
    if op == OP_EVENT then
        if fdno == fd then
            -- remove from runq
            if msec then
                runq:remove(self)
            end

            if disabled then
                self:revoke()
            end

            return true
        end
    elseif op == OP_RUNQ then
        -- revoked by unwaitfd
        if self.evasa == 'unwaitfd' then
            self.evasa = ''
            return false
            -- timed out
        elseif msec then
            return false, nil, true
        end
    end

    -- remove from runq
    if msec then
        runq:remove(self)
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
    return waitable(self, OPERATORS.readable, 'readable', fd, msec)
end

--- wait_writable
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
function Callee:wait_writable(fd, msec)
    return waitable(self, OPERATORS.writable, 'writable', fd, msec)
end

--- sleep
--- @param msec integer
--- @return boolean ok
--- @return string? err
function Callee:sleep(msec)
    local ok, err = self.act.runq:push(self, msec)

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

--- sigwait
--- @param msec integer
--- @vararg integer signo
--- @return integer signo
--- @return string? err
--- @return boolean? timeout
function Callee:sigwait(msec, ...)
    local runq = self.act.runq
    local event = self.act.event
    local sigset, sigmap

    -- register to runq with msec
    if msec then
        local ok, err = runq:push(self, msec)

        if not ok then
            return nil, err
        end
    end

    sigset = deque_new()
    sigmap = {}
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
        -- wait registered signals
    else
        local op, signo

        -- revoke all events currently in use
        self:revoke()
        -- wait signal events
        self.sigset = sigset
        op, signo = yield()
        self.sigset = nil

        -- remove from runq
        if msec then
            runq:remove(self)
        end

        -- revoke signal events
        for _ = 1, #sigset do
            event:revoke(sigset:pop())
        end

        -- got signal event
        if op == OP_EVENT and sigmap[signo] then
            return signo
            -- timed out
        elseif op == OP_RUNQ then
            return nil, nil, true
        end

        -- normally unreachable
        error('invalid implements')
    end
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
        callee.wait = true
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
--- @param atexit boolean
--- @param fn function
--- @vararg any
function Callee:renew(atexit, fn, ...)
    self.atexit = atexit
    self.args:set(0, ...)
    self.co:reset(fn)
    -- set relationship
    attach2caller(CURRENT_CALLEE, self, atexit)
end

--- new
--- @param act act.context
--- @param atexit boolean
--- @param fn function
--- @vararg any
--- @return act.callee callee
function Callee:init(act, atexit, fn, ...)
    local args = argv_new()
    args:set(0, ...)

    self.act = act
    self.atexit = atexit
    self.co = reco_new(fn)
    self.args = args
    self.argv = argv_new()
    self.node = deque_new()
    self.rlock = {}
    self.wlock = {}
    -- ev = [event object]
    self.evfd = -1
    self.evasa = '' -- '', 'readable' or 'writable'
    self.evuse = false -- true or false

    -- set callee-id
    -- remove 'table: ' prefix
    self.cid = strsub(tostring(self), 10)
    -- set relationship
    attach2caller(CURRENT_CALLEE, self, atexit)

    return self
end

return {
    new = require('metamodule').new(Callee),
    acquire = acquire,
    unwait = unwait,
    unwait_readable = unwait_readable,
    unwait_writable = unwait_writable,
    resume = resume,
}

