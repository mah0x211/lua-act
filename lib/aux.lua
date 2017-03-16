--[[

  Copyright (C) 2017 Masatoshi Teruya

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  lib/aux.lua
  lua-synops
  Created by Masatoshi Teruya on 17/03/04.

--]]

--- file scope variables
local type = type;
local floor = math.floor;
--- constants
local INFINITE = math.huge;
local OP_EVENT = 0;
local OP_RUNQ = 1;


--- isUInt
-- @param val
-- @return ok
local function isUInt( val )
    return type( val ) == 'number' and val >= 0 and val < INFINITE and
           val == floor( val );
end


--- isFunction
-- @param fn
-- @return ok
local function isFunction( fn )
    return type( fn ) == 'function';
end


return {
    OP_EVENT = OP_EVENT,
    OP_RUNQ = OP_RUNQ,
    isUInt = isUInt,
    isFunction = isFunction
};


