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

  lib/callee.lua
  lua-synops
  Created by Masatoshi Teruya on 16/12/26.

--]]
--- file scope variables
local Deque = require('deque');
local Aux = require('synops.aux');
local Coro = require('synops.coro');
local msleep = require('synops.hrtimer').msleep;
local isUInt = Aux.isUInt;
local yield = coroutine.yield;
local setmetatable = setmetatable;
local pcall = pcall;
local unpack = unpack or table.unpack;
local concat = table.concat;
-- constants
local OP_EVENT = Aux.OP_EVENT;
local OP_RUNQ = Aux.OP_RUNQ;
-- local CO_OK = Coro.OK;
-- local CO_YIELD = Coro.YIELD;
-- local ERRRUN = Coro.ERRRUN;
-- local ERRSYNTAX = Coro.ERRSYNTAX;
-- local ERRMEM = Coro.ERRMEM;
-- local ERRERR = Coro.ERRERR;
--- static variables
local CURRENT_CALLEE;


--- class Callee
local Callee = {};


--- __call
function Callee:call( ... )
    local co = self.co;
    local done, status;

    CURRENT_CALLEE = self;
    -- call with passed arguments
    done, status = co( ... );
    CURRENT_CALLEE = false;

    if done then
        self:dispose( not status and true or false );
    elseif self.term then
        self:dispose( true );
    end
end


--- dispose
function Callee:dispose( ok )
    local runq = self.synops.runq;
    local event = self.synops.event;

    runq:remove( self );

    -- revoke signal events
    if self.sigset then
        for i = 1, #self.sigset do
            event:revoke( self.sigset:pop() );
        end
        self.sigset = nil;
    end

    -- revoke io events
    if #self.pool > 0 then
        local ioev = self.pool:pop();

        repeat
            local fd = ioev:ident();

            self.revs[fd] = nil;
            self.wevs[fd] = nil;
            event:revoke( ioev );
            ioev = self.pool:pop();
        until ioev == nil;
    end

    -- run exit function
    if self.exitfn then
        pcall( unpack( self.exitfn ) );
        self.exitfn = nil;
    end

    self.term = nil;
    self.synops.pool:push( self );

    -- dispose child routines
    if #self.node > 0 then
        local child = self.node:pop();

        repeat
            runq:remove( child );
            child.root = nil;
            child.ref = nil;
            child:dispose( true );
            child = self.node:pop();
        until child == nil;
    end

    -- call root node
    if self.root then
        local root = self.root;
        local ref = self.ref;

        self.root = nil;
        self.ref = nil;
        root.node:remove( ref );
        if root.wait then
            root.wait = nil;
            root:call( ok, self.co:getres() );
        elseif not ok then
            error( concat( { self.co:getres() }, '\n' ) );
        end
    elseif not ok then
        error( concat( { self.co:getres() }, '\n' ) );
    end
end


--- exit
-- @param ...
function Callee:exit( ... )
    self.term = true;
    return yield( ... );
end


--- atexit
-- @param fn
-- @param ...
function Callee:atexit( fn, ... )
    --- TODO: probably, should be implemented in C to improve performance
    self.exitfn = { fn, ... };
end


--- await
-- @return ok
-- @return ...
function Callee:await()
    if #self.node > 0 then
        self.wait = true;
        return yield();
    end
end


--- ioable
-- @param evs
-- @param asa
-- @param fd
-- @param deadline
-- @return ok
-- @return err
-- @return timeout
function Callee:ioable( evs, asa, fd, deadline )
    local runq = self.synops.runq;
    local event = self.synops.event;
    local item = evs[fd];
    local op, ev, fdno, disabled;

    -- register to runq
    if deadline then
        local ok, err = runq:push( self, deadline );

        if not ok then
            return false, err;
        end
    end

    if item then
        local ok, err;

        ev = item:data();
        ok, err = ev:watch();
        if not ok then
            if deadline then
                runq:remove( self );
            end

            evs[fd] = nil;
            self.pool:remove( item );
            event:revoke( ev );

            return false, err;
        end
    -- register io(readable or writable) event
    else
        local err;

        ev, err = event[asa]( event, self, fd );
        if err then
            if deadline then
                runq:remove( self );
            end

            return false, err;
        end

        item = self.pool:push( ev );
        evs[fd] = item;
    end

    -- wait until event fired
    op, fdno, disabled = yield();
    -- got io event
    if op == OP_EVENT and fdno == fd then
        -- remove from runq
        if deadline then
            runq:remove( self );
        end

        if disabled then
            evs[fd] = nil;
            self.pool:remove( item );
            event:revoke( ev );
        else
            ev:unwatch();
        end

        return true;
    -- timed out
    elseif op == OP_RUNQ then
        ev:unwatch();
        return false, nil, true;
    -- remove from runq
    elseif deadline then
        runq:remove( self );
    end

    -- revoke io event
    -- unwatch io event
    evs[fd] = nil;
    self.pool:remove( item );
    event:revoke( ev );

    error( 'invalid implements' );
