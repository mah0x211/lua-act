/*
 *  Copyright (C) 2017 Masatoshi Teruya
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to
 *  deal in the Software without restriction, including without limitation the
 *  rights to use, copy, modify, merge, publish, distribute, sublicense,
 *  and/or sell copies of the Software, and to permit persons to whom the
 *  Software is furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *  DEALINGS IN THE SOFTWARE.
 *
 *  pipe.c
 *  lua-act
 *  Created by Masatoshi Teruya on 17/03/19.
 *
 */
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <limits.h>
// lua
#include <lua.h>
#include <lauxlib.h>
#include "lauxhlib.h"


#define PIPE_READER_MT   "act.pipe.reader"
#define PIPE_WRITER_MT   "act.pipe.writer"

typedef struct {
    int fd;
} pipe_fd_t;


static int write_lua( lua_State *L )
{
    pipe_fd_t *p = lauxh_checkudata( L, 1, PIPE_WRITER_MT );
    size_t len = 0;
    const char *buf = lauxh_checklstring( L, 2, &len );
    ssize_t rv = 0;

    // invalid length
    if( !len ){
        lua_pushnil( L );
        lua_pushstring( L, strerror( EINVAL ) );
        return 2;
    }

    rv = write( p->fd, buf, len );
    switch( rv )
    {
        // closed by peer
        case 0:
            return 0;

        // got error
        case -1:
            // again
            if( errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ){
                lua_pushinteger( L, 0 );
                lua_pushnil( L );
                lua_pushboolean( L, 1 );
                return 3;
            }
            // closed by peer
            else if( errno == EPIPE ){
                return 0;
            }
            // got error
            lua_pushnil( L );
            lua_pushstring( L, strerror( errno ) );
            return 2;

        default:
            lua_pushinteger( L, rv );
            lua_pushnil( L );
            lua_pushboolean( L, len - (size_t)rv );
            return 3;
    }
}


static int read_lua( lua_State *L )
{
    pipe_fd_t *p = lauxh_checkudata( L, 1, PIPE_READER_MT );
    char buf[PIPE_BUF] = {0};
    ssize_t rv = read( p->fd, buf, PIPE_BUF );

    switch( rv ){
        // close by peer
        case 0:
        break;

        // got error
        case -1:
            lua_pushnil( L );
            // again
            if( errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ){
                lua_pushnil( L );
                lua_pushboolean( L, 1 );
                rv = 3;
            }
            // got error
            else {
                lua_pushstring( L, strerror( errno ) );
                rv = 2;
            }
        break;

        default:
            lua_pushlstring( L, buf, rv );
            rv = 1;
    }

    return rv;
}


static inline int close_lua( lua_State *L, const char *tname )
{
    pipe_fd_t *p = lauxh_checkudata( L, 1, tname );

    if( p->fd != -1 )
    {
        int fd = p->fd;

        p->fd = -1;
        if( close( fd ) == -1 ){
            lua_pushstring( L, strerror( errno ) );
            return 1;
        }
    }

    lua_pushnil( L );
    return 1;
}

static int close_writer_lua( lua_State *L ){
    return close_lua( L, PIPE_WRITER_MT );
}

static int close_reader_lua( lua_State *L ){
    return close_lua( L, PIPE_READER_MT );
}


static inline int fd_lua( lua_State *L, const char *tname )
{
    pipe_fd_t *p = lauxh_checkudata( L, 1, tname );

    lua_pushinteger( L, p->fd );
    return 1;
}

static int fd_writer_lua( lua_State *L ){
    return fd_lua( L, PIPE_WRITER_MT );
}

static int fd_reader_lua( lua_State *L ){
    return fd_lua( L, PIPE_READER_MT );
}


static inline int tostring_lua( lua_State *L, const char *tname )
{
    lua_pushfstring( L, "%s: %p", tname, lua_touserdata( L, 1 ) );
    return 1;
}

static int tostring_writer_lua( lua_State *L ){
    return tostring_lua( L, PIPE_WRITER_MT );
}

static int tostring_reader_lua( lua_State *L ){
    return tostring_lua( L, PIPE_READER_MT );
}


static int gc_lua( lua_State *L )
{
    pipe_fd_t *p = lua_touserdata( L, 1 );

    if( p->fd != -1 ){
        close( p->fd );
    }

    return 0;
}


static inline int setflags( int fd )
{
    int flg = fcntl( fd, F_GETFL, 0 );

    if( flg != -1 && fcntl( fd, F_SETFL, flg|O_NONBLOCK ) != -1 ){
        return fcntl( fd, F_SETFD, flg|FD_CLOEXEC );
    }

    return -1;
}


static int new_lua( lua_State *L )
{
    pipe_fd_t *reader = lua_newuserdata( L, sizeof( pipe_fd_t ) );
    pipe_fd_t *writer = lua_newuserdata( L, sizeof( pipe_fd_t ) );
    int fds[2];

    if( pipe( fds ) == 0 )
    {
        if( setflags( fds[0] ) == 0 && setflags( fds[1] ) == 0 ){
            *reader = (pipe_fd_t){ fds[0] };
            *writer = (pipe_fd_t){ fds[1] };
            luaL_getmetatable( L, PIPE_READER_MT );
            lua_setmetatable( L, -3 );
            luaL_getmetatable( L, PIPE_WRITER_MT );
            lua_setmetatable( L, -2 );

            return 2;
        }

        close( fds[0] );
        close( fds[1] );
    }

    // got error
    lua_pushnil( L );
    lua_pushnil( L );
    lua_pushstring( L, strerror( errno ) );

    return 3;
}


static inline void createmt( lua_State *L, const char *tname,
                             struct luaL_Reg *mmethods,
                             struct luaL_Reg *methods )
{
    struct luaL_Reg *ptr = mmethods;

    // create new metatable of tname already exists
    luaL_newmetatable( L, tname );
    // push metamethods
    while( ptr->name ){
        lauxh_pushfn2tbl( L, ptr->name, ptr->func );
        ptr++;
    }
    // push methods
    ptr = methods;
    lua_pushstring( L, "__index" );
    lua_newtable( L );
    while( ptr->name ){
        lauxh_pushfn2tbl( L, ptr->name, ptr->func );
        ptr++;
    }
    lua_rawset( L, -3 );
    lua_pop( L, 1 );
}


LUALIB_API int luaopen_act_pipe_syscall( lua_State *L )
{
    struct luaL_Reg reader_mmethods[] = {
        { "__gc", gc_lua },
        { "__tostring", tostring_reader_lua },
        { NULL, NULL }
    };
    struct luaL_Reg reader_methods[] = {
        { "fd", fd_reader_lua },
        { "close", close_reader_lua },
        { "read", read_lua },
        { NULL, NULL }
    };
    struct luaL_Reg writer_mmethods[] = {
        { "__gc", gc_lua },
        { "__tostring", tostring_writer_lua },
        { NULL, NULL }
    };
    struct luaL_Reg writer_methods[] = {
        { "fd", fd_writer_lua },
        { "close", close_writer_lua },
        { "write", write_lua },
        { NULL, NULL }
    };

    createmt( L, PIPE_READER_MT, reader_mmethods, reader_methods );
    createmt( L, PIPE_WRITER_MT, writer_mmethods, writer_methods );
    lua_pushcfunction( L, new_lua );

    return 1;
}

