local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local nanotime = require('testcase.timer').nanotime
local signal = require('signal')
local act = require('act')

function testcase.signal_occurrs()
    -- test that wait until signal occurrs
    assert(act.run(with_luacov(function()
        signal.block(signal.SIGUSR1)

        local wait = false
        act.spawn(with_luacov(function()
            wait = true
            local elapsed = nanotime()
            local signo, err, timeout = act.sigwait(50, signal.SIGUSR1)
            elapsed = (nanotime() - elapsed) * 1000

            wait = false
            assert.equal(signo, signal.SIGUSR1)
            assert.is_nil(err)
            assert.is_nil(timeout)
            assert.less(elapsed, 2)
        end))

        act.later()
        assert.is_true(wait)
        signal.kill(signal.SIGUSR1)
        assert(act.await())
    end)))
end

function testcase.no_signal_occurrs()
    -- test that return immediately if no signal is specified
    assert(act.run(with_luacov(function()
        local wait = false
        act.spawn(with_luacov(function()
            wait = true
            local elapsed = nanotime()
            local signo, err, timeout = act.sigwait(50)
            elapsed = (nanotime() - elapsed) * 1000

            wait = false
            assert.is_nil(signo)
            assert.is_nil(err)
            assert.is_nil(timeout)
            assert.less(elapsed, 2)
        end))

        act.later()
        assert.is_false(wait)
    end)))
end

function testcase.timeout()
    -- test that fail by timeout
    assert(act.run(with_luacov(function()
        act.spawn(with_luacov(function()
            local signo, err, timeout = act.sigwait(50, signal.SIGUSR1)

            assert.is_nil(signo)
            assert.is_nil(err)
            assert.is_true(timeout)
        end))

        act.later()
        assert(act.await())
    end)))
end

function testcase.invalid_signal()
    -- test that return error if invalid signal is specified
    assert(act.run(with_luacov(function()
        local signo, err = act.sigwait(50, signal.SIGUSR1, -1)
        assert.is_nil(signo)
        assert.match(err, 'EINVAL')
    end)))
end

function testcase.signal_throws()
    -- test that fail with invalid arguments
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.sigwait, -1)
        assert.match(err, 'msec must be unsigned integer')

        err = assert.throws(act.sigwait, nil, 'SIGUSR1')
        assert.match(err, 'number expected')
    end)))

    -- test that fail on called from outside of execution context
    local err = assert.throws(act.sigwait)
    assert.match(err, 'outside of execution')
end
