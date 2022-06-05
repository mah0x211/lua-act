--
-- Copyright (C) 2016 Masatoshi Teruya
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
local deque_new = require('deque').new
local minheap_new = require('minheap').new
local hrtimer = require('act.hrtimer')
local hrtimer_getmsec = hrtimer.getmsec
local hrtimer_remain = hrtimer.remain
local hrtimer_msleep = hrtimer.msleep
local aux = require('act.aux')
local isUInt = aux.isUInt
local isFunction = aux.isFunction
--- constants
local OP_RUNQ = aux.OP_RUNQ

--- @class act.runq.RunQ
local RunQ = {}

function RunQ:__newindex()
    error('attempt to protected value', 2)
end

--- init
--- @return act.runq.RunQ
function RunQ:init()
    rawset(self, 'heap', minheap_new())
    rawset(self, 'ref', {})
    return self
end

--- push
--- @param callee act.callee.Callee
--- @param msec integer
--- @return boolean ok
--- @return string? err
function RunQ:push(callee, msec)
    local ref = self.ref

    if not callee or not isFunction(callee.call) then
        return false, 'callee must have a call method'
    elseif msec == nil then
        msec = hrtimer_getmsec()
    elseif not isUInt(msec) then
        return false, 'msec must be unsigned integer'
    else
        msec = hrtimer_getmsec(msec)
    end

    -- register callee
    if not ref[callee] then
        local queue = ref[msec]
        local qelm

        -- create new queue associated for msec
        if not queue then
            queue = deque_new()
            -- push callee to queue
            qelm = queue:unshift(callee)
            -- push queue to minheap
            ref[msec] = queue
            ref[queue] = self.heap:push(msec, queue)
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
--- @param callee act.callee.Callee
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
            ref[helm.pri] = nil
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
            local nqueue = #queue
            local ref = self.ref

            ref[queue] = nil
            ref[helm.pri] = nil

            -- consume the current queued callees
            for _ = 1, nqueue do
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
        return hrtimer_remain(helm.pri)
    end

    return -1
end

--- sleep
--- @return boolean ok
--- @return string? err
function RunQ:sleep()
    local helm = self.heap:peek()

    -- sleep until deadline
    if helm then
        return hrtimer_msleep(helm.pri)
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
    new = require('metamodule').new.RunQ(RunQ),
}

