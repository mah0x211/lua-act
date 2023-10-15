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
local format = string.format
local concat = table.concat
local type = type
local waitpid = require('waitpid')
local gettime = require('time.clock').gettime
local fork = require('act.fork')
local aux = require('act.aux')
local is_int = aux.is_int
local is_uint = aux.is_uint
local is_unsigned = aux.is_unsigned
local Callee = require('act.callee')
local new_callee = Callee.new
local callee_acquire = Callee.acquire
local callee_resume = Callee.resume
local callee_unwait = Callee.unwait
local callee_unwait_readable = Callee.unwait_readable
local callee_unwait_writable = Callee.unwait_writable
local new_context = require('act.context').new
--- constants
--- @type act.context?
local ACT_CTX
local EVENT_CACHE_ENABLED = false

--- event_cache
--- @param enabled boolean
local function event_cache(enabled)
    if callee_acquire() then
        error('the event cache state cannot be changed at runtime execution', 2)
    elseif type(enabled) ~= 'boolean' then
        error('enabled must be boolean', 2)
    end
    EVENT_CACHE_ENABLED = enabled
end

--- spawn_child
--- @param is_atexit boolean
--- @param fn function
--- @param ... any
--- @return any cid
local function spawn_child(is_atexit, fn, ...)
    -- create new callee
    local callee = new_callee(ACT_CTX, is_atexit, fn, ...)
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

--- @class waitpid.result
--- @field pid integer process id
--- @field exit integer exit code
--- @field sigcont boolean true if the process was resumed by SIGCONT
--- @field sigterm integer signal number that caused the process to terminate
--- @field sigstop integer signal number that caused the process to stop

--- pwaitpid
--- @param sec? number timeout in seconds
--- @param wpid? integer process id to wait
--- @param ... string options
--- | 'nohang' : set WNOHANG option (default)
--- | 'untraced' : set WUNTRACED option
--- | 'continued' : set WCONTINUED option
--- @return waitpid.result? res
--- @return any err
--- @return boolean? timeout
local function pwaitpid(sec, wpid, ...)
    local callee = callee_acquire()
    if callee then
        local interval = 0.1
        local deadline

        if sec ~= nil then
            if not is_unsigned(sec) then
                error('sec must be unsigned number or nil', 2)
            end
            deadline = gettime() + sec
            if interval > sec then
                interval = sec
            end
        end

        if wpid ~= nil and not is_int(wpid) then
            error('wpid must be integer', 2)
        end

        while true do
            local res, err, again = waitpid(wpid, 'nohang', ...)
            if res then
                return res
            elseif not again then
                return nil, err
            end

            if deadline then
                local remain = deadline - gettime()
                if remain <= 0 then
                    -- timeout
                    return nil, nil, true
                elseif remain < interval then
                    -- update interval
                    interval = remain
                end
            end

            -- sleep
            callee:sleep(interval)
        end
    end

    error('cannot call waitpid() from outside of execution context', 2)
end

--- spawn
--- @param fn function
--- @param ... any
--- @return any cid
local function spawn(fn, ...)
    if callee_acquire() then
        if type(fn) ~= 'function' then
            error('fn must be function', 2)
        end
        return spawn_child(false, fn, ...)
    end

    error('cannot call spawn() from outside of execution context', 2)
end

--- exit
--- @param ... any
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
--- @param sec? number
--- @param ... any
--- @return boolean ok
local function yield(sec, ...)
    local callee = callee_acquire()
    if callee then
        if sec ~= nil and not is_unsigned(sec) then
            error('sec must be unsigned number or nil', 2)
        end
        return callee:yield(sec, ...)
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
--- @param sec? number
--- @return table stat
--- @return boolean timeout
local function await(sec)
    local callee = callee_acquire()
    if callee then
        if sec ~= nil and not is_unsigned(sec) then
            error('sec must be unsigned number or nil', 2)
        end
        return callee:await(sec)
    end

    error('cannot call await() at outside of execution context', 2)
end

--- suspend
--- @param sec? number
--- @return boolean ok
--- @return any ...
local function suspend(sec)
    local callee = callee_acquire()
    if callee then
        if sec ~= nil and not is_unsigned(sec) then
            error('sec must be unsigned number or nil', 2)
        end
        return callee:suspend(sec)
    end

    error('cannot call suspend() at outside of execution context', 2)
end

--- resume
--- @param cid any
--- @param ... any
--- @return boolean ok
local function resume(cid, ...)
    if callee_acquire() then
        return callee_resume(cid, ...)
    end

    error('cannot call resume() at outside of execution context', 2)
end

--- sleep
--- @param sec number
--- @return integer rem
--- @return string? err
local function sleep(sec)
    local callee = callee_acquire()
    if callee then
        if not is_unsigned(sec) then
            error('sec must be unsigned number', 2)
        end
        return callee:sleep(sec)
    end

    error('cannot call sleep() from outside of execution context', 2)
