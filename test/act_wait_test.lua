local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local nanotime = require('testcase.timer').nanotime
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

function testcase.wait_readable_writable()
    local sock, peer = socketpair()

    -- test that wait until fd is readable
    assert(act.run(with_luacov(function()
        local wait = false
        local cid = act.spawn(with_luacov(function()
            wait = true
            assert(act.wait_readable(sock:fd(), 50))
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

    -- test that wait until fd is writable
    assert(act.run(with_luacov(function()
        local ok, err, timeout = act.wait_writable(sock:fd(), 50)
        assert.is_true(ok)
        assert.is_nil(err)
        assert.is_nil(timeout)
    end)))

    -- test that fail by timeout
    assert(sock:sendbuf(5))
    local msg = string.rep('x', sock:sendbuf())
    while sock:write(msg) == #msg do
    end
    for _, waitfn in ipairs({
        act.wait_readable,
        act.wait_writable,
    }) do
        assert(act.run(with_luacov(function()
            local ok, err, timeout = waitfn(sock:fd(), 50)
            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_true(timeout)
        end)))
    end

    -- test that returns error if fd is invalid
    for _, waitfn in ipairs({
        act.wait_readable,
        act.wait_writable,
    }) do
        assert(act.run(with_luacov(function()
            local ok, err, timeout = waitfn(123456789, 50)
            assert.is_false(ok)
            assert(error.is(err, errno.EBADF))
            assert.is_nil(timeout)
        end)))
    end

    -- test that returns operation already in progress error
    for _, waitfn in ipairs({
        act.wait_readable,
        act.wait_writable,
    }) do
        local wait = false
        assert(act.run(with_luacov(function()
            local cid = act.spawn(with_luacov(function()
                wait = true
                local ok, err, timeout = waitfn(sock:fd(), 50)
                wait = false
                assert.is_false(ok)
                assert.is_nil(err)
                assert.is_true(timeout)
            end))

            act.later()
            assert.is_true(wait)
            local ok, err, timeout = waitfn(sock:fd(), 50)
            assert.is_false(ok)
            assert.match(err, 'EALREADY')
            assert.is_nil(timeout)
            assert.equal(act.await(), {
                cid = cid,
                status = 'ok',
                result = {},
            })
        end)))
    end
end

function testcase.unwait_readable_writable()
    local sock, _ = socketpair()
    assert(sock:sendbuf(5))
    local msg = string.rep('x', sock:sendbuf())
    while sock:write(msg) == #msg do
    end

    -- test that cancel wait_readable by unwait_readable
    assert(act.run(with_luacov(function()
        local wait = false
        local cid = act.spawn(with_luacov(function()
            wait = true
            local elapsed = nanotime()
            local ok, err, timeout = act.wait_readable(sock:fd(), 50)
            elapsed = (nanotime() - elapsed) * 1000
            wait = false
            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
            assert.less(elapsed, 10)
        end))

        act.later()
        assert.is_true(wait)
        act.unwait_readable(sock:fd())
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            status = 'ok',
            result = {},
        })
    end)))

    -- test that cancel wait_writable by unwait_writable func
    assert(act.run(with_luacov(function()
        local wait = false
        local cid = act.spawn(with_luacov(function()
            wait = true
            local ok, err, timeout = act.wait_writable(sock:fd(), 50)
            wait = false
            assert.is_false(ok)
            assert.is_nil(err)
            assert.is_nil(timeout)
        end))

        act.later()
        assert.is_true(wait)
        act.unwait_writable(sock:fd())
        local res = assert(act.await())
        assert.equal(res, {
            cid = cid,
            status = 'ok',
            result = {},
        })
    end)))

    -- test that cancel wait_readable and wait_writable by unwait
    for _, waitfn in ipairs({
        act.wait_readable,
        act.wait_writable,
    }) do
        assert(act.run(with_luacov(function()
            local wait = false
            local cid = act.spawn(with_luacov(function()
                wait = true
                local ok, err, timeout = waitfn(sock:fd(), 50)
                wait = false
                assert.is_false(ok)
                assert.is_nil(err)
                assert.is_nil(timeout)
            end))

            act.later()
            assert.is_true(wait)
            act.unwait(sock:fd())
            local res = assert(act.await())
            assert.equal(res, {
                cid = cid,
                status = 'ok',
                result = {},
            })
        end)))
    end
end

function testcase.wait_fails_on_shutdown()
    -- test that fail on shutdown
    for _, waitfn in ipairs({
        act.wait_readable,
        act.wait_writable,
    }) do
        assert(act.run(with_luacov(function()
            local sock, _ = socketpair()
            assert(sock:sendbuf(5))
            local msg = string.rep('x', sock:sendbuf())
            while sock:write(msg) == #msg do
            end

            local wait = false
            local cid = act.spawn(with_luacov(function()
                wait = true
                local ok, err, timeout = waitfn(sock:fd(), 50)
                wait = false
                assert.is_true(ok)
                assert.is_nil(err)
                assert.is_nil(timeout)
                if waitfn == act.wait_readable then
                    return sock:read()
                end
                return sock:write('hello')
            end))

            act.later()
            assert.is_true(wait)
            sock:shutdown()
            local res = assert(act.await())
            assert.equal(res.cid, cid)

            if waitfn == act.wait_readable then
                assert.equal(res.result, {})
            else
                assert.equal(res.result, {
                    [2] = errno.EPIPE.message,
                })
            end
        end)))
    end
end

function testcase.wait_unwait_throws_error_for_invalid_arguments()
    -- test that throws an error if argument is invalid
    for _, waitfn in ipairs({
        act.wait_readable,
        act.wait_writable,
    }) do
        assert(act.run(with_luacov(function()
            local err = assert.throws(waitfn, -1)
            assert.match(err, 'fd must be unsigned integer')

            err = assert.throws(waitfn, 0, -1)
            assert.match(err, 'msec must be unsigned integer')
        end)))
    end

    -- test that throws an error if argument is invalid
    for _, unwaitfn in ipairs({
        act.unwait_readable,
        act.unwait_writable,
        act.unwait,
    }) do
        assert(act.run(with_luacov(function()
            local err = assert.throws(unwaitfn, -1)
            assert.match(err, 'fd must be unsigned integer')
        end)))
    end
end

function testcase.wait_throws_error_for_outside_of_execution_context()
    for _, fn in ipairs({
        act.wait_readable,
        act.wait_writable,
    }) do
        -- test that throws an error if called from outside of execution context
        local err = assert.throws(fn)
        assert.match(err, 'outside of execution')
    end
end

function testcase.unwait_did_not_throws_error_for_outside_of_execution_context()
    for _, fn in ipairs({
        act.unwait_readable,
        act.unwait_writable,
        act.unwait,
    }) do
        -- test that throws an error if called from outside of execution context
        assert.is_false(fn(1))
    end
end

