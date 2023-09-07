local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local gettime = require('time.clock').gettime
local act = require('act')

function testcase.sleep_until_specified_time()
    -- test that sleep
    assert(act.run(with_luacov(function()
        local elapsed = gettime()
        local remain = assert.is_uint(act.sleep(0.01))
        assert.equal(remain, 0)
        elapsed = gettime() - elapsed
        assert.less(elapsed, 0.014)
    end)))
end

function testcase.wakeup_order()
    -- test that coroutines are woken up in order of shortest sleep time
    assert(act.run(with_luacov(function()
        act.spawn(with_luacov(function()
            act.sleep(0.035)
            return 'awake 0.035'
        end))

        act.spawn(with_luacov(function()
            act.sleep(0.01)
            return 'awake 0.01'
        end))

        act.spawn(with_luacov(function()
            act.sleep(0.025)
            return 'awake 0.025'
        end))

        act.spawn(with_luacov(function()
            act.sleep(0.005)
            return 'awake 0.005'
        end))

        local res = assert(act.await())
        assert(res.result[1] == 'awake 0.005')

        res = assert(act.await())
        assert(res.result[1] == 'awake 0.01')

        res = assert(act.await())
        assert(res.result[1] == 'awake 0.025')

        res = assert(act.await())
        assert(res.result[1] == 'awake 0.035')
    end)))
end

function testcase.resume_sleeping_coroutine()
    -- test that resume sleeping thread
    assert(act.run(with_luacov(function()
        local cid = act.spawn(with_luacov(function()
            return act.sleep(0.035)
        end))

        act.sleep(0.01)
        assert(act.resume(cid))
        local res = assert(act.await())
        assert.equal(res.cid, cid)
        assert.greater_or_equal(res.result[1], 0.02)
        assert.less_or_equal(res.result[1], 0.03)
    end)))
end

function testcase.throw_error()
    -- test that fail with invalid deadline
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.sleep, -1)
        assert.match(err, 'sec must be unsigned number')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.sleep, 1.0)
    assert.match(err, 'outside of execution')
end

