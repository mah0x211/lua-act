require('luacov')
local testcase = require('testcase')
local new_event = require('act.event').new

function testcase.new()
    -- test that create event
    local event = new_event()
    assert.match(event, '^act.event: 0x%x+$', false)

    -- test that cache_enabled is false by default
    assert.is_false(event.cache_enabled)

    -- test that create event with cache_enabled
    event = new_event(true)
    assert.is_true(event.cache_enabled)

    -- test that create event with invalid cache_enabled
    local err = assert.throws(new_event, 'foo')
    assert.match(err, 'cache_enabled must be boolean or nil', false)
end

function testcase.register()
    local callee = {}

    -- test that register oneshot event
    local event = new_event()
    local evinfo, err, is_ready = event:register(callee, 'readable', 0,
                                                 'oneshot')
    assert.is_nil(err)
    assert.is_nil(is_ready)
    assert.equal(evinfo, {
        asa = 'readable',
        val = 0,
        trigger = 'oneshot',
        callee = callee,
        ev = evinfo.ev,
    })

    -- test that cannot register fd twice with different trigger
    evinfo, err, is_ready = event:register(callee, 'readable', 0, 'edge')
    assert.is_nil(evinfo)
    assert.match(err, 'EEXIST')
    assert.is_nil(is_ready)

    event:revoke('readable', 0)

    -- test that register edge-triggered event
    evinfo, err, is_ready = event:register(callee, 'readable', 0, 'edge')
    assert.is_nil(err)
    assert.is_nil(is_ready)
    assert.equal(evinfo, {
        asa = 'readable',
        val = 0,
        trigger = 'edge',
        callee = callee,
        ev = evinfo.ev,
    })

    -- test that return cached event if event is already registered
    local cached_evinfo
    cached_evinfo, err, is_ready = event:register(callee, 'readable', 0, 'edge')
    assert.is_nil(err)
    assert.is_nil(is_ready)
    assert.equal(cached_evinfo, evinfo)

    -- test that return is_ready=true and reset is_ready field if event is ready
    evinfo.is_ready = true
    cached_evinfo, err, is_ready = event:register(callee, 'readable', 0, 'edge')
    assert.is_nil(cached_evinfo)
    assert.is_nil(err)
    assert.is_true(is_ready)
    assert.is_nil(evinfo.is_ready)

    event:revoke('readable', 0)
end

function testcase.revoke()
    local callee = {}

    -- test that event will be revoked
    local event = new_event()
    local evinfo = event:register(callee, 'readable', 0)
    assert.equal(evinfo, event.used.readable[0])
    assert.is_true(event:revoke('readable', 0))
    assert.is_nil(event.used.readable[0])

    -- test that return false if event is not registered
    assert.is_false(event:revoke('readable', 0))
end

function testcase.cache()
    local callee = {}

    -- test that event will be revoked if cache_enabled is false
    local event = new_event()
    local evinfo = event:register(callee, 'readable', 0)
    assert.equal(evinfo, event.used.readable[0])
    event:cache('readable', 0)
    assert.is_nil(event.used.readable[0])

    -- test that event will not be revoked if cache_enabled is true
    event = new_event(true)
    evinfo = event:register(callee, 'readable', 0)
    assert.equal(evinfo, event.used.readable[0])
    event:cache('readable', 0)
    assert.equal(evinfo, event.used.readable[0])
    event:revoke('readable', 0)
end

