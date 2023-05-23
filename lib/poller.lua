--
-- Copyright (C) 2023 Masatoshi Fukunaga
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
local epoll = require('epoll')
local kqueue = require('kqueue')

--- @class poller.event
--- @field renew fun(self, p:poller?):(ok:boolean, err:string, errno:integer)
--- @field revert fun(self):(ev:poller.empty_event, err:string, errno:integer)
--- @field watch fun(self):(ok:boolean, err:string, errno:integer)
--- @field unwatch fun(self):(ok:boolean, err:string, errno:integer)
--- @field is_enabled fun(self):boolean
--- @field is_level fun(self):boolean
--- @field as_level fun(self):(ok:boolean, err:string, errno:integer)
--- @field is_edge fun(self):boolean
--- @field as_edge fun(self):(ok:boolean, err:string, errno:integer)
--- @field is_oneshot fun(self):boolean
--- @field as_oneshot fun(self):(ok:boolean, err:string, errno:integer)
--- @field ident fun(self):integer
--- @field udata fun(self):any
--- @field getinfo fun(self, event:string):table

--- @class poller.empty_event
--- @field renew fun(self, p:poller?):(ok:boolean, err:string, errno:integer)
--- @field is_level fun(self):boolean
--- @field as_level fun(self):boolean
--- @field is_edge fun(self):boolean
--- @field as_edge fun(self):boolean
--- @field is_oneshot fun(self):boolean
--- @field as_oneshot fun(self):boolean
--- @field as_read fun(self, fd:integer, udata:any):(ev:poller.event, err:string, errno:integer)
--- @field as_write fun(self, fd:integer, udata:any):(ev:poller.event, err:string, errno:integer)
--- @field as_signal fun(self, signo:integer, udata:any):(ev:poller.event, err:string, errno:integer)
--- @field as_timer fun(self, ident:integer, msec:integer, udata:any):(ev:poller.event, err:string, errno:integer)

--- @class poller
--- @field renew fun(self):(ok:boolean, err:string, errno:integer)
--- @field new_event fun(self):poller.empty_event
--- @field wait fun(self, msec:integer? ):(n:integer, err:string, errno:integer)
--- @field consume fun(self, msec:integer? ):(ev:poller.event, udata:any, errno:integer)

--- new
--- @return poller?
--- @return string? err
--- @return number? errno
local function new()
    local newfn = assert(epoll.usable() and epoll.new or kqueue.usable() and
                             kqueue.new,
                         'neither epoll nor kqueue is available: act is not supported on this platform')
    return newfn()
end

return new
