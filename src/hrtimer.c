/**
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
 *  hrtimer.c
 *  lua-act
 *  Created by Masatoshi Teruya on 17/03/05.
 *
 */
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
// lua
#include "hrtimer.h"
#include "lauxhlib.h"
#include <lauxlib.h>
#include <lua.h>

static int msleep_lua(lua_State *L)
{
    lua_Integer deadline = lauxh_checkuinteger(L, 1) * 1000000ULL;
    uint64_t now         = hrt_getnsec();

    if (deadline < now || hrt_nanosleep(deadline - now) == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }

    // got error
    lua_pushboolean(L, 0);
    lua_pushstring(L, strerror(errno));

    return 2;
}

static int nsleep_lua(lua_State *L)
{
    lua_Integer deadline = lauxh_checkuinteger(L, 1);
    uint64_t now         = hrt_getnsec();

    if (deadline < now || hrt_nanosleep(deadline - now) == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }

    // got error
    lua_pushboolean(L, 0);
    lua_pushstring(L, strerror(errno));

    return 2;
}

static int remain_lua(lua_State *L)
{
    lua_Integer msec = lauxh_checkuinteger(L, 1);
    uint64_t now     = hrt_getnsec() / 1000000ULL;

    // return a remaining msec
    if ((uint64_t)msec > now) {
        lua_pushinteger(L, msec - now);
    } else {
        lua_pushinteger(L, 0);
    }

    return 1;
}

static int getmsec_lua(lua_State *L)
{
    lua_Integer msec = lauxh_optuinteger(L, 1, 0);

    lua_pushinteger(L, hrt_getnsec() / 1000000ULL + (uint64_t)msec);

    return 1;
}

static int getnsec_lua(lua_State *L)
{
    lua_Integer nsec = lauxh_optuinteger(L, 1, 0);

    lua_pushinteger(L, hrt_getnsec() + (uint64_t)nsec);

    return 1;
}

LUALIB_API int luaopen_act_hrtimer(lua_State *L)
{
    lua_newtable(L);
    lauxh_pushfn2tbl(L, "getnsec", getnsec_lua);
    lauxh_pushfn2tbl(L, "getmsec", getmsec_lua);
    lauxh_pushfn2tbl(L, "remain", remain_lua);
    lauxh_pushfn2tbl(L, "nsleep", nsleep_lua);
    lauxh_pushfn2tbl(L, "msleep", msleep_lua);

    return 1;
}
