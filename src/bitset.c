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

#include "bitset.h"
#include "lauxhlib.h"

#define MODULE_MT "act.bitset"

static int add_lua(lua_State *L)
{
    bitset_t *bs      = luaL_checkudata(L, 1, MODULE_MT);
    uint_fast64_t pos = 0;

    if (bitset_ffz(bs, &pos) == -1 || bitset_set(bs, pos) == -1) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        lua_pushinteger(L, errno);
        return 3;
    }
    lua_pushinteger(L, pos);
    return 1;
}

static int ffz_lua(lua_State *L)
{
    bitset_t *bs      = luaL_checkudata(L, 1, MODULE_MT);
    uint_fast64_t pos = 0;

    switch (bitset_ffz(bs, &pos)) {
    case 0:
    case 1:
        lua_pushinteger(L, pos);
        return 1;

    default:
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        lua_pushinteger(L, errno);
        return 3;
    }
}

static int unset_lua(lua_State *L)
{
    bitset_t *bs    = luaL_checkudata(L, 1, MODULE_MT);
    lua_Integer pos = lauxh_checkinteger(L, 2);

    switch (bitset_unset(bs, pos)) {
    case 0:
        lua_pushboolean(L, 1);
        return 1;

    default:
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        lua_pushinteger(L, errno);
        return 3;
    }
}

static int set_lua(lua_State *L)
{
    bitset_t *bs    = luaL_checkudata(L, 1, MODULE_MT);
    lua_Integer pos = lauxh_checkinteger(L, 2);

    switch (bitset_set(bs, pos)) {
    case 0:
        lua_pushboolean(L, 1);
        return 1;

    default:
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        lua_pushinteger(L, errno);
        return 3;
    }
}

static int get_lua(lua_State *L)
{
    bitset_t *bs    = luaL_checkudata(L, 1, MODULE_MT);
    lua_Integer pos = lauxh_checkinteger(L, 2);

    switch (bitset_get(bs, pos)) {
    case 0:
        lua_pushboolean(L, 0);
        return 1;
    case 1:
        lua_pushboolean(L, 1);
        return 1;
    default:
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        lua_pushinteger(L, errno);
        return 3;
    }
}

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, MODULE_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    bitset_t *bs = lua_touserdata(L, 1);
    bitset_destroy(bs);
    return 0;
}

static int new_lua(lua_State *L)
{
    bitset_t *bs = lua_newuserdata(L, sizeof(bitset_t));

    // init bitset
    if (bitset_init(bs, 64 * 64) == 0) {
        lauxh_setmetatable(L, MODULE_MT);
        return 1;
    }

    // failed to initialize bitset
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    lua_pushinteger(L, errno);
    return 3;
}

LUALIB_API int luaopen_act_bitset(lua_State *L)
{
    struct luaL_Reg mmethod[] = {
        {"__gc",       gc_lua      },
        {"__tostring", tostring_lua},
        {NULL,         NULL        }
    };
    struct luaL_Reg method[] = {
        {"get",   get_lua  },
        {"set",   set_lua  },
        {"unset", unset_lua},
        {"ffz",   ffz_lua  },
        {"add",   add_lua  },
        {NULL,    NULL     }
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
