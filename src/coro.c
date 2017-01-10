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
 *  Created by Masatoshi Teruya on 17/01/08.
 *
 */


#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
// lua
#include <lua.h>
#include <lauxlib.h>
#include "lauxhlib.h"


// helper macros for lua_State
#define lstate_fn2tbl(L,k,v) do{ \
    lua_pushstring(L,k); \
    lua_pushcfunction(L,v); \
    lua_rawset(L,-3); \
}while(0)


#define lstate_num2tbl(L,k,v) do{ \
    lua_pushstring(L,k); \
    lua_pushinteger(L,v); \
    lua_rawset(L,-3); \
}while(0)


#define MODULE_MT   "coop.coro"


typedef struct {
    int ref_fn;
    int ref_co;
    int ref_arg;
    int ref_res;
    lua_State *co;
    lua_State *arg;
    lua_State *res;
} coro_t;


static int call_lua( lua_State *L )
{
    coro_t *coro = luaL_checkudata( L, 1, MODULE_MT );
    int argc = 0;
    lua_Integer status = 0;

    // clear res thread
    lua_settop( coro->res, 0 );

    // should create new thread
    if( !coro->co )
    {
CREATE_NEWTHREAD:
        // failed to create new thread
        if( !( coro->co = lua_newthread( L ) ) ){
            lua_pushstring( coro->res, strerror( errno ) );
            lua_pushinteger( L, LUA_ERRMEM );
            return 1;
        }

        // retain thread
        coro->ref_co = lauxh_ref( L );
        goto SET_ENTRYFN;
    }
    else
    {
        // get current status
        switch( lua_status( coro->co ) ){
            // push function and arguments
            case 0:
SET_ENTRYFN:
                lauxh_pushref( coro->co, coro->ref_fn );
                argc = lua_gettop( coro->arg );
                lua_xmove( coro->arg, coro->co, argc );
            break;

            // push arguments
            case LUA_YIELD:
                argc = lua_gettop( L ) - 1;
                if( argc ){
                    lua_xmove( L, coro->co, argc );
                }
            break;

            default:
                goto CREATE_NEWTHREAD;
        }
    }

    // run thread
#if LUA_VERSION_NUM >= 502
    status = lua_resume( coro->co, L, argc );
#else
    status = lua_resume( coro->co, argc );
#endif
    lua_settop( L, 0 );

    switch( status )
    {
        case 0:
            // move the return values to res thread
            lua_xmove( coro->co, coro->res, lua_gettop( coro->co ) );
            lua_pushboolean( L, 1 );
            return 1;

        case LUA_YIELD:
            // move the return values to res thread
            lua_xmove( coro->co, coro->res, lua_gettop( coro->co ) );
            lua_pushboolean( L, 0 );
            return 1;

        // LUA_ERRMEM:
        // LUA_ERRERR:
        // LUA_ERRSYNTAX:
        // LUA_ERRRUN:
        default:
            // move the return values to res thread
            lua_xmove( coro->co, coro->res, 1 );
            lua_pushboolean( L, 1 );
            lua_pushinteger( L, status );

            // create traceback
#if LUA_VERSION_NUM >= 502
            // push stack trace to res thread
            luaL_traceback( coro->res, coro->co, NULL, 0 );
#else
            // get debug module
            lua_getfield( coro->co, LUA_GLOBALSINDEX, "debug" );
            if( lua_istable( coro->co, -1 ) )
            {
                // get traceback function
                lua_getfield( coro->co, -1, "traceback" );
                if( lua_isfunction( coro->co, -1 ) ){
                    // call
                    lua_call( coro->co, 0, 1 );
                    // push stack trace to res thread
                    lua_xmove( coro->co, coro->res, 1 );
                }
            }
#endif

            // remove current thread
            coro->co = NULL;
            coro->ref_co = lauxh_unref( L, coro->ref_co );

            return 2;
    }
}


