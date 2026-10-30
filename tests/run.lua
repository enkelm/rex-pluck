local source = debug.getinfo(1, "S").source:gsub("^@", "")
local directory = assert(source:match("(.*/)"))
local H = dofile(directory .. "harness.lua")
_G.H = H
dofile(directory .. "integration.test.lua")
H.finish()
