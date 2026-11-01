-- One automatically zoomed floating snapshot of all visible panes; no input to source programs.
local filename = debug.getinfo(1, "S").source
if filename:sub(1, 1) == "@" then filename = filename:sub(2) end
local directory = assert(filename:match("(.*/)"), "Load Pluck from its init.lua file.")
if ... == nil then -- Preserve the original direct-load entrypoint.
  return dofile(directory .. "config.lua").apply(nil, function(options) assert(loadfile(filename))(options) end)
end
local shell = "com.superlogical.terminal.shell"
local function checked(result, err)
  if result == nil then error(err or "Rex call failed.", 0) end
  return result
end

rex.action{
  name = "pluck_copy", title = "Pluck: Copy Token", category = "Terminal",
  keywords = "pluck copy hint url path sha uuid clipboard snapshot",
  description = "Copy a hinted token across all visible terminal panes in this tab, using a zoomed floating snapshot.",
  args = {},
  run = function(ctx)
    if not ctx.session_id or not ctx.block_id then error("Focus the intended terminal pane first.", 0) end
    local placement = checked(rex.session.describe_block{ block_id = ctx.block_id })
    local block = placement.block or {}
    if not block.window_id then error("The invoking pane is not in a window.", 0) end
    local view = checked(rex.session.view{})
    for _, window in ipairs(view.windows or {}) do
      if window.window_id == block.window_id then
        -- Reuse and rezoom this window's picker, including after a config reload.
        for _, layer in ipairs(window.layers or {}) do
          if layer.kind == "floating" then
            for _, candidate in ipairs(layer.blocks or {}) do
              if candidate.label == "Pluck" and candidate.flavor == shell then
                return checked(rex.session.zoom_block{ block_id = candidate.block_id, zoom = true })
              end
            end
          end
        end
        local status = checked(rex.call("server.status"))
        local created = checked(rex.session.new_layer{
          window_id = window.window_id, bounds = { 0.02, 0.02, 0.96, 0.96 }, focus = false,
          layout = rex.layout.block{
            flavor = shell, label = "Pluck",
            options = {
              command = { "/bin/sh", directory .. "launch.sh", ctx.block_id, status.instance_id,
                window.window_id, window.focused_block_id or ctx.block_id, window.zoomed_block_id or "" },
              exit = { on_completion = true, quick_exit_threshold_ms = 0 },
            },
          },
        })
        -- Zoom also takes focus. Do it in one call so an already zoomed source need not
        -- be unzoomed just to focus the floating picker first.
        local zoomed, zoom_err = rex.session.zoom_block{ block_id = created.block_ids[1], zoom = true }
        if not zoomed then
          rex.session.close_layer{ layer_id = created.layer_id }
          error(zoom_err or "Cannot zoom the Pluck picker.", 0)
        end
        return created
      end
    end
    error("The invoking window closed before Pluck opened.", 0)
  end,
}
