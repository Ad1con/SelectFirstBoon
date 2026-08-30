-- Mock ReturnOfModding surface: rom.gui, rom.ImGui, rom.log, rom.config.
local M = { logs = {}, guiCallbacks = {}, imguiCalls = {}, saves = 0 }

-- ------------------------------------------------------------ rom.config ----
-- Mirrors the primitives Chalk is built on: config_file:new(path, true),
-- :bind(section, key, default, description) -> entry, entry:get()/:set(),
-- and config_file:save().
local function makeConfig(initial, opts)
  opts = opts or {}
  local store = {}
  for k, v in pairs(initial or {}) do store[k] = v end
  M.store = store

  local file
  file = {
    bind = function(_, section, key, default, description)
      M.bound = M.bound or {}
      M.bound[key] = { section = section, default = default, description = description }
      if store[key] == nil then store[key] = default end
      return {
        get = function() return store[key] end,
        set = function(_, v) store[key] = v end,
      }
    end,
    save = function() M.saves = M.saves + 1 end,
  }

  return {
    config_file = {
      new = function(_, path, save)
        if opts.throw then error("simulated config_file failure") end
        M.configPath = path
        return file
      end,
    },
  }
end

-- ---------------------------------------------------------------- ImGui ----
-- `script` drives interaction: which combo opens, which selectable is clicked,
-- which checkbox toggles.
function M.makeImGui(script)
  script = script or {}
  local depth = { window = 0, combo = 0, menu = 0 }
  M.depth = depth
  local calls = {}
  M.imguiCalls = calls
  M.disabledTexts = {}
  local function rec(name) calls[#calls + 1] = name end

  local imgui
  imgui = {
    Begin = function(_, open)
      rec("Begin"); depth.window = depth.window + 1
      return (script.closeWindow ~= true), (script.collapsed ~= true)
    end,
    End = function() rec("End"); depth.window = depth.window - 1 end,
    BeginCombo = function() rec("BeginCombo")
      if script.openCombo then depth.combo = depth.combo + 1 end
      return script.openCombo == true
    end,
    EndCombo = function() rec("EndCombo"); depth.combo = depth.combo - 1 end,
    Selectable = function(id) rec("Selectable:" .. id)
      return script.click ~= nil and id:find(script.click, 1, true) ~= nil
    end,
    SliderFloat = function(label, value, minValue, maxValue, fmt)
      local scripted = script[label]
      if scripted ~= nil then return scripted, true end
      return value, false
    end,
    Checkbox = function(label, value)
      rec("Checkbox:" .. label)
      if script.toggle == label then return not value, true end
      return value, false
    end,
    BeginMenu = function() rec("BeginMenu")
      if script.openMenu then depth.menu = depth.menu + 1 end
      return script.openMenu == true
    end,
    EndMenu = function() rec("EndMenu"); depth.menu = depth.menu - 1 end,
    MenuItem = function(l) rec("MenuItem:" .. l); return script.clickMenuItem == l end,
    Text = function() rec("Text")
      -- Fails after Begin has pushed a window, which is the case that actually
      -- risks a leaked window if End is skipped.
      if script.errorInBody then error("simulated ImGui failure inside the window body") end
    end,
    TextDisabled = function(t) rec("TextDisabled"); M.lastDisabledText = t
      M.disabledTexts[#M.disabledTexts + 1] = t end,
    Separator = function() rec("Separator") end,
    Spacing = function() rec("Spacing") end,
    SameLine = function() rec("SameLine") end,
    AlignTextToFramePadding = function() rec("Align") end,
    PushItemWidth = function() rec("PushItemWidth") end,
    PopItemWidth = function() rec("PopItemWidth") end,
    IsItemHovered = function() return false end,
    SetTooltip = function() rec("SetTooltip") end,
    SetNextWindowSize = function() rec("SetNextWindowSize") end,
  }
  return imgui
end

function M.install(game, configOpts, configInitial, sjsonOpts)
  -- The plugin clears the stored pick at boot unless this is on (v4.9.0). Every
  -- scenario that seeds a God is testing what happens WITH a pick set, so the
  -- default here keeps it; the launch-reset scenario passes false explicitly.
  configInitial = configInitial or {}
  if configInitial.KeepPickAfterRestart == nil then
    configInitial.KeepPickAfterRestart = true
  end
  M.logs = {}
  M.guiCallbacks = {}
  M.saves = 0
  M.bound = nil
  M.configPath = nil
  M.hookedFile = nil
  M.animations = nil
  M.hookedFiles = nil
  M.obstacleFile = nil
  M.obstacles = nil
  M.byFile = nil
  rom = {
    game = game,
    log = {
      info = function(m) M.logs[#M.logs+1] = m end,
      -- Faithful to the real binding: rom.log.error RAISES. Any use of it from
      -- the main chunk kills the module load. Encoded here so the mistake
      -- cannot come back unnoticed.
      error = function(m) error(m, 2) end,
      warning = function(m) M.logs[#M.logs+1] = "WARN " .. m end,
    },
    ImGuiCond = { FirstUseEver = 4 },
    ImGui = M.makeImGui({}),
    path = { combine = function(a, b) return a .. "\\" .. b end },
    paths = { config = function() return "C:\\fake\\config" end, Content = "C:\\fake\\Content" },
    gui = {
      add_to_menu_bar = function(fn) M.guiCallbacks.menuBar = fn end,
      add_imgui       = function(fn) M.guiCallbacks.window = fn end,
    },
    mods = {
      -- Only LuaENVY-ENVY. SGG_Modding-ENVY is a deprecation shim that was
      -- never declared in the manifest, so a clean install would not have
      -- it; the mock offering it hid that the plugin depended on it.
      ["LuaENVY-ENVY"] = { auto = function() end },
      ["SGG_Modding-ModUtil"] = {
        once_loaded = { game = function(cb) M.pendingGameLoad = cb end },
      },
    },
  }
  -- An `a and b and nil or c` chain always yields c in Lua, so "absent" has to
  -- be a real branch or it silently installs a working config backend.
  if not (configOpts and configOpts.absent) then
    rom.config = makeConfig(configInitial, configOpts)
  end
  -- Real branch, not an `a and b and nil or c` chain: that always yields c in
  -- Lua and would silently install a working SJSON for the "absent" scenario.
  -- SGG_Modding-SJSON: to_object returns the table; hook records the target and
  -- runs the mutator against a stand-in Animations list.
  if not (sjsonOpts and sjsonOpts.absent) then
    rom.mods["SGG_Modding-SJSON"] = {
      to_object = function(tbl, order) M.lastOrder = order; return tbl end,
      -- Two different files get hooked now: the animations file for the icons
      -- and Obstacles/GUI.sjson for the button. Serve the right root for each.
      -- Keyed by path: more than one obstacle file and more than one animation
      -- file get hooked now, and a shared table would let the second wipe the
      -- first -- which is exactly the kind of thing a test should not hide.
      hook = function(path, fn)
        if sjsonOpts and sjsonOpts.throw then error("simulated sjson.hook failure") end
        M.hookedFiles = M.hookedFiles or {}
        M.hookedFiles[#M.hookedFiles + 1] = path
        M.byFile = M.byFile or {}
        local isObstacles = path:find("Obstacles", 1, true) ~= nil
        local root = isObstacles and "Obstacles" or "Animations"
        if M.byFile[path] == nil then M.byFile[path] = { [root] = {} } end
        fn(M.byFile[path])
        if isObstacles then
          M.obstacleFile = path
          M.obstacles = M.byFile[path]
        else
          M.hookedFile = path
          M.animations = M.byFile[path]
        end
      end,
    }
  end
  _PLUGIN = { guid = "Adicon-SelectFirstBoon" }
end

return M
