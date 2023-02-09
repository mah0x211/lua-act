require('luacov')
local testcase = require('testcase')
local aux = require('act.aux')

function testcase.is_str()
    -- test that true if argument is string
    assert.is_true(aux.is_str('foo'))

    -- test that false if argument is not string
    for _, v in ipairs({
        1,
        true,
        false,
        {},
        function()
        end,
    }) do
        assert.is_false(aux.is_str(v))
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

function testcase.is_func()
    -- test that true if argument is function
    assert.is_true(aux.is_func(function()
    end))

    -- test that false if argument is not uint
    for _, v in ipairs({
        'foo',
        -1,
        0,
        1.1,
        true,
        false,
        {},
    }) do
        assert.is_false(aux.is_func(v))
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

