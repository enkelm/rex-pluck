local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local directory = assert(source:match("(.*/)"), "Load rex-pluck from its init.lua module file.")
local M = {}

function M.setup()
  dofile(directory .. "pluck/init.lua")
  return M
end

return M
