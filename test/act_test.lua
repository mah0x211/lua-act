local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local nanotime = require('testcase.timer').nanotime
local getpid = require('testcase.getpid')
local errno = require('errno')
local llsocket = require('llsocket')
local act = require('act')

local SOCKPAIR

local function socketpair()
    collectgarbage('collect')
    SOCKPAIR = assert(llsocket.socket.pair(llsocket.SOCK_STREAM, nil, true))
    return SOCKPAIR[1], SOCKPAIR[2]
end

function testcase.after_each()
    for _, sock in ipairs(SOCKPAIR or {}) do
        sock:close()
    end
end

function testcase.run()
    -- test that return true with function argument
    assert(act.run(with_luacov(function()
    end)))

    -- test that success with function argument and arugments
    assert(act.run(with_luacov(function(a, b)
        assert(a == 'foo', 'a is unknown argument')
        assert(b == 'bar', 'b is unknown argument')
    end), 'foo', 'bar'))

    -- test that fail when called from the running function
    assert(act.run(with_luacov(function()
        local ok, err = act.run(function()
        end)
        assert.is_false(ok)
        assert.match(err, 'act run already')
    end)))

    -- test that fail with a non-function argument
    local err = assert.throws(act.run)
    assert.match(err, 'fn must be function')
end

function testcase.getcid()
    -- test that return callee-id
    assert(act.run(with_luacov(function()
        assert.is_uint(act.getcid())
    end)))

    -- test that throws an error if called from outside of execution context
    local err = assert.throws(act.getcid)
    assert.match(err, 'cannot call getcid() at outside of execution context')
end

function testcase.pollable()
    -- test that return false if called from outside of execution context
    assert.is_false(act.pollable())

    -- test that return true if inside of execution context
    assert(act.run(with_luacov(function()
        assert.is_true(act.pollable())
    end)))
end

function testcase.fork()
    local pid = getpid()

    -- test that fork process
    assert(act.run(with_luacov(function()
        local p = assert(act.fork())
        if p:is_child() then
            assert.not_equal(pid, getpid())
            return
        end
        local res = assert(p:wait())
        assert.equal(res.exit, 0)
    end)))
    if pid ~= getpid() then
        -- ignore child process
        return
    end

    -- test that throws an error if called from outside of execution context
    local err = assert.throws(act.fork)
    assert.match(err, 'cannot call fork() from outside of execution context')
end

function testcase.spawn()
    -- test that spawn new coroutine
    assert(act.run(with_luacov(function()
        local executed = false
        act.spawn(function()
            executed = true
        end)
        act.sleep(0)
        assert(executed, 'child coroutine did not executed')
    end)))

    -- test that fail with a non-function argument
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.spawn, 1)
        assert.match(err, 'fn must be function')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.spawn, function()
    end)
    assert.match(err, 'outside of execution')
end

function testcase.later()
    -- test that run after execution of other coroutines
    assert.is_true(act.run(with_luacov(function()
        local executed = false

        act.spawn(function()
            executed = true
        end)
        act.later()
        assert(executed, 'child coroutine did not executed')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.later)
    assert.match(err, 'outside of execution')
end

function testcase.atexit()
    -- test that calling a function on exit
    local executed = false
    assert(act.run(with_luacov(function()
        act.atexit(function(a, b)
            assert(a == 'foo')
            assert(b == 'bar')
            executed = true
        end, 'foo', 'bar')
    end)))
    assert(executed, 'could not executed')

    -- test that calling functions in reverse order of registration
    executed = {
        count = 0,
    }
    assert(act.run(with_luacov(function()
        act.atexit(function()
            executed.count = executed.count + 1
            executed.first = executed.count
        end)
        act.atexit(function()
            executed.count = executed.count + 1
            executed.second = executed.count
        end)
        act.atexit(function()
            executed.count = executed.count + 1
            executed.last = executed.count
        end)
    end)))
    assert.equal(executed, {
        count = 3,
        last = 1,
        second = 2,
        first = 3,
    })

    -- test that pass a previous error message
    executed = false
    assert(act.run(with_luacov(function()
        act.atexit(function(a, b, ok, status, err)
            assert.equal(a, 'foo')
            assert.equal(b, 'bar')
            assert.is_false(ok)
            assert.equal(status, act.ERRRUN)
            assert.match(err, 'hello')
            executed = true
        end, 'foo', 'bar')

        act.atexit(function()
            error('hello')
        end)
    end)))
    assert(executed, 'could not executed')

    -- test that return atexit error
    assert(act.run(with_luacov(function()
        act.spawn(with_luacov(function()
            assert(act.atexit(function()
                error('world')
            end))
            return 'hello'
        end))

        local res = assert(act.await())
        assert.match(res.error, 'world.+traceback', false)
    end)))

    -- test that return the return values of main function
    assert(act.run(with_luacov(function()
        act.spawn(with_luacov(function()
            assert(act.atexit(function(...)
                return ...
            end))
            return 'hello', 'world'
        end))

        local res = assert(act.await())
        assert.equal(res.result, {
            true,
            act.OK,
            'hello',
            'world',
        })
    end)))

    -- test that recover the error of main function
    assert(act.run(with_luacov(function()
        act.spawn(with_luacov(function()
            assert(act.atexit(function(a, b, ok, status, ...)
                return ...
            end, 'foo', 'bar'))
            error('hello')
        end))

        local res = assert(act.await())
        assert.match(res.result[1], 'hello.+traceback', false)
    end)))

    -- test that fail with a non-function argument
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.atexit, 1)
        assert.match(err, 'fn must be function')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.atexit, function()
    end)
    assert.match(err, 'outside of execution')
