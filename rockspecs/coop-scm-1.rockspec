package = "coop"
version = "scm-1"
source = {
    url = "gitrec://github.com/mah0x211/lua-coop.git"
}
description = {
    summary = "coroutine based cooperative multitasking module",
    homepage = "https://github.com/mah0x211/lua-coop",
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
    "luarocks-fetch-gitrec >= 0.2",
    "deque >= 0.3.1",
    "sentry >= 0.5.0",
}
build = {
    type = "builtin",
    modules = {
        coop = "coop.lua",
        ['coop.aux'] = "lib/aux.lua",
        ['coop.callee'] = "lib/callee.lua",
        ['coop.event'] = "lib/event.lua",
        ['coop.runq'] = "lib/runq.lua",
        ['coop.coro'] = {
            incdirs = { "deps/lauxhlib" },
            sources = { "src/coro.c" }
        },
        ['coop.hrtimer'] = {
            incdirs = { "deps/lauxhlib" },
            sources = { "src/hrtimer.c" }
        }
    }
}
