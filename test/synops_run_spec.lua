--[[

  test/synops_run_spec.lua
  lua-synops
  Created by Masatoshi Teruya on 17/03/18.

--]]
--- file scope variables
local socket = require('posix.sys.socket')
local unistd = require('posix.unistd')
local fcntl = require('posix.fcntl')
local signal = require('signal')
local system = require('system')
local synops = require('synops')


signal.blockAll()

local function shutdown( fd )
    assert( socket.shutdown( fd, socket.SHUT_RDWR ) )
end

local function shutdown_rd( fd )
    assert( socket.shutdown( fd, socket.SHUT_RD ) )
end

local function shutdown_wr( fd )
    assert( socket.shutdown( fd, socket.SHUT_WR ) )
end

local function close( fd )
    unistd.close( fd )
end

local function recv( fd )
    return socket.recv( fd, 100 )
end

local function send( fd, msg )
    return socket.send( fd, msg )
end

local function socketpair( bufsiz )
    local reader, writer = assert( socket.socketpair(
        socket.AF_UNIX, socket.SOCK_STREAM, 0
    ))
    assert( fcntl.fcntl( reader, fcntl.O_NONBLOCK, 1 ) )
    assert( fcntl.fcntl( writer, fcntl.O_NONBLOCK, 1 ) )

    if bufsiz then
        assert( socket.setsockopt(
            reader, socket.SOL_SOCKET, socket.SO_RCVBUF, bufsiz
        ))
        assert( socket.setsockopt(
            writer, socket.SOL_SOCKET, socket.SO_SNDBUF, bufsiz
        ))
    end

    return reader, writer
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

        it('success', function()
            local executed = false

            assert.is_true( synops.run(function()
                assert( synops.atexit(function() executed = true end) )
            end))

            assert( executed, 'child coroutine did not executed' )
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
                assert( ok, 'failed to synops.await' )
                assert( val == 'hello', 'failed to synops.await' )

                ok, val = synops.await()
                assert( ok, 'failed to synops.await' )
                assert( val == 'world', 'failed to synops.await' )

                ok, val = synops.await()
                assert( not ok, 'failed to synops.await' )
                assert( val == 'error occurred', 'failed to synops.await' )
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
                assert( ok )
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
                local ok, err, timeout = synops.readable( reader, 50 )

                assert( ok == false )
                assert( timeout == true )
            end))
        end)


        it('fail on shutdown', function()
            assert.is_true( synops.run(function()
                local reader, writer = socketpair()
                local ok, msg

                synops.spawn(function()
                    local ok, err, timeout = synops.readable( reader, 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    return recv( reader )
                end)

                synops.later()
                shutdown( reader )

                ok, msg = synops.await()
                assert( ok )
                assert( msg == '' )
            end))
        end)


        it('success', function()
            assert.is_true( synops.run(function()
                local reader, writer = socketpair()
                local ok, msg

                synops.spawn(function()
                    local ok, err, timeout = synops.readable( reader, 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )
                    return recv( reader )
                end)

                synops.later()
                send( writer, 'hello world!' )

                ok, msg = synops.await()
                assert( ok )
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
                local ok

                synops.spawn(function()
                    local ok, err, timeout = synops.writable( writer, 50 )

                    assert( ok == false )
                    assert( err == nil )
                    assert( timeout == true )
                end)

                send( writer, 'hello' )
                synops.later()

                ok = synops.await()
                assert( ok == true )
            end))
        end)


        it('fail on shutdown', function()
            assert.is_true( synops.run(function()
                local reader, writer = socketpair( 5 )
                local ok, len, err

                synops.spawn(function()
                    local ok, err, timeout = synops.writable( writer, 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    return send( writer, 'hello' )
                end)

                send( writer, 'hello' )
                synops.later()
                shutdown( writer )

                ok, len, err = synops.await()
                assert( ok )
                assert( len == nil )
                assert( err ~= nil )
            end))
        end)


        it('success', function()
            assert.is_true( synops.run(function()
                local reader, writer = socketpair()
                local ok, len

                synops.spawn(function()
                    local ok, err, timeout = synops.writable( writer, 50 )

                    assert( ok == true )
                    assert( err == nil )
                    assert( timeout == nil )

                    return send( writer, 'hello' )
                end)

                send( writer, 'hello' )
                synops.later()
                assert( recv( reader, 100 ) == 'hello' )

                ok, len = synops.await()
                assert( ok )
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
                assert( signal.kill( 0, signal.SIGUSR1 ) )

                ok = synops.await()
                assert( ok == true )
            end))
        end)
    end)

end)


