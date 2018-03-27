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
local Argv = require('argv');
local Deque = require('deque');
local Aux = require('synops.aux');
local Coro = require('synops.coro');
local concat = Aux.concat;
local isUInt = Aux.isUInt;
local yield = coroutine.yield;
local setmetatable = setmetatable;
local tostring = tostring;
local strsub = string.sub;
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
local SUSPENDED = setmetatable({},{
    __mode = 'v'
});
local RLOCKS = {};
local WLOCKS = {};
local ROPERATORS = {};
local WOPERATORS = {};
local CURRENT_CALLEE;



--- resume
-- @param cid
-- @param ...
-- @return ok
local function resume( cid, ... )
    local callee = SUSPENDED[cid];

    -- found a suspended callee
    if callee then
        SUSPENDED[cid] = nil;
        callee.argv:set( 0, ... );
        -- resume via runq
        callee.synops.runq:remove( callee );
        callee.synops.runq:push( callee );

        return true;
    end

    return false;
end


--- resumeq
-- @param runq
-- @param cidq
local function resumeq( runq, cidq )
    -- first index is used for holding a fd
    for i = 1, #cidq do
        local cid = cidq[i];
        local callee = SUSPENDED[cid];

        -- found a suspended callee
        if callee then
            SUSPENDED[cid] = nil;
            -- resume via runq
            runq:remove( callee );
            runq:push( callee );
        end
    end
end



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
    -- remove state properties
    self.term = nil;
    SUSPENDED[self.cid] = nil;

    -- resume all suspended callee
    for fd, cidq in pairs( self.rlock ) do
        -- remove cidq maintained by fd
        RLOCKS[fd] = nil;
        resumeq( runq, cidq );
    end
    self.rlock = {};

    -- resume all suspended callee
    for fd, cidq in pairs( self.wlock ) do
        -- remove cidq maintained by fd
        WLOCKS[fd] = nil;
        resumeq( runq, cidq );
    end
    self.wlock = {};

    -- revoke signal events
    if self.sigset then
        for _ = 1, #self.sigset do
            event:revoke( self.sigset:pop() );
        end
        self.sigset = nil;
    end

    -- revoke readable events
    for fd, ev in pairs( self.events.readable ) do
        ROPERATORS[fd] = nil;
        event:revoke( ev );
    end
    self.events.readable = {};

    -- revoke writable events
    for fd, ev in pairs( self.events.writable ) do
        WOPERATORS[fd] = nil;
        event:revoke( ev );
    end
    self.events.writable = {};

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

    -- add to pool for reuse
    self.synops.pool:push( self );
end


--- exit
-- @param ...
function Callee:exit( ... )
    self.term = true;
    yield( ... );

    -- normally unreachable
    error( 'invalid implements' );
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


--- suspend
-- @param msec
-- @return ok
-- @return ...
-- @return timeout
function Callee:suspend( msec )
    local cid = self.cid;

    if msec ~= nil then
        -- suspend until reached to msec
        local ok, err = self.synops.runq:push( self, msec );

        if not ok then
            return false, err;
        end
    end

    -- wait until resumed by resume method
    SUSPENDED[cid] = self;
    if yield() == OP_RUNQ then
        -- resumed by time-out if self exists in suspend list
        if SUSPENDED[cid] then
            SUSPENDED[cid] = nil;
            self.synops.runq:remove( self );
            return false, nil, true;
        end

        -- resumed
        return true, self.argv:select();
    end

    -- normally unreachable
    error( 'invalid implements' );
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


--- rwunlock
-- @param self
-- @param locks
-- @param asa
-- @param fd
local function rwunlock( self, locks, asa, fd )
    local cidq = self[asa][fd];

    -- resume all suspended callee
    if cidq then
        self[asa][fd] = nil;
        -- remove cidq maintained by fd
        locks[fd] = nil;
        resumeq( self.synops.runq, cidq );
    end
end


--- readunlock
-- @param fd
function Callee:readunlock( fd )
    rwunlock( self, RLOCKS, 'rlock', fd );
end


--- writeunlock
-- @param fd
function Callee:writeunlock( fd )
    rwunlock( self, WLOCKS, 'wlock', fd );
