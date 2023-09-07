require('luacov')
local testcase = require('testcase')
local aux = require('act.aux')

function testcase.is_unsigned()
    -- test that true if argument is uint
    assert.is_true(aux.is_unsigned(1.0))

    -- test that false if argument is not uint
    for _, v in ipairs({
        'foo',
        -1,
        -1.1,
        true,
        false,
        {},
        function()
        end,
    }) do
        assert.is_false(aux.is_unsigned(v))
    end
end

function testcase.is_int()
    -- test that true if argument is uint
    assert.is_true(aux.is_int(1))

    -- test that false if argument is not uint
    for _, v in ipairs({
        'foo',
        -1.12,
        1.1,
        true,
        false,
        {},
        function()
        end,
    }) do
        assert.is_false(aux.is_int(v))
    end
end

function testcase.is_uint()
    -- test that true if argument is uint
    assert.is_true(aux.is_uint(1))

    -- test that false if argument is not uint
    for _, v in ipairs({
        'foo',
        -1,
        1.1,
        true,
        false,
        {},
        function()
        end,
    }) do
        assert.is_false(aux.is_uint(v))
    end
end

function testcase.concat()
    local func = function()
    end
    local tbl = {}

    -- test that table
    assert.equal(aux.concat({
        1,
        true,
        false,
        func,
        'foo',
        tbl,
    }), table.concat({
        '1',
        'true',
        'false',
        tostring(func),
        'foo',
        tostring(tbl),
    }))
end

