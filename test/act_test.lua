require('luacov')
local testcase = require('testcase')
local nanotime = require('testcase.timer').nanotime
local errno = require('errno')
local llsocket = require('llsocket')
local signal = require('signal')
local act = require('act')

local function socketpair()
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

    -- test that fail with a non-function argument
    assert.is_false(act.run())
    assert.is_false(act.run(1))
    assert.is_false(act.run('str'))
    assert.is_false(act.run({}))

    -- test that fail when called from the running function
    assert.is_false(act.run(function(a, b)
        assert(act.run(function()
        end))
    end, 'foo', 'bar'))
end

function testcase.sleep()
    -- test that sleep
    assert(act.run(function()
        local deadline = 10
        local elapsed = nanotime()

        act.sleep(deadline)
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

        local _, msg = assert(act.await())
        assert(msg == 'awake 5')

        _, msg = assert(act.await())
        assert(msg == 'awake 10')

        _, msg = assert(act.await())
        assert(msg == 'awake 25')

        _, msg = assert(act.await())
        assert(msg == 'awake 35')
    end))

    -- test that fail with invalid deadline
    assert(act.run(function()
        for _, v in ipairs({
            'str',
            1.1,
            -1,
        }) do
            local ok, err = act.sleep(v)
            assert.is_false(ok)
            assert.match(err, 'msec must be unsigned integer')
        end
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
        assert.match(err, 'function expected, got number')
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
        act.atexit(function(a, b, err)
            assert(a == 'foo')
            assert(b == 'bar')
            assert(string.find(err, 'hello'))
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

        local ok, err = act.await()
        assert.is_false(ok)
        assert.match(err, 'world.+traceback', false)
    end))

    -- test that return the return values of main function
    assert(act.run(function()
        act.spawn(function()
            assert(act.atexit(function(...)
                return ...
            end))
            return 'hello', 'world'
        end)

        local ok, a, b = act.await()
        assert.is_true(ok)
        assert.equal({
            a,
            b,
        }, {
            'hello',
            'world',
        })
    end))

    -- test that recover the error of main function
    assert(act.run(function()
        act.spawn(function()
            assert(act.atexit(function(a, b, ...)
                return ...
            end, 'foo', 'bar'))
            error('hello')
        end)

        local ok, err = act.await()
        assert.is_true(ok)
        assert.match(err, 'hello.+traceback', false)
    end))

    -- test that fail with a non-function argument
    assert(act.run(function()
        local err = assert.throws(act.atexit, 1)
        assert.match(err, 'function expected, got number')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.atexit, function()
    end)
    assert.match(err, 'outside of execution')
end

function testcase.await()
    -- test that waiting for spawned coroutines to terminate
    assert(act.run(function()
        act.spawn(function()
            return 'hello'
        end)
        act.spawn(function()
            return 'world'
        end)
        act.spawn(function()
            return error('error occurred')
        end)

        assert.equal({
            {
                act.await(),
            },
            {
                act.await(),
            },
        }, {
            {
                true,
                'hello',
            },
            {
                true,
                'world',
            },
        })

        local ok, val = act.await()
        assert.is_false(ok)
        assert.match(val, 'error occurred')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.await)
    assert.match(err, 'outside of execution')
end

function testcase.exit()
    -- test that perform coroutine termination
    assert.is_true(act.run(function()
        act.spawn(function()
            return act.exit('hello world!')
        end)
        local ok, val = act.await()
        assert.is_true(ok)
        assert.equal(val, 'hello world!')
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
        act.spawn(function()
            wait = true
            assert(act.wait_readable(reader:fd(), 50))
            wait = false
            return reader:recv()
        end)

        act.later()
        assert.is_true(wait)
        writer:send('hello world!')
        local ok, msg = act.await()
        assert.is_true(ok)
        assert.equal(msg, 'hello world!')
    end))

    -- test that fail with invalid arguments
    assert(act.run(function()
        local err = assert.throws(act.wait_readable, -1)
        assert.match(err, 'fd value range')
    end))

    assert(act.run(function()
        local ok, err, timeout = act.wait_readable(0, -1)
        assert.is_false(ok)
        assert.match(err, 'msec must be unsigned integer')
        assert.is_nil(timeout)
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

        act.spawn(function()
            local ok, err, timeout = act.wait_readable(sock:fd(), 50)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return sock:recv()
        end)

        act.later()
        sock:shutdown(llsocket.SHUT_RDWR)

        local ok, msg, err, again = act.await()
        assert.is_true(ok)
        assert.is_nil(msg)
        assert.is_nil(err)
        assert.is_nil(again)
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.wait_readable)
    assert.match(err, 'outside of execution')
end

function testcase.wait_writable()
    -- test that wait until fd is writable
    assert(act.run(function()
        local reader, writer = socketpair()

        act.spawn(function()
            local ok, err, timeout = act.wait_writable(writer:fd(), 50)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return writer:send('hello')
        end)

        act.later()
        local _, len, err = assert(act.await())
        assert(len, err)
        assert.equal(len, 5)
        assert.equal(reader:recv(), 'hello')
    end))

    -- test that fail with invalid arguments
    assert(act.run(function()
        local err = assert.throws(act.wait_writable, -1)
        assert.match(err, 'fd value range')
    end))

    assert(act.run(function()
        local ok, err, timeout = act.wait_writable(0, -1)
        assert.is_false(ok)
        assert.match(err, 'msec must be unsigned integer')
        assert.is_nil(timeout)
    end))

    -- test that fail by timeout
    assert(act.run(function()
        local sock = socketpair()
        assert(sock:sndbuf(5))
        local msg = string.rep('x', sock:sndbuf(5))
        assert(sock:send(msg))

        act.spawn(function()
            local ok, err, timeout = act.wait_writable(sock:fd(), 50)

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
        end)
        act.later()
        local ok = act.await()
        assert.is_true(ok)
    end))

    -- test that fail on shutdown
    assert(act.run(function()
        local sock = socketpair()
        assert(sock:sndbuf(5))
        local msg = string.rep('x', sock:sndbuf(5))
        assert(sock:send(msg))
        local wait = false
        act.spawn(function()
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

        local ok, len, err, again = act.await()
        assert.is_true(ok)
        assert.is_nil(len)
        assert.equal(err.type, errno.EPIPE)
        assert.is_nil(again)
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

    -- test that fail with invalid arguments
    assert(act.run(function()
        local signo, err, timeout = act.sigwait(-1)
        assert.is_nil(signo)
        assert.match(err, 'msec must be unsigned integer')
        assert.is_nil(timeout)
    end))

    assert(act.run(function()
        local err = assert.throws(act.sigwait, nil, -1000)
        assert.match(err, 'invalid signal number')
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
        local ok, err, timeout = act.suspend('abc')
        assert.is_false(ok)
        assert.match(err, 'msec must be unsigned integer')
        assert.is_nil(timeout)
    end))

    assert(act.run(function()
        local ok = act.resume('abc')
        assert.is_false(ok)
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

        local _, msg = assert(act.await())
        assert.equal(msg, 'lock ok 30')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock ok 20')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock ok 10')
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
        local _, msg = assert(act.await())
        assert.equal(msg, 'lock 10 msec')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock ok 1000')
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

        local _, msg = assert(act.await())
        assert.equal(msg, 'lock 2 timeout 10')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock 1 timeout 20')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock 1 and 2 ok 30')
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

        local _, msg = assert(act.await())
        assert.equal(msg, 'lock timeout 10')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock timeout 20')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock ok 30')
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
            local ok, err, timeout = act.read_lock(writer:fd(), 30)

            act.sleep(5)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 30'
        end)

        act.spawn(function()
            local ok, err, timeout = act.read_lock(writer:fd(), 20)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 20'
        end)

        act.spawn(function()
            local ok, err, timeout = act.read_lock(writer:fd(), 10)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 10'
        end)

        local _, msg = assert(act.await())
        assert.equal(msg, 'lock ok 30')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock ok 20')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock ok 10')
    end))

    -- test that unlock after locked
    assert(act.run(function()
        local _, writer = socketpair()
        local locked = false
        act.spawn(function()
            local ok, err, timeout = act.read_lock(writer:fd(), 30)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)

            locked = true
            act.sleep(10)
            act.read_unlock(writer:fd())
            locked = false
            return 'lock 10 msec'
        end)

        act.spawn(function()
            local elapsed = nanotime()
            local ok, err, timeout = act.read_lock(writer:fd(), 1000)
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
        local _, msg = assert(act.await())
        assert.equal(msg, 'lock 10 msec')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock ok 1000')
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

        local _, msg = assert(act.await())
        assert.equal(msg, 'lock 2 timeout 10')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock 1 timeout 20')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock 1 and 2 ok 30')
    end))

    -- test that wakes up in order of the shortest timeout
    assert(act.run(function()
        local _, writer = socketpair()

        act.spawn(function()
            local ok, err, timeout = act.read_lock(writer:fd(), 30)

            act.sleep(30)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            return 'lock ok 30'
        end)

        act.spawn(function()
            local elapsed = nanotime()
            local ok, err, timeout = act.read_lock(writer:fd(), 20)
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
            local ok, err, timeout = act.read_lock(writer:fd(), 10)
            elapsed = (nanotime() - elapsed) * 1000

            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
            assert.greater(elapsed, 1)
            assert.less(elapsed, 20)
            return 'lock timeout 10'
        end)

        local _, msg = assert(act.await())
        assert.equal(msg, 'lock timeout 10')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock timeout 20')

        _, msg = assert(act.await())
        assert.equal(msg, 'lock ok 30')
    end))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.write_lock)
    assert.match(err, 'outside of execution')
end