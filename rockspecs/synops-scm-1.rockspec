package = "synops"
version = "scm-1"
source = {
    url = "gitrec://github.com/mah0x211/lua-synops.git"
}
description = {
    summary = "coroutine based synchronously non-blocking operations module",
    homepage = "https://github.com/mah0x211/lua-synops",
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
    "luarocks-fetch-gitrec >= 0.2",
    "deque >= 0.3.1",
    "minheap >= 0.1.1",
    "sentry >= 0.6.0",
}
build = {
    type = "builtin",
    modules = {
        synops = "synops.lua",
        ['synops.aux'] = "lib/aux.lua",
        ['synops.callee'] = "lib/callee.lua",
        ['synops.event'] = "lib/event.lua",
        ['synops.runq'] = "lib/runq.lua",
        ['synops.coro'] = {
            incdirs = { "deps/lauxhlib" },
            sources = { "src/coro.c" }
        },
        ['synops.hrtimer'] = {
            incdirs = { "deps/lauxhlib" },
            sources = { "src/hrtimer.c" }
        }
    }
}
