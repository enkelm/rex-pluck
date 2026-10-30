local directory = assert(debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)"))
dofile(directory .. "pluck/init.lua")
