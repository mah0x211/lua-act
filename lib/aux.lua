--
-- Copyright (C) 2017 Masatoshi Teruya
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- lib/aux.lua
-- lua-act
-- Created by Masatoshi Teruya on 17/03/04.
--
--- file scope variables
local type = type
local floor = math.floor
local tblconcat = table.concat
local tostring = tostring
--- constants
local INF_POS = math.huge
local INF_NEG = -INF_POS
local OP_EVENT = 0
local OP_RUNQ = 1

--- is_unsigned
--- @param v any
--- @return boolean ok
local function is_unsigned(v)
    return type(v) == 'number' and v >= 0 and v < INF_POS
end

--- is_int
--- @param v any
--- @return boolean ok
local function is_int(v)
    return type(v) == 'number' and v > INF_NEG and v < INF_POS and v == floor(v)
end

--- is_uint
--- @param v any
--- @return boolean ok
local function is_uint(v)
    return type(v) == 'number' and v >= 0 and v < INF_POS and v == floor(v)
end

--- concat
--- @param tbl table
--- @param sep string
--- @param i integer
--- @param j integer
--- @return string str
local function concat(tbl, sep, i, j)
    for pos = i or 1, j or #tbl do
        local arg = tbl[pos]

        if type(arg) ~= 'string' then
            tbl[pos] = tostring(arg)
        end
    end

    return tblconcat(tbl, sep, i, j)
end

return {
    OP_EVENT = OP_EVENT,
    OP_RUNQ = OP_RUNQ,
    is_int = is_int,
    is_uint = is_uint,
    is_unsigned = is_unsigned,
    concat = concat,
}