static int getres_lua( lua_State *L )
{
    coro_t *coro = luaL_checkudata( L, 1, MODULE_MT );
    int argc = lua_gettop( coro->res );

    if( argc ){
        lua_xmove( coro->res, L, argc );
        return argc;
    }

    return 0;
}


static int setarg_lua( lua_State *L )
{
    int argc = lua_gettop( L );
    coro_t *coro = luaL_checkudata( L, 1, MODULE_MT );

    if( argc > 1 ){
        lua_xmove( L, coro->arg, argc - 1 );
    }

    return 0;
}


static int init_lua( lua_State *L )
{
    int argc = lua_gettop( L );
    coro_t *coro = luaL_checkudata( L, 1, MODULE_MT );

    luaL_checktype( L, 2, LUA_TFUNCTION );
    if( argc > 2 ){
        lua_xmove( L, coro->arg, argc - 2 );
    }
    lauxh_unref( L, coro->ref_fn );
    coro->ref_fn = lauxh_ref( L );

    // remove current thread if yielded coroutine
    if( coro->co && lua_status( coro->co ) == LUA_YIELD ){
        coro->co = NULL;
        coro->ref_co = lauxh_unref( L, coro->ref_co );
    }

    return 0;
}


static int tostring_lua( lua_State *L )
{
    lua_pushfstring( L, MODULE_MT ": %p", lua_touserdata( L, 1 ) );
    return 1;
}


static int gc_lua( lua_State *L )
{
    coro_t *coro = lua_touserdata( L, 1 );

    lauxh_unref( L, coro->ref_fn );
    lauxh_unref( L, coro->ref_co );
    lauxh_unref( L, coro->ref_arg );
    lauxh_unref( L, coro->ref_res );

    return 0;
}


static int new_lua( lua_State *L )
{
    int argc = lua_gettop( L );
    lua_State *co = NULL;
    lua_State *arg = NULL;
    lua_State *res = NULL;

    luaL_checktype( L, 1, LUA_TFUNCTION );
    if( ( co = lua_newthread( L ) ) &&
        ( arg = lua_newthread( L ) ) &&
        ( res = lua_newthread( L ) ) )
    {
        int ref_res = lauxh_ref( L );
        int ref_arg = lauxh_ref( L );
        int ref_co = lauxh_ref( L );
        int ref_fn = LUA_NOREF;
        coro_t *coro = NULL;

        if( argc > 1 ){
            lua_xmove( L, arg, argc - 1 );
        }
        ref_fn = lauxh_ref( L );

        if( ( coro = lua_newuserdata( L, sizeof( coro_t ) ) ) ){
            *coro = (coro_t){
                .ref_fn = ref_fn,
                .ref_co = ref_co,
                .ref_arg = ref_arg,
                .ref_res = ref_res,
                .co = co,
                .arg = arg,
                .res = res
            };
            lauxh_setmetatable( L, MODULE_MT );
            return 1;
        }
    }

    // got error
    lua_settop( L, 0 );
    lua_pushnil( L );
    lua_pushstring( L, strerror( errno ) );

    return 2;
}


LUALIB_API int luaopen_coop_coro( lua_State *L )
{
    struct luaL_Reg mmethod[] = {
        { "__gc", gc_lua },
        { "__tostring", tostring_lua },
        { "__call", call_lua },
        { NULL, NULL }
    };
    struct luaL_Reg method[] = {
        { "init", init_lua },
        { "setarg", setarg_lua },
        { "getres", getres_lua },
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
    // add status code
    lauxh_pushnum2tbl( L, "OK", 0 );
    lauxh_pushnum2tbl( L, "YIELD", LUA_YIELD );
    lauxh_pushnum2tbl( L, "ERRMEM", LUA_ERRMEM );
    lauxh_pushnum2tbl( L, "ERRERR", LUA_ERRERR );
    lauxh_pushnum2tbl( L, "ERRSYNTAX", LUA_ERRSYNTAX );
    lauxh_pushnum2tbl( L, "ERRRUN", LUA_ERRRUN );

    return 1;
}


