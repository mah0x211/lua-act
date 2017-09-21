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
local concat = Aux.concat;
local yield = coroutine.yield;
local setmetatable = setmetatable;
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
-- @param ok
function Callee:dispose( ok )
    local runq = self.synops.runq;
    local event = self.synops.event;

    runq:remove( self );

    -- revoke signal events
    if self.sigset then
        for _ = 1, #self.sigset do
            event:revoke( self.sigset:pop() );
        end
        self.sigset = nil;
    end

    -- revoke io events
    for _ = 1, #self.pool do
        local ioev = self.pool:pop();
        local fd = ioev:ident();

        self.revs[fd] = nil;
        self.wevs[fd] = nil;
        event:revoke( ioev );
    end

    self.term = nil;
    self.synops.pool:push( self );

    -- dispose child coroutines
    for _ = 1, #self.node do
        local child = self.node:pop();

        -- remove from runq
        runq:remove( child );
        -- release references
        child.root = nil;
        child.ref = nil;
        -- call dispose method
        child:dispose( true );
    end

    -- call root node
    if self.root then
        local root = self.root;
        local ref = self.ref;

        -- release references
        self.root = nil;
        self.ref = nil;
        -- detouch from from root node
        root.node:remove( ref );
        -- root node waiting for child results
        if root.wait then
            root.wait = nil;
            -- should not return ok value if atexit function
            if root.atexit then
                root.atexit = nil;
                root:call( self.co:getres() );
            else
                root:call( ok, self.co:getres() );
            end
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


--- await
-- @return ok
-- @return ...
function Callee:await()
    if #self.node > 0 then
        self.wait = true;
        return yield();
    end

    return true;
end


--- later
-- @return ok
-- @return err
function Callee:later()
    local ok, err = self.synops.runq:push( self );

    if not ok then
        return false, err;
    elseif yield() == OP_RUNQ then
        return true;
    end

    -- normally unreachable
    error( 'invalid implements' );
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

    -- normally unreachable
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
    if self.synops.event:len() > 0 or self.synops.runq:len() > 0 then
        local ok, err = self.synops.runq:push( self, deadline );

        if not ok then
            return false, err;
        elseif yield() == OP_RUNQ then
            return true;
        end

        -- normally unreachable
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

    -- register to runq with deadline
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
            for _ = 1, #sigset do
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
        for _ = 1, #sigset do
            event:revoke( sigset:pop() );
        end

        -- got signal event
        if op == OP_EVENT and sigmap[signo] then
            return signo;
        -- timed out
        elseif op == OP_RUNQ then
            return nil, nil, true;
        -- remove from runq
        elseif deadline then
            runq:remove( self );
        end

        -- normally unreachable
        error( 'invalid implements' );
    end
end


--- torelate
-- @param self
-- @param atexit
local function torelate( self, atexit )
    if CURRENT_CALLEE then
        local root = CURRENT_CALLEE;

        -- TODO: must be refactor
        -- set as a parent
        if atexit then
            local current = root;

            -- atexit node always await child node
            self.wait = true;
            self.atexit = true;

            root = root.root;
            -- change root node of current callee
            if root then
                -- remove current reference from root
                root.node:remove( current.ref );

                self.root = root;
                self.ref = root.node:push( self );

                current.root = self;
                current.ref = self.node:push( current );
            else
                current.root = self;
                current.ref = self.node:push( current );
            end
        -- set as a child
        else
            self.root = root;
            self.ref = root.node:push( self );
        end
    elseif atexit then
        error( 'invalid implements' );
    end
end


--- init
-- @param atexit
-- @param fn
-- @param ...
function Callee:init( atexit, fn, ... )
    self.co:init( atexit, fn, ... );
    -- set relationship
    torelate( self, atexit );
end


--- new
-- @param synops
-- @param atexit
-- @param fn
-- @param ...
-- @return callee
-- @return err
local function new( synops, atexit, fn, ... )
    local co, err = Coro.new( atexit, fn, ...  );
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
    -- set callee-id
    -- remove 'table: ' prefix
    callee.cid = tostring( callee ):sub(10);
    -- set relationship
    torelate( callee, atexit );

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

