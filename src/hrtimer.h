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
 *  hrtimer.h
 *  lua-act
 *  Created by Masatoshi Teruya on 17/03/05.
 *
 */

#ifndef act_hrtimer_h
#define act_hrtimer_h

#include <stdint.h>
#include <time.h>

#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/mach_time.h>

static inline uint64_t hrt_getnsec( void )
{
    static mach_timebase_info_data_t tbinfo = { 0 };

    if( tbinfo.denom == 0 ){
        (void)mach_timebase_info( &tbinfo );
    }

    return mach_absolute_time() * tbinfo.numer / tbinfo.denom;
}

#else

static inline uint64_t hrt_getnsec( void )
{
    struct timespec ts = {0};

#if defined(CLOCK_MONOTONIC_COARSE)
    clock_gettime( CLOCK_MONOTONIC_COARSE, &ts );
#else
    clock_gettime( CLOCK_MONOTONIC, &ts );
#endif

    return (uint64_t)ts.tv_sec * 1000000000 + (uint64_t)ts.tv_nsec;
}

#endif


static inline int hrt_nanosleep( uint64_t nsec )
{
    struct timespec req = {
        .tv_sec = nsec / UINT64_C(1000000000),
        .tv_nsec = nsec % UINT64_C(1000000000)
    };

    return nanosleep( &req, NULL );
}

#endif
