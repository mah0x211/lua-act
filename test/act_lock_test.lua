local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local nanotime = require('testcase.timer').nanotime
local act = require('act')
local new_lockq = require('act.lockq').new
local new_runq = require('act.runq').new

function testcase.new_lockq()
    --- create a new lockq
    local lockq = new_lockq(new_runq())
    assert.match(lockq, '^act.lockq: ', false)

    -- test that throw an error
    local err = assert.throws(new_lockq)
    assert.match(err, 'runq must be instance of act.runq')
end

function testcase.attempt_to_protected_value()
    local lockq = new_lockq(new_runq())

    -- test that throw an error
    local err = assert.throws(function()
        lockq.foo = true
    end)
    assert.match(err, 'attempt to protected value')
end

function testcase.release()
    local lockq = new_lockq(new_runq())
    local callee1 = {
        call = function()
        end,
    }
    local callee2 = {
        call = function()
        end,
    }
    local fd = 1
    assert(lockq:read_lock(callee1, fd, 100))
    assert.equal(lockq.rlockq[fd].locker, callee1)

    assert(act.run(with_luacov(function()
        local try_lock = false
        act.spawn(with_luacov(function()
            try_lock = true
            assert(lockq:read_lock(callee2, fd, 100))
            try_lock = false
        end))
        act.later()
        assert.is_true(try_lock)

        -- confirm that callee2 is waiting for the lock
        assert.equal(lockq.rlockq[fd][callee2], 1)
        assert.equal(lockq.rlockq[fd][1], callee2)

        -- test that release the callee2 from the waitq of the lockq
        assert.equal(1, lockq:release(callee2))
        assert.equal(lockq.rlockq[fd].locker, callee1)
        assert.is_nil(lockq.rlockq[fd][callee2])
        assert.is_false(lockq.rlockq[fd][1])
    end)))

    assert.equal(1, lockq:release(callee1))
end

function testcase.lock()
    for _, lockfn in ipairs({
        act.read_lock,
        act.write_lock,
    }) do
        -- test that wakes up in the order of calling the lock function
        assert(act.run(with_luacov(function()
            local fd = 1

            act.spawn(with_luacov(function()
                local ok, err, timeout = lockfn(fd, 30)

                act.sleep(5)
                assert.is_true(ok)
                assert.is_nil(err)
                assert.is_nil(timeout)

                -- test that return true if the lock is already held
                ok, err, timeout = lockfn(fd, 30)
                assert.is_true(ok)
                assert.is_nil(err)
                assert.is_nil(timeout)

                return 'lock ok 30'
            end))

            act.spawn(with_luacov(function()
                local ok, err, timeout = lockfn(fd, 20)

                assert.is_true(ok)
                assert.is_nil(err)
                assert.is_nil(timeout)
                return 'lock ok 20'
            end))

            act.spawn(with_luacov(function()
                local ok, err, timeout = lockfn(fd, 10)

                assert.is_true(ok)
                assert.is_nil(err)
                assert.is_nil(timeout)
                return 'lock ok 10'
            end))

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
        end)))
    end
end

function testcase.lock_timeout()
    for _, lockfn in ipairs({
        act.read_lock,
        act.write_lock,
    }) do
        -- test that lock without timeout
        assert(act.run(with_luacov(function()
            local fd = 1

            assert(lockfn(fd))
            act.spawn(with_luacov(function()
                local elapsed = nanotime()
                local ok, err, timeout = lockfn(fd)
                elapsed = (nanotime() - elapsed) * 1000
                assert.is_false(ok)
                assert.is_nil(err)
                assert.is_true(timeout)
                assert.less(elapsed, 10)
                return 'lock timeout'
            end))

            local res = assert(act.await())
            assert.equal(res.result, {
                'lock timeout',
            })
        end)))

        -- test that wakes up in the order of calling the lock function
        assert(act.run(with_luacov(function()
            local fd = 1

            assert(lockfn(fd, 30))
            act.spawn(with_luacov(function()
                local elapsed = nanotime()
                local ok, err, timeout = lockfn(fd, 30)
                elapsed = (nanotime() - elapsed) * 1000
                assert.is_false(ok)
                assert.is_nil(err)
                assert.is_true(timeout)
                assert.greater(elapsed, 30)
                assert.less(elapsed, 40)
                return 'timeout'
            end))

            local res = assert(act.await())
            assert.equal(res.result, {
                'timeout',
            })
        end)))
    end
end

