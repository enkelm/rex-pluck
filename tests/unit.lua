local source = debug.getinfo(1, "S").source:gsub("^@", "")
local directory = assert(source:match("(.*/)"))
local H = dofile(directory .. "harness.lua")
_G.H = H
dofile(directory .. "pluck.test.lua")
dofile(directory .. "pluck-window.test.lua")
dofile(directory .. "pluck-config.test.lua")
H.finish()
