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
-- act.lua
-- lua-act
-- Created by Masatoshi Teruya on 16/12/25.
--
--- ignore SIGPIPE
require('act.ignsigpipe')
--- file scope variables
local pcall = pcall
local fork = require('act.fork')
local aux = require('act.aux')
local is_int = aux.is_int
local is_uint = aux.is_uint
local is_func = aux.is_func
local Callee = require('act.callee')
local new_callee = Callee.new
local callee_acquire = Callee.acquire
local callee_resume = Callee.resume
local callee_unwait_writable = Callee.unwait_writable
local callee_unwait_readable = Callee.unwait_readable
local callee_unwait = Callee.unwait
local new_context = require('act.context').new
--- constants
--- @type act.context?
local ACT_CTX

--- spawn_child
--- @param is_atexit boolean
--- @param fn function
--- @vararg any
--- @return any cid
--- @return string? err
local function spawn_child(is_atexit, fn, ...)
    -- create new callee
    local callee = new_callee(ACT_CTX, is_atexit, fn, ...)

    -- push to runq if not atexit
    if not is_atexit then
        ACT_CTX:pushq(callee)
    end

    return callee.cid
end

--- pollable
--- @return boolean ok
local function pollable()
    return callee_acquire() and true or false
end

--- pfork
--- @return fork.process? p
--- @return any err
--- @return boolean? again
local function pfork()
    if callee_acquire() then
        --- @type fork.process, any, boolean
        local p, err, again = fork()

        if not p then
            return nil, err, again
        elseif p:is_child() then
            -- child process must be rebuilding event properties
            ACT_CTX:renew()
        end

        return p
    end

    error('cannot call fork() from outside of execution context', 2)
end

--- spawn
--- @param fn function
--- @vararg ...
--- @return any cid
--- @return string? err
local function spawn(fn, ...)
    if callee_acquire() then
        if not is_func(fn) then
            error('fn must be function', 2)
        end
        return spawn_child(false, fn, ...)
    end

    error('cannot call spawn() from outside of execution context', 2)
end

--- exit
--- @vararg ...
local function exit(...)
    local callee = callee_acquire()
    if callee then
        callee:exit(...)
    end

    error('cannot call exit() at outside of execution context', 2)
end

--- later
local function later()
    local callee = callee_acquire()
    if not callee then
        error('cannot call later() from outside of execution context', 2)
    end
    callee:later()
end

--- yield
--- @param msec? integer
--- @param ... any
--- @return boolean ok
local function yield(msec, ...)
    local callee = callee_acquire()
    if callee then
        if msec ~= nil and not is_uint(msec) then
            error('msec must be unsigned integer', 2)
        end
        return callee:yield(msec, ...)
    end
    error('cannot call yield() from outside of execution context', 2)
end

--- awaitq_size
--- @param qsize? integer
--- @return integer qlen
local function awaitq_size(qsize)
    local callee = callee_acquire()
    if callee then
        if qsize ~= nil and not is_int(qsize) then
            error('qsize must be integer', 2)
        end
        return callee:awaitq_size(qsize)
    end

    error('cannot call awaitq_size() at outside of execution context', 2)
end

--- await
--- @param msec? integer
--- @return table stat
--- @return boolean timeout
local function await(msec)
    local callee = callee_acquire()
    if callee then
        if msec ~= nil and not is_uint(msec) then
            error('msec must be unsigned integer', 2)
        end
        return callee:await(msec)
    end

    error('cannot call await() at outside of execution context', 2)
end

--- suspend
--- @param msec? integer
--- @return boolean ok
--- @return any ...
local function suspend(msec)
    local callee = callee_acquire()
    if callee then
        if msec ~= nil and not is_uint(msec) then
            error('msec must be unsigned integer', 2)
        end
        return callee:suspend(msec)
    end

    error('cannot call suspend() at outside of execution context', 2)
end

--- resume
--- @param cid any
--- @vararg ...
--- @return boolean ok
local function resume(cid, ...)
    if callee_acquire() then
        return callee_resume(cid, ...)
    end

    error('cannot call resume() at outside of execution context', 2)
end

--- sleep
--- @param msec integer
--- @return integer rem
--- @return string? err
local function sleep(msec)
    local callee = callee_acquire()
    if callee then
        if not is_uint(msec) then
            error('msec must be unsigned integer', 2)
        end
        return callee:sleep(msec)
    end

    error('cannot call sleep() from outside of execution context', 2)
end

--- sigwait
--- @param msec integer
--- @vararg any
--- @return integer signo
--- @return string? err
--- @return boolean? timeout
local function sigwait(msec, ...)
    local callee = callee_acquire()
    if callee then
        if msec ~= nil and not is_uint(msec) then
            error('msec must be unsigned integer', 2)
        end
        return callee:sigwait(msec, ...)
    end

    error('cannot call sleep() from outside of execution context', 2)
end

