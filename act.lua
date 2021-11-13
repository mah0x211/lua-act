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
-- act.lua
-- lua-act
-- Created by Masatoshi Teruya on 16/12/25.
--
--- ignore SIGPIPE
require('nosigpipe')
--- file scope variables
local Deque = require('deq')
local fork = require('process').fork
local waitpid = require('process').waitpid
local RunQ = require('act.runq')
local Event = require('act.event')
local Callee = require('act.callee')
local setmetatable = setmetatable
--- constants
local WNOHANG = require('process').WNOHANG
local ACT_CTX

--- spawn
-- @param atexit
-- @param fn
-- @param ...
-- @return cid
-- @return err
local function spawn(atexit, fn, ...)
    local callee = ACT_CTX.pool:pop()
    local ok, err

    -- use pooled callee
    if callee then
        callee:init(atexit, fn, ...)
    else
        -- create new callee
        callee = Callee.new(ACT_CTX, atexit, fn, ...)
    end

    -- push to runq if not atexit
    if not atexit then
        ok, err = ACT_CTX.runq:push(callee)
        if not ok then
            return nil, err
        end
    end

    return callee.cid
end

--- class Act
local Act = {}

--- pollable
-- @return ok
function Act.pollable()
    return Callee.acquire() and true or false
end

--- fork
-- @return pid
-- @return err
-- @return again
function Act.fork()
    if Callee.acquire() then
        local pid, err, again = fork()

        if not pid then
            return nil, err, again
        elseif pid == 0 then
            -- child process must be rebuilding event properties
            ACT_CTX.event:renew()
        end

        return pid
    end

    error('cannot call fork() from outside of execution context', 2)
end

--- waitpid
-- @param pid
-- @return status
-- @return err
function Act.waitpid(pid)
    if Callee.acquire() then
        return waitpid(pid, WNOHANG)
    end

    error('cannot call waitpid() from outside of execution context', 2)
end

--- spawn
-- @param fn
-- @param ...
-- @return cid
-- @return err
function Act.spawn(fn, ...)
    if Callee.acquire() then
        return spawn(false, fn, ...)
    end

    error('cannot call spawn() from outside of execution context', 2)
end

--- exit
-- @param ...
function Act.exit(...)
    local callee = Callee.acquire()

    if callee then
        callee:exit(...)
    end

    error('cannot call exit() at outside of execution context', 2)
end

--- later
-- @return ok
-- @return err
function Act.later()
    local callee = Callee.acquire()

    if callee then
        return callee:later()
    end

    error('cannot call later() from outside of execution context', 2)
end

--- atexit
-- @param fn
-- @param ...
-- @return ok
-- @return err
function Act.atexit(fn, ...)
    if Callee.acquire() then
        local _, err = spawn(true, fn, ...)

        return not err, err
    end

    error('cannot call atexit() at outside of execution context', 2)
end

--- await
-- @return ok
-- @return ...
function Act.await()
    local callee = Callee.acquire()

    if callee then
        return callee:await()
    end

    error('cannot call await() at outside of execution context', 2)
end

--- suspend
-- @param msec
-- @return ok
-- @return ...
-- @return timeout
function Act.suspend(msec)
    local callee = Callee.acquire()

    if callee then
        return callee:suspend(msec)
    end

    error('cannot call suspend() at outside of execution context', 2)
end

--- resume
-- @param cid
-- @param ...
-- @return ok
function Act.resume(cid, ...)
    if Callee.acquire() then
        return Callee.resume(cid, ...)
    end

    error('cannot call resume() at outside of execution context', 2)
end

--- sleep
-- @param msec
-- @return ok
-- @return err
function Act.sleep(msec)
    local callee = Callee.acquire()

    if callee then
        return callee:sleep(msec)
    end

    error('cannot call sleep() from outside of execution context', 2)
end

