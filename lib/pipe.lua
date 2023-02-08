--
-- Copyright (C) 2018-present Masatoshi Fukunaga
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
-- lib/pipe.lua
-- lua-act
-- Created by Masatoshi Teruya on 18/04/17.
--
--- file scope variables
local strsub = string.sub
local rawset = rawset
local pipe = require('pipe')
local wait_readable = require('act').wait_readable
local wait_writable = require('act').wait_writable
local unwait_readable = require('act').unwait_readable
local unwait_writable = require('act').unwait_writable

--- @class act.pipe
--- @field reader pipe.reader
--- @field writer pipe.writer
local Pipe = {}

--- init
--- @return act.pipe? pipe
--- @return any err
function Pipe:init()
    local reader, writer, err = pipe(true)

    if err then
        return nil, err
    end

    rawset(self, 'reader', reader)
    rawset(self, 'writer', writer)
    return self
end

--- read
--- @param msec integer
--- @return string str
--- @return any err
--- @return boolean? timeout
function Pipe:read(msec)
    local str, err, again = self.reader:read()
    if not again then
        return str, err
    end

    local reader = self.reader
    local ok, timeout
    repeat
        -- wait until readable
        ok, err, timeout = wait_readable(reader:fd(), msec)
        if ok then
            str, err, again = reader:read()
        end
    until not again or timeout

    return str, err, timeout
end

--- write
--- @param str string
--- @param msec integer
--- @return integer len
--- @return any err
--- @return boolean? timeout
function Pipe:write(str, msec)
    local len, err, again = self.writer:write(str)
    if not again then
        return len, err
    end

    local writer = self.writer
    local total = 0
    local ok, timeout
    repeat
        total = total + len
        -- eliminate write data
        if len > 0 then
            str = strsub(str, len + 1)
        end

        -- wait until writable
        ok, err, timeout = wait_writable(writer:fd(), msec)
        if ok then
            len, err, again = writer:write(str)
        end
    until not again or timeout

    return len and total + len, err, timeout
end

--- close
function Pipe:close()
    unwait_readable(self.reader:fd())
    unwait_writable(self.writer:fd())
    -- close descriptors
    self.reader:close()
    self.writer:close()
end

return {
    new = require('metamodule').new(Pipe),
}

