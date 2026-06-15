local testcase = require('testcase')
local assert = require('assert')
local stack = require('act.stack')

function testcase.new_empty_and_tostring()
    local s = stack()
    assert.match(tostring(s), 'act.stack: 0x', false)
    assert.equal(#s, 0)
end

function testcase.new_with_initial_values()
    local s = stack('a', 'b', 'c')
    assert.equal(#s, 3)
    -- values are taken in order; pop returns the last pushed
    assert.equal(s:pop(), 'c')
    assert.equal(s:pop(), 'b')
    assert.equal(s:pop(), 'a')
    assert.equal(#s, 0)
end

function testcase.push_pop()
    local s = stack()
    s:push('x', 'y', 'z')
    assert.equal(#s, 3)
    assert.equal(s:pop(), 'z')
    assert.equal(s:pop(), 'y')
    assert.equal(s:pop(), 'x')
end

function testcase.pop_when_empty_returns_nothing()
    local s = stack()
    assert.equal(select('#', s:pop()), 0)
end

function testcase.push_with_no_args_is_noop()
    local s = stack('a')
    s:push()
    assert.equal(#s, 1)
end

function testcase.unshift_prepends_to_head()
    local s = stack('b', 'c')
    s:unshift('a0', 'a1')
    -- head is now a0,a1,b,c -> pop yields c,b,a1,a0
    assert.equal(s:pop(), 'c')
    assert.equal(s:pop(), 'b')
    assert.equal(s:pop(), 'a1')
    assert.equal(s:pop(), 'a0')
end

function testcase.unshift_with_no_args_is_noop()
    local s = stack('a', 'b')
    s:unshift()
    assert.equal(#s, 2)
end

function testcase.insert_at_head()
    local s = stack('b', 'c')
    -- idx <= 1 prepends
    s:insert(1, 'a0', 'a1')
    assert.equal(s:pop(), 'c')
    assert.equal(s:pop(), 'b')
    assert.equal(s:pop(), 'a1')
    assert.equal(s:pop(), 'a0')
end

function testcase.insert_at_middle()
    local s = stack('a', 'b', 'c', 'd')
    -- insert at idx=2 within current length
    s:insert(2, 'X', 'Y')
    assert.equal(#s, 6)
end

function testcase.insert_beyond_length_appends()
    local s = stack('a', 'b')
    -- idx > tail and not <=1: extra args are still appended at the tail
    s:insert(99, 'X')
    assert.equal(#s, 3)
    assert.equal(s:pop(), 'X')
end

function testcase.insert_with_no_extra_args_is_noop()
    local s = stack('a', 'b')
    s:insert(1)
    assert.equal(#s, 2)
end

function testcase.set_replaces_contents()
    local s = stack('a', 'b', 'c')
    s:set('x', 'y')
    assert.equal(#s, 2)
    assert.equal(s:pop(), 'y')
    assert.equal(s:pop(), 'x')
end

function testcase.set_with_no_args_clears()
    local s = stack('a', 'b')
    s:set()
    assert.equal(#s, 0)
end

function testcase.clear_returns_all_values()
    local s = stack('a', 'b', 'c')
    local a, b, c = s:clear()
    assert.equal(a, 'a')
    assert.equal(b, 'b')
    assert.equal(c, 'c')
    assert.equal(#s, 0)
end

function testcase.clear_with_args_appends_then_returns_all()
    local s = stack('a')
    local a, b, c = s:clear('b', 'c')
    assert.equal(a, 'a')
    assert.equal(b, 'b')
    assert.equal(c, 'c')
    assert.equal(#s, 0)
end

function testcase.clear_when_empty_returns_nothing()
    local s = stack()
    assert.equal(select('#', s:clear()), 0)
end

function testcase.gc_cleanup()
    stack('a', 'b', 'c')
    collectgarbage('collect')
    collectgarbage('collect')
end