--- read_lock
--- @param fd integer
--- @param msec? integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function read_lock(fd, msec)
    local callee = callee_acquire()
    if callee then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        elseif msec ~= nil and not is_uint(msec) then
            error('msec must be unsigned integer or nil', 2)
        end
        return callee:read_lock(fd, msec)
    end

    error('cannot call read_lock() from outside of execution context', 2)
end

--- read_unlock
--- @param fd integer
local function read_unlock(fd)
    local callee = callee_acquire()
    if callee then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        end
        return callee:read_unlock(fd)
    end

    error('cannot call read_unlock() from outside of execution context', 2)
end

--- write_lock
--- @param fd integer
--- @param msec? integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
local function write_lock(fd, msec)
    local callee = callee_acquire()
    if callee then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        elseif msec ~= nil and not is_uint(msec) then
            error('msec must be unsigned integer or nil', 2)
        end
        return callee:write_lock(fd, msec)
    end

    error('cannot call write_lock() from outside of execution context', 2)
end

--- write_unlock
--- @param fd integer
local function write_unlock(fd)
    local callee = callee_acquire()
    if callee then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        end
        return callee:write_unlock(fd)
    end

    error('cannot call write_unlock() from outside of execution context', 2)
end

--- unwait_readable
--- @param fd integer
--- @return boolean ok
local function unwait_readable(fd)
    if callee_acquire() then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        end
        callee_unwait_readable(fd)
        return true
    end

    error('cannot call unwait_readable() from outside of execution context', 2)
end

--- unwait_writable
--- @param fd integer
--- @return boolean ok
local function unwait_writable(fd)
    if callee_acquire() then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        end
        callee_unwait_writable(fd)
        return true
    end

    error('cannot call unwait_writable() from outside of execution context', 2)
end

--- unwait
--- @param fd integer
--- @return boolean ok
local function unwait(fd)
    if callee_acquire() then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        end
        callee_unwait(fd)
        return true
    end

    error('cannot call unwait() from outside of execution context', 2)
end

--- wait_readable
--- @param fd integer
--- @param msec? integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
local function wait_readable(fd, msec)
    local callee = callee_acquire()

    if callee then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        elseif msec ~= nil and not is_uint(msec) then
            error('msec must be unsigned integer', 2)
        end
        return callee:wait_readable(fd, msec)
    end

    error('cannot call wait_readable() from outside of execution context', 2)
end

--- wait_writable
--- @param fd integer
--- @param msec? integer
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
local function wait_writable(fd, msec)
    local callee = callee_acquire()
    if callee then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        elseif msec ~= nil and not is_uint(msec) then
            error('msec must be unsigned integer', 2)
        end
        return callee:wait_writable(fd, msec)
    end

    error('cannot call wait_writable() from outside of execution context', 2)
end

--- getcid
--- @return any cid
local function getcid()
    local callee = callee_acquire()
    if callee then
        return callee.cid
    end

    error('cannot call getcid() at outside of execution context', 2)
end

--- atexit
--- @param exitfn function
--- @vararg any
--- @return boolean ok
--- @return string? err
local function atexit(exitfn, ...)
    if callee_acquire() then
        if not is_func(exitfn) then
            error('exitfn must be function', 2)
        end

        local _, err = spawn_child(true, exitfn, ...)
        return not err, err
    end

    error('cannot call atexit() at outside of execution context', 2)
end

--- runloop
--- @param mainfn function
--- @vararg any
--- @return boolean ok
--- @return any err
local function runloop(mainfn, ...)
    -- create act context
    local err
    ACT_CTX, err = new_context()
    if err then
        return false, err
    end

    -- create main coroutine
    local ok
    ok, err = spawn_child(false, mainfn, ...)
    if not ok then
        return false, err
    end

    -- run act scheduler
    local runq = ACT_CTX.runq
    local event = ACT_CTX.event
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
--- @param mainfn function
--- @vararg any
--- @return boolean ok
--- @return any err
local function run(mainfn, ...)
    -- check first argument
    if not is_func(mainfn) then
        error('mainfn must be function', 2)
    elseif ACT_CTX then
        return false, 'act run already'
    end

    local ok, rv, err = pcall(runloop, mainfn, ...)
    ACT_CTX = nil
    if ok then
        return rv, err
    end

    return false, rv
end

-- exports
return {
    run = run,
    getcid = getcid,
    wait_writable = wait_writable,
    wait_readable = wait_readable,
    unwait = unwait,
    unwait_writable = unwait_writable,
    unwait_readable = unwait_readable,
    write_unlock = write_unlock,
    write_lock = write_lock,
    read_unlock = read_unlock,
    read_lock = read_lock,
    sigwait = sigwait,
    sleep = sleep,
    resume = resume,
    suspend = suspend,
    await = await,
    awaitq_size = awaitq_size,
    atexit = atexit,
    yield = yield,
    later = later,
    exit = exit,
    spawn = spawn,
    fork = pfork,
    pollable = pollable,
}
