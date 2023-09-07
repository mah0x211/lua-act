--
-- Copyright (C) 2016-present Masatoshi Fukunaga
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
-- lib/runq.lua
-- lua-act
-- Created by Masatoshi Teruya on 16/12/24.
--
--- file scope variables
local rawset = rawset
local type = type
local is_unsigned = require('act.aux').is_unsigned
local new_minheap = require('act.minheap')
local new_deque = require('act.deque')
local gettime = require('time.clock').gettime
local sleep = require('time.sleep')
--- constants
local OP_RUNQ = require('act.aux').OP_RUNQ

--- @class act.runq
--- @field heap minheap
--- @field deadline2queue table<number, act.deque>
--- @field callee2qelm table<act.callee, act.deque.element>
--- @field queue2helm table<act.deque, minheap.element>
--- @field qelm2queue table<act.deque.element, act.deque>
local RunQ = {}

function RunQ:__newindex()
    error('attempt to protected value', 2)
end

--- init
--- @return act.runq
function RunQ:init()
    rawset(self, 'heap', new_minheap())
    rawset(self, 'deadline2queue', {})
    rawset(self, 'callee2qelm', {})
    rawset(self, 'qelm2queue', {})
    rawset(self, 'queue2helm', {})
    return self
end

--- push
--- @param callee act.callee
--- @param sec? number
function RunQ:push(callee, sec)
    -- check arguments
    assert(callee and type(callee.call) == 'function',
           'callee must have a call method')
    assert(sec == nil or is_unsigned(sec), 'sec must be unsigned number or nil')
    assert(self.callee2qelm[callee] == nil, 'callee is already registered')

    local deadline = gettime() + (sec and sec > 0 and sec or 0)
    local deadline2queue = self.deadline2queue
    local queue = deadline2queue[deadline]
    local qelm

    if not queue then
        -- create new queue associated with deadline
        queue = new_deque() --- @type act.deque
        -- keep a queue associated with deadline
        deadline2queue[deadline] = queue
        -- push queue to minheap
        self.queue2helm[queue] = self.heap:push(deadline, queue)
    end

    -- push callee to queue
    qelm = queue:unshift(callee)
    self.callee2qelm[callee] = qelm
    self.qelm2queue[qelm] = queue
end

--- remove
--- @param callee act.callee
function RunQ:remove(callee)
    local qelm = self.callee2qelm[callee]

    if qelm then
        local queue = self.qelm2queue[qelm]

        queue:remove(qelm)
        self.callee2qelm[callee] = nil
        self.qelm2queue[qelm] = nil
        if #queue == 0 and self.queue2helm[queue] then
            local helm = self.queue2helm[queue]
            self.queue2helm[queue] = nil
            -- remove the element holds callee from heap
            self.heap:del(helm.idx)
            self.deadline2queue[helm.pri] = nil
        end
    end
end

--- consume queue
--- @return number sec
function RunQ:consume()
    local helm = self.heap:peek()

    if not helm then
        return -1
    end

    local deadline = helm.pri
    local now = gettime()
    if deadline > now then
        -- return remaining seconds
        return deadline - now
    end
    self.heap:pop()

    -- consumes queues that exceed the deadline
    local queue2helm = self.queue2helm
    local deadline2queue = self.deadline2queue
    local queue = helm.val

    queue2helm[queue] = nil
    deadline2queue[deadline] = nil

    local callee2qelm = self.callee2qelm
    local qelm2queue = self.qelm2queue
    for _ = 1, #queue do
        local callee = queue:pop()
        if not callee then
            break
        end

        -- remove from used table
        qelm2queue[callee2qelm[callee]] = nil
        callee2qelm[callee] = nil
        -- call by runq
        callee:call(OP_RUNQ)
    end

    helm = self.heap:peek()
    if not helm then
        return -1
    end

    -- return remaining seconds of next deadline
    deadline = helm.pri
    now = gettime()
    return deadline > now and deadline - now or 0
end

--- sleep
--- @return boolean ok
--- @return any err
function RunQ:sleep()
    local helm = self.heap:peek()

    -- sleep until deadline
    if helm then
        local deadline = helm.pri
        local now = gettime()
        if deadline > now then
            local _, err = sleep(deadline - now)
            if err then
                return false, err
            end
        end
    end

    return true
end

--- len returns the number of the queue
--- @return integer nqueue
function RunQ:len()
    return self.heap.len
end

return {
    new = require('metamodule').new(RunQ),
}

