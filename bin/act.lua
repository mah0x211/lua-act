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
-- bin/act.lua
-- lua-act
-- Created by Masatoshi Teruya on 17/03/18.
--
--- file scope variables
local Act = require('act')
local ActRun = Act.run
local loadfile = loadfile
local select = select
local USAGE = [[
act - coroutine based synchronously non-blocking operations module
Usage: act [filename] [arg, ...]
]]

Act.run = nil
if not arg[1] then
    print(USAGE)
    os.exit(0)
end

-- export APIs to global except Act.run
for k, v in pairs(Act) do
    if type(k) == 'string' and k ~= 'run' and type(v) == 'function' then
        _G[k] = v
    end
end

local fn = assert(loadfile(arg[1]))
local ok, err = ActRun(fn, select(2, ...))

if not ok then
    print(err)
    os.exit(-1)
end