end

--- sigwait
--- @param sec? number
--- @param ... any
--- @return integer signo
--- @return string? err
--- @return boolean? timeout
local function sigwait(sec, ...)
    local callee = callee_acquire()
    if callee then
        if sec ~= nil and not is_unsigned(sec) then
            error('sec must be unsigned number or nil', 2)
        end
        return callee:sigwait(sec, ...)
    end

    error('cannot call sleep() from outside of execution context', 2)
end

--- read_lock
--- @param fd integer
--- @param sec? number
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function read_lock(fd, sec)
    local callee = callee_acquire()
    if callee then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        elseif sec ~= nil and not is_unsigned(sec) then
            error('sec must be unsigned number or nil', 2)
        end
        return callee:read_lock(fd, sec)
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
--- @param sec? number
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
local function write_lock(fd, sec)
    local callee = callee_acquire()
    if callee then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        elseif sec ~= nil and not is_unsigned(sec) then
            error('sec must be unsigned number or nil', 2)
        end
        return callee:write_lock(fd, sec)
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
    if ACT_CTX then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        end
        callee_unwait_readable(ACT_CTX, fd)
        return true
    end

    return false
end

--- unwait_writable
--- @param fd integer
--- @return boolean ok
local function unwait_writable(fd)
    if ACT_CTX then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        end
        callee_unwait_writable(ACT_CTX, fd)
        return true
    end

    return false
end

--- unwait
--- @param fd integer
--- @return boolean ok
local function unwait(fd)
    if ACT_CTX then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        end
        callee_unwait(ACT_CTX, fd)
        return true
    end

    return false
end

--- wait_readable
--- @param fd integer
--- @param sec? number
--- @return integer? fd
--- @return any err
--- @return boolean? timeout
local function wait_readable(fd, sec)
    local callee = callee_acquire()

    if callee then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        elseif sec ~= nil and not is_unsigned(sec) then
            error('sec must be unsigned number or nil', 2)
        end
        return callee:wait_readable(fd, sec)
    end

    error('cannot call wait_readable() from outside of execution context', 2)
end

--- wait_writable
--- @param fd integer
--- @param sec? number
--- @return integer? fd
--- @return any err
--- @return boolean? timeout
local function wait_writable(fd, sec)
    local callee = callee_acquire()
    if callee then
        if not is_uint(fd) then
            error('fd must be unsigned integer', 2)
        elseif sec ~= nil and not is_unsigned(sec) then
            error('sec must be unsigned number or nil', 2)
        end
        return callee:wait_writable(fd, sec)
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
--- @param ... any
--- @return boolean ok
local function atexit(exitfn, ...)
    if callee_acquire() then
        if type(exitfn) ~= 'function' then
            error('exitfn must be function', 2)
        end
        spawn_child(true, exitfn, ...)
        return true
    end

    error('cannot call atexit() at outside of execution context', 2)
end

--- runloop
--- @param mainfn function
--- @param ... any
--- @return boolean ok
--- @return any err
local function runloop(mainfn, ...)
    -- create act context
    local err
    ACT_CTX, err = new_context(EVENT_CACHE_ENABLED)
    if err then
        return false, err
    end

    -- create main coroutine
    spawn_child(false, mainfn, ...)

    -- run act scheduler
    local runq = ACT_CTX.runq
    local event = ACT_CTX.event
    while true do
        -- consume runq
        local sec = runq:consume()
        -- finish if no more callee
        if not ACT_CTX:has_active_callees() then
            return true
        end

        -- consume events
        local remain
        remain, err = event:consume(sec)
        if err then
            -- got critical error
            return false, err
        elseif remain == 0 then
            -- no more events
            -- finish if no more callee
            if runq:len() == 0 then
                -- get traceback of active callees
                local infos = ACT_CTX:getinfo_active_callees()
                if #infos > 0 then
                    -- some callees may be waiting for resume by other callees
                    -- but no body resume them.
                    local list = {
                        'deadlock detected',
                    }
                    for i = 1, #infos do
                        list[#list + 1] =
                            format('  %s:%d', infos[i].short_src,
                                   infos[i].currentline)
                    end
                    error(concat(list, '\n'))
                end
                return true
            end

            -- sleep until timer time elapsed
            local ok
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
--- @param ... any
--- @return boolean ok
--- @return any err
local function run(mainfn, ...)
    -- check first argument
    if type(mainfn) ~= 'function' then
        error('mainfn must be function', 2)
    elseif ACT_CTX then
        return false, 'act run already'
    end

    local ok, rv, err = pcall(runloop, mainfn, ...)
    collectgarbage('collect')
    ACT_CTX = nil
    if ok then
        return rv, err
    end

    return false, rv
end

-- exports
return {
    run = run,
    event_cache = event_cache,
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
    waitpid = pwaitpid,
    pollable = pollable,
}
