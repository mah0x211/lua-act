--[[

  test/synops_spec.lua
  lua-synops
  Created by Masatoshi Teruya on 17/03/18.

--]]
--- file scope variables
local llsocket = require('llsocket')
local signal = require('signal')
local system = require('system')
local synops = require('synops')


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



describe('test synops module:', function()

    describe('test synops.run -', function()
        it('fail with a non-function argument', function()
            assert.is_not_true( synops.run() )
            assert.is_not_true( synops.run(1) )
            assert.is_not_true( synops.run('str') )
            assert.is_not_true( synops.run({}) )
        end)

        it('success with function argument', function()
            assert.is_true( synops.run(function()end) )
        end)

        it('success with function argument and arugments', function()
            assert.is_true( synops.run(function( a, b )
                assert( a == 'foo', 'a is unknown argument' )
                assert( b == 'bar', 'b is unknown argument' )
            end, 'foo', 'bar' ) )
        end)

        it('fail when called from the running function', function()
            assert.is_not_true( synops.run(function( a, b )
                assert( synops.run(function()end) )
            end, 'foo', 'bar' ) )
        end)
    end)


    describe('test synops.sleep -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.sleep, 1000 ) )
        end)

        it('fail with invalid deadline', function()
            assert.is_not_true( synops.run(function()
                assert( synops.sleep( 'str' ) )
            end) )
            assert.is_not_true( synops.run(function()
                assert( synops.sleep( 1.1 ) )
            end) )
            assert.is_not_true( synops.run(function()
                assert( synops.sleep( -1 ) )
            end) )
        end)

        it('success with valid deadline', function()
            assert.is_true( synops.run(function()
                local deadline = 10
                local elapsed = system.gettime()

                assert( synops.sleep( deadline ) )
                elapsed = ( system.gettime() - elapsed ) * 1000 - deadline
                assert( elapsed < 10, 'overslept ' .. tostring( elapsed ) )
            end))
        end)
    end)


    describe('test synops.spawn -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.spawn, function()end ) )
        end)

        it('fail with a non-function argument', function()
            assert.is_not_true( synops.run(function()
                synops.spawn( 1 )
            end))
        end)

        it('success', function()
            assert.is_true( synops.run(function()
                local executed = false

                assert( synops.spawn(function() executed = true end) )
                synops.sleep(0)
                assert( executed, 'child coroutine did not executed' )
            end))
        end)
    end)


    describe('test synops.later -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.later ) )
        end)

        it('success', function()
            assert.is_true( synops.run(function()
                local executed = false

                synops.spawn(function() executed = true end)
                assert( synops.later() )
                assert( executed, 'child coroutine did not executed' )
            end))
        end)
    end)


    describe('test synops.atexit -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.atexit, function()end ) )
        end)


        it('fail with a non-function argument', function()
            assert.is_not_true( synops.run(function()
                assert( synops.atexit( 1 ) )
            end))
        end)


        it('should call function', function()
            local executed = false

            assert.is_true( synops.run(function()
                assert( synops.atexit(function( a, b )
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

            assert.is_true( synops.run(function()
                assert( synops.atexit(function()
                    executed[#executed+1] = count
                    count = count - 1
                end))
                assert( synops.atexit(function()
                    executed[#executed+1] = count
                    count = count - 1
                end))
                assert( synops.atexit(function()
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

            assert.is_true( synops.run(function()
                assert( synops.atexit(function( a, b, err )
                    assert( a == 'foo' )
                    assert( b == 'bar' )
                    assert( err:find('hello') )
                    executed = true
                end, 'foo', 'bar' ))

                assert( synops.atexit(function()
                    error( 'hello' )
                end))
            end))

            assert( executed, 'could not executed' )
        end)


        it('should return atexit error', function()
            assert.is_true( synops.run(function()
                local ok, err, trace

                synops.spawn(function()
                    assert( synops.atexit(function() error( 'world' ) end))

                    return 'hello'
                end)

                ok, err, trace = synops.await()
                assert( ok == false )
                assert( err:find('world') )
                assert( trace:find('traceback') )
            end))
        end)


        it('should return the return values of main function', function()
            assert.is_true( synops.run(function()
                local ok, a, b

                synops.spawn(function()
                    assert( synops.atexit(function( ... ) return ... end))

                    return 'hello', 'world'
                end)

                ok, a, b = synops.await()
                assert( ok == true )
                assert( a == 'hello' )
                assert( b == 'world' )
            end))
        end)


        it('should recover the error of main function', function()
            assert.is_true( synops.run(function()
                local ok, err, trace

                synops.spawn(function()
                    assert( synops.atexit(function( a, b, ... )
                        return ...
                    end, 'foo', 'bar' ))

                    error( 'hello' )
                end)

                ok, err, trace = synops.await()
                assert( ok == true )
                assert( err:find('hello') )
                assert( trace:find('traceback') )
            end))
        end)

    end)


    describe('test synops.await -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.await ) )
        end)

        it('success', function()
            assert.is_true( synops.run(function()
                local ok, val

                synops.spawn(function() return 'hello' end)
                synops.spawn(function() return 'world' end)
                synops.spawn(function() return error('error occurred') end)

                ok, val = synops.await()
                assert( ok == true )
                assert( val == 'hello' )

                ok, val = synops.await()
                assert( ok == true )
                assert( val == 'world' )

                ok, val = synops.await()
                assert( not ok )
                assert( val:find('error occurred') )
            end))
        end)
    end)


    describe('test synops.exit -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.exit ) )
        end)

        it('success', function()
            assert.is_true( synops.run(function()
                local ok, val

                synops.spawn(function() return synops.exit('hello world!') end)
                ok, val = synops.await()
                assert( ok == true )
                assert( val == 'hello world!' )
            end))
        end)
    end)


    describe('test synops.readable -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.readable ) )
        end)

        it('fail with invalid arguments', function()
            assert.is_not_true( synops.run(function()
                synops.readable( -1 )
            end))

            assert.is_not_true( synops.run(function()
                assert( synops.readable( 0, -1 ) )
            end))
        end)

        it('fail by timeout', function()
            assert.is_true( synops.run(function()
                local reader, writer = socketpair()
                local ok, err, timeout = synops.readable( reader:fd(), 50 )

                assert( ok == false )
                assert( timeout == true )
            end))
        end)


        it('fail on shutdown', function()
            assert.is_true( synops.run(function()
                local reader, writer = socketpair()
                local ok, msg, err, again

                synops.spawn(function()
                    local ok, err, timeout = synops.readable( reader:fd(), 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    return reader:recv()
                end)

                synops.later()
                reader:shutdown( llsocket.SHUT_RDWR )

                ok, msg, err, again = synops.await()
                assert( ok == true )
                assert( msg == nil )
                assert( err == nil )
                assert( again == nil )
            end))
        end)


        it('success', function()
            assert.is_true( synops.run(function()
                local reader, writer = socketpair()
                local ok, msg

                synops.spawn(function()
                    local ok, err, timeout = synops.readable( reader:fd(), 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return reader:recv()
                end)

                synops.later()
                writer:send( 'hello world!' )

                ok, msg = synops.await()
                assert( ok == true )
                assert( msg == 'hello world!' )
            end))
        end)
    end)


    describe('test synops.writable -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.writable ) )
        end)

        it('fail with invalid arguments', function()
            assert.is_not_true( synops.run(function()
                synops.writable( -1 )
            end))

            assert.is_not_true( synops.run(function()
                assert( synops.writable( 0, -1 ) )
            end))
        end)

        it('fail by timeout', function()
            assert.is_true( synops.run(function()
                local reader, writer = socketpair( 5 )
                local buflen = writer:sndbuf()
                local chunk = buflen / 99 + 1
                local msg = {}
                local ok

                for i = 1, chunk do
                    msg[i] = ('%099d'):format(0)
                end
                msg = table.concat( msg )

                synops.spawn(function()
                    local ok, err, timeout = synops.writable( writer:fd(), 50 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                end)

                writer:send( msg )
                synops.later()

                ok = synops.await()
                assert( ok == true )
            end))
        end)


        it('fail on shutdown', function()
            assert.is_true( synops.run(function()
                local reader, writer = socketpair( 5 )
                local ok, len, err, again

                synops.spawn(function()
                    local ok, err, timeout = synops.writable( writer:fd(), 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    return writer:send( 'hello' )
                end)

                writer:send( 'hello' )
                synops.later()
                writer:shutdown( llsocket.SHUT_RDWR )

                ok, len, err, again = synops.await()
                assert( ok == true )
                assert( len == nil )
                assert( err == nil )
                assert( again == nil )
            end))
        end)


        it('success', function()
            assert.is_true( synops.run(function()
                local reader, writer = socketpair()
                local ok, len

                synops.spawn(function()
                    local ok, err, timeout = synops.writable( writer:fd(), 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    return writer:send( 'hello' )
                end)

                writer:send( 'hello' )
                synops.later()
                assert( reader:recv() == 'hello' )

                ok, len = synops.await()
                assert( ok == true )
                assert( len == 5 )
            end))
        end)
    end)


    describe('test synops.sigwait -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.sigwait ) )
        end)

        it('fail with invalid arguments', function()
            assert.is_not_true( synops.run(function()
                assert( synops.sigwait( -1 ) )
            end))

            assert.is_not_true( synops.run(function()
                synops.sigwait( nil, -1000 )
            end))
        end)

        it('fail by timeout', function()
            assert.is_true( synops.run(function()

                synops.spawn(function()
                    local signo, err, timeout = synops.sigwait(
                        50, signal.SIGUSR1
                    )

                    assert( signo == nil )
                    assert( err == nil )
                    assert( timeout == true )
                end)

                synops.later()

                ok = synops.await()
                assert( ok == true )
            end))
        end)

        it('success', function()
            assert.is_true( synops.run(function()
                assert( signal.block( signal.SIGUSR1 ) )

                synops.spawn(function()
                    local signo, err, timeout = synops.sigwait(
                        50, signal.SIGUSR1
                    )

                    assert( signo == signal.SIGUSR1 )
                    assert( err == nil )
                    assert( timeout == nil )
                end)

                synops.later()
                assert( signal.kill( signal.SIGUSR1 ) )

                ok = synops.await()
                assert( ok == true )
            end))
        end)
    end)


    describe('test synops.suspend -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.suspend ) )
        end)

        it('timed out', function()
            assert.is_true( synops.run(function()
                local ok, val, timeout = synops.suspend()

                assert( ok == false )
                assert( val == nil )
                assert( timeout == true )

                ok, val, timeout = synops.suspend(100)

                assert( ok == false )
                assert( val == nil )
                assert( timeout == true )
            end))
        end)
    end)


    describe('test synops.resume -', function()
        it('fail on called from outside of execution context', function()
            assert.is_not_true( pcall( synops.resume ) )
        end)

        it('fail on called with invalid cid', function()
            assert.is_true( synops.run(function()
                local ok = synops.resume('abc')

                assert( ok == false )
            end))
        end)

        it('success', function()
            assert.is_true( synops.run(function()
                local ok, val, timeout;

                synops.spawn(function( cid )
                    assert( synops.resume( cid, 'hello' ) )
                end, synops.getcid())

                ok, val, timeout = synops.suspend(1000)
                assert( ok == true )
                assert( val == 'hello' )
                assert( not timeout )
            end))
        end)
    end)

end)


