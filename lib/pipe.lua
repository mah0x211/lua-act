--
-- Copyright (C) 2018 Masatoshi Teruya
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
local pipe = require('act.pipe.syscall')
local waitReadable = require('act').waitReadable
local waitWritable = require('act').waitWritable
local unwaitReadable = require('act').unwaitReadable
local unwaitWritable = require('act').unwaitWritable
local strsub = string.sub

--- class Pipe
local Pipe = {}

--- read
-- @param msec
-- @return str
-- @return err
-- @return timeout
function Pipe:read(msec)
    local str, err, again = self.reader:read()

    if not again then
        return str, err
    else
        local reader = self.reader
        local ok, timeout

        repeat
            -- wait until readable
            ok, err, timeout = waitReadable(reader:fd(), msec)
            if ok then
                str, err, again = reader:read()
            end
        until not again or timeout

        return str, err, timeout
    end
end

--- write
-- @param str
-- @param msec
-- @return len
-- @return err
-- @return timeout
function Pipe:write(str, msec)
    local len, err, again = self.writer:write(str)

    if not again then
        return len, err
    else
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
            ok, err, timeout = waitWritable(writer:fd(), msec)
            if ok then
                len, err, again = writer:write(str)
            end
        until not again or timeout

        return len and total + len, err, timeout
    end
end

--- close
function Pipe:close()
    unwaitReadable(self.reader:fd())
    unwaitWritable(self.writer:fd())
    -- close descriptors
    self.reader:close()
    self.writer:close()
end

--- new
-- @return pipe
local function new()
    local reader, writer, err = pipe()

    if err then
        return nil, err
    end

    return setmetatable({
        reader = reader,
        writer = writer,
    }, {
        __index = Pipe,
    })
end

return {
    new = new,
}

