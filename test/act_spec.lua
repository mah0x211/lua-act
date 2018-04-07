--[[

  test/act_spec.lua
  lua-act
  Created by Masatoshi Teruya on 17/03/18.

--]]
--- file scope variables
local llsocket = require('llsocket')
local signal = require('signal')
local system = require('system')
local act = require('act')


signal.blockAll()


local function socketpair( bufsiz )
    local socks = assert( llsocket.socket.pair(
        llsocket.SOCK_STREAM, true
    ))

    if bufsiz then
        assert( socks[1]:rcvbuf( bufsiz ) )
        assert( socks[2]:sndbuf( bufsiz ) )
    end

    return socks[1], socks[2]
end



describe('test act module:', function()

    describe('test act.run -', function()
        it('fail with a non-function argument', function()
            assert.is_not_true( act.run() )
            assert.is_not_true( act.run(1) )
            assert.is_not_true( act.run('str') )
            assert.is_not_true( act.run({}) )
        end)

        it('success with function argument', function()
            assert.is_true( act.run(function()end) )
        end)

        it('success with function argument and arugments', function()
            assert.is_true( act.run(function( a, b )
                assert( a == 'foo', 'a is unknown argument' )
                assert( b == 'bar', 'b is unknown argument' )
            end, 'foo', 'bar' ) )
        end)

        it('fail when called from the running function', function()
            assert.is_not_true( act.run(function( a, b )
                assert( act.run(function()end) )
            end, 'foo', 'bar' ) )
        end)
    end)


    describe('test act.sleep -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.sleep, 1000 ) )
        end)

        it('fail with invalid deadline', function()
            assert.is_not_true( act.run(function()
                assert( act.sleep( 'str' ) )
            end) )
            assert.is_not_true( act.run(function()
                assert( act.sleep( 1.1 ) )
            end) )
            assert.is_not_true( act.run(function()
                assert( act.sleep( -1 ) )
            end) )
        end)

        it('success with valid deadline', function()
            assert.is_true( act.run(function()
                local deadline = 10
                local elapsed = system.gettime()

                assert( act.sleep( deadline ) )
                elapsed = ( system.gettime() - elapsed ) * 1000 - deadline
                assert( elapsed < 10, 'overslept ' .. tostring( elapsed ) )
            end))
        end)

        it('get up in order of shortest sleep time', function()
            assert.is_true( act.run(function()
                local ok, msg

                act.spawn(function()
                    local ok, err = act.sleep(35)

                    assert( ok == true )
                    assert( err == nil )
                    return 'awake 35'
                end)

                act.spawn(function()
                    local ok, err = act.sleep(10)

                    assert( ok == true )
                    assert( err == nil )
                    return 'awake 10'
                end)

                act.spawn(function()
                    local ok, err = act.sleep(25)

                    assert( ok == true )
                    assert( err == nil )
                    return 'awake 25'
                end)

                act.spawn(function()
                    local ok, err = act.sleep(5)

                    assert( ok == true )
                    assert( err == nil )
                    return 'awake 5'
                end)

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'awake 5' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'awake 10' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'awake 25' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'awake 35' )
            end))
        end)
    end)


    describe('test act.spawn -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.spawn, function()end ) )
        end)

        it('fail with a non-function argument', function()
            assert.is_not_true( act.run(function()
                act.spawn( 1 )
            end))
        end)

        it('success', function()
            assert.is_true( act.run(function()
                local executed = false

                assert( act.spawn(function() executed = true end) )
                act.sleep(0)
                assert( executed, 'child coroutine did not executed' )
            end))
        end)
    end)


    describe('test act.later -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.later ) )
        end)

        it('success', function()
            assert.is_true( act.run(function()
                local executed = false

                act.spawn(function() executed = true end)
                assert( act.later() )
                assert( executed, 'child coroutine did not executed' )
            end))
        end)
    end)


    describe('test act.atexit -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.atexit, function()end ) )
        end)


        it('fail with a non-function argument', function()
            assert.is_not_true( act.run(function()
                assert( act.atexit( 1 ) )
            end))
        end)


        it('should call function', function()
            local executed = false

            assert.is_true( act.run(function()
                assert( act.atexit(function( a, b )
                    assert( a == 'foo' )
                    assert( b == 'bar' )
                    executed = true
                end, 'foo', 'bar' ))
            end))

            assert( executed, 'could not executed' )
        end)


        it('should call functions in reverse order of registration', function()
            local executed = {}
            local count = 3

            assert.is_true( act.run(function()
                assert( act.atexit(function()
                    executed[#executed+1] = count
                    count = count - 1
                end))
                assert( act.atexit(function()
                    executed[#executed+1] = count
                    count = count - 1
                end))
                assert( act.atexit(function()
                    executed[#executed+1] = count
                    count = count - 1
                end))
            end))

            assert( count == 0, 'could not executed' )
            count = 3
            for i = 1, #executed do
                assert(
                    executed[i] == count,
                    'could not executed in reverse order of registration'
                )
                count = count - 1
            end
        end)


        it('should pass a previous error message', function()
            local executed = false

            assert.is_true( act.run(function()
                assert( act.atexit(function( a, b, err )
                    assert( a == 'foo' )
                    assert( b == 'bar' )
                    assert( err:find('hello') )
                    executed = true
                end, 'foo', 'bar' ))

                assert( act.atexit(function()
                    error( 'hello' )
                end))
            end))

            assert( executed, 'could not executed' )
        end)


        it('should return atexit error', function()
            assert.is_true( act.run(function()
                local ok, err, trace

                act.spawn(function()
                    assert( act.atexit(function() error( 'world' ) end))

                    return 'hello'
                end)

                ok, err, trace = act.await()
                assert( ok == false )
                assert( err:find('world') )
                assert( trace:find('traceback') )
            end))
        end)


        it('should return the return values of main function', function()
            assert.is_true( act.run(function()
                local ok, a, b

                act.spawn(function()
                    assert( act.atexit(function( ... ) return ... end))

                    return 'hello', 'world'
                end)

                ok, a, b = act.await()
                assert( ok == true )
                assert( a == 'hello' )
                assert( b == 'world' )
            end))
        end)


        it('should recover the error of main function', function()
            assert.is_true( act.run(function()
                local ok, err, trace

                act.spawn(function()
                    assert( act.atexit(function( a, b, ... )
                        return ...
                    end, 'foo', 'bar' ))

                    error( 'hello' )
                end)

                ok, err, trace = act.await()
                assert( ok == true )
                assert( err:find('hello') )
                assert( trace:find('traceback') )
            end))
        end)

    end)


    describe('test act.await -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.await ) )
        end)

        it('success', function()
            assert.is_true( act.run(function()
                local ok, val

                act.spawn(function() return 'hello' end)
                act.spawn(function() return 'world' end)
                act.spawn(function() return error('error occurred') end)

                ok, val = act.await()
                assert( ok == true )
                assert( val == 'hello' )

                ok, val = act.await()
                assert( ok == true )
                assert( val == 'world' )

                ok, val = act.await()
                assert( not ok )
                assert( val:find('error occurred') )
            end))
        end)
    end)


    describe('test act.exit -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.exit ) )
        end)

        it('success', function()
            assert.is_true( act.run(function()
                local ok, val

                act.spawn(function() return act.exit('hello world!') end)
                ok, val = act.await()
                assert( ok == true )
                assert( val == 'hello world!' )
            end))
        end)
    end)


    describe('test act.waitReadable -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.waitReadable ) )
        end)

        it('fail with invalid arguments', function()
            assert.is_not_true( act.run(function()
                act.waitReadable( -1 )
            end))

            assert.is_not_true( act.run(function()
                assert( act.waitReadable( 0, -1 ) )
            end))
        end)

        it('fail by timeout', function()
            assert.is_true( act.run(function()
                local reader, writer = socketpair()
                local ok, err, timeout = act.waitReadable( reader:fd(), 50 )

                assert( ok == false )
                assert( timeout == true )
            end))
        end)


        it('fail on shutdown', function()
            assert.is_true( act.run(function()
                local reader, writer = socketpair()
                local ok, msg, err, again

                act.spawn(function()
                    local ok, err, timeout = act.waitReadable( reader:fd(), 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    return reader:recv()
                end)

                act.later()
                reader:shutdown( llsocket.SHUT_RDWR )

                ok, msg, err, again = act.await()
                assert( ok == true )
                assert( msg == nil )
                assert( err == nil )
                assert( again == nil )
            end))
        end)


        it('success', function()
            assert.is_true( act.run(function()
                local reader, writer = socketpair()
                local ok, msg

                act.spawn(function()
                    local ok, err, timeout = act.waitReadable( reader:fd(), 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return reader:recv()
                end)

                act.later()
                writer:send( 'hello world!' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'hello world!' )
            end))
        end)
    end)


    describe('test act.waitWritable -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.waitWritable ) )
        end)

        it('fail with invalid arguments', function()
            assert.is_not_true( act.run(function()
                act.waitWritable( -1 )
            end))

            assert.is_not_true( act.run(function()
                assert( act.waitWritable( 0, -1 ) )
            end))
        end)

        it('fail by timeout', function()
            assert.is_true( act.run(function()
                local reader, writer = socketpair( 5 )
                local buflen = writer:sndbuf()
                local chunk = buflen / 99 + 1
                local msg = {}
                local ok

                for i = 1, chunk do
                    msg[i] = ('%099d'):format(0)
                end
                msg = table.concat( msg )

                act.spawn(function()
                    local ok, err, timeout = act.waitWritable( writer:fd(), 50 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                end)

                writer:send( msg )
                act.later()

                ok = act.await()
                assert( ok == true )
            end))
        end)


        it('fail on shutdown', function()
            assert.is_true( act.run(function()
                local reader, writer = socketpair( 5 )
                local ok, len, err, again

                act.spawn(function()
                    local ok, err, timeout = act.waitWritable( writer:fd(), 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    return writer:send( 'hello' )
                end)

                writer:send( 'hello' )
                act.later()
                writer:shutdown( llsocket.SHUT_RDWR )

                ok, len, err, again = act.await()
                assert( ok == true )
                assert( len == nil )
                assert( err == nil )
                assert( again == nil )
            end))
        end)


        it('success', function()
            assert.is_true( act.run(function()
                local reader, writer = socketpair()
                local ok, len

                act.spawn(function()
                    local ok, err, timeout = act.waitWritable( writer:fd(), 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    return writer:send( 'hello' )
                end)

                writer:send( 'hello' )
                act.later()
                assert( reader:recv() == 'hello' )

                ok, len = act.await()
                assert( ok == true )
                assert( len == 5 )
            end))
        end)
    end)


    describe('test act.sigwait -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.sigwait ) )
        end)

        it('fail with invalid arguments', function()
            assert.is_not_true( act.run(function()
                assert( act.sigwait( -1 ) )
            end))

            assert.is_not_true( act.run(function()
                act.sigwait( nil, -1000 )
            end))
        end)

        it('fail by timeout', function()
            assert.is_true( act.run(function()

                act.spawn(function()
                    local signo, err, timeout = act.sigwait(
                        50, signal.SIGUSR1
                    )

                    assert( signo == nil )
                    assert( err == nil )
                    assert( timeout == true )
                end)

                act.later()

                ok = act.await()
                assert( ok == true )
            end))
        end)

        it('success', function()
            assert.is_true( act.run(function()
                assert( signal.block( signal.SIGUSR1 ) )

                act.spawn(function()
                    local signo, err, timeout = act.sigwait(
                        50, signal.SIGUSR1
                    )

                    assert( signo == signal.SIGUSR1 )
                    assert( err == nil )
                    assert( timeout == nil )
                end)

                act.later()
                assert( signal.kill( signal.SIGUSR1 ) )

                ok = act.await()
                assert( ok == true )
            end))
        end)
    end)


    describe('test act.suspend -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.suspend ) )
        end)

        it('timed out', function()
            assert.is_true( act.run(function()
                local ok, val, timeout = act.suspend()

                assert( ok == false )
                assert( val == nil )
                assert( timeout == true )

                ok, val, timeout = act.suspend(100)

                assert( ok == false )
                assert( val == nil )
                assert( timeout == true )
            end))
        end)
    end)


    describe('test act.resume -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.resume ) )
        end)

        it('fail on called with invalid cid', function()
            assert.is_true( act.run(function()
                local ok = act.resume('abc')

                assert( ok == false )
            end))
        end)

        it('success', function()
            assert.is_true( act.run(function()
                local ok, val, timeout;

                act.spawn(function( cid )
                    assert( act.resume( cid, 'hello' ) )
                end, act.getcid())

                ok, val, timeout = act.suspend(1000)
                assert( ok == true )
                assert( val == 'hello' )
                assert( not timeout )
            end))
        end)
    end)


    describe('test act.readLock -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.readLock ) )
        end)

        it('wakes up in order of the shortest timeout', function()
            assert.is_true( act.run(function()
                local reader, writer = socketpair()

                act.spawn(function()
                    local ok, err, timeout = act.readLock( reader:fd(), 30 )

                    act.sleep(30)
                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return 'lock ok 30'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.readLock( reader:fd(), 20 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                    return 'lock timeout 20'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.readLock( reader:fd(), 10 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                    return 'lock timeout 10'
                end)

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock timeout 10' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock timeout 20' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock ok 30' )
            end))
        end)


        it('wakes up in the order of calling the lock function', function()
            assert.is_true( act.run(function()
                local reader, writer = socketpair()

                act.spawn(function()
                    local ok, err, timeout = act.readLock( reader:fd(), 30 )

                    act.sleep(5)
                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return 'lock ok 30'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.readLock( reader:fd(), 20 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return 'lock ok 20'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.readLock( reader:fd(), 10 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return 'lock ok 10'
                end)

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock ok 30' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock ok 20' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock ok 10' )
            end))
        end)


        it('can handle multiple locks at the same time', function()
            assert.is_true( act.run(function()
                local reader1, writer1 = socketpair()
                local reader2, writer2 = socketpair()

                act.spawn(function()
                    local ok, err, timeout

                    ok, err, timeout = act.readLock( reader1:fd(), 30 )
                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    ok, err, timeout = act.readLock( reader2:fd(), 30 )
                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    act.sleep(30)

                    return 'lock 1 and 2 ok 30'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.readLock( reader1:fd(), 20 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                    return 'lock 1 timeout 20'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.readLock( reader2:fd(), 10 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                    return 'lock 2 timeout 10'
                end)

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock 2 timeout 10' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock 1 timeout 20' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock 1 and 2 ok 30' )
            end))
        end)
    end)


    describe('test act.writeLock -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( act.writeLock ) )
        end)

        it('wakes up in order of the shortest timeout', function()
            assert.is_true( act.run(function()
                local reader, writer = socketpair()

                act.spawn(function()
                    local ok, err, timeout = act.writeLock( writer:fd(), 30 )

                    act.sleep(30)
                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return 'lock ok 30'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.writeLock( writer:fd(), 20 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                    return 'lock timeout 20'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.writeLock( writer:fd(), 10 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                    return 'lock timeout 10'
                end)

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock timeout 10' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock timeout 20' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock ok 30' )
            end))
        end)

        it('wakes up in the order of calling the lock function', function()
            assert.is_true( act.run(function()
                local reader, writer = socketpair()

                act.spawn(function()
                    local ok, err, timeout = act.readLock( writer:fd(), 30 )

                    act.sleep(5)
                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return 'lock ok 30'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.readLock( writer:fd(), 20 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return 'lock ok 20'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.readLock( writer:fd(), 10 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return 'lock ok 10'
                end)

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock ok 30' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock ok 20' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock ok 10' )
            end))
        end)

        it('can handle multiple locks at the same time', function()
            assert.is_true( act.run(function()
                local reader1, writer1 = socketpair()
                local reader2, writer2 = socketpair()

                act.spawn(function()
                    local ok, err, timeout

                    ok, err, timeout = act.readLock( writer1:fd(), 30 )
                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    ok, err, timeout = act.readLock( writer2:fd(), 30 )
                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    act.sleep(30)

                    return 'lock 1 and 2 ok 30'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.readLock( writer1:fd(), 20 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                    return 'lock 1 timeout 20'
                end)

                act.spawn(function()
                    local ok, err, timeout = act.readLock( writer2:fd(), 10 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                    return 'lock 2 timeout 10'
                end)

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock 2 timeout 10' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock 1 timeout 20' )

                ok, msg = act.await()
                assert( ok == true )
                assert( msg == 'lock 1 and 2 ok 30' )
            end))
        end)
    end)
end)


