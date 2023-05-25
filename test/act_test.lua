local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local getpid = require('testcase.getpid')
local act = require('act')

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
        act.atexit(function(stat, a, b)
            assert.is_table(stat)
            assert.is_int(stat.cid)
            stat.cid = nil
            assert.equal(stat, {
                status = act.OK,
                result = {
                    'hello',
                    'world',
                },
            })
            assert.equal(a, 'foo')
            assert.equal(b, 'bar')
            executed = true
        end, 'foo', 'bar')
        return 'hello', 'world'
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
        act.atexit(function(stat, a, b)
            assert.is_table(stat)
            assert.is_int(stat.cid)
            assert.is_nil(stat.result)
            assert.equal(stat.status, act.ERRRUN)
            assert.match(stat.error, 'hello')
            assert.equal(a, 'foo')
            assert.equal(b, 'bar')
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
            end, 'foo', 'bar'))
            return 'hello', 'world'
        end))

        local res = assert(act.await())
        assert.is_table(res)
        assert.is_int(res.cid)
        assert.is_table(res.result)
        local stat = res.result[1]
        assert.is_int(stat.cid)
        stat.cid = nil
        assert.equal(res.result, {
            {
                result = {
                    'hello',
                    'world',
                },
                status = act.OK,
            },
            'foo',
            'bar',
        })
    end)))

    -- test that recover the error of main function
    assert(act.run(with_luacov(function()
        act.spawn(with_luacov(function()
            assert(act.atexit(function(...)
                return ...
            end, 'foo', 'bar'))
            error('hello')
        end))

        local res = assert(act.await())
        assert.is_nil(res.result[1].result)
        assert.equal(res.result[2], 'foo')
        assert.equal(res.result[3], 'bar')
        assert.match(res.result[1].error, 'hello.+traceback', false)
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
                    status = act.OK,
                    result = {
                        'hello',
                    },
                },
            },
            {
                {
                    cid = cid2,
                    status = act.OK,
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
            status = act.OK,
            result = {
                'hello world!',
            },
        })
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.exit)
    assert.match(err, 'outside of execution')
end

