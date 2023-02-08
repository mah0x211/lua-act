local with_luacov = require('luacov').with_luacov
local testcase = require('testcase')
local act_run = require('act').run
local pipe = require('act.pipe')
local gettime = require('act.hrtimer').getmsec
local errno = require('errno')

function testcase.new()
    -- test that create new pipe
    local p = assert(pipe.new())
    assert.match(p, '^act.pipe: ', false)
end

function testcase.read_write()
    assert(act_run(with_luacov(function()
        local p = assert(pipe.new())

        -- test that return again=true if no data available
        local t = gettime()
        local s, err, again = p:read(50)
        t = gettime() - t
        assert.is_nil(s)
        assert.is_nil(err)
        assert.is_true(again)
        assert.greater_or_equal(t, 50)
        assert.less(t, 60)

        -- test that write message to pipe
        local msg = 'hello'
        local n = assert(p:write(msg))
        assert.equal(n, #msg)

        -- test that read message from pipe
        s = assert(p:read())
        assert.equal(s, msg)

        -- test that return again=true if no write buffer available
        while true do
            t = gettime()
            n, err, again = p:write(msg, 50)
            t = gettime() - t
            if n ~= #msg then
                assert.is_nil(err)
                assert.is_true(again)
                assert.greater_or_equal(t, 50)
                assert.less(t, 60)
                break
            end
        end
    end)))
end

function testcase.close()
    assert(act_run(with_luacov(function()
        local p = assert(pipe.new())

        -- test that reader and writer cannot uses after closing the pipe
        p:close()
        local _, err = p:read()
        assert.equal(err.type, errno.EBADF)
        _, err = p:write('hello')
        assert.equal(err.type, errno.EBADF)
    end)))
end
