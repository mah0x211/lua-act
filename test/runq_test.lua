require('luacov')
local testcase = require('testcase')
local runq = require('act.runq')
local getmsec = require('act.hrtimer').getmsec

function testcase.new()
    -- test that create new runq
    local q = runq.new()
    assert.equal(q:len(), 0)
    assert.equal(q.ref, {})

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
    assert(q:push(callee, 1))
    assert(q:push({
        call = function()
        end,
    }, 2))
    assert.equal(q:len(), 2)

    -- test that cannot add same callee
    local ok, err = q:push(callee, 1)
    assert.is_false(ok)
    assert.match(err, 'callee is already registered')

    -- test that callee must has a function in call field
    ok, err = q:push({})
    assert.is_false(ok)
    assert.match(err, 'callee must have a call method')

    -- test that callee must has a function in call field
    err = assert.throws(q.push, q, {
        call = function()
        end,
    }, -1)
    assert.match(err, 'unsigned integer expected')
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
    assert(q:push(a))
    assert(q:push(b))

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
    local msec = q:consume()
    if msec == 0 then
        msec = q:consume()
    end
    assert.equal(msec, -1)
    assert.equal(q.ref, {})
    assert.equal(res, {
        'a',
        'b',
        'c',
    })

    -- test that returns remaining msec
    q:push(a, 100)
    assert.less_or_equal(q:consume(), 100)
end

function testcase.sleep()
    local q = runq.new()
    local callee = {
        call = function()
        end,
    }

    -- test that return immdiately if no executable callee in run-q
    local t = getmsec()
    assert.is_true(q:sleep())
    t = getmsec() - t
    assert.greater_or_equal(t, 0)
    assert.less_or_equal(t, 1)

    -- test that return immdiately if executable callee is in run-q
    assert.is_true(q:push(callee))
    t = getmsec()
    assert.is_true(q:sleep())
    t = getmsec() - t
    assert.greater_or_equal(t, 0)
    assert.less_or_equal(t, 1)
    q:consume()

    -- test that sleep until callee is ready to execute
    assert.is_true(q:push(callee, 100))
    t = getmsec()
    assert.is_true(q:sleep())
    t = getmsec() - t
    assert.greater_or_equal(t, 90)
    assert.less(t, 110)
end

