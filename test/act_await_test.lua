local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local act = require('act')

function testcase.await_exit_child()
    assert(act.run(with_luacov(function()
        -- test that waiting for spawned threads to terminate
        local cid = act.spawn(function()
            return 'hello'
        end)

        assert.equal(act.await(), {
            cid = cid,
            status = 'ok',
            result = {
                'hello',
            },
        })

        -- test that return nil if no child threads exist
        assert.is_nil(act.await())

        -- test that cannot receive child thread stat if child thread is terminated before await call
        local is_exit = false
        act.spawn(function()
            is_exit = true
            return 'hello'
        end)

        act.sleep(0.01)
        assert.is_true(is_exit)
        assert.is_nil(act.await())
    end)))
end

function testcase.awaitq_size()
    assert(act.run(with_luacov(function()
        -- test that default await queue size
        assert.equal(act.awaitq_size(), 0)

        -- test that set await queueing size to 2
        assert.equal(act.awaitq_size(2), 2)

        -- test that queueing the exit stats of child threads
        local cid1 = act.spawn(function()
            return 'foo'
        end)
        local cid2 = act.spawn(function()
            return 'bar'
        end)
        act.spawn(function()
            return 'baz'
        end)

        act.sleep(0.01)
        assert.equal({
            act.await(),
            act.await(),
            act.await(),
        }, {
            {
                cid = cid1,
                status = 'ok',
                result = {
                    'foo',
                },
            },
            {
                cid = cid2,
                status = 'ok',
                result = {
                    'bar',
                },
            },
        })
    end)))
end

function testcase.order_of_thread_termination()
    assert(act.run(with_luacov(function()
        -- test that return data in the order in which child threads terminated
        act.awaitq_size(-1)
        local cid1 = act.spawn(function()
            return 'hello'
        end)
        local cid2 = act.spawn(function()
            return 'act'
        end)
        local cid3 = act.spawn(function()
            return 'world'
        end)

        assert.equal(act.await().cid, cid1)
        assert.equal(act.await().cid, cid2)
        assert.equal(act.await().cid, cid3)
    end)))
end

function testcase.return_error_status()
    assert(act.run(with_luacov(function()
        -- test that returns error status
        local cid = act.spawn(function()
            return error('error occurred')
        end)

        local res = assert(act.await())
        assert.contains(res, {
            cid = cid,
            status = 'errrun',
        })
        assert.match(res.error, 'error occurred')
    end)))
end

function testcase.timeout()
    assert(act.run(with_luacov(function()
        -- test that timeout
        act.spawn(function()
            act.sleep(1)
        end)
        local res, timeout = act.await(0.1)
        assert.is_nil(res)
        assert.is_true(timeout)
    end)))
end

function testcase.fail_on_invalid_argument()
    assert(act.run(with_luacov(function()
        -- test that fails on invalid argument
        local err = assert.throws(act.await, 'foo')
        assert.match(err, 'sec must be unsigned number')

        err = assert.throws(act.awaitq_size, 0.5)
        assert.match(err, 'qsize must be integer')
    end)))
end

function testcase.fail_on_called_from_outside_of_execution_context()
    -- test that fail on called from outside of execution context
    local err = assert.throws(act.await)
    assert.match(err, 'outside of execution')

    err = assert.throws(act.awaitq_size)
    assert.match(err, 'outside of execution')
end

