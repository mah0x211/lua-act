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
local floor = math.floor
local new_minheap = require('act.minheap')
local new_deque = require('act.deque')
local hrtimer = require('act.hrtimer')
local hrtimer_getnsec = hrtimer.getnsec
local hrtimer_remain = hrtimer.remain
local hrtimer_nsleep = hrtimer.nsleep
local aux = require('act.aux')
local is_func = aux.is_func
--- constants
local OP_RUNQ = aux.OP_RUNQ

--- nsec2msec
---@param nsec integer
---@return integer msec
local function nsec2msec(nsec)
    return floor(nsec / 1000000)
end

--- @class act.runq
--- @field heap minheap
--- @field ref table<act.callee, deque.element>|table<integer, deque>|table<deque, minheap.element>
local RunQ = {}

function RunQ:__newindex()
    error('attempt to protected value', 2)
end

--- init
--- @return act.runq
function RunQ:init()
    rawset(self, 'heap', new_minheap())
    rawset(self, 'ref', {})
    return self
end

--- push
--- @param callee act.callee
--- @param msec? integer
--- @return boolean ok
--- @return any err
function RunQ:push(callee, msec)
    if not callee or not is_func(callee.call) then
        return false, 'callee must have a call method'
    end
    local nsec = hrtimer_getnsec(msec and msec * 1000000 or 0)
    msec = nsec2msec(nsec)

    -- register callee
    local ref = self.ref
    if not ref[callee] then
        local queue = ref[msec]
        local qelm

        if not queue then
            -- create new queue associated for msec
            queue = new_deque() --- @type deque
            -- push callee to queue
            qelm = queue:unshift(callee)
            -- push queue to minheap
            ref[msec] = queue
            ref[queue] = self.heap:push(nsec, queue)
        else
            -- push callee to existing queue
            qelm = queue:unshift(callee)
        end

        ref[callee] = qelm
        ref[qelm] = queue

        return true
    end

    return false, 'callee is already registered'
end

--- remove
--- @param callee act.callee
function RunQ:remove(callee)
    local ref = self.ref
    local qelm = ref[callee]

    if qelm then
        local queue = ref[qelm]

        ref[callee] = nil
        ref[qelm] = nil
        queue:remove(qelm)
        if #queue == 0 and ref[queue] then
            local helm = ref[queue]

            ref[queue] = nil
            ref[nsec2msec(helm.pri)] = nil
            self.heap:del(helm.idx)
        end
    end
end

--- consume queue
--- @return integer msec
function RunQ:consume()
    local msec = self:remain()

    if msec < 1 then
        local helm = self.heap:pop()

        if helm then
            local queue = helm.val
            local ref = self.ref

            ref[queue] = nil
            ref[nsec2msec(helm.pri)] = nil

            -- consume the current queued callees
            for _ = 1, #queue do
                local callee = queue:pop()

                if not callee then
                    break
                end

                -- remove from used table
                ref[ref[callee]] = nil
                ref[callee] = nil
                -- call by runq
                callee:call(OP_RUNQ)
            end
        end

        return self:remain()
    end

    return msec
end

--- remain
--- @return integer msec
function RunQ:remain()
    local helm = self.heap:peek()

    -- return remaining msec
    if helm then
        return hrtimer_remain(nsec2msec(helm.pri))
    end

    return -1
end

--- sleep
--- @return boolean ok
--- @return any err
function RunQ:sleep()
    local helm = self.heap:peek()

    -- sleep until deadline
    if helm then
        return hrtimer_nsleep(helm.pri)
    end

    -- no need to sleep
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