function testcase.unlock()
    for lockfn, unlockfn in ipairs({
        [act.read_lock] = act.read_unlock,
        [act.write_lock] = act.write_unlock,
    }) do
        -- test that unlock after locked
        assert(act.run(with_luacov(function()
            local fd = 1
            local locked = false

            act.spawn(with_luacov(function()
                assert(lockfn(fd, 30))

                locked = true
                act.sleep(10)
                unlockfn(fd)
                locked = false
                return 'lock 10 msec'
            end))

            act.spawn(with_luacov(function()
                local elapsed = nanotime()
                local ok, timeout = lockfn(fd, 1000)
                elapsed = (nanotime() - elapsed) * 1000

                assert.is_false(locked)
                assert.is_true(ok)
                assert.is_nil(timeout)
                assert.less(elapsed, 20)
                return 'lock ok 1000'
            end))

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
        end)))
    end
end

function testcase.lock_multiple_fd()
    for _, lockfn in ipairs({
        act.read_lock,
        act.write_lock,
    }) do
        -- test that can handle multiple locks at the same time
        assert(act.run(with_luacov(function()
            local fd1, fd2 = 1, 2

            act.spawn(with_luacov(function()
                local ok, err, timeout = lockfn(fd1, 30)
                assert.is_true(ok)
                assert.is_nil(err)
                assert.is_nil(timeout)

                ok, err, timeout = lockfn(fd2, 30)
                assert.is_true(ok)
                assert.is_nil(err)
                assert.is_nil(timeout)

                act.sleep(30)

                return 'lock 1 and 2 ok 30'
            end))

            act.spawn(with_luacov(function()
                local ok, err, timeout = lockfn(fd1, 20)

                assert.is_false(ok)
                assert.is_nil(err)
                assert.is_true(timeout)
                return 'lock 1 timeout 20'
            end))

            act.spawn(with_luacov(function()
                local ok, err, timeout = lockfn(fd2, 10)

                assert.is_false(ok)
                assert.is_nil(err)
                assert.is_true(timeout)
                return 'lock 2 timeout 10'
            end))

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
        end)))
    end
end

function testcase.lock_timeout_order()
    for _, lockfn in ipairs({
        act.read_lock,
        act.write_lock,
    }) do
        -- test that wakes up in order of the shortest timeout
        assert(act.run(with_luacov(function()
            local fd = 1

            act.spawn(with_luacov(function()
                local ok, err, timeout = lockfn(fd, 30)

                act.sleep(30)
                assert.is_true(ok)
                assert.is_nil(err)
                assert.is_nil(timeout)
                return 'lock ok 30'
            end))

            act.spawn(with_luacov(function()
                local elapsed = nanotime()
                local ok, err, timeout = lockfn(fd, 20)
                elapsed = (nanotime() - elapsed) * 1000

                assert.is_false(ok)
                assert.is_nil(err)
                assert.is_true(timeout)
                assert.greater(elapsed, 10)
                assert.less(elapsed, 30)
                return 'lock timeout 20'
            end))

            act.spawn(with_luacov(function()
                local elapsed = nanotime()
                local ok, err, timeout = lockfn(fd, 10)
                elapsed = (nanotime() - elapsed) * 1000

                assert.is_false(ok)
                assert.is_nil(err)
                assert.is_true(timeout)
                assert.greater(elapsed, 1)
                assert.less(elapsed, 20)
                return 'lock timeout 10'
            end))

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
        end)))
    end
end

function testcase.read_lock_invalid_argument()
    -- test that fail on called with invalid argument
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.read_lock, -1)
        assert.match(err, 'fd must be unsigned integer')

        err = assert.throws(act.read_lock, 1, {})
        assert.match(err, 'msec must be unsigned integer')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.read_lock)
    assert.match(err, 'outside of execution')
end

function testcase.read_unlock_invalid_argument()
    -- test that fail on called with invalid argument
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.read_unlock, -1)
        assert.match(err, 'fd must be unsigned integer')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.read_unlock)
    assert.match(err, 'outside of execution')
end

function testcase.write_lock_invalid_argument()
    -- test that fail on called with invalid argument
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.write_lock, -1)
        assert.match(err, 'fd must be unsigned integer')

        err = assert.throws(act.write_lock, 1, {})
        assert.match(err, 'msec must be unsigned integer')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.write_lock)
    assert.match(err, 'outside of execution')
end

function testcase.write_unlock_invalid_argument()
    -- test that fail on called with invalid argument
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.write_unlock, -1)
        assert.match(err, 'fd must be unsigned integer')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.write_unlock)
    assert.match(err, 'outside of execution')
end

