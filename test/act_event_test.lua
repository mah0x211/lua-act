local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local new_socketpair = require('testcase.socketpair')
local error = require('error')
local errno = require('errno')
local act = require('act')

local SOCKPAIR

local function socketpair()
    collectgarbage('collect')
    SOCKPAIR = {
        new_socketpair(true),
    }
    return SOCKPAIR[1], SOCKPAIR[2]
end

function testcase.after_each()
    for _, sock in ipairs(SOCKPAIR or {}) do
        sock:close()
    end
end

function testcase.readable_event()
    local sock, peer = socketpair()

    -- test that wait until fd is readable
    assert(act.run(with_luacov(function()
        local wait = false
        local cid = act.spawn(with_luacov(function()
            wait = true
            local evid = assert(act.new_readable_event(sock:fd()))
            assert(act.wait_event(evid, 50))
            assert(act.dispose_event(evid))
            wait = false
            return sock:read()
        end))

        act.later()
        assert.is_true(wait)
        peer:write('hello world!')
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            status = 'ok',
            result = {
                'hello world!',
            },
        })
    end)))

    -- test that fail by timeout
    assert(act.run(with_luacov(function()
        local evid = assert(act.new_readable_event(sock:fd()))
        local ok, err, timeout = act.wait_event(evid, 50)
        assert.is_false(ok)
        assert.is_nil(err)
        assert.is_true(timeout)
    end)))

    -- test that returns error if fd is invalid
    assert(act.run(with_luacov(function()
        local evid, err = act.new_readable_event(123456789)
        assert.is_nil(evid)
        assert(error.is(err, errno.EBADF))
    end)))

    -- test that returns operation already in progress error
    assert(act.run(with_luacov(function()
        act.spawn(with_luacov(function()
            local evid, err = act.new_readable_event(sock:fd())
            assert.is_nil(evid)
            assert.equal(err, 'operation already in progress')
        end))

        local evid = assert(act.new_readable_event(sock:fd()))
        act.later()
        act.dispose_event(evid)
    end)))

    -- test that throws an error if fd is invalid
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.new_readable_event, 'foo')
        assert.match(err, 'fd must be unsigned integer')
    end)))

    -- test that throws an error if called from outside of execution context
    local err = assert.throws(act.new_readable_event, -1)
    assert.match(err, 'outside of execution')
end

function testcase.writable_event()
    local sock, _ = socketpair()

    -- test that wait until fd is writable
    assert(act.run(with_luacov(function()
        local evid = assert(act.new_writable_event(sock:fd()))
        local ok, err, timeout = act.wait_event(evid, 50)
        assert.is_true(ok)
        assert.is_nil(err)
        assert.is_nil(timeout)
    end)))

    -- test that fail by timeout
    assert(sock:sendbuf(5))
    local msg = string.rep('x', sock:sendbuf())
    while sock:write(msg) == #msg do
    end
    assert(act.run(with_luacov(function()
        local evid = assert(act.new_writable_event(sock:fd()))
        local ok, err, timeout = act.wait_event(evid, 50)
        assert.is_false(ok)
        assert.is_nil(err)
        assert.is_true(timeout)
    end)))

    -- test that returns error if fd is invalid
    assert(act.run(with_luacov(function()
        local evid, err = act.new_writable_event(123456789)
        assert.is_nil(evid)
        assert(error.is(err, errno.EBADF))
    end)))

    -- test that returns operation already in progress error
    assert(act.run(with_luacov(function()
        act.spawn(with_luacov(function()
            local evid, err = assert(act.new_writable_event(sock:fd()))
            assert.is_nil(evid)
            assert.equal(err, 'operation already in progress')
        end))

        local evid = assert(act.new_writable_event(sock:fd()))
        act.later()
        act.dispose_event(evid)
    end)))

    -- test that throws an error if fd is invalid
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.new_writable_event, 'foo')
        assert.match(err, 'fd must be unsigned integer')
    end)))

    -- test that throws an error if called from outside of execution context
    local err = assert.throws(act.new_writable_event, -1)
    assert.match(err, 'outside of execution')
end

function testcase.wait_event()
    -- test that throws an error if evid is invalid
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.wait_event, 123)
        assert.match(err, 'evid must be string')
    end)))

    -- test that throws an error if msec is invalid
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.wait_event, 'foo', 'bar')
        assert.match(err, 'msec must be unsigned integer')
    end)))

    -- test that throws an error if called from outside of execution context
    local err = assert.throws(act.wait_event, -1)
    assert.match(err, 'outside of execution')
end

function testcase.dispose_event()
    -- test that throws an error if evid is invalid
    assert(act.run(with_luacov(function()
        local err = assert.throws(act.dispose_event, 123)
        assert.match(err, 'evid must be string')
    end)))

    -- test that throws an error if called from outside of execution context
    local err = assert.throws(act.dispose_event, -1)
    assert.match(err, 'outside of execution')
end
