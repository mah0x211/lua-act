/**
 *  Copyright (C) 2023 Masatoshi Fukunaga
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to
 *  deal in the Software without restriction, including without limitation the
 *  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 *  sell copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 *  IN THE SOFTWARE.
 */

#include "lauxhlib.h"

#define MODULE_MT "act.stack"

typedef struct {
    int ref;
    lua_State *L;
} act_stack_t;

static int unshift_lua(lua_State *L)
{
    int argc       = lua_gettop(L) - 1;
    act_stack_t *s = luaL_checkudata(L, 1, MODULE_MT);

    // prepend all arguments to stack
    if (argc > 0) {
        lua_xmove(s->L, L, lua_gettop(s->L));
        lua_xmove(L, s->L, lua_gettop(L) - 1);
    }

    return 0;
}

static int pop_lua(lua_State *L)
{
    act_stack_t *s = luaL_checkudata(L, 1, MODULE_MT);
    if (lua_gettop(s->L)) {
        lua_xmove(s->L, L, 1);
    }
    return lua_gettop(L) - 1;
}

static int push_lua(lua_State *L)
{
    int argc       = lua_gettop(L) - 1;
    act_stack_t *s = luaL_checkudata(L, 1, MODULE_MT);

    // append all arguments to stack
    if (argc > 0) {
        lua_xmove(L, s->L, argc);
    }

    return 0;
}

static int set_lua(lua_State *L)
{
    int argc       = lua_gettop(L) - 1;
    act_stack_t *s = luaL_checkudata(L, 1, MODULE_MT);
    lua_Integer n  = 0;

    // clear arguments
    lua_settop(s->L, 0);
    if (argc) {
        // store all arguments
        lua_xmove(L, s->L, argc);
    }

    return 0;
}

static int clear_lua(lua_State *L)
{
    act_stack_t *s = luaL_checkudata(L, 1, MODULE_MT);
    int n          = lua_gettop(L) - 1;

    if (n) {
        // append all arguments to stack
        lua_xmove(L, s->L, n);
    }
    // return all stack values
    n = lua_gettop(s->L);
    lua_xmove(s->L, L, n);
    return n;
}

static int len_lua(lua_State *L)
{
    act_stack_t *s = luaL_checkudata(L, 1, MODULE_MT);
    lua_pushinteger(L, lua_gettop(s->L));
    return 1;
}

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, MODULE_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    act_stack_t *s = lua_touserdata(L, 1);
    lua_settop(s->L, 0);
    lauxh_unref(L, s->ref);
    return 0;
}

static int new_lua(lua_State *L)
{
    int argc       = lua_gettop(L);
    act_stack_t *s = lua_newuserdata(L, sizeof(act_stack_t));

    s->L   = lua_newthread(L);
    s->ref = lauxh_ref(L);
    lauxh_setmetatable(L, MODULE_MT);
    if (argc) {
        lua_insert(L, 1);
        // store all arguments
        lua_xmove(L, s->L, argc);
    }
    return 1;
}

LUALIB_API int luaopen_act_stack(lua_State *L)
{
    struct luaL_Reg mmethod[] = {
        {"__gc",       gc_lua      },
        {"__tostring", tostring_lua},
        {"__len",      len_lua     },
        {NULL,         NULL        }
    };
    struct luaL_Reg method[] = {
        {"clear",   clear_lua  },
        {"set",     set_lua    },
        {"push",    push_lua   },
        {"pop",     pop_lua    },
        {"unshift", unshift_lua},
        {NULL,      NULL       }
    };

    // create table __metatable
    luaL_newmetatable(L, MODULE_MT);
    // metamethods
    for (struct luaL_Reg *ptr = mmethod; ptr->name; ptr++) {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
    }
    lua_newtable(L);
    for (struct luaL_Reg *ptr = method; ptr->name; ptr++) {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
    }
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    // add new function
    lua_pushcfunction(L, new_lua);
    return 1;
}
