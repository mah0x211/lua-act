require('luacov')
local testcase = require('testcase')
local new_context = require('act.context').new

function testcase.new()
    -- test that create new instance of act.context
    local ctx = assert(new_context())
    assert.match(ctx, '^act%.context: ', false)

    -- test that throws an error if attempt to newindex
    local err = assert.throws(function()
        ctx.foo = 'bar'
    end)
    assert.match(err, 'attempt to protected value')
end

function testcase.renew()
    local ctx = assert(new_context())

    -- test that renew registered events
    assert.is_true(ctx:renew())

    -- test that renew method can be called any time
    assert.is_true(ctx:renew())
end

function testcase.pushq()
    local ctx = assert(new_context())

    -- test that push a callee to internal run-q
    local res = {}
    local callee = {
        call = function()
            res[#res + 1] = 'called'
        end,
    }
    ctx:pushq(callee)
    assert.equal(ctx.runq:len(), 1)
    ctx.runq:consume()
    assert.equal(ctx.runq:len(), 0)
    assert.equal(res, {
        'called',
    })
end

function testcase.cidset()
    local ctx = assert(new_context())

    -- test that allocate cid from cidset
    local list = {
        assert(ctx:cid_alloc()),
    }
    for i = 2, 4500 do
        list[i] = assert(ctx:cid_alloc())
        assert.equal(list[i], list[i - 1] + 1)
    end

    -- test that free cid to cidset
    for i = 2, 100, 2 do
        assert(ctx:cid_free(list[i]))
    end

    -- test that return unused cid
    for i = 2, 100, 2 do
        list[i] = assert(ctx:cid_alloc())
        assert.equal(list[i], list[i - 1] + 1)
    end
end
