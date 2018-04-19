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
 *  aux.c
 *  lua-act
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


typedef struct {
    void *mem;
    size_t blk;
    size_t cap;
    size_t use;
} aux_mem_t;


#define aux_mem_nil (aux_mem_t){    \
    .mem = NULL,                    \
    .blk = 0,                       \
    .cap = 0,                       \
    .use = 0                        \
}


static int aux_mem_init( aux_mem_t *m )
{
    long blk = sysconf( _SC_PAGESIZE );

    if( blk != -1 )
    {
        void *mem = malloc( blk );
        if( mem ){
            m->mem = mem;
            m->blk = blk;
            m->cap = blk;
            m->use = 0;
            return 0;
        }
    }

    return -1;
}


static void aux_mem_dispose( aux_mem_t *m )
{
    if( m->mem ){
        free( m->mem );
        m->mem = NULL;
    }
}


static int aux_mem_cpy( aux_mem_t *m, void *data, size_t len )
{
    size_t remain = m->cap - m->use;

    // grow mem block
    if( remain < len )
    {
        size_t nbyte = m->cap + ( len / m->blk + ( len % m->blk > 0 ) ) * m->blk;
        void *mem = realloc( m->mem, nbyte );

        if( !mem ){
            return -1;
        }
        m->mem = mem;
        m->cap = nbyte;
    }

    memcpy( m->mem + m->use, data, len );
    m->use += len;

    return 1;
}


static inline size_t decode_str( lua_State *L, uint8_t *data, size_t len,
                                 size_t pos )
{
    if( ( len - pos ) >= sizeof( size_t ) )
    {
        size_t slen = *(size_t*)(data + pos);

        pos += sizeof( size_t );
        if( ( len - pos ) >= slen ){
            const char *str = (const char*)(data + pos);

            lua_pushlstring( L, str, slen );
            return pos + slen;
        }
    }

    return 0;
}


static inline size_t decode_num( lua_State *L, uint8_t *data, size_t len,
                                 size_t pos )
{
    if( ( len - pos ) >= sizeof( lua_Number ) ){
        lua_Number *num = (lua_Number*)(data + pos);

        lua_pushnumber( L, *num );
        return pos + sizeof( lua_Number );
    }

    return 0;
}

static inline size_t decode_bol( lua_State *L, uint8_t *data, size_t len,
                                 size_t pos )
{
    if( ( len - pos ) >= 1 ){
        lua_pushboolean( L, data[pos] );
        return pos + 1;
    }

    return 0;
}


static size_t decode_val( lua_State *L, uint8_t *data, size_t len, size_t pos );

static inline size_t decode_tbl( lua_State *L, uint8_t *data, size_t len,
                                 size_t pos )
{
    if( ( len - pos ) >= ( sizeof( int ) + sizeof( int ) ) )
    {
        int narr = *(int*)(data + pos);
        int nrec = *(int*)(data + pos + sizeof( int ) );
        size_t tail = 0;
        int pair = 0;

        lua_createtable( L, narr, nrec );
        pos += sizeof( int ) + sizeof( int );

        while( pos < len )
        {
            switch( data[pos] )
            {
                case LUA_TNIL:
                    if( !pair ){
                        return pos + 1;
                    }
                    return 0;

                default:
                    if( !( pos = decode_val( L, data, len, pos ) ) ){
                        // unsupported value
                        return 0;
                    }
            }

            if( ++pair > 1 ){
                pair = 0;
                lua_rawset( L, -3 );
            }
        }

        return pos;
    }

    return 0;
}


static size_t decode_val( lua_State *L, uint8_t *data, size_t len, size_t pos )
{
    switch( data[pos++] ){
        case LUA_TBOOLEAN:
            return decode_bol( L, data, len, pos );

        case LUA_TNUMBER:
            return decode_num( L, data, len, pos );

        case LUA_TSTRING:
            return decode_str( L, data, len, pos );

        case LUA_TTABLE:
            return decode_tbl( L, data, len, pos );

        // found illegal byte sequence
        default:
            return 0;
    }
}


static int decode_lua( lua_State *L )
{
    size_t len = 0;
    uint8_t *data = (uint8_t*)lauxh_checklstring( L, 1, &len );
    size_t pos = 0;
    int n = 0;

    while( pos < len )
    {
        pos = decode_val( L, data, len, pos );
        if( !pos ){
            lua_settop( L, 0 );
            lua_pushnil( L );
            lua_pushstring( L, strerror( EILSEQ ) );
            return 2;
        }
        n++;
    }

    return n;
}


static inline int encode_str( lua_State *L, aux_mem_t *m, int idx )
{
    uint8_t buf[1 + sizeof( size_t )] = {
        LUA_TSTRING, 0
    };
    size_t *len = (size_t*)(buf + 1);
    const char *str = lua_tolstring( L, idx, len );

    if( aux_mem_cpy( m, (void*)buf, sizeof( buf ) ) == 1 )
    {
        if( *len ){
            return aux_mem_cpy( m, (void*)str, *len );
        }
        return 1;
    }

    return -1;
}


