--
-- Copyright (C) 2023 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
--- @class reco
--- @field __call fun(self):(done:boolean,status:integer)
--- @field __tostring fun(self):string
--- @field reset fun(self, fn:function?)
--- @field results fun(self):(...:any)
local reco = require('reco')
return {
    new = require('reco').new, --- @type fun(fn:function):reco
    OK = reco.OK, --- @type integer
    YIELD = reco.YIELD, --- @type integer
    ERRRUN = reco.ERRRUN, --- @type integer
    ERRSYNTAX = reco.ERRSYNTAX, --- @type integer
    ERRMEM = reco.ERRMEM, --- @type integer
    ERRERR = reco.ERRERR, --- @type integer
}
