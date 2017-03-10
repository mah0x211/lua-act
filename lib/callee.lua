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
  lua-coop
  Created by Masatoshi Teruya on 16/12/26.

--]]
--- file scope variables
local Deque = require('deque');
local Aux = require('coop.aux');
local Coro = require('coop.coro');
local msleep = require('coop.hrtimer').msleep;
local isUInt = Aux.isUInt;
local yield = coroutine.yield;
local setmetatable = setmetatable;
local pcall = pcall;
local unpack = unpack or table.unpack;
-- constants
local OP_EVENT = Aux.OP_EVENT;
local OP_RUNQ = Aux.OP_RUNQ;
-- local CO_OK = Coro.OK;
-- local CO_YIELD = Coro.YIELD;
-- local ERRRUN = Coro.ERRRUN;
-- local ERRSYNTAX = Coro.ERRSYNTAX;
-- local ERRMEM = Coro.ERRMEM;
-- local ERRERR = Coro.ERRERR;
-- event-status
local EV_ERR = -3;
local EV_HUP = -2;
local EV_NOOP = -1;
local EV_OK = 0;
local EV_TIMEOUT = 1;


--- class Callee
local Callee = {};


--- __call
function Callee:call( ... )
    local co = self.co;
    local ok, err;

    self.coop.callee = self;
    -- call with passed arguments
    ok, err = co( ... );
    self.coop.callee = false;

    if ok or self.term then
        self:dispose( ok or self.term, err );
    end
end


--- dispose
function Callee:dispose( ok, err )
    local runq = self.coop.runq;
    local event = self.coop.event;
    local ref = self.ref;

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
    self.coop.pool:push( self );

    -- dispose child routines
    if #self.node > 0 then
        local child = self.node:pop();

        repeat
            runq:remove( child );
            child:dispose();
            child = self.node:pop();
        until child == nil;
    end

    if err then
        print( self.co:getres() );
    end

    -- call root node
    if ref then
        local root = self.root;

        self.root = nil;
        self.ref = nil;
        root.node:remove( ref );
        if root.wait then
            root.wait = nil;
            root:call( ok, self.co:getres() );
        end
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
    self.exitfn = { fn, ... };
end


--- await
function Callee:await()
    if #self.node > 0 then
        self.wait = true;
        return yield();
    end
end


--- ioable
-- @param evs
-- @param fd
-- @param deadline
-- @return status
-- @return err
function Callee:ioable( evs, asa, fd, deadline )
    local event = self.coop.event;
    local item = evs[fd];
    local op, ev, disabled;


    if item then
        local ok, err;

        ev = item:data();
        ok, err = ev:watch();
        if not ok then
            evs[fd] = nil;
            self.pool:remove( item );
            event:revoke( ev );
            return EV_ERR, err;
        end
    -- register io(readable or writable) event
    else
        local err;

        ev, err = event[asa]( event, self, fd );
        if err then
            return EV_ERR, err;
        end

        item = self.pool:push( ev );
        evs[fd] = item;
    end

    -- wait until event fired
    op, fdno, disabled = yield();

    -- got io event
    if op == OP_EVENT and fdno == fd then
        if disabled then
            evs[fd] = nil;
            self.pool:remove( item );
            event:revoke( ev );
            return EV_HUP;
        end

        ev:unwatch();
        return EV_OK;
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
-- @return status
-- @return err
function Callee:readable( fd, deadline )
    return self:ioable( self.revs, 'readable', fd, deadline );
end


--- writable
-- @param fd
-- @param deadline
-- @return status
-- @return err
function Callee:writable( fd, deadline )
    return self:ioable( self.wevs, 'writable', fd, deadline );
end


--- sleep
-- @param deadline
-- @return ok
-- @return err
function Callee:sleep( deadline )
    -- use runq
    if self.coop.event:len() > 0 then
        local ok, err = self.coop.runq:push( self, deadline );

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
-- @param status
-- @param err
function Callee:sigwait( deadline, ... )
    local event = self.coop.event;
    local sigset, sigmap;

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

            return EV_ERR, err;
        end

        -- maintain registered event
        sigset:push( ev );
        sigmap[signo] = true;
    end

    -- no need to wait signal if empty
    if #sigset == 0 then
        return EV_NOOP;
    -- wait registered signals
    else
        local op, signo;

        self.sigset = sigset;
        op, signo, hup = yield();
        self.sigset = nil;
        -- revoke signal events
        for i = 1, #sigset do
            event:revoke( sigset:pop() );
        end


        if op == OP_EVENT and sigmap[signo] then
            return signo;
        end
    end

    error( 'invalid implements' );
end


--- init
-- @param coop
-- @param fn
-- @param ctx
-- @param ...
-- @return ok
-- @return err
function Callee:init( coop, fn, ctx, ... )
    if ctx then
        self.co:init( fn, ctx, coop, ... );
    else
        self.co:init( fn, coop, ... );
    end

    -- set relationship
    if coop.callee then
        self.root = coop.callee;
        self.ref = self.root.node:push( self );
    end
end


--- new
-- @param coop
-- @param fn
-- @param ctx
-- @param ...
-- @return callee
-- @return err
local function new( coop, fn, ctx, ... )
    local co, callee, err;

    if ctx then
        co, err = Coro.new( fn, ctx, coop, ...  );
    else
        co, err = Coro.new( fn, coop, ...  );
    end

    if err then
        return nil, err;
    end

    callee = setmetatable({
        coop = coop,
        co = co,
        node = Deque.new(),
        pool = Deque.new(),
        revs = {},
        wevs = {}
    }, {
        __index = Callee
    });
    -- set relationship
    if coop.callee then
        callee.root = coop.callee;
        callee.ref = callee.root.node:push( callee );
    end

    return callee;
end


return {
    new = new,
    EV_ERR = EV_ERR,
    EV_HUP = EV_HUP,
    EV_NOOP = EV_NOOP,
    EV_OK = EV_OK,
    EV_TIMEOUT = EV_TIMEOUT
};