end


--- rwlock
-- @param self
-- @param locks
-- @param asa
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
local function rwlock( self, locks, asa, fd, msec )
    assert( isUInt( fd ), 'fd must be unsigned integer' );
    if not self[asa][fd] then
        local cidq = locks[fd];

        -- other callee is waiting
        if cidq then
            local idx = #cidq + 1;
            local ok, err, timeout;

            cidq[idx] = self.cid;
            ok, err, timeout = self:suspend( msec );
            cidq[idx] = false;

            return ok, err, timeout;
        end

        -- create read or write queue
        locks[fd] = {};
        self[asa][fd] = locks[fd];
    end

    return true;
end


--- readlock
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Callee:readlock( fd, msec )
    return rwlock( self, RLOCKS, 'rlock', fd, msec );
end


--- writelock
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Callee:writelock( fd, msec )
    return rwlock( self, WLOCKS, 'wlock', fd, msec );
end


--- ioable
-- @param self
-- @param operators
-- @param asa
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
local function ioable( self, operators, asa, fd, msec )
    local runq = self.synops.runq;
    local event = self.synops.event;
    local events = self.events;
    local ev = events[asa][fd];
    local op, fdno, disabled;

    -- event not found
    if not ev then
        local callee = operators[fd];

        -- another callee has an 'asa' event of fd
        if callee then
            -- currently in-use
            if callee.events.inuse == fd then
                return false, 'operation already in progress';
            end
            ev = callee.events[asa][fd];
        end

        -- register to runq
        if msec then
            local ok, err = runq:push( self, msec );

            if not ok then
                return false, err;
            end
        end

        -- found an event from another callee
        if ev then
            -- change context
            ev:context( self );
            -- remove ev from anothor callee
            callee.events[asa][fd] = nil;
        else
            local err;

            -- register io(readable or writable) event
            ev, err = event[asa]( event, self, fd );
            if err then
                if msec then
                    runq:remove( self );
                end

                return false, err;
            end
        end

        -- save to local and global table
        events.inuse = fd;
        events[asa][fd] = ev;
        operators[fd] = self;
    end

    -- wait until event fired
    op, fdno, disabled = yield();
    events.inuse = -1;

    -- got io event
    if op == OP_EVENT then
        if fdno == fd then
            -- remove from runq
            if msec then
                runq:remove( self );
            end

            if disabled then
                events[asa][fd] = nil;
                operators[fd] = nil;
                event:revoke( ev );
            end

            return true;
        end
    -- timed out
    elseif op == OP_RUNQ then
        return false, nil, true;
    end

    -- remove from runq
    if msec then
        runq:remove( self );
    end

    -- revoke io event
    events[asa][fd] = nil;
    operators[fd] = nil;
    event:revoke( ev );

    -- normally unreachable
    error( 'invalid implements' );
end


--- readable
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Callee:readable( fd, msec )
    return ioable( self, ROPERATORS, 'readable', fd, msec );
end


--- writable
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Callee:writable( fd, msec )
    return ioable( self, WOPERATORS, 'writable', fd, msec );
end


--- sleep
-- @param msec
-- @return ok
-- @return err
function Callee:sleep( msec )
    local ok, err = self.synops.runq:push( self, msec );

    if not ok then
        return false, err;
    elseif yield() == OP_RUNQ then
        return true;
    end

    -- normally unreachable
    error( 'invalid implements' );
end


--- sigwait
-- @param msec
-- @param ...
-- @return signo
-- @return err
-- @return timeout
function Callee:sigwait( msec, ... )
    local runq = self.synops.runq;
    local event = self.synops.event;
    local sigset, sigmap;

    -- register to runq with msec
    if msec then
        local ok, err = runq:push( self, msec );

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
        elseif msec then
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
        argv = Argv.new(),
        node = Deque.new(),
        rlock = {},
        wlock = {},
        events = {
            inuse = -1,
            readable = {},
            writable = {},
        }
    }, {
        __index = Callee
    });
    -- set callee-id
    -- remove 'table: ' prefix
    callee.cid = strsub( tostring( callee ), 10 );
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
    acquire = acquire,
    resume = resume
};

