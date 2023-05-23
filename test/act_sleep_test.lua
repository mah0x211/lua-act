local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local nanotime = require('testcase.timer').nanotime
local act = require('act')

function testcase.sleep_until_specified_time()
    -- test that sleep
    assert(act.run(with_luacov(function()
        local deadline = 10
        local elapsed = nanotime()

        local remain = assert.is_uint(act.sleep(deadline))
        assert.equal(remain, 0)
        elapsed = (nanotime() - elapsed) * 1000
        assert.less(elapsed, 14)
    end)))
end

function testcase.wakeup_order()
    -- test that coroutines are woken up in order of shortest sleep time
    assert(act.run(with_luacov(function()
        act.spawn(with_luacov(function()
            act.sleep(35)
            return 'awake 35'
        end))

        act.spawn(with_luacov(function()
            act.sleep(10)
            return 'awake 10'
        end))

        act.spawn(with_luacov(function()
            act.sleep(25)
            return 'awake 25'
        end))

        act.spawn(with_luacov(function()
            act.sleep(5)
            return 'awake 5'
        end))

        local res = assert(act.await())
        assert(res.result[1] == 'awake 5')

        res = assert(act.await())
        assert(res.result[1] == 'awake 10')

        res = assert(act.await())
        assert(res.result[1] == 'awake 25')

        res = assert(act.await())
        assert(res.result[1] == 'awake 35')
    end)))
end

function testcase.resume_sleeping_coroutine()
    -- test that resume sleeping thread
    assert(act.run(with_luacov(function()
        local cid = act.spawn(with_luacov(function()
            return act.sleep(35)
        end))

        act.sleep(10)
        assert(act.resume(cid))
        local res = assert(act.await())
        assert.equal(res.cid, cid)
        assert.greater_or_equal(res.result[1], 20)
        assert.less_or_equal(res.result[1], 30)
    end)))
end

function testcase.throw_error()
    -- test that fail with invalid deadline
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.sleep, -1)
        assert.match(err, 'msec must be unsigned integer')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.sleep, 1000)
    assert.match(err, 'outside of execution')
end

