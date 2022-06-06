require('luacov')
local testcase = require('testcase')
local pipe = require('act.pipe')

function testcase.new()
    -- test that create new pipe
    local p = assert(pipe.new())
    assert.match(p, '^act.pipe: ', false)
end
