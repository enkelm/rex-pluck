-- Setup configuration stays local so this repository has no sibling-module dependency.
local name, prefix = "rex-pluck", "pluck_"
local defaults = { copy = "cmd+shift+y" }
local default_bounds = nil -- Pluck always zooms; geometry is not a public setup option.
local previous = {}
local M = {}

local function reject(message) error(name .. ": " .. message, 0) end
local function resolve(options)
  if options == nil then options = {} end
  if type(options) ~= "table" then reject("setup expects one config table") end
  for key in pairs(options) do
    if key ~= "bindings" and (key ~= "bounds" or not default_bounds) then
      reject("unknown setup option " .. tostring(key))
    end
  end
  local requested = options.bindings
  if requested ~= nil and requested ~= false and type(requested) ~= "table" then
    reject("bindings must be a table or false")
  end
  if type(requested) == "table" then
    for action in pairs(requested) do
      if defaults[action] == nil then reject("unknown binding action " .. tostring(action)) end
    end
  end
  local config, seen = { bindings = {} }, {}
  for action, default in pairs(defaults) do
    local key = default
    if requested == false then key = false
    elseif requested and requested[action] ~= nil then key = requested[action] end
    if key ~= false and (type(key) ~= "string" or not key:find("%S")) then
      reject("bindings." .. action .. " must be a non-empty key chord or false")
    end
    if key then
      if seen[key] then reject("bindings." .. action .. " duplicates the chord for " .. seen[key]) end
      seen[key] = action
    end
    config.bindings[action] = key
  end
  if default_bounds then
    local bounds = options.bounds
    if bounds == nil then bounds = default_bounds end
    if type(bounds) ~= "table" then reject("bounds must be {x, y, width, height}") end
    for key in pairs(bounds) do
      if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 4 then
        reject("bounds must contain exactly four coordinates")
      end
    end
    config.bounds = {}
    for index = 1, 4 do
      local value = bounds[index]
      if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        reject("bounds must contain four finite numbers")
      end
      config.bounds[index] = value
    end
    local x, y, width, height = config.bounds[1], config.bounds[2], config.bounds[3], config.bounds[4]
    if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > 1 or y + height > 1 then
      reject("bounds must be a positive rectangle inside the normalized 0..1 window")
    end
  end
  return config
end

function M.apply(options, register)
  local config = resolve(options) -- Reject bad input before touching actions or bindings.
  local current = {}
  for _, key in pairs(config.bindings) do if key then current[key] = true end end
  for key in pairs(previous) do if not current[key] then rex.unbind(key) end end
  register(config)
  for action, key in pairs(config.bindings) do if key then rex.bind(key, prefix .. action) end end
  previous = current
end

return M