end

function testcase.await()
    -- test that waiting for spawned coroutines to terminate
    assert(act.run(with_luacov(function()
        local cid1 = act.spawn(function()
            return 'hello'
        end)
        local cid2 = act.spawn(function()
            return 'world'
        end)
        local cid3 = act.spawn(function()
            return error('error occurred')
        end)

        assert.equal({
            {
                act.await(100),
            },
            {
                act.await(100),
            },
        }, {
            {
                {
                    cid = cid1,
                    result = {
                        'hello',
                    },
                },
            },
            {
                {
                    cid = cid2,
                    result = {
                        'world',
                    },
                },
            },
        })

        local res = assert(act.await())
        assert.contains(res, {
            cid = cid3,
            status = act.ERRRUN,
        })
        assert.match(res.error, 'error occurred')

        -- test that timeout
        act.spawn(function()
            act.sleep(1000)
        end)
        local timeout
        res, timeout = act.await(100)
        assert.is_nil(res)
        assert.is_true(timeout)

        -- test that throws an error if msec argument is invalid
        local err = assert.throws(act.await, {})
        assert.match(err, 'msec must be unsigned integer')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.await)
    assert.match(err, 'outside of execution')
end

function testcase.exit()
    -- test that perform coroutine termination
    assert(act.run(with_luacov(function()
        local cid = act.spawn(with_luacov(function()
            return act.exit('hello world!')
        end))
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {
                'hello world!',
            },
        })
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.exit)
    assert.match(err, 'outside of execution')
end

function testcase.wait_unwait_readable()
    -- test that wait until fd is readable
    assert(act.run(with_luacov(function()
        local reader, writer = socketpair()
        local wait = false
        local cid = act.spawn(with_luacov(function()
            wait = true
            assert(act.wait_readable(reader:fd(), 50))
            wait = false
            return reader:recv()
        end))

        act.later()
        assert.is_true(wait)
        writer:send('hello world!')
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {
                'hello world!',
            },
        })
    end)))

    -- test that cancel waiting until fd is readable
    assert(act.run(with_luacov(function()
        local reader = socketpair()
        local wait = false
        local cid = act.spawn(with_luacov(function()
            wait = true
            local ok, err, timeout = act.wait_readable(reader:fd(), 50)
            wait = false
            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
        end))

        act.later()
        assert.is_true(wait)
        act.unwait_readable(reader:fd())
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {},
        })
    end)))

    -- test that the unwait function can cancel waiting until fd is readable
    assert(act.run(with_luacov(function()
        local reader = socketpair()
        local wait = false
        local cid = act.spawn(with_luacov(function()
            wait = true
            local ok, err, timeout = act.wait_readable(reader:fd(), 50)
            wait = false
            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
        end))

        act.later()
        assert.is_true(wait)
        act.unwait(reader:fd())
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {},
        })
    end)))

    -- test that fail by timeout
    assert(act.run(with_luacov(function()
        local sock = socketpair()
        local ok, err, timeout = act.wait_readable(sock:fd(), 50)
        assert.is_false(ok)
        assert.is_nil(err)
        assert.is_true(timeout)
    end)))

    -- test that fail on shutdown
    assert(act.run(with_luacov(function()
        local sock = socketpair()
        local cid = act.spawn(with_luacov(function()
            local ok, err, timeout = act.wait_readable(sock:fd(), 50)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return sock:recv()
        end))

        act.later()
        sock:shutdown(llsocket.SHUT_RDWR)

        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {},
        })
    end)))

    -- test that fail with invalid arguments
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.wait_readable, -1)
        assert.match(err, 'fd must be unsigned integer')

        err = assert.throws(act.wait_readable, 0, -1)
        assert.match(err, 'msec must be unsigned integer')

        err = assert.throws(act.unwait_readable, -1)
        assert.match(err, 'fd must be unsigned integer')

        err = assert.throws(act.unwait, -1)
        assert.match(err, 'fd must be unsigned integer')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.wait_readable)
    assert.match(err, 'outside of execution')

    err = assert.throws(act.unwait_readable)
    assert.match(err, 'outside of execution')

    err = assert.throws(act.unwait)
    assert.match(err, 'outside of execution')
