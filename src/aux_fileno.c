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
 *  aux_fileno.c
 *  lua-synops
 *  Created by Masatoshi Teruya on 17/03/19.
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


static int filno_lua( lua_State *L )
{
    FILE *f = lauxh_checkfile( L, 1 );

    lua_pushinteger( L, fileno( f ) );

    return 1;
}


LUALIB_API int luaopen_synops_aux_fileno( lua_State *L )
{
    lua_pushcfunction( L, filno_lua );

    return 1;
}


