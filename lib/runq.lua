--[[

  Copyright (C) 2016 Masatoshi Teruya

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

  lib/runq.lua
  lua-coop
  Created by Masatoshi Teruya on 16/12/24.

--]]

--- file scope variables
local Deque = require('deque');
local setmetatable = setmetatable;


-- class RunQ
local RunQ = {};


--- push
-- @param callee
function RunQ:push( callee )
    if not self.used[callee] then
        self.used[callee] = self.queue:unshift( callee );
    end
end


--- remove
-- @param callee
function RunQ:remove( callee )
    local item = self.used[callee];

    if item then
        self.used[callee] = nil;
        self.queue:remove( item );
    end
end


--- consume
-- @return qlen
function RunQ:consume()
    local nqueue = #self.queue;

    if nqueue > 0 then
        local queue = self.queue;
        local used = self.used;
        local callee;

        -- consume the current queued callees
        for _ = 1, nqueue do
            callee = queue:pop();
            if not callee then
                return #queue;
            end

            -- remove from used table
            used[callee] = nil;
            callee:call();
        end

        return #queue;
    end

    return 0;
end


--- len
-- @return nqueue
function RunQ:len()
    return #self.queue;
end


--- new
-- @return runq
local function new()
    return setmetatable({
        queue = Deque.new(),
        used = setmetatable({},{ __mode = 'k' })
    },{
        __index = RunQ
    });
end


return {
    new = new
};


