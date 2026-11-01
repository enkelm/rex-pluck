local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local directory = assert(source:match("(.*/)"), "Load rex-pluck from its init.lua module file.")
local Config = dofile(directory .. "pluck/config.lua")
local M = {}

function M.setup(options)
  Config.apply(options, function(config)
    assert(loadfile(directory .. "pluck/init.lua"))(config)
  end)
  return M
end

return M
