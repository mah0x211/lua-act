require('luacov')
local testcase = require('testcase')
local nanotime = require('testcase.timer').nanotime
local getpid = require('testcase.getpid')
local errno = require('errno')
local llsocket = require('llsocket')
local signal = require('signal')
local act = require('act')

local function socketpair()
    collectgarbage('collect')
    local pair = assert(llsocket.socket.pair(llsocket.SOCK_STREAM, nil, true))
    return pair[1], pair[2]
end

function testcase.run()
    -- test that return true with function argument
    assert(act.run(function()
    end))

    -- test that success with function argument and arugments
    assert(act.run(function(a, b)
        assert(a == 'foo', 'a is unknown argument')
        assert(b == 'bar', 'b is unknown argument')
    end, 'foo', 'bar'))

    -- test that fail when called from the running function
    assert(act.run(function()
        local ok, err = act.run(function()
        end)
        assert.is_false(ok)
        assert.match(err, 'act run already')
    end))

    -- test that fail with a non-function argument
    local err = assert.throws(act.run)
    assert.match(err, 'fn must be function')
end

function testcase.fork()
    -- test that fork process
    assert(act.run(function()
        local pid = getpid()
        local p = assert(act.fork())
        if p:is_child() then
            assert.not_equal(pid, getpid())
            return
        end
        local res = assert(p:wait())
        assert.equal(res.exit, 0)
    end))
end

