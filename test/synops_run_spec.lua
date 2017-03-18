--[[

  test/synops_run_spec.lua
  lua-synops
  Created by Masatoshi Teruya on 17/03/18.

--]]
--- file scope variables
local SynopsRun = require('synops').run;


describe('test Synops.run API', function()
    it('fail with a non-function argument', function()
        assert.is_not_true( pcall( SynopsRun ) )
        assert.is_not_true( pcall( SynopsRun, 1 ) )
        assert.is_not_true( pcall( SynopsRun, 'str' ) )
        assert.is_not_true( pcall( SynopsRun, {} ) )
    end)

    it('success with function argument', function()
        assert.is_true( pcall( SynopsRun, function()end ) )
    end)

    it('success with function argument and arugments', function()
        assert.is_true( pcall( SynopsRun, function( a, b )
            assert( a == 'foo', 'a is unknown argument' )
            assert( b == 'bar', 'b is unknown argument' )
        end, 'foo', 'bar' ) )
    end)

    it('fail when called from the running function', function()
        assert.is_not_true( pcall( SynopsRun, function( a, b )
            assert( SynopsRun(function()end) )
        end, 'foo', 'bar' ) )
    end)
end)


