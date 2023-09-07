local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local gettime = require('time.clock').gettime
local act = require('act')

function testcase.suspend_resume()
    -- test that resume a suspended coroutine
    assert(act.run(with_luacov(function()
        local suspended = false
        local cid = act.spawn(with_luacov(function()
            suspended = true
            local elapsed = gettime()
            local ok, val = act.suspend()
            elapsed = gettime() - elapsed

            assert.is_true(ok)
            assert.equal(val, 'hello')
            -- returned immediately if resumed
            assert.less(elapsed, 0.002)
        end))

        act.later()
        assert.is_true(suspended)
        assert(act.resume(cid, 'hello'))
        assert(act.await())
    end)))

end

function testcase.suspend_timeout()
    -- test that suspend timed out
    assert(act.run(with_luacov(function()
        local ok, val = act.suspend(0.1)
        assert.is_false(ok)
        assert.is_nil(val)

        ok, val = act.suspend(0.1)
        assert.is_false(ok)
        assert.is_nil(val)
    end)))
end

function testcase.suspend_throws_error_for_invalid_arguments()
    -- test that throws an error if argument is invalid
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.suspend, 'abc')
        assert.match(err, 'sec must be unsigned number')
    end)))
end

function testcase.suspend_and_resume_throws_error_for_outside_of_execution_context()
    -- test that fail on called from outside of execution context
    for _, fn in ipairs({
        act.suspend,
        act.resume,
    }) do
        local err = assert.throws(fn)
        assert.match(err, 'outside of execution')
    end
end

