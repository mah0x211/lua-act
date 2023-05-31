local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local act = require('act')

function testcase.yield()
    assert(act.run(with_luacov(function()
        -- test that resume yielded child threads
        local cid = act.spawn(function()
            assert.is_true(act.yield(1, 'hello'))
            return 'world'
        end)

        local res = assert(act.await(100))
        assert.equal(res, {
            cid = cid,
            status = 'yield',
            result = {
                'hello',
            },
        })
        res = assert(act.await(100))
        res.cid = nil
        assert.equal(res, {
            status = 'ok',
            result = {
                'world',
            },
        })
    end)))
end

function testcase.timeout()
    assert(act.run(with_luacov(function()
        -- test that timeout
        local cid = act.spawn(function()
            assert.is_false(act.yield(5, 'hello'))
            return 'timeout'
        end)

        act.awaitq_size(-1)
        act.sleep(10)
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            status = 'ok',
            result = {
                'timeout',
            },
        })
    end)))
end

function testcase.fail_on_main_thread()
    assert(act.run(with_luacov(function()
        act.atexit(function()
            return 'hello'
        end)

        -- test that fail on called from main thread
        local err = assert.throws(act.yield, 10, 'hello')
        assert.match(err, 'parent is not exists')
    end)))
end

function testcase.fail_on_invalid_argument()
    assert(act.run(with_luacov(function()
        -- test that waiting for spawned coroutines to terminate
        local err = assert.throws(act.yield, 'foo')
        assert.match(err, 'msec must be unsigned integer')
    end)))
end

function testcase.fail_on_called_from_outside_of_execution_context()
    -- test that fail on called from outside of execution context
    local err = assert.throws(act.yield)
    assert.match(err, 'outside of execution')
end