function testcase.sleep()
    -- test that sleep
    assert(act.run(function()
        local deadline = 10
        local elapsed = nanotime()

        assert.is_uint(act.sleep(deadline))
        elapsed = (nanotime() - elapsed) * 1000
        assert.less(elapsed, 14)
    end))

    -- test that get up in order of shortest sleep time
    assert(act.run(function()
        act.spawn(function()
            act.sleep(35)
            return 'awake 35'
        end)

        act.spawn(function()
            act.sleep(10)
            return 'awake 10'
        end)

        act.spawn(function()
            act.sleep(25)
            return 'awake 25'
        end)

        act.spawn(function()
            act.sleep(5)
            return 'awake 5'
        end)

        local res = assert(act.await())
        assert(res.result[1] == 'awake 5')

        res = assert(act.await())
        assert(res.result[1] == 'awake 10')

        res = assert(act.await())
        assert(res.result[1] == 'awake 25')

        res = assert(act.await())
        assert(res.result[1] == 'awake 35')
    end))

    -- test that resume sleeping thread
    assert(act.run(function()
        local cid = act.spawn(function()
            return act.sleep(35)
        end)

        act.sleep(10)
        assert(act.resume(cid))
        local res = assert(act.await())
        assert.equal(res.cid, cid)
        assert.greater_or_equal(res.result[1], 20)
        assert.less_or_equal(res.result[1], 25)
    end))

    -- test that fail with invalid deadline
    assert(act.run(function()
        local err = assert.throws(act.sleep, -1)
        assert.match(err, 'msec must be unsigned integer')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.sleep, 1000)
    assert.match(err, 'outside of execution')
end

function testcase.spawn()
    -- test that spawn new coroutine
    assert(act.run(function()
        local executed = false
        act.spawn(function()
            executed = true
        end)
        act.sleep(0)
        assert(executed, 'child coroutine did not executed')
    end))

    -- test that fail with a non-function argument
    assert(act.run(function()
        local err = assert.throws(act.spawn, 1)
        assert.match(err, 'fn must be function')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.spawn, function()
    end)
    assert.match(err, 'outside of execution')
end

function testcase.later()
    -- test that run after execution of other coroutines
    assert.is_true(act.run(function()
        local executed = false

        act.spawn(function()
            executed = true
        end)
        act.later()
        assert(executed, 'child coroutine did not executed')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.later)
    assert.match(err, 'outside of execution')
end

function testcase.atexit()
    -- test that calling a function on exit
    local executed = false
    assert(act.run(function()
        act.atexit(function(a, b)
            assert(a == 'foo')
            assert(b == 'bar')
            executed = true
        end, 'foo', 'bar')
    end))
    assert(executed, 'could not executed')

    -- test that calling functions in reverse order of registration
    executed = {
        count = 0,
    }
    assert(act.run(function()
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
    end))
    assert.equal(executed, {
        count = 3,
        last = 1,
        second = 2,
        first = 3,
    })

    -- test that pass a previous error message
    executed = false
    assert(act.run(function()
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
    end))
    assert(executed, 'could not executed')

    -- test that return atexit error
    assert(act.run(function()
        act.spawn(function()
            assert(act.atexit(function()
                error('world')
            end))
            return 'hello'
        end)

        local res = assert(act.await())
        assert.match(res.error, 'world.+traceback', false)
    end))

    -- test that return the return values of main function
    assert(act.run(function()
        act.spawn(function()
            assert(act.atexit(function(...)
                return ...
            end))
            return 'hello', 'world'
        end)

        local res = assert(act.await())
        assert.equal(res.result, {
            true,
            act.OK,
            'hello',
            'world',
        })
    end))

    -- test that recover the error of main function
    assert(act.run(function()
        act.spawn(function()
            assert(act.atexit(function(a, b, ok, status, ...)
                return ...
            end, 'foo', 'bar'))
            error('hello')
        end)

        local res = assert(act.await())
        assert.match(res.result[1], 'hello.+traceback', false)
    end))

    -- test that fail with a non-function argument
    assert(act.run(function()
        local err = assert.throws(act.atexit, 1)
        assert.match(err, 'fn must be function')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.atexit, function()
    end)
    assert.match(err, 'outside of execution')
end

function testcase.await()
    -- test that waiting for spawned coroutines to terminate
    assert(act.run(function()
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
        local err, timeout
        res, err, timeout = act.await(100)
        assert.is_nil(res)
        assert.is_nil(err)
        assert.is_true(timeout)
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.await)
    assert.match(err, 'outside of execution')
end

function testcase.exit()
    -- test that perform coroutine termination
    assert(act.run(function()
        local cid = act.spawn(function()
            return act.exit('hello world!')
        end)
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {
                'hello world!',
            },
        })
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.exit)
    assert.match(err, 'outside of execution')
end

function testcase.wait_readable()
    -- test that wait until fd is readable
    assert(act.run(function()
        local reader, writer = socketpair()
        local wait = false
        local cid = act.spawn(function()
            wait = true
            assert(act.wait_readable(reader:fd(), 50))
            wait = false
            return reader:recv()
        end)

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
    end))

    -- test that fail by timeout
    assert(act.run(function()
        local sock = socketpair()
        local ok, err, timeout = act.wait_readable(sock:fd(), 50)
        assert.is_false(ok)
        assert.is_nil(err)
        assert.is_true(timeout)
    end))

    -- test that fail on shutdown
    assert(act.run(function()
        local sock = socketpair()
        local cid = act.spawn(function()
            local ok, err, timeout = act.wait_readable(sock:fd(), 50)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return sock:recv()
        end)

        act.later()
        sock:shutdown(llsocket.SHUT_RDWR)

        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {},
        })
    end))

    -- test that fail with invalid arguments
    assert(act.run(function()
        local err = assert.throws(act.wait_readable, -1)
        assert.match(err, 'fd must be unsigned integer')

        err = assert.throws(act.wait_readable, 0, -1)
        assert.match(err, 'msec must be unsigned integer')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.wait_readable)
    assert.match(err, 'outside of execution')
end

function testcase.wait_writable()
    -- test that wait until fd is writable
    assert(act.run(function()
        local reader, writer = socketpair()
        local cid = act.spawn(function()
            local ok, err, timeout = act.wait_writable(writer:fd(), 50)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return writer:send('hello')
        end)

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
    end))

    -- test that fail by timeout
    assert(act.run(function()
        local sock = socketpair()
        assert(sock:sndbuf(5))
        local msg = string.rep('x', sock:sndbuf(5))
        assert(sock:send(msg))

        local cid = act.spawn(function()
            local ok, err, timeout = act.wait_writable(sock:fd(), 50)

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
        end)

        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            result = {},
        })
    end))

    -- test that fail on shutdown
    assert(act.run(function()
        local sock = socketpair()
        assert(sock:sndbuf(5))
        local msg = string.rep('x', sock:sndbuf(5))
        assert(sock:send(msg))
        local wait = false
        local cid = act.spawn(function()
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
        end)

        sock:send('hello')
        act.later()
        assert.is_true(wait)
        sock:shutdown(llsocket.SHUT_RDWR)

        local res = assert(act.await())
        assert.equal(res.cid, cid)
        assert.is_nil(res.result[1])
        assert.equal(res.result[2].type, errno.EPIPE)
        assert.is_nil(res.result[3])
    end))

    -- test that fail with invalid arguments
    assert(act.run(function()
        local err = assert.throws(act.wait_writable, -1)
        assert.match(err, 'fd must be unsigned integer')

        err = assert.throws(act.wait_writable, 0, -1)
        assert.match(err, 'msec must be unsigned integer')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.wait_writable)
    assert.match(err, 'outside of execution')
end

function testcase.sigwait()
    -- test that wait until signal occurrs
    assert(act.run(function()
        signal.block(signal.SIGUSR1)

        local wait = false
        act.spawn(function()
            wait = true
            local elapsed = nanotime()
            local signo, err, timeout = act.sigwait(50, signal.SIGUSR1)
            elapsed = (nanotime() - elapsed) * 1000

            wait = false
            assert.equal(signo, signal.SIGUSR1)
            assert.is_nil(err)
            assert.is_nil(timeout)
            -- returned immediately if descriptor changed
            assert.less(elapsed, 2)
        end)

        act.later()
        assert.is_true(wait)
        signal.kill(signal.SIGUSR1)
        assert(act.await())
    end))

    -- test that fail by timeout
    assert(act.run(function()
        act.spawn(function()
            local signo, err, timeout = act.sigwait(50, signal.SIGUSR1)

            assert.is_nil(signo)
            assert.is_nil(err)
            assert.is_true(timeout)
        end)

        act.later()
        assert(act.await())
    end))

    -- test that fail with invalid arguments
    assert(act.run(function()
        local err = assert.throws(act.sigwait, -1)
        assert.match(err, 'msec must be unsigned integer')

        err = assert.throws(act.sigwait, nil, -1000)
        assert.match(err, 'invalid signal number')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.sigwait)
    assert.match(err, 'outside of execution')
end

function testcase.suspend_resume()
    -- test that resume a suspended coroutine
    assert(act.run(function()
        local suspended = false
        local cid = act.spawn(function()
            suspended = true
            local elapsed = nanotime()
            local ok, val, timeout = act.suspend(100)
            elapsed = (nanotime() - elapsed) * 1000

            assert.is_true(ok)
            assert.equal(val, 'hello')
            assert.is_nil(timeout)
            -- returned immediately if resumed
            assert.less(elapsed, 2)
        end)

        act.later()
        assert.is_true(suspended)
        assert(act.resume(cid, 'hello'))
        assert(act.await())
    end))

    -- test that suspend timed out
    assert(act.run(function()
        local ok, val, timeout = act.suspend()

        assert.is_false(ok)
        assert.is_nil(val)
        assert.is_true(timeout)

        ok, val, timeout = act.suspend(100)
        assert.is_false(ok)
        assert.is_nil(val)
        assert.is_true(timeout)
    end))

    -- test that fail on called with invalid argument
    assert(act.run(function()
        local err = assert.throws(act.suspend, 'abc')
        assert.match(err, 'msec must be unsigned integer')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.suspend)
    assert.match(err, 'outside of execution')

    err = assert.throws(act.resume)
    assert.match(err, 'outside of execution')
end

function testcase.read_lock_unlock()
    -- test that wakes up in the order of calling the lock function
    assert(act.run(function()
        local sock = socketpair()

        act.spawn(function()
            local ok, err, timeout = act.read_lock(sock:fd(), 30)

            act.sleep(5)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 30'
        end)

        act.spawn(function()
            local ok, err, timeout = act.read_lock(sock:fd(), 20)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 20'
        end)

        act.spawn(function()
            local ok, err, timeout = act.read_lock(sock:fd(), 10)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 10'
        end)

        local res = assert(act.await())
        assert.equal(res.result, {
            'lock ok 30',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock ok 20',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock ok 10',
        })
    end))

    -- test that unlock after locked
    assert(act.run(function()
        local sock = socketpair()
        local locked = false
        act.spawn(function()
            local ok, err, timeout = act.read_lock(sock:fd(), 30)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)

            locked = true
            act.sleep(10)
            act.read_unlock(sock:fd())
            locked = false
            return 'lock 10 msec'
        end)

        act.spawn(function()
            local elapsed = nanotime()
            local ok, err, timeout = act.read_lock(sock:fd(), 1000)
            elapsed = (nanotime() - elapsed) * 1000

            assert.is_false(locked)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            assert.less(elapsed, 15)
            return 'lock ok 1000'
        end)

        act.later()
        assert.is_true(locked)
        local res = assert(act.await())
        assert.equal(res.result, {
            'lock 10 msec',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock ok 1000',
        })
    end))

    -- test that can handle multiple locks at the same time
    assert(act.run(function()
        local sock1, sock2 = socketpair()

        act.spawn(function()
            local ok, err, timeout = act.read_lock(sock1:fd(), 30)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)

            ok, err, timeout = act.read_lock(sock2:fd(), 30)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)

            act.sleep(30)

            return 'lock 1 and 2 ok 30'
        end)

        act.spawn(function()
            local ok, err, timeout = act.read_lock(sock1:fd(), 20)

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
            return 'lock 1 timeout 20'
        end)

        act.spawn(function()
            local ok, err, timeout = act.read_lock(sock2:fd(), 10)

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
            return 'lock 2 timeout 10'
        end)

        local res = assert(act.await())
        assert.equal(res.result, {
            'lock 2 timeout 10',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock 1 timeout 20',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock 1 and 2 ok 30',
        })
    end))

    -- test that wakes up in order of the shortest timeout
    assert(act.run(function()
        local sock = socketpair()

        act.spawn(function()
            local ok, err, timeout = act.read_lock(sock:fd(), 30)

            act.sleep(30)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 30'
        end)

        act.spawn(function()
            local elapsed = nanotime()
            local ok, err, timeout = act.read_lock(sock:fd(), 20)
            elapsed = (nanotime() - elapsed) * 1000

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
            assert.greater(elapsed, 10)
            assert.less(elapsed, 30)
            return 'lock timeout 20'
        end)

        act.spawn(function()
            local elapsed = nanotime()
            local ok, err, timeout = act.read_lock(sock:fd(), 10)
            elapsed = (nanotime() - elapsed) * 1000

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
            assert.greater(elapsed, 1)
            assert.less(elapsed, 20)
            return 'lock timeout 10'
        end)

        local res = assert(act.await())
        assert.equal(res.result, {
            'lock timeout 10',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock timeout 20',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock ok 30',
        })
    end))

    -- test that fail on called with invalid argument
    assert(act.run(function()
        local err = assert.throws(act.read_lock, -1)
        assert.match(err, 'fd must be unsigned integer')

        err = assert.throws(act.read_lock, 1, {})
        assert.match(err, 'msec must be unsigned integer')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.read_lock)
    assert.match(err, 'outside of execution')
end

function testcase.write_lock_unlock()
    -- test that wakes up in the order of calling the lock function
    assert(act.run(function()
        local _, writer = socketpair()

        act.spawn(function()
            local ok, err, timeout = act.write_lock(writer:fd(), 30)

            act.sleep(5)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 30'
        end)

        act.spawn(function()
            local ok, err, timeout = act.write_lock(writer:fd(), 20)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 20'
        end)

        act.spawn(function()
            local ok, err, timeout = act.write_lock(writer:fd(), 10)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 10'
        end)

        local res = assert(act.await())
        assert.equal(res.result, {
            'lock ok 30',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock ok 20',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock ok 10',
        })
    end))

    -- test that unlock after locked
    assert(act.run(function()
        local _, writer = socketpair()
        local locked = false
        act.spawn(function()
            local ok, err, timeout = act.write_lock(writer:fd(), 30)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)

            locked = true
            act.sleep(10)
            act.write_unlock(writer:fd())
            locked = false
            return 'lock 10 msec'
        end)

        act.spawn(function()
            local elapsed = nanotime()
            local ok, err, timeout = act.write_lock(writer:fd(), 1000)
            elapsed = (nanotime() - elapsed) * 1000

            assert.is_false(locked)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            assert.less(elapsed, 15)
            return 'lock ok 1000'
        end)

        act.later()
        assert.is_true(locked)
        local res = assert(act.await())
        assert.equal(res.result, {
            'lock 10 msec',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock ok 1000',
        })
    end))

    -- test that can handle multiple locks at the same time
    assert(act.run(function()
        local sock1, sock2 = socketpair()

        act.spawn(function()
            local ok, err, timeout = act.write_lock(sock1:fd(), 30)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)

            ok, err, timeout = act.write_lock(sock2:fd(), 30)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)

            act.sleep(30)

            return 'lock 1 and 2 ok 30'
        end)

        act.spawn(function()
            local ok, err, timeout = act.write_lock(sock1:fd(), 20)

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
            return 'lock 1 timeout 20'
        end)

        act.spawn(function()
            local ok, err, timeout = act.write_lock(sock2:fd(), 10)

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
            return 'lock 2 timeout 10'
        end)

        local res = assert(act.await())
        assert.equal(res.result, {
            'lock 2 timeout 10',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock 1 timeout 20',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock 1 and 2 ok 30',
        })
    end))

    -- test that wakes up in order of the shortest timeout
    assert(act.run(function()
        local _, writer = socketpair()

        act.spawn(function()
            local ok, err, timeout = act.write_lock(writer:fd(), 30)

            act.sleep(30)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 30'
        end)

        act.spawn(function()
            local elapsed = nanotime()
            local ok, err, timeout = act.write_lock(writer:fd(), 20)
            elapsed = (nanotime() - elapsed) * 1000

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
            assert.greater(elapsed, 10)
            assert.less(elapsed, 30)
            return 'lock timeout 20'
        end)

        act.spawn(function()
            local elapsed = nanotime()
            local ok, err, timeout = act.write_lock(writer:fd(), 10)
            elapsed = (nanotime() - elapsed) * 1000

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
            assert.greater(elapsed, 1)
            assert.less(elapsed, 20)
            return 'lock timeout 10'
        end)

        local res = assert(act.await())
        assert.equal(res.result, {
            'lock timeout 10',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock timeout 20',
        })

        res = assert(act.await())
        assert.equal(res.result, {
            'lock ok 30',
        })
    end))

    -- test that fail on called with invalid argument
    assert(act.run(function()
        local err = assert.throws(act.write_lock, -1)
        assert.match(err, 'fd must be unsigned integer')

        err = assert.throws(act.write_lock, 1, {})
        assert.match(err, 'msec must be unsigned integer')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.write_lock)
    assert.match(err, 'outside of execution')
end