end

function testcase.wait_writable()
    -- test that wait until fd is writable
    assert(act.run(with_luacov(function()
        local reader, writer = socketpair()
        local cid = act.spawn(with_luacov(function()
            local ok, err, timeout = act.wait_writable(writer:fd(), 50)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return writer:send('hello')
        end))

        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {
                5,
                nil,
                false,
            },
        })
        assert.equal(reader:recv(), 'hello')
    end)))

    -- test that cancel waiting until fd is writable
    assert(act.run(with_luacov(function()
        local sock = socketpair()
        assert(sock:sndbuf(5))
        local msg = string.rep('x', sock:sndbuf(5))
        assert(sock:send(msg))

        local wait = false
        local cid = act.spawn(with_luacov(function()
            wait = true
            local ok, err, timeout = act.wait_writable(sock:fd(), 50)
            wait = false
            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
        end))

        act.later()
        assert.is_true(wait)
        act.unwait_writable(sock:fd())
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {},
        })
    end)))

    -- test that unwait function can cancel waiting until fd is writable
    assert(act.run(with_luacov(function()
        local sock = socketpair()
        assert(sock:sndbuf(5))
        local msg = string.rep('x', sock:sndbuf(5))
        assert(sock:send(msg))

        local wait = false
        local cid = act.spawn(with_luacov(function()
            wait = true
            local ok, err, timeout = act.wait_writable(sock:fd(), 50)
            wait = false
            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
        end))

        act.later()
        assert.is_true(wait)
        act.unwait(sock:fd())
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {},
        })
    end)))

    -- test that fail by timeout
    assert(act.run(with_luacov(function()
        local sock = socketpair()
        assert(sock:sndbuf(5))
        local msg = string.rep('x', sock:sndbuf(5))
        assert(sock:send(msg))

        local cid = act.spawn(with_luacov(function()
            local ok, err, timeout = act.wait_writable(sock:fd(), 50)

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
        end))

        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {},
        })
    end)))

    -- test that fail on shutdown
    assert(act.run(with_luacov(function()
        local sock = socketpair()
        assert(sock:sndbuf(5))
        local msg = string.rep('x', sock:sndbuf(5))
        assert(sock:send(msg))
        local wait = false
        local cid = act.spawn(with_luacov(function()
            wait = true
            local elapsed = nanotime()
            local ok, err, timeout = act.wait_writable(sock:fd(), 10)
            elapsed = (nanotime() - elapsed) * 1000

            wait = false
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            -- returned immediately if descriptor changed
            assert.less(elapsed, 2)

            return sock:send('hello')
        end))

        sock:send('hello')
        act.later()
        assert.is_true(wait)
        sock:shutdown(llsocket.SHUT_RDWR)

        local res = assert(act.await())
        assert.equal(res.cid, cid)
        assert.is_nil(res.result[1])
        assert.equal(res.result[2].type, errno.EPIPE)
        assert.is_nil(res.result[3])
    end)))

    -- test that fail with invalid arguments
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.wait_writable, -1)
        assert.match(err, 'fd must be unsigned integer')

        err = assert.throws(act.wait_writable, 0, -1)
        assert.match(err, 'msec must be unsigned integer')

        err = assert.throws(act.unwait_writable, -1)
        assert.match(err, 'fd must be unsigned integer')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.wait_writable)
    assert.match(err, 'outside of execution')

    err = assert.throws(act.unwait_writable)
    assert.match(err, 'outside of execution')
end

function testcase.suspend_resume()
    -- test that resume a suspended coroutine
    assert(act.run(with_luacov(function()
        local suspended = false
        local cid = act.spawn(with_luacov(function()
            suspended = true
            local elapsed = nanotime()
            local ok, val, timeout = act.suspend(100)
            elapsed = (nanotime() - elapsed) * 1000

            assert.is_true(ok)
            assert.equal(val, 'hello')
            assert.is_nil(timeout)
            -- returned immediately if resumed
            assert.less(elapsed, 2)
        end))

        act.later()
        assert.is_true(suspended)
        assert(act.resume(cid, 'hello'))
        assert(act.await())
    end)))

    -- test that suspend timed out
    assert(act.run(with_luacov(function()
        local ok, val, timeout = act.suspend()

        assert.is_false(ok)
        assert.is_nil(val)
        assert.is_true(timeout)

        ok, val, timeout = act.suspend(100)
        assert.is_false(ok)
        assert.is_nil(val)
        assert.is_true(timeout)
    end)))

    -- test that fail on called with invalid argument
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.suspend, 'abc')
        assert.match(err, 'msec must be unsigned integer')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.suspend)
    assert.match(err, 'outside of execution')

    err = assert.throws(act.resume)
    assert.match(err, 'outside of execution')
end

