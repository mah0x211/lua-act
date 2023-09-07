local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local getpid = require('testcase.getpid')
local errno = require('errno')
local act = require('act')
local gettime = require('time.clock').gettime

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

    -- ignore child process
    if pid ~= getpid() then
        return
    end

    -- test that throws an error if called from outside of execution context
    local err = assert.throws(act.fork)
    assert.match(err, 'cannot call fork() from outside of execution context')
end

function testcase.waitpid()
    local pid = getpid()

    -- test that wait child process exit forever
    assert(act.run(with_luacov(function()
        local p = assert(act.fork())
        if p:is_child() then
            act.sleep(0.5)
            return
        end

        local res, err, timeout = act.waitpid()
        assert.equal(res, {
            pid = p:pid(),
            exit = 0,
        })
        assert.is_nil(err)
        assert.is_nil(timeout)
    end)))

    -- ignore child process
    if pid ~= getpid() then
        return
    end

    -- test that wait specified child process exit
    assert(act.run(with_luacov(function()
        local p1 = assert(act.fork())
        if p1:is_child() then
            act.sleep(0.5)
            return
        end

        local p2 = assert(act.fork())
        if p2:is_child() then
            return
        end

        local res, err, timeout = act.waitpid(nil, p1:pid())
        assert.equal(res, {
            pid = p1:pid(),
            exit = 0,
        })
        assert.is_nil(err)
        assert.is_nil(timeout)

        -- cleanup
        while act.waitpid() do
        end
    end)))

    -- ignore child process
    if pid ~= getpid() then
        return
    end

    assert(act.run(with_luacov(function()
        local p = assert(act.fork())
        if p:is_child() then
            act.sleep(0.5)
            return
        end

        -- test that wait child process exit with timeout
        local elapsed = gettime()
        local res, err, timeout = act.waitpid(0.2)
        elapsed = gettime() - elapsed
        assert.is_nil(res)
        assert.is_nil(err)
        assert.is_true(timeout)
        assert.greater(elapsed, 0.2)
        assert.less(elapsed, 0.25)

        -- that that wait child process exit with timeout that less than 100 msec
        elapsed = gettime()
        res, err, timeout = act.waitpid(0.05)
        elapsed = gettime() - elapsed
        assert.is_nil(res)
        assert.is_nil(err)
        assert.is_true(timeout)
        assert.greater(elapsed, 0.045)
        assert.less(elapsed, 0.059)

        -- cleanup
        while act.waitpid() do
        end

    end)))

    -- ignore child process
    if pid ~= getpid() then
        return
    end

    -- test that return error if no child process exists
    assert(act.run(with_luacov(function()
        local res, err, timeout = act.waitpid()
        assert.is_nil(res)
        assert.equal(err.type, errno.ECHILD)
        assert.is_nil(timeout)
    end)))

    -- test that throws an error if argument is invalid
    assert(act.run(with_luacov(function()
        -- test that throws an error if msec is not a valid number
        local err = assert.throws(act.waitpid, -1)
        assert.match(err, 'sec must be unsigned number or nil')

        -- test that throws an error if wpid is not a valid number
        err = assert.throws(act.waitpid, nil, 'foo')
        assert.match(err, 'wpid must be integer')
    end)))

    -- test that throws an error if called from outside of execution context
    local err = assert.throws(act.waitpid)
    assert.match(err, 'cannot call waitpid() from outside of execution context')
end
