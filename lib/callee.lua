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
local OPERATORS = {
    readable = {},
    writable = {}
};
local CURRENT_CALLEE;


--- unwaitfd
-- @param operators
-- @param fd
-- @return ok
-- @return err
local function unwaitfd( operators, fd )
    local callee = operators[fd];

    -- found
    if callee then
        operators[fd] = nil;
        callee.synops.runq:remove( callee );
        callee.synops.event:revoke( callee.ev );
        -- reset event properties
        callee.ev = nil;
        callee.evfd = -1;
        -- currently in-use
        if callee.evuse then
            callee.evuse = false;
            callee.evasa = 'unwaitfd';
            -- requeue without timeout
            return callee.synops.runq:push( callee );
        end
        callee.evasa = '';
    end

    return true;
end


--- unwaitReadable
-- @param fd
-- @return ok
-- @return err
local function unwaitReadable( fd )
    return unwaitfd( OPERATORS.readable, fd );
end


--- unwaitWritable
-- @param fd
-- @return ok
-- @return err
local function unwaitWritable( fd )
    return unwaitfd( OPERATORS.writable, fd );
end


--- unwait
-- @param fd
-- @return ok
-- @return err
local function unwait( fd )
    local _, rerr = unwaitfd( OPERATORS.readable, fd );
    local _, werr = unwaitfd( OPERATORS.writable, fd );

    if not rerr and not werr then
        return true;
    end

    return false, rerr or werr;
end


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


--- revoke
function Callee:revoke()
    local event = self.synops.event;

    -- revoke signal events
    if self.sigset then
        local sigset = self.sigset;

        for _ = 1, #sigset do
            event:revoke( sigset:pop() );
        end
        self.sigset = nil;
    end

    -- revoke io event
    if self.evfd ~= -1 then
        local ev = self.ev;

        OPERATORS[self.evasa][self.evfd] = nil;
        self.ev = nil;
        self.evfd = -1;
        self.evasa = '';
        self.evuse = false;
        event:revoke( ev );
    end
end


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

    -- revoke all events currently in use
    self:revoke();

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
        -- revoke all events currently in use
        self:revoke();
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

    -- revoke all events currently in use
    self:revoke();
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
    end

    -- revoke all events currently in use
    self:revoke();
    if yield() == OP_RUNQ then
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


--- readUnlock
-- @param fd
function Callee:readUnlock( fd )
    rwunlock( self, RLOCKS, 'rlock', fd );
end


--- writeUnlock
-- @param fd
function Callee:writeUnlock( fd )
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


--- readLock
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Callee:readLock( fd, msec )
    return rwlock( self, RLOCKS, 'rlock', fd, msec );
end


--- writeLock
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Callee:writeLock( fd, msec )
    return rwlock( self, WLOCKS, 'wlock', fd, msec );
end


--- waitable
-- @param self
-- @param operators
-- @param asa
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
local function waitable( self, operators, asa, fd, msec )
    local runq = self.synops.runq;
    local event = self.synops.event;
    local op, fdno, disabled;

    -- fd is not watching yet
    if self.evfd ~= fd or self.evasa ~= asa then
        local callee = operators[fd];

        -- revoke retained event
        self:revoke();

        -- another callee has an 'asa' event of fd
        if callee then
            -- currently in-use
            if callee.evuse then
                return false, 'operation already in progress';
            end

            -- retain ev and related info
            self.ev = callee.ev;
            self.evfd = fd;
            self.evasa = asa;
            operators[fd] = self;
            self.ev:context( self );

            -- remove ev and related info
            callee.ev = nil;
            callee.evfd = -1;
            callee.evasa = '';
        end

        -- register to runq
        if msec then
            local ok, err = runq:push( self, msec );

            if not ok then
                return false, err;
            end
        end

        -- register io(readable or writable) event
        if not self.ev then
            local ev, err = event[asa]( event, self, fd );

            if err then
                if msec then
                    runq:remove( self );
                end

                return false, err;
            end

            -- retain ev and related info
            self.ev = ev;
            self.evfd = fd;
            self.evasa = asa;
            operators[fd] = self;
        end
    end

    self.evuse = true;
    -- wait until event fired
    op, fdno, disabled = yield();
    self.evuse = false;

    -- got io event
    if op == OP_EVENT then
        if fdno == fd then
            -- remove from runq
            if msec then
                runq:remove( self );
            end

            if disabled then
                self:revoke();
            end

            return true;
        end
    elseif op == OP_RUNQ then
        -- revoked by unwaitfd
        if self.evasa == 'unwaitfd' then
            self.evasa = '';
            return false;
        -- timed out
        elseif msec then
            return false, nil, true;
        end
    end

    -- remove from runq
    if msec then
        runq:remove( self );
    end

    -- revoke event
    self:revoke();

    -- normally unreachable
    error( 'invalid implements' );
end


--- waitReadable
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Callee:waitReadable( fd, msec )
    return waitable( self, OPERATORS.readable, 'readable', fd, msec );
end


--- waitWritable
-- @param fd
-- @param msec
-- @return ok
-- @return err
-- @return timeout
function Callee:waitWritable( fd, msec )
    return waitable( self, OPERATORS.writable, 'writable', fd, msec );
end


--- sleep
-- @param msec
-- @return ok
-- @return err
function Callee:sleep( msec )
    local ok, err = self.synops.runq:push( self, msec );

    if not ok then
        return false, err;
    end

    -- revoke all events currently in use
    self:revoke();
    if yield() == OP_RUNQ then
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

        -- revoke all events currently in use
        self:revoke();
        -- wait signal events
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
        -- ev = [event object]
        evfd = -1,
        evasa = '', -- '', 'readable' or 'writable'
        evuse = false, -- true or false
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
    unwait = unwait,
    unwaitReadable = unwaitReadable,
    unwaitWritable = unwaitWritable,
    resume = resume
};