static inline int encode_num( lua_State *L, aux_mem_t *m, int idx )
{
    uint8_t buf[1 + sizeof( size_t )] = {
        LUA_TNUMBER, 0
    };
    lua_Number *num = (lua_Number*)(buf + 1);

    *num = lua_tonumber( L, idx );
    return aux_mem_cpy( m, (void*)buf, sizeof( buf ) );
}


static inline int encode_bol( lua_State *L, aux_mem_t *m, int idx )
{
    uint8_t buf[2] = {
        LUA_TBOOLEAN,
        (uint8_t)lua_toboolean( L, idx )
    };

    return aux_mem_cpy( m, (void*)buf, 2 );
}


static int encode_val( lua_State *L, aux_mem_t *m, int idx );

static int encode_tbl( lua_State *L, aux_mem_t *m, int idx )
{
    uint8_t buf[1 + sizeof( int ) * 2] = {
        LUA_TTABLE, 0
    };
    uint8_t *header = NULL;
    size_t offset = m->use + 1;
    int narr = 0;
    int nrec = 0;
    int kvidx = 0;

    // set header
    if( aux_mem_cpy( m, (void*)buf, sizeof( buf ) ) != 1 ){
        return -1;
    }

    // printf("ENCODE TABLE-------------- %d\n", lua_gettop( th ));
    // push space
    lua_pushnil( L );
    while( lua_next( L, idx ) )
    {
        kvidx = lua_gettop( L );
        switch( lua_type( L, kvidx - 1 ) )
        {
            case LUA_TBOOLEAN:
            case LUA_TNUMBER:
            case LUA_TSTRING:
            case LUA_TTABLE:
                switch( lua_type( L, kvidx ) )
                {
                    case LUA_TBOOLEAN:
                    case LUA_TNUMBER:
                    case LUA_TSTRING:
                    case LUA_TTABLE:
                        // encode keyval pair
                        if( encode_val( L, m, kvidx - 1 ) == 1 &&
                            encode_val( L, m, kvidx ) == 1 )
                        {
                            // printf("push keyval pair: narr:%d nrec: %d\n", *narr, *nrec);
                            // printf("concat: %d elms\n", lua_gettop( th ) - top );
                            if( lauxh_isinteger( L, -2 ) ){
                                narr++;
                            }
                            else {
                                nrec++;
                            }
                            lua_pop( L, 1 );
                            continue;
                        }
                        // failure
                        // printf("failed to push keyval pair: narr:%d nrec: %d\n", *narr, *nrec);
                        return -1;
                }
            break;

            default:
                lua_pop( L, 1 );
        }
    }

    // set narr and nrec
    *(int*)(m->mem + offset) = narr;
    *(int*)(m->mem + offset + sizeof( int )) = nrec;
    // set end-of-table
    *buf = LUA_TNIL;
    // printf("ENCODE TABLE--------------EOF %d\n", lua_gettop( th ) );

    return aux_mem_cpy( m, (void*)buf, 1 );
}


static int encode_val( lua_State *L, aux_mem_t *m, int idx )
{
    switch( lua_type( L, idx ) ){
        case LUA_TBOOLEAN:
            return encode_bol( L, m, idx );

        case LUA_TNUMBER:
            return encode_num( L, m, idx );

        case LUA_TSTRING:
            return encode_str( L, m, idx );

        case LUA_TTABLE:
            return encode_tbl( L, m, idx );

        // unsupported value
        default:
            // printf("found unsupported value %d %s\n", lua_type(L,idx), lua_typename(L,lua_type(L,idx)));
            return 0;
    }
}


static int encode_lua( lua_State *L )
{
    int argc = lua_gettop( L );
    aux_mem_t m = aux_mem_nil;
    int i = 1;

    if( aux_mem_init( &m ) == -1 ){
        lua_settop( L, 0 );
        lua_pushnil( L );
        lua_pushstring( L, strerror( errno ) );
        return 2;
    }

    for(; i <= argc; i++ )
    {
        if( encode_val( L, &m, i ) == -1 ){
            aux_mem_dispose( &m );
            lua_pushnil( L );
            lua_pushstring( L, strerror( errno ) );
            return 2;
        }
    }

    lua_settop( L, 0 );
    if( m.use ){
        lua_pushlstring( L, m.mem, m.use );
    }
    else {
        lua_pushnil( L );
    }
    aux_mem_dispose( &m );

    return 1;
}


static int fileno_lua( lua_State *L )
{
    FILE *f = lauxh_checkfile( L, 1 );

    lua_pushinteger( L, fileno( f ) );

    return 1;
}


LUALIB_API int luaopen_act_aux_syscall( lua_State *L )
{
    struct luaL_Reg funcs[] = {
        { "fileno", fileno_lua },
        { "encode", encode_lua },
        { "decode", decode_lua },
        { NULL, NULL }
    };
    struct luaL_Reg *ptr = funcs;

    lua_newtable( L );
    while( ptr->name ){
        lauxh_pushfn2tbl( L, ptr->name, ptr->func );
        ptr++;
    }

    return 1;
}