end



--- readable
-- @param fd
-- @param deadline
-- @return ok
-- @return err
-- @return timeout
function Callee:readable( fd, deadline )
    return self:ioable( self.revs, 'readable', fd, deadline );
end


--- writable
-- @param fd
-- @param deadline
-- @return ok
-- @return err
-- @return timeout
function Callee:writable( fd, deadline )
    return self:ioable( self.wevs, 'writable', fd, deadline );
end


--- sleep
-- @param deadline
-- @return ok
-- @return err
function Callee:sleep( deadline )
    -- use runq
    if self.synops.event:len() > 0 then
        local ok, err = self.synops.runq:push( self, deadline );

        if not ok then
            return false, err;
        elseif yield() == OP_RUNQ then
            return true;
        end

        error( 'invalid implements' );

    -- return immediately
    elseif deadline == nil then
        return true;
    -- use msleep
    elseif not isUInt( deadline ) then
        return false, 'deadline must be unsigned integer';
    elseif msleep( deadline ) then
        return true;
    end

    return false, 'syserror';
end


--- sigwait
-- @param deadline
-- @param ...
-- @return signo
-- @return err
-- @return timeout
function Callee:sigwait( deadline, ... )
    local runq = self.synops.runq;
    local event = self.synops.event;
    local sigset, sigmap;

    -- register to runq
    if deadline then
        local ok, err = runq:push( self, deadline );

        if not ok then
            return nil, err;
        end
    end

    sigset = Deque.new();
    sigmap = {};
    -- register signal events
    for _, signo in pairs({...}) do
        local ev, err = event:signal( self, signo, true );

        if err then
            -- revoke signal events
            for j = 1, #sigset do
                event:revoke( sigset:pop() );
            end

            return nil, err;
        end

        -- maintain registered event
        sigset:push( ev );
        sigmap[signo] = true;
    end

    -- no need to wait signal if empty
    if #sigset == 0 then
        return nil;
    -- wait registered signals
    else
        local op, signo;

        self.sigset = sigset;
        op, signo = yield();
        self.sigset = nil;
        -- revoke signal events
        for i = 1, #sigset do
            event:revoke( sigset:pop() );
        end

        if op == OP_EVENT and sigmap[signo] then
            return signo;
        -- timed out
        elseif op == OP_RUNQ then
            return nil, nil, true;
        -- remove from runq
        elseif deadline then
            runq:remove( self );
        end
    end

    error( 'invalid implements' );
end


--- init
-- @param fn
-- @param ...
-- @return ok
-- @return err
function Callee:init( fn, ... )
    self.co:init( fn, ... );
    -- set relationship
    if CURRENT_CALLEE then
        self.root = CURRENT_CALLEE;
        self.ref = self.root.node:push( self );
    end
end


--- new
-- @param synops
-- @param fn
-- @param ...
-- @return callee
-- @return err
local function new( synops, fn, ... )
    local co, err = Coro.new( fn, ...  );
    local callee;

    if err then
        return nil, err;
    end

    callee = setmetatable({
        synops = synops,
        co = co,
        node = Deque.new(),
        pool = Deque.new(),
        revs = {},
        wevs = {}
    }, {
        __index = Callee
    });
    -- set relationship
    if CURRENT_CALLEE then
        callee.root = CURRENT_CALLEE;
        callee.ref = callee.root.node:push( callee );
    end

    return callee;
end


--- acquire
-- @return callee
local function acquire()
    return CURRENT_CALLEE;
end


return {
    new = new,
    acquire = acquire
};

