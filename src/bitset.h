/**
 *  Copyright (C) 2023 Masatoshi Fukunaga
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a
 *  copy of this software and associated documentation files (the "Software"),
 *  to deal in the Software without restriction, including without limitation
 *  the rights to use, copy, modify, merge, publish, distribute, sublicense,
 *  and/or sell copies of the Software, and to permit persons to whom the
 *  Software is furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 *  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *  DEALINGS IN THE SOFTWARE.
 */

#ifndef bitset_h
#define bitset_h

#include <errno.h>
#include <limits.h>
#include <lua.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    size_t nbit;
    size_t len;
    uint_fast64_t *set;
} bitset_t;

#define BS_WIDTH (CHAR_BIT * sizeof(uint_fast64_t))

#define BIT2SET_SIZE(nbit)                                                     \
    (nbit < BS_WIDTH ? 1 : (nbit / BS_WIDTH) + !!(nbit % BS_WIDTH))

/**
 * Initialize bitset_t structure.
 * @param bs bitset_t structure to be initialized.
 * @param nbit number of initial bit capacity.
 * @return zero if success, otherwise -1 and set errno to indicate the error.
 */
static inline int bitset_init(bitset_t *bs, size_t nbit)
{
    size_t len = BIT2SET_SIZE(nbit);

    bs->set = (uint_fast64_t *)calloc(len, sizeof(uint_fast64_t));
    if (bs->set) {
        bs->len  = len;
        bs->nbit = len * BS_WIDTH;
        return 0;
    }
    return -1;
}

/**
 * Destroy bitset_t structure.
 * @param bs bitset_t structure to be freed.
 */
static inline void bitset_destroy(bitset_t *bs)
{
    if (bs->set) {
        free(bs->set);
        bs->nbit = 0;
        bs->len  = 0;
        bs->set  = NULL;
    }
}

/**
 * Resize a vector holding bits of bitset_t structure to the specified bit size.
 * @param bs bitset_t structure to be resized.
 * @param nbit number of new bit capacity.
 * @return zero if success, otherwise -1 and set errno to indicate the error.
 */
static inline int bitset_resize(bitset_t *bs, size_t nbit)
{
    if (!bs->set) {
        return bitset_init(bs, nbit);
    }

    size_t len = BIT2SET_SIZE(nbit);

    if (len != bs->len) {
        uint_fast64_t *set =
            (uint_fast64_t *)realloc(bs->set, sizeof(uint_fast64_t) * len);

        // failed to allocate memory
        if (!set) {
            return -1;
        }

        if (len > bs->len) {
            // clear allocated bits if size increased
            memset(set + bs->len, 0, (len - bs->len) * sizeof(uint_fast64_t));
        } else {
            // clear unused bits
            set[len - 1] &=
                (~((uint_fast64_t)0) >> (BS_WIDTH - nbit % BS_WIDTH));
        }

        // update properties
        bs->nbit = len * BS_WIDTH;
        bs->len  = len;
        bs->set  = set;
    }

    return 0;
}

#undef BIT2SET_SIZE

/**
 * Get bit value at the specified position.
 * @param bs bitset_t structure.
 * @param pos position of bit.
 * @return bit value 0 or 1 if success, otherwise -1 and set errno to indicate
 * the error.
 */
static inline int bitset_get(bitset_t *bs, uint_fast64_t pos)
{
    if (bs->set && pos < bs->nbit) {
        return (int)((bs->set[pos / BS_WIDTH] >> (pos % BS_WIDTH)) &
                     (uint_fast64_t)1);
    }
    errno = ERANGE;
    return -1;
}

/**
 * Set bit value at the specified position.
 * @param bs bitset_t structure.
 * @param pos position of bit.
 * @return zero if success, otherwise -1 and set errno to indicate the error.
 */
static inline int bitset_set(bitset_t *bs, uint_fast64_t pos)
{
    if (bs->set) {
        if (pos >= bs->nbit &&
            bitset_resize(bs, bs->nbit + (pos - bs->nbit) + 1) != 0) {
            return -1;
        }
        bs->set[pos / BS_WIDTH] |= (uint_fast64_t)1 << (pos % BS_WIDTH);
        return 0;
    }
    errno = ERANGE;
    return -1;
}

/**
 * Unset bit value at the specified position.
 * @param bs bitset_t structure.
 * @param pos position of bit.
 * @return zero if success, otherwise -1 and set errno to indicate the error.
 */
static inline int bitset_unset(bitset_t *bs, uint_fast64_t pos)
{
    if (bs->set && pos < bs->nbit) {
        bs->set[pos / BS_WIDTH] &= ~((uint_fast64_t)1 << (pos % BS_WIDTH));
        return 0;
    }
    errno = ERANGE;
    return -1;
}

/**
 * Find first zero bit position in the bitset and store it to pos.
 * @param bs bitset_t structure.
 * @param pos pointer to store position of first zero bit.
 * @return 1 if success, otherwise 0 if no zero bit found, -1 if error occurred.
 */
static inline int bitset_ffz(bitset_t *bs, uint_fast64_t *pos)
{
    if (bs->set) {
        for (size_t i = 0; i < bs->len; i++) {
            if (bs->set[i] != ~((uint_fast64_t)0)) {
                // found an element that is not all ones.
                // Use __builtin_ctz to find position of the first 0-bit
                size_t position = __builtin_ctzll(~bs->set[i]);
                *pos            = i * BS_WIDTH + position;
                return 1;
            }
        }
        // set pos to the end of bitset if no zero bit found
        *pos = bs->nbit;
        return 0;
    }
    errno = EINVAL; // Invalid argument
    return -1;
}

#undef BS_WIDTH

#endif
