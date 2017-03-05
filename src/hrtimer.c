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
 *  coro.c
 *  lua-coop
 *  Created by Masatoshi Teruya on 17/03/05.
 *
 */
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
// lua
#include <lua.h>
#include <lauxlib.h>
#include "lauxhlib.h"
#include "hrtimer.h"


#define MODULE_MT   "coop.hrtimer"


typedef struct {
    uint64_t nsec;
} hrtimer_t;


static int sleep_lua( lua_State *L )
{
    hrtimer_t *h = luaL_checkudata( L, 1, MODULE_MT );
    uint64_t nsec = hrt_getnsec();

    if( nsec > h->nsec || hrt_nanosleep( h->nsec - nsec ) == 0 ){
        lua_pushboolean( L, 1 );
        return 1;
    }

    // got error
    lua_pushboolean( L, 1 );
    lua_pushstring( L, strerror( errno ) );

    return 1;
}


static int remain_lua( lua_State *L )
{
    hrtimer_t *h = luaL_checkudata( L, 1, MODULE_MT );
    uint64_t nsec = hrt_getnsec();

    lua_pushinteger( L, ( nsec < h->nsec ) ? h->nsec - nsec : -1 );

    return 1;
}


static int init_lua( lua_State *L )
{
    hrtimer_t *h = luaL_checkudata( L, 1, MODULE_MT );
    lua_Integer msec = lauxh_checkinteger( L, 2 );

    h->nsec = hrt_getnsec() + (uint64_t)msec * 1000000ULL;

    return 0;
}


static int tostring_lua( lua_State *L )
{
    lua_pushfstring( L, MODULE_MT ": %p", lua_touserdata( L, 1 ) );
    return 1;
}


static int new_lua( lua_State *L )
{
    lua_Integer msec = lauxh_optinteger( L, 1, 0 );
    hrtimer_t *h = lua_newuserdata( L, sizeof( hrtimer_t ) );

    if( h ){
        h->nsec = hrt_getnsec() + (uint64_t)msec * 1000000ULL;
        lauxh_setmetatable( L, MODULE_MT );

        return 1;
    }

    // got error
    lua_pushnil( L );
    lua_pushstring( L, strerror( errno ) );

    return 2;
}


static int msleep_lua( lua_State *L )
{
    lua_Integer msec = lauxh_optinteger( L, 1, 0 );

    if( msec < 1 || hrt_nanosleep( msec * 1000000ULL ) == 0 ){
        lua_pushboolean( L, 1 );
        return 1;
    }

    // got error
    lua_pushboolean( L, 0 );
    lua_pushstring( L, strerror( errno ) );

    return 2;
}



LUALIB_API int luaopen_coop_hrtimer( lua_State *L )
{
    struct luaL_Reg mmethod[] = {
        { "__tostring", tostring_lua },
        { NULL, NULL }
    };
    struct luaL_Reg method[] = {
        { "init", init_lua },
        { "remain", remain_lua },
        { "sleep", sleep_lua },
        { NULL, NULL }
    };
    struct luaL_Reg *ptr = mmethod;

    // create table __metatable
    luaL_newmetatable( L, MODULE_MT );
    // metamethods
    while( ptr->name ){
        lauxh_pushfn2tbl( L, ptr->name, ptr->func );
        ptr++;
    }
    // metamethods
    ptr = method;
    lua_pushstring( L, "__index" );
    lua_newtable( L );
    while( ptr->name ){
        lauxh_pushfn2tbl( L, ptr->name, ptr->func );
        ptr++;
    }
    lua_rawset( L, -3 );
    lua_pop( L, 1 );

    // add new function
    lua_newtable( L );
    lauxh_pushfn2tbl( L, "new", new_lua );
    lauxh_pushfn2tbl( L, "msleep", msleep_lua );

    return 1;
}