--- sigwait
-- @param msec
-- @param ...
-- @return signo
-- @return err
-- @return timeout
function Act.sigwait(msec, ...)
    local callee = Callee.acquire()

    if callee then
        return callee:sigwait(msec, ...)
    end

    error('cannot call sleep() from outside of execution context', 2)
end

--- read_lock
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Act.read_lock(fd, msec)
    local callee = Callee.acquire()

    if callee then
        return callee:read_lock(fd, msec)
    end

    error('cannot call read_lock() from outside of execution context', 2)
end

--- read_unlock
-- @param fd
function Act.read_unlock(fd)
    local callee = Callee.acquire()

    if callee then
        return callee:read_unlock(fd)
    end

    error('cannot call read_unlock() from outside of execution context', 2)
end

--- write_lock
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Act.write_lock(fd, msec)
    local callee = Callee.acquire()

    if callee then
        return callee:write_lock(fd, msec)
    end

    error('cannot call write_lock() from outside of execution context', 2)
end

--- write_unlock
-- @param fd
function Act.write_unlock(fd)
    local callee = Callee.acquire()

    if callee then
        return callee:write_unlock(fd)
    end

    error('cannot call write_unlock() from outside of execution context', 2)
end

--- unwait_readable
-- @param fd
function Act.unwait_readable(fd)
    if Callee.acquire() then
        Callee.unwait_readable(fd)
    else
        error('cannot call unwait_readable() from outside of execution context',
              2)
    end
end

--- unwait_writable
-- @param fd
function Act.unwait_writable(fd)
    if Callee.acquire() then
        Callee.unwait_writable(fd)
    else
        error('cannot call unwait_writable() from outside of execution context',
              2)
    end
end

--- unwait
-- @param fd
function Act.unwait(fd)
    if Callee.acquire() then
        Callee.unwait(fd)
    else
        error('cannot call unwait() from outside of execution context', 2)
    end
end

--- wait_readable
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Act.wait_readable(fd, msec)
    local callee = Callee.acquire()

    if callee then
        return callee:wait_readable(fd, msec)
    end

    error('cannot call wait_readable() from outside of execution context', 2)
end

--- wait_writable
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Act.wait_writable(fd, msec)
    local callee = Callee.acquire()

    if callee then
        return callee:wait_writable(fd, msec)
    end

    error('cannot call wait_writable() from outside of execution context', 2)
end

--- getcid
-- @return cid
function Act.getcid()
    local callee = Callee.acquire()

    if callee then
        return callee.cid
    end

    error('cannot call getcid() at outside of execution context', 2)
end

--- runloop
-- @param fn
-- @param ...
-- @return ok
-- @return err
local function runloop(fn, ...)
    local event, runq, ok, err

    -- check first argument
    assert(type(fn) == 'function', 'fn must be function')

    if ACT_CTX then
        return false, 'act run already'
    end

    -- create event
    event, err = Event.new()
    if err then
        return false, err
    end

    -- create act context
    runq = RunQ.new()
    ACT_CTX = setmetatable({
        event = event,
        runq = runq,
        pool = Deque.new(),
    }, {
        __newindex = function()
            error('attempt to protected value', 2)
        end,
    })

    -- create main coroutine
    ok, err = spawn(false, fn, ...)
    if not ok then
        return false, err
    end

    -- run act scheduler
    while true do
        -- consume runq
        local msec = runq:consume()
        local remain

        -- consume events
        remain, err = event:consume(msec)
        if err then
            -- got critical error
            return false, err
        elseif remain == 0 then
            -- no more events
            -- finish if no more callee
            if runq:len() == 0 then
                return true
            end

            -- sleep until timer time elapsed
            ok, err = runq:sleep()
            if not ok then
                -- got critical error
                return ok, err
            end
        end
    end
end

--- run
-- @param fn
-- @param ...
-- @return ok
-- @return err
function Act.run(fn, ...)
    local ok, rv, err = pcall(runloop, fn, ...)

    ACT_CTX = nil
    if ok then
        return rv, err
    end

    return false, rv
end

-- exports
return Act
