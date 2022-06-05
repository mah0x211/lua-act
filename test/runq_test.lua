require('luacov')
local testcase = require('testcase')
local runq = require('act.runq')

function testcase.new()
    -- test that create new runq
    local q = runq.new()
    assert.equal(q:len(), 0)
    assert.equal(q.ref, {})
end

function testcase.push()
    local q = runq.new()

    -- test that push callee to runq
    assert(q:push({
        call = function()
        end,
    }, 1))
    assert(q:push({
        call = function()
        end,
    }, 2))
    assert.equal(q:len(), 2)

    -- test that callee must has a function in call field
    local ok, err = q:push({})
    assert.is_false(ok)
    assert.match(err, 'callee must have a call method')

    -- test that callee must has a function in call field
    ok, err = q:push({
        call = function()

        end,
    }, -1)
    assert.is_false(ok)
    assert.match(err, 'msec must be unsigned integer')
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
    assert.equal(q:consume(), -1)
    assert.equal(q.ref, {})
    assert.equal(res, {
        'a',
        'b',
        'c',
    })
end

