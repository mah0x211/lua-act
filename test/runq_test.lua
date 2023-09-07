require('luacov')
local testcase = require('testcase')
local runq = require('act.runq')
local gettime = require('time.clock').gettime

function testcase.new()
    -- test that create new runq
    local q = runq.new()
    assert.equal(q:len(), 0)

    -- test that throws an error if attempt to newindex
    local err = assert.throws(function()
        q.foo = 'bar'
    end)
    assert.match(err, 'attempt to protected value')
end

function testcase.push()
    local q = runq.new()

    -- test that push callee to runq
    local callee = {
        call = function()
        end,
    }
    q:push(callee, 1)
    q:push({
        call = function()
        end,
    }, 2)
    assert.equal(q:len(), 2)

    -- test that cannot add same callee
    local err = assert.throws(q.push, q, callee, 1)
    assert.match(err, 'callee is already registered')

    -- test that callee must has a function in call field
    err = assert.throws(q.push, q, {})
    assert.match(err, 'callee must have a call method')

    -- test that sec must be unsigned number
    err = assert.throws(q.push, q, {
        call = function()
        end,
    }, -1)
    assert.match(err, 'sec must be unsigned number or nil')
end

function testcase.remove()
    local q = runq.new()
    local a = {
        call = function()
        end,
    }
    local b = {
        call = function()
        end,
    }
    q:push(a)
    q:push(b)

    -- test that remove the pushed callees
    q:remove(a)
    assert.equal(q:len(), 1)
    q:remove(b)
    assert.equal(q:len(), 0)
end

function testcase.consume()
    local q = runq.new()
    local res = {}
    local a = {
        call = function()
            res[1] = 'a'
        end,
    }
    local b = {
        call = function()
            res[2] = 'b'
        end,
    }
    local c = {
        call = function()
            res[3] = 'c'
        end,
    }
    q:push(a)
    q:push(b)
    q:push(c)

    -- test that invoking the callee.call method
    local sec = q:consume()
    while sec ~= -1 do
        sec = q:consume()
    end
    assert.equal(res, {
        'a',
        'b',
        'c',
    })

    -- test that returns remaining msec
    q:push(a, 0.1)
    assert.less_or_equal(q:consume(), 0.1)
end

function testcase.sleep()
    local q = runq.new()
    local callee = {
        call = function()
        end,
    }

    -- test that return immdiately if no executable callee in run-q
    local t = gettime()
    assert.is_true(q:sleep())
    t = gettime() - t
    assert.greater_or_equal(t, 0.0)
    assert.less_or_equal(t, 0.001)

    -- test that return immdiately if executable callee is in run-q
    q:push(callee)
    t = gettime()
    assert.is_true(q:sleep())
    t = gettime() - t
    assert.greater_or_equal(t, 0.0)
    assert.less_or_equal(t, 0.001)
    q:consume()

    -- test that sleep until callee is ready to execute
    q:push(callee, 0.1)
    t = gettime()
    assert.is_true(q:sleep())
    t = gettime() - t
    assert.greater_or_equal(t, 0.09)
    assert.less(t, 0.11)
end

