-- The launcher exits after this call, automatically closing only its floating terminal.
local view, err = rex.session.view{}
if not view then error(err or "Cannot inspect the Rex view.", 0) end
if view.active_window_id ~= rex.args.window then return end
for _, window in ipairs(view.windows or {}) do
  if window.window_id == rex.args.window then
    if window.focused_block_id ~= rex.block_id then return end
    local own_picker = false
    for _, layer in ipairs(window.layers or {}) do
      if layer.kind == "floating" then
        for _, block in ipairs(layer.blocks or {}) do
          if block.block_id == rex.block_id and block.label == "Pluck" and block.flavor == "com.superlogical.terminal.shell" then
            own_picker = true
          end
        end
      end
    end
    if not own_picker then return end
    local zoomed = rex.args.zoom and rex.args.zoom ~= ""
    local target = zoomed and rex.args.zoom or rex.args.focus
    for _, layer in ipairs(window.layers or {}) do
      for _, block in ipairs(layer.blocks or {}) do
        if block.block_id == target and target ~= rex.block_id then
          local restored, restore_err
          if zoomed then restored, restore_err = rex.session.zoom_block{ block_id = target, zoom = true }
          else restored, restore_err = rex.session.focus_block{ block_id = target } end
          if not restored then error(restore_err or "Cannot restore the previous Rex view.", 0) end
          return
        end
      end
    end
    return -- The origin closed or moved. Never select a replacement pane in its place.
  end
end
