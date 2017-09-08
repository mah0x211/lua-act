--[[

  test/synops_runq_spec.lua
  lua-coop
  Created by Masatoshi Teruya on 17/01/4.

--]]
--- file scope variables
local SynopsRunQ = require('synops.runq')


describe('test synops.runq module:', function()
    local runq = SynopsRunQ.new()
    local res = {}
    local a = { call = function() res[1] = 'a' end }
    local b = { call = function() res[2] = 'b' end }
    local c = { call = function() res[3] = 'c' end }


    describe('test a initial properties -', function()
        it('equal to 0', function()
            assert.are.equal( 0, runq:len() )
        end)

        it('equal to an empty table', function()
            assert.are.same( {}, runq.ref )
        end)
    end)


    describe('test runq:push method -', function()
        it('should be inserting the items', function()
            assert.is_true( runq:push( a, 1 ) )
            assert.is_true( runq:push( b, 2 ) )
            assert.are.equal( 2, runq:len() );
        end)
    end)


    describe('test runq:remove method -', function()
        it('should be removed the pushed items', function()
            runq:remove( a )
            runq:remove( b )
            assert.are.equal( 0, runq:len() )
        end);
    end)


    describe('test runq:consume method -', function()
        it('should be invoking the pushed items', function()
            runq:push( a, 1 )
            runq:push( b, 2 )
            runq:push( c, 3 )

            assert.are.equal( 3, runq:len() );
            assert.are.equal( 2, runq:consume(-1) );
            assert.are.equal( 2, runq:len() );
            assert.are.equal( 3, runq:consume(-1) );
            assert.are.equal( 1, runq:len() );
            assert.are.equal( -1, runq:consume(-1) );
            assert.are.equal( 0, runq:len() );

            assert.are.same( {}, runq.ref );

            assert.are.same( { 'a', 'b', 'c' }, res );
        end);
    end)
end)

