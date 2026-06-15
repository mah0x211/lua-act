local testcase = require('testcase')
local assert = require('assert')
local bitset = require('act.bitset')

function testcase.new_and_tostring()
    local bs = bitset()
    assert.match(tostring(bs), 'act.bitset: 0x', false)
end

function testcase.get_set_unset()
    local bs = bitset()
    -- initial value is 0
    assert.is_false(bs:get(0))
    assert.is_false(bs:get(100))
    -- set then get returns 1
    assert.is_true(bs:set(10))
    assert.is_true(bs:get(10))
    -- unset then get returns 0
    assert.is_true(bs:unset(10))
    assert.is_false(bs:get(10))
end

function testcase.set_resizes_when_pos_exceeds_capacity()
    local bs = bitset()
    -- initial capacity is 4096 bits, set beyond it triggers resize
    assert.is_true(bs:set(8192))
    assert.is_true(bs:get(8192))
    assert.is_false(bs:get(8000))
end

function testcase.get_out_of_range_returns_error()
    local bs = bitset()
    -- get does not resize; out-of-range returns nil + ERANGE message
    local v, err, errno = bs:get(1000000)
    assert.is_nil(v)
    assert.is_string(err)
    assert.greater(errno, 0)
end

function testcase.unset_out_of_range_returns_error()
    local bs = bitset()
    -- unset does not resize; out-of-range returns nil + ERANGE message
    local ok, err, errno = bs:unset(1000000)
    assert.is_nil(ok)
    assert.is_string(err)
    assert.greater(errno, 0)
end

function testcase.ffz_empty_partial_full()
    local bs = bitset()
    -- empty: first zero is position 0
    assert.equal(bs:ffz(), 0)
    -- after setting bit 0, first zero is 1
    bs:set(0)
    assert.equal(bs:ffz(), 1)
    -- after setting bit 1, first zero is 2
    bs:set(1)
    assert.equal(bs:ffz(), 2)
end

function testcase.ffz_returns_capacity_when_full()
    local bs = bitset()
    for pos = 0, 4095 do
        bs:set(pos)
    end
    -- when bitset is fully set, ffz reports nbit (no zero bit found)
    assert.equal(bs:ffz(), 4096)
end

function testcase.add_returns_consecutive_positions()
    local bs = bitset()
    assert.equal(bs:add(), 0)
    assert.equal(bs:add(), 1)
    assert.equal(bs:add(), 2)
    bs:unset(1)
    -- next add reuses freed position
    assert.equal(bs:add(), 1)
    assert.equal(bs:add(), 3)
end

function testcase.add_grows_beyond_initial_capacity()
    local bs = bitset()
    -- exhaust initial capacity
    for _ = 0, 4095 do
        bs:add()
    end
    -- next add must trigger resize and succeed
    assert.equal(bs:add(), 4096)
    assert.is_true(bs:get(4096))
end

function testcase.gc_cleanup()
    local bs = bitset()
    bs:set(0)
    bs = nil -- luacheck: ignore 311
    collectgarbage('collect')
    collectgarbage('collect')
end
