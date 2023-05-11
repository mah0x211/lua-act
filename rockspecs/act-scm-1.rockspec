rockspec_format = "3.0"
package = "act"
version = "scm-1"
source = {
    url = "git+https://github.com/mah0x211/lua-act.git",
}
description = {
    summary = "coroutine based synchronously non-blocking operations module",
    homepage = "https://github.com/mah0x211/lua-act",
    license = "MIT/X11",
    maintainer = "Masatoshi Fukunaga",
}
dependencies = {
    "lua >= 5.1",
    "lauxhlib >= 0.5",
    "argv >= 0.3",
    "mah0x211/deque >= 0.5",
    "fork >= 0.2",
    "metamodule >= 0.4",
    "minheap >= 0.2",
    "nosigpipe >= 0.1",
    "reco >= 1.5",
    "epoll >= 0.2.0",
    "kqueue >= 0.3.0",
}
build = {
    type = "builtin",
    modules = {
        act = "act.lua",
        ['act.aux'] = "lib/aux.lua",
        ['act.callee'] = "lib/callee.lua",
        ['act.context'] = "lib/context.lua",
        ['act.event'] = "lib/event.lua",
        ['act.getcpus'] = {
            sources = {
                "src/getcpus.c",
            },
        },
        ['act.hrtimer'] = {
            sources = {
                "src/hrtimer.c",
            },
        },
        ['act.poller'] = "lib/poller.lua",
        ['act.pool'] = "lib/pool.lua",
        ['act.runq'] = "lib/runq.lua",
    },
}
