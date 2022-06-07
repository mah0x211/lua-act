local testcase = require('testcase')
local getcpus = require('act.getcpus')

function testcase.new()
    -- test that return number of cpus
    local ncpu = getcpus()
    assert.greater(ncpu, 0)
end
