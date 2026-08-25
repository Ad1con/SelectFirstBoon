-- =============================================================================
-- SelectFirstBoon test suite
-- =============================================================================
--
-- Run:   lua run_tests.lua        (from this directory)
-- Verified on Lua 5.1.5 and Lua 5.4.6. Both must pass before shipping.
--
-- WHY EVERYTHING AT THE TOP LEVEL IS A GLOBAL, WHICH LOOKS WRONG
--
-- Lua caps a function at 200 active local variables, and a file's main chunk is
-- a function. This suite grew past that: at 107 sections it declared 264 locals
-- at the top level, and Lua 5.4 refused to parse it with
--
--     run_tests.lua:2634: too many local variables (limit is 200) in main function
--
-- Lua 5.1 accepted the identical file, which is how it went unnoticed. The two
-- versions do not agree on this limit in practice, so "it runs here" was never
-- evidence that it runs anywhere.
--
-- Globals do not occupy registers, so making the top-level declarations global
-- removes the ceiling entirely. This is a standalone script, not a library, so
-- there is nothing for them to leak into. Sixteen bare forward declarations
-- became explicit "= nil" to stay valid statements.
--
-- Do not convert these back to locals. Adding sections will silently re-break
-- the parse on 5.4 while still working on 5.1.
-- =============================================================================

PLUGIN = "../main.lua"
M = dofile("./mocks.lua")

pass, fail = 0, 0
function check(name, cond, got)
  if cond then pass = pass + 1; print(("  PASS  %s"):format(name))
  else fail = fail + 1; print(("  FAIL  %s  (got: %s)"):format(name, tostring(got))) end
end
function section(s) print("\n" .. s) end
function logsMatch(pat)
  for _, m in ipairs(M.logs) do if m:find(pat, 1, true) then return m end end
  return nil
end

-- Fresh plugin instance each scenario, since it holds module-level state.
function boot(configOpts, configInitial, loadGame, sjsonOpts)
  local G = dofile("./harness.lua")
  M.install(G, configOpts, configInitial, sjsonOpts)
  M.pendingGameLoad = nil
  dofile(PLUGIN)
  if loadGame ~= false then
    assert(M.pendingGameLoad, "plugin never registered once_loaded.game")
    M.pendingGameLoad()
  end
  return G
end

function draw(script)
  rom.ImGui = M.makeImGui(script or {})
  M.guiCallbacks.window()
end
function drawMenu(script)
  rom.ImGui = M.makeImGui(script or {})
  M.guiCallbacks.menuBar()
end
-- The window starts closed, so every scenario that inspects it has to open it
-- through the menu first -- same path a player takes.
function openWindow()
  drawMenu({ openMenu = true, clickMenuItem = "Settings" })
end
function settingsGod(G)
  for _, c in ipairs(G.ScreenData.InventoryScreen.ItemCategories) do
    if c.Name == "First Boon" then return M.store.God end
  end
end
function disabledMatch(pat)
  for _, t in ipairs(M.disabledTexts or {}) do
    if t:find(pat, 1, true) then return t end
  end
  return nil
end

-- Buttons were indexed by position here, which meant every test that touched a
-- special or a gate broke the moment a fourth special was added. Look them up by
-- what they ARE instead: the layout is free to change, the identity is not.
function btnFor(scr, value)
  for _, b in ipairs(scr.SelectFirstBoonButtons or scr) do
    if b.SelectFirstBoonGod == value then return b end
  end
end
function gateBtn(scr, who)
  for _, b in ipairs(scr.SelectFirstBoonButtons or scr) do
    local g = b.SelectFirstBoonGate
    if g ~= nil and g.who == who then return b end
  end
end

-- 1 --------------------------------------------------------------------------
section("1. Default is vanilla: nothing is forced")
G = boot(nil, { God = "", RespectEligibility = true, LogDecisions = true })
G.CurrentRun = G.newRun()
r = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, r, {}, {})
check("boon left to vanilla roll", r.ForceLootName == "ApolloUpgrade", r.ForceLootName)
check("no force logged", logsMatch("forced first boon") == nil, nil)

-- 2 --------------------------------------------------------------------------
section("2. Catalog built from LootData")
check("nineteen boon gods found (nine vanilla plus ten added)", logsMatch("god catalog built from LootData (GodLoot, not DebugOnly): 19 entries") ~= nil,
  logsMatch("god catalog built"))

-- 3 --------------------------------------------------------------------------
section("3. Config wiring (ReturnOfModding config API, no Chalk, no import)")
check("cfg path built from the plugin guid",
  M.configPath == "C:\\fake\\config\\Adicon-SelectFirstBoon.cfg", M.configPath)
check("all five keys bound", M.bound ~= nil and M.bound.God ~= nil
  and M.bound.RespectEligibility ~= nil and M.bound.LogDecisions ~= nil
  and M.bound.BlockHermesBeforeBoon ~= nil and M.bound.BlockSeleneBeforeBoon ~= nil, nil)
check("bound with descriptions", M.bound and M.bound.God.description ~= "" , nil)
check("nothing raised at load", logsMatch("startup failed") == nil, logsMatch("startup failed"))

-- 4 --------------------------------------------------------------------------
section("4. Menu bar")
drawMenu({ openMenu = true, clickMenuItem = "Settings" })
check("BeginMenu/EndMenu balanced", M.depth.menu == 0, M.depth.menu)
draw({})
check("window rendered after menu click", #M.imguiCalls > 0, #M.imguiCalls)
check("Begin/End balanced", M.depth.window == 0, M.depth.window)

-- 5 --------------------------------------------------------------------------
section("5. Picking a god from the dropdown")
draw({ openCombo = true, click = "Zeus" })
check("BeginCombo/EndCombo balanced", M.depth.combo == 0, M.depth.combo)
check("setting written", M.store.God == "ZeusUpgrade", M.store.God)
check("flushed to disk", M.saves > 0, M.saves)
check("selection logged", logsMatch("god set to ZeusUpgrade") ~= nil, nil)

-- 6 --------------------------------------------------------------------------
section("6. The chosen god now takes effect, mid-run, with no restart")
G.CurrentRun = G.newRun()
r2 = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, r2, {}, {})
check("forced to Zeus", r2.ForceLootName == "ZeusUpgrade", r2.ForceLootName)

-- 7 --------------------------------------------------------------------------
section("7. Phase 1 invariants still hold with the god set from config")
G.CurrentRun = G.newRun()
chosen, a, b = {}, G.newRoom("Boon"), G.newRoom("Boon")
G.SetupRoomReward(G.CurrentRun, a, chosen, {})
table.insert(chosen, { RewardType = "Boon", ForceLootName = a.ForceLootName })
G.SetupRoomReward(G.CurrentRun, b, chosen, {})
check("two doors never both Zeus", a.ForceLootName == "ZeusUpgrade" and b.ForceLootName ~= "ZeusUpgrade", b.ForceLootName)

G.CurrentRun = G.newRun()
pre = G.newRoom("Boon", { ForceLootName = "AresUpgrade" })
G.SetupRoomReward(G.CurrentRun, pre, {}, {})
check("story-forced reward untouched", pre.ForceLootName == "AresUpgrade", pre.ForceLootName)

G.CurrentRun = G.newRun({ { Name = "HeraKeepsake", ForceBoonName = "HeraUpgrade", Uses = 1 } })
ks = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, ks, {}, {})
check("equipped keepsake still wins", ks.ForceLootName == "HeraUpgrade", ks.ForceLootName)

G.CurrentRun = G.newRun()
c1 = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, c1, {}, {})
G.GiveLoot({ ForceLootName = "ZeusUpgrade" })
c2 = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, c2, {}, {})
check("spent after the boon spawns", c2.ForceLootName ~= "ZeusUpgrade", c2.ForceLootName)

G.CurrentRun = G.newRun()
G.GiveLoot({ ForceLootName = "ZeusUpgrade", BoughtFromShop = true })
check("shop purchase does not spend it", G.CurrentRun.SelectFirstBoon_Spawned == nil, G.CurrentRun.SelectFirstBoon_Spawned)

nb = G.newRoom("WeaponUpgrade"); G.SetupRoomReward(G.CurrentRun, nb, {}, {})
check("non-boon rewards untouched", nb.ForceLootName == nil, nb.ForceLootName)

-- 8 --------------------------------------------------------------------------
section("8. Switching back to None")
draw({ openCombo = true, click = "Standard" })
check("setting cleared", M.store.God == "", M.store.God)
G.CurrentRun = G.newRun()
off = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, off, {}, {})
check("vanilla roll restored", off.ForceLootName == "ApolloUpgrade", off.ForceLootName)

-- 9 --------------------------------------------------------------------------
section("9. Eligibility toggle")
G = boot(nil, { God = "ZeusUpgrade", RespectEligibility = true, LogDecisions = true })
openWindow()
G.ELIGIBLE = { "ApolloUpgrade", "DemeterUpgrade" }
G.CurrentRun = G.newRun()
locked = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, locked, {}, {})
check("locked god declined", locked.ForceLootName == "ApolloUpgrade", locked.ForceLootName)
draw({ toggle = "First boon disabled for unmet gods" })
check("toggle persisted false", M.store.RespectEligibility == false, M.store.RespectEligibility)
G.CurrentRun = G.newRun()
unlocked = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, unlocked, {}, {})
check("now forces regardless (keepsake parity)", unlocked.ForceLootName == "ZeusUpgrade", unlocked.ForceLootName)

-- 10 -------------------------------------------------------------------------
section("10. Dropdown does not crash in the main menu")
G.CurrentRun = nil
draw({ openCombo = true })
check("no CurrentRun: rendered without error", logsMatch("window render failed") == nil, logsMatch("window render failed"))
check("status says no run", disabledMatch("No run in progress") ~= nil, M.lastDisabledText)

-- 11 -------------------------------------------------------------------------
section("11. Unknown god name in the .cfg")
-- Up to 4.24.0 this only warned and left the value sitting in the config. That
-- was survivable while the only way to get one was hand-editing; it stopped being
-- survivable when a god was REMOVED from the plugin (Medea, v4.25.0) and every
-- config that had picked her held a name nothing would ever answer to. The menu
-- would show that pick and it could never fire.
G = boot(nil, { God = "PanUpgrade", RespectEligibility = false, LogDecisions = true })
check("flagged in the log", logsMatch("no longer exists; reset to Standard") ~= nil, nil)
check("and actually cleared, not just complained about", M.store.God == "", M.store.God)
G.CurrentRun = G.newRun()
bogus = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, bogus, {}, {})
check("treated as None, vanilla roll kept", bogus.ForceLootName == "ApolloUpgrade", bogus.ForceLootName)

-- 12 -------------------------------------------------------------------------
section("12. Config backend missing entirely")
G = boot({ absent = true })
openWindow()
check("still installs", logsMatch("installed; first boon god is") ~= nil, nil)
check("says settings will not persist", logsMatch("will not persist") ~= nil, nil)
check("reported as a warning, not fatal", logsMatch("WARNING:") ~= nil, nil)
draw({ openCombo = true, click = "Hera" })
G.CurrentRun = G.newRun()
nochalk = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, nochalk, {}, {})
check("in-memory choice still works", nochalk.ForceLootName == "HeraUpgrade", nochalk.ForceLootName)

-- 13 -------------------------------------------------------------------------
section("13. Config backend throwing on load")
G = boot({ throw = true })
check("logged, not fatal", logsMatch("config load failed") ~= nil, nil)
check("hooks still installed", logsMatch("installed; first boon god is") ~= nil, nil)

-- 14 -------------------------------------------------------------------------
section("14. UI drawn before the game scripts finish loading")
G = boot(nil, { God = "ZeusUpgrade" }, false)
openWindow()
draw({})
check("no crash", logsMatch("window render failed") == nil, logsMatch("window render failed"))
check("Begin/End balanced", M.depth.window == 0, M.depth.window)
check("says it is waiting", disabledMatch("Waiting") ~= nil, M.lastDisabledText)

-- 15 -------------------------------------------------------------------------
section("15. An ImGui failure mid-window")
G = boot(nil, { God = "ZeusUpgrade" })
openWindow()
draw({ errorInBody = true })
check("End still called, no leaked window", M.depth.window == 0, M.depth.window)
check("failure logged", logsMatch("window render failed") ~= nil, nil)
draw({})
check("window closed itself rather than repeating", #M.imguiCalls == 0, #M.imguiCalls)
G.CurrentRun = G.newRun()
afterFail = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, afterFail, {}, {})
check("game logic unaffected by the UI failure", afterFail.ForceLootName == "ZeusUpgrade", afterFail.ForceLootName)

-- 16 -------------------------------------------------------------------------
section("16. Collapsed window")
G = boot(nil, { God = "ZeusUpgrade" })
openWindow()
draw({ collapsed = true })
check("Begin/End still balanced", M.depth.window == 0, M.depth.window)
check("body skipped", logsMatch("window render failed") == nil, nil)

-- 17 -------------------------------------------------------------------------
section("17. DebugOnly inherited by gods (the case I could not settle from source)")
-- EnableArtemis off, so the DebugOnly sweep really does empty the list. With her
-- on, she is registered after the sweep and would legitimately survive it.
G = dofile("./harness.lua")
for _, d in pairs(G.LootData) do if d.GodLoot then d.DebugOnly = true end end
-- Every added god off, not just the emblem four: any that registers after the
-- sweep survives it legitimately and the list is no longer empty.
M.install(G, nil, { God = "ZeusUpgrade", EnableArtemis = false, EnableAthena = false,
                   EnableDionysus = false, EnableHades = false,
                   EnableNarcissus = false, EnableArachne = false, EnableCirce = false,
                   EnableEcho = false, EnableIcarus = false, EnableMedea = false })
M.pendingGameLoad = nil
dofile(PLUGIN)
M.pendingGameLoad()
check("falls back to the unfiltered list", logsMatch("DebugOnly filter emptied the list") ~= nil, logsMatch("god catalog built"))
G.CurrentRun = G.newRun()
inherited = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, inherited, {}, {})
check("still forces correctly", inherited.ForceLootName == "ZeusUpgrade", inherited.ForceLootName)

-- 18 -------------------------------------------------------------------------
section("18. LootData unreadable entirely")
G = dofile("./harness.lua")
G.LootData = nil
M.install(G, nil, { God = "ZeusUpgrade" })
M.pendingGameLoad = nil
dofile(PLUGIN)
M.pendingGameLoad()
check("static fallback catalog used", logsMatch("static fallback list") ~= nil, logsMatch("god catalog built"))

-- 19 -------------------------------------------------------------------------
section("19. rom.log.error is never used (it raises in this build)")
sawRaise = false
G = dofile("./harness.lua")
M.install(G, { throw = true })
M.pendingGameLoad = nil
loaded = pcall(function() dofile(PLUGIN) end)
check("module still loads with a broken config backend", loaded, loaded)
if loaded and M.pendingGameLoad then
  G.ModUtil = nil                      -- force the install path to complain too
  local okGame = pcall(M.pendingGameLoad)
  check("and survives a missing ModUtil", okGame, okGame)
end
for _, m in ipairs(M.logs) do if m:find("WARNING:", 1, true) then sawRaise = true end end
check("failures surfaced as INFO/WARNING lines", sawRaise, nil)

-- 20 -------------------------------------------------------------------------
section("20. Never-first gates")
G = boot(nil, { God = "", BlockHermesBeforeBoon = true, BlockSeleneBeforeBoon = true, LogDecisions = true })
G.CurrentRun = G.newRun()
function elig(name) return G.IsRoomRewardEligible(G.CurrentRun, G.newRoom("x"), { Name = name }, {}, {}) end
check("Hermes held back with no boon", elig("HermesUpgrade") == false, elig("HermesUpgrade"))
check("Selene held back with no boon", elig("SpellDrop") == false, elig("SpellDrop"))
check("ordinary rewards untouched", elig("Boon") == true and elig("StackUpgrade") == true, nil)
check("logged once", logsMatch("holding HermesUpgrade out of the reward pool") ~= nil, nil)

G.CurrentRun.LootTypeHistory.ZeusUpgrade = 1
check("released once a god boon is held", elig("HermesUpgrade") == true, elig("HermesUpgrade"))
check("Selene released too", elig("SpellDrop") == true, elig("SpellDrop"))

G.CurrentRun = G.newRun()
G.CurrentRun.LootTypeHistory.WeaponUpgrade = 1
check("a hammer also releases the gate", elig("HermesUpgrade") == true, elig("HermesUpgrade"))

G.CurrentRun = G.newRun()
G.CurrentRun.LootTypeHistory.SpellDrop = 1
check("a Selene spell does not release it", elig("HermesUpgrade") == false, elig("HermesUpgrade"))

-- 21 -------------------------------------------------------------------------
section("21. Gates never turn ineligible into eligible")
G.ELIGIBLE_BASE = false
check("vanilla rejection preserved for Hermes", elig("HermesUpgrade") == false, elig("HermesUpgrade"))
check("vanilla rejection preserved for Boon", elig("Boon") == false, elig("Boon"))
G.ELIGIBLE_BASE = true

-- 22 -------------------------------------------------------------------------
section("22. Gates are independent settings")
G = boot(nil, { God = "", BlockHermesBeforeBoon = false, BlockSeleneBeforeBoon = true })
G.CurrentRun = G.newRun()
check("Hermes allowed when its gate is off", elig("HermesUpgrade") == true, elig("HermesUpgrade"))
check("Selene still held back", elig("SpellDrop") == false, elig("SpellDrop"))
openWindow()
draw({ toggle = "Selene waits until I hold a boon" })
check("toggle persisted", M.store.BlockSeleneBeforeBoon == false, M.store.BlockSeleneBeforeBoon)
check("Selene allowed immediately, mid-run", elig("SpellDrop") == true, elig("SpellDrop"))

-- 23 -------------------------------------------------------------------------
section("23. Gates work with no run, and alongside a forced god")
G = boot(nil, { God = "ZeusUpgrade", BlockHermesBeforeBoon = true })
G.CurrentRun = nil
check("no CurrentRun: does not block, does not throw", elig("HermesUpgrade") == true, elig("HermesUpgrade"))
G.CurrentRun = G.newRun()
both = G.newRoom("Boon"); G.SetupRoomReward(G.CurrentRun, both, {}, {})
check("god forcing still works", both.ForceLootName == "ZeusUpgrade", both.ForceLootName)
check("and Hermes still held back", elig("HermesUpgrade") == false, elig("HermesUpgrade"))
G.GiveLoot({ ForceLootName = "ZeusUpgrade" })
check("Zeus spawning alone does not release the gate (pickup does)", elig("HermesUpgrade") == false, elig("HermesUpgrade"))
G.CurrentRun.LootTypeHistory.ZeusUpgrade = 1
check("picking it up releases the gate", elig("HermesUpgrade") == true, elig("HermesUpgrade"))

-- 24 -------------------------------------------------------------------------
section("24. Availability markers past the max-gods cap")
G = boot(nil, { God = "ZeusUpgrade", RespectEligibility = true })
openWindow()
G.CurrentRun = G.newRun()
G.MAXED = false
draw({ openCombo = true })
check("below the cap: markers shown for genuinely unavailable gods",
  disabledMatch("Armed") ~= nil, M.lastDisabledText)

G.MAXED = true
G.CurrentRun.LootTypeHistory.ZeusUpgrade = 1
draw({ openCombo = true })
marked = false
for _, c in ipairs(M.imguiCalls) do
  -- Parenthesised, or the "Only force gods I have unlocked" checkbox label
  -- matches "locked" and the check is meaningless.
  if c:find("(unavailable)", 1, true) or c:find("(locked)", 1, true) then marked = true end
end
check("past the cap: no god is marked", not marked, marked)
check("and the UI explains why", disabledMatch("max-gods cap") ~= nil, M.lastDisabledText)
check("no render failure", logsMatch("window render failed") == nil, logsMatch("window render failed"))

-- 25 -------------------------------------------------------------------------
section("25. The word 'locked' is gone from the UI")
G = boot(nil, { God = "", RespectEligibility = true })
openWindow()
G.CurrentRun = G.newRun()
G.MAXED = false
G.ELIGIBLE = { "ZeusUpgrade" }
draw({ openCombo = true })
sawLocked, sawUnavailable = false, false
for _, c in ipairs(M.imguiCalls) do
  if c:find("(locked)", 1, true) then sawLocked = true end
  if c:find("(unavailable)", 1, true) then sawUnavailable = true end
end
check("never says (locked)", not sawLocked, sawLocked)
check("says (unavailable) instead", sawUnavailable, sawUnavailable)

-- 26 -------------------------------------------------------------------------
section("26. Native inventory tab: install")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true })
cats = G.ScreenData.InventoryScreen.ItemCategories
mine = nil
for _, c in ipairs(cats) do if c.Name == "First Boon" then mine = c end end
check("category inserted", mine ~= nil, nil)
check("vanilla categories untouched", #cats == 3 and cats[1].Name == "InventoryScreen_ResourcesTab", #cats)
check("points at our handlers", mine and mine.OpenFunctionName == "SelectFirstBoon_InventoryTabOpen"
  and mine.CloseFunctionName == "SelectFirstBoon_InventoryTabClose", nil)
check("handlers registered on the game table (CallFunctionName reads _G)",
  type(G.SelectFirstBoon_InventoryTabOpen) == "function"
  and type(G.SelectFirstBoon_InventoryTabClose) == "function", nil)
check("no GameStateRequirements, so it always shows", mine and type(mine.GameStateRequirements) == "table"
  and next(mine.GameStateRequirements) == nil, nil)
check("logged", logsMatch("inventory tab installed") ~= nil, nil)

-- 27 -------------------------------------------------------------------------
section("27. Install is idempotent")
M.pendingGameLoad()
count = 0
for _, c in ipairs(G.ScreenData.InventoryScreen.ItemCategories) do
  if c.Name == "First Boon" then count = count + 1 end
end
check("still exactly one category", count == 1, count)
check("said so", logsMatch("inventory tab already present") ~= nil, nil)

-- 28 -------------------------------------------------------------------------
section("28. Drawing the tab")
scr = G.newInventoryScreen()
G.textBoxWrites = {}
G.visibilityCalls = 0
okDraw = pcall(G.SelectFirstBoon_InventoryTabOpen, scr)
check("open handler does not throw", okDraw, okDraw)
-- Writes go to the screen's own right-hand scroll now, the same four boxes every
-- vanilla category uses, instead of a text block over the grid.
function writesTo(id)
  local out = {}
  for _, w in ipairs(G.textBoxWrites) do if w.Id == id then out[#out + 1] = w end end
  return out
end
nameWrites = writesTo(4301)
descWrites = writesTo(4302)
detailWrites = writesTo(4303)
flavorWrites = writesTo(4304)
check("writes into InfoBoxName", #nameWrites == 1 and nameWrites[1].RawText == "First Boon",
  nameWrites[1] and nameWrites[1].RawText)
check("writes the current god into InfoBoxDescription",
  #descWrites == 1 and descWrites[1].RawText:find("Zeus", 1, true) ~= nil,
  descWrites[1] and descWrites[1].RawText)
check("both gates get their own line in InfoBoxDetails",
  #detailWrites == 2 and detailWrites[1].Append == nil and detailWrites[2].Append == true,
  #detailWrites)
check("flavour line present", #flavorWrites == 1, #flavorWrites)
check("every box faded in", nameWrites[1].FadeTarget == 1.0 and flavorWrites[1].FadeTarget == 1.0, nil)
check("uses RawText, not the localisation path",
  nameWrites[1].RawText ~= nil and nameWrites[1].Text == nil, nil)
check("no text component of its own over the grid any more",
  scr.Components["SelectFirstBoonText"] == nil, nil)
-- Matches how the Pins tab does it (screen.NumItems = #GameState.StoreItemPins),
-- so InventoryScreenUpdateVisibility sees a real count.
check("NumItems reflects the buttons drawn", scr.NumItems == 26, scr.NumItems)
check("refreshes visibility", G.visibilityCalls == 1, G.visibilityCalls)

G.textBoxWrites = {}
okClose = pcall(G.SelectFirstBoon_InventoryTabClose, scr)
check("close handler does not throw", okClose, okClose)
-- The boxes are the screen's, so close hands them back empty instead of leaving
-- our text sitting under whatever category comes next.
cleared = 0
for _, w in ipairs(G.textBoxWrites) do
  if w.FadeTarget == 0.0 and w.RawText == nil then cleared = cleared + 1 end
end
check("close fades all four info boxes", cleared == 4, cleared)

-- 29 -------------------------------------------------------------------------
section("29. Tab failures never escape into the screen render path")
G.TEXTBOX_THROWS = true
check("open survives a throwing ModifyTextBox", pcall(G.SelectFirstBoon_InventoryTabOpen, G.newInventoryScreen()), nil)
check("close survives it too", pcall(G.SelectFirstBoon_InventoryTabClose, G.newInventoryScreen()), nil)
check("and it is logged", logsMatch("inventory tab open failed") ~= nil, nil)
G.TEXTBOX_THROWS = false
-- The tab builds its own text component now, so a screen with no
-- EmptyCategoryHint is simply irrelevant to it.
noHint = G.newInventoryScreen(false)
check("no longer depends on EmptyCategoryHint at all",
  pcall(G.SelectFirstBoon_InventoryTabOpen, noHint), nil)
-- A screen with no info boxes at all must degrade to silence, not to an error.
bare = G.newInventoryScreen()
bare.Components.InfoBoxName = nil
check("survives a screen with no info panel", pcall(G.SelectFirstBoon_InventoryTabOpen, bare), nil)
check("and says so", logsMatch("info panel components unavailable") ~= nil, nil)

-- 30 -------------------------------------------------------------------------
section("30. Tab can be switched off, and a missing screen is survivable")
G = boot(nil, { God = "", ShowInventoryTab = false })
found = false
for _, c in ipairs(G.ScreenData.InventoryScreen.ItemCategories) do
  if c.Name == "First Boon" then found = true end
end
check("no category added", not found, found)
check("said why", logsMatch("inventory tab disabled by config") ~= nil, nil)

G = dofile("./harness.lua")
G.ScreenData = nil
M.install(G, nil, { ShowInventoryTab = true })
M.pendingGameLoad = nil
dofile(PLUGIN)
M.pendingGameLoad()
check("missing ScreenData logged, not fatal", logsMatch("ItemCategories unavailable") ~= nil, nil)
check("the rest of the plugin still installed", logsMatch("installed; first boon god is") ~= nil, nil)

-- 31 -------------------------------------------------------------------------
section("31. Tab icon reflects the chosen god")
function tabIcon(G)
  for _, c in ipairs(G.ScreenData.InventoryScreen.ItemCategories) do
    if c.Name == "First Boon" then return c.Icon end
  end
end
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true })
check("uses the custom static symbol", tabIcon(G) == "SelectFirstBoon_Symbol_Zeus", tabIcon(G))
check("not the dialogue tab's icon", tabIcon(G):find("Icon-Log", 1, true) == nil, tabIcon(G))
check("logged with the icon", logsMatch("icon SelectFirstBoon_Symbol_Zeus") ~= nil, nil)

G = boot(nil, { God = "", ShowInventoryTab = true })
check("Standard uses the pomegranate, not a god", tabIcon(G) == "SelectFirstBoon_Symbol_Pom", tabIcon(G))
check("never a keepsake portrait", tabIcon(G):find("Keepsake", 1, true) == nil, tabIcon(G))

-- 32 -------------------------------------------------------------------------
section("32. Changing the god updates the icon live")
openWindow()
draw({ openCombo = true, click = "Hera" })
check("icon followed the selection", tabIcon(G) == "SelectFirstBoon_Symbol_Hera", tabIcon(G))
-- "##God" on purpose: the mock matches a Selectable by substring, and the
-- StandardIcon combo's own entries contain the word Standard in their ids.
draw({ openCombo = true, click = "Standard##none" })
check("and back to the pomegranate for Standard", tabIcon(G) == "SelectFirstBoon_Symbol_Pom", tabIcon(G))

-- 33 -------------------------------------------------------------------------
section("33. Icon fallback chain")
-- A god added by another plugin carries a namespaced loot name and may not set
-- Icon in the shape this expects. It does set SpeakerName, and that IS the art
-- folder name, so SpeakerName is tried before falling back to the god's own
-- BoonInfoIcon: a matched symbol beats an unmatched per-god icon.
G = dofile("./harness.lua")
G.LootData.ApolloUpgrade.Icon = nil
G.LootData.ApolloUpgrade.BoonInfoIcon = "BoonInfoSymbolApolloIcon"
M.install(G, nil, { God = "ApolloUpgrade", ShowInventoryTab = true })
M.pendingGameLoad = nil
dofile(PLUGIN)
M.pendingGameLoad()
check("no Icon: recovers the symbol from SpeakerName",
  tabIcon(G) == "SelectFirstBoon_Symbol_Apollo", tabIcon(G))

-- Only once BOTH are gone does the god's own icon get used.
G = dofile("./harness.lua")
G.LootData.ApolloUpgrade.Icon = nil
G.LootData.ApolloUpgrade.SpeakerName = nil
G.LootData.ApolloUpgrade.BoonInfoIcon = "BoonInfoSymbolApolloIcon"
M.install(G, nil, { God = "ApolloUpgrade", ShowInventoryTab = true })
M.pendingGameLoad = nil
dofile(PLUGIN)
M.pendingGameLoad()
check("no Icon and no SpeakerName: uses BoonInfoIcon",
  tabIcon(G) == "BoonInfoSymbolApolloIcon", tabIcon(G))

G = dofile("./harness.lua")
G.LootData.ApolloUpgrade.Icon = nil
G.LootData.ApolloUpgrade.SpeakerName = nil
G.LootData.ApolloUpgrade.BoonInfoIcon = nil
M.install(G, nil, { God = "ApolloUpgrade", ShowInventoryTab = true })
M.pendingGameLoad = nil
dofile(PLUGIN)
M.pendingGameLoad()
check("missing falls back rather than nil", tabIcon(G) == "SelectFirstBoon_Symbol_Pom", tabIcon(G))

-- 34 -------------------------------------------------------------------------
section("34. Custom static tab icons via sjson")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabIconScale = 0.45 })
check("hooked the animations file", M.hookedFile ~= nil
  and M.hookedFile:find("GUI_Screens_VFX.sjson", 1, true) ~= nil, M.hookedFile)
-- Twelve god symbols (Hammer joined the set for the hammer special) plus one
-- file-based entry for Selene, who has no symbol in BoonSelectSymbols.
-- Twelve god symbols (Hammer joined the set), one file-based entry for Selene,
-- and the twelve keepsake portraits. BOTH sets are registered every time so the
-- style is a live setting rather than a reinstall.
-- Twelve god symbols, one file entry for Selene's symbol-style art, twelve door
-- icons plus the hammer's, and twelve keepsake portraits. Every set is
-- registered every time so the style is a live setting, not a reinstall.
-- Sixteen god symbols (the twelve droppable ones plus Artemis, Athena, Dionysus
-- and Hades, whose art the base game already has), one file entry for Selene's
-- symbol-style art, twelve door icons plus the hammer and the flat pomegranate, and the portraits --
-- which now cover Artemis, Athena, Dionysus and Hades too, since the door style
-- sends them to a portrait rather than to their haloed symbol.
-- One Selene art now, plus one halo entry per file-based halo source (the two
-- vanilla halo sources register nothing -- they are the game's own animations).
check("registers all three sets, Selene's art and every halo source",
  M.animations ~= nil and #M.animations.Animations == 62,
  M.animations and #M.animations.Animations)
portraitEntry = nil
for _, e in ipairs(M.animations.Animations) do
  if e.Name == "SelectFirstBoon_Portrait_Zeus" then portraitEntry = e end
end
check("portraits come from the keepsake gift folder",
  portraitEntry ~= nil and portraitEntry.FilePath
    == "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_big\\Zeus",
  portraitEntry and portraitEntry.FilePath)
check("and are static and unlit, like their KeepsakeMax_Corner base",
  portraitEntry.NumFrames == 1 and portraitEntry.Material == "Unlit", nil)
seleneEntry, hammerEntry = nil, nil
for _, e in ipairs(M.animations.Animations) do
  if e.Name == "SelectFirstBoon_Symbol_@Selene" then seleneEntry = e end
  if e.Name == "SelectFirstBoon_Symbol_Hammer" then hammerEntry = e end
end
check("hammer uses the matched god symbol set",
  hammerEntry ~= nil and hammerEntry.FilePath == "GUI\\Screens\\BoonSelectSymbols\\Hammer",
  hammerEntry and hammerEntry.FilePath)
check("Selene uses her door-preview art instead",
  seleneEntry ~= nil and seleneEntry.FilePath == "Items\\Loot\\SpellDrop_Preview",
  seleneEntry and seleneEntry.FilePath)
check("and is static and unlit like the rest",
  seleneEntry.NumFrames == 1 and seleneEntry.Material == "Unlit", nil)
zeusEntry = nil
for _, e in ipairs(M.animations.Animations) do
  if e.Name == "SelectFirstBoon_Symbol_Zeus" then zeusEntry = e end
end
check("Zeus entry exists", zeusEntry ~= nil, nil)
check("points at the game's own matched art, nothing shipped",
  zeusEntry and zeusEntry.FilePath == "GUI\\Screens\\BoonSelectSymbols\\Zeus", zeusEntry and zeusEntry.FilePath)
check("static: single frame, no animated base",
  zeusEntry and zeusEntry.NumFrames == 1 and zeusEntry.StartFrame == 1 and zeusEntry.EndFrame == 1
  and zeusEntry.InheritFrom == nil, nil)
check("uses the configured scale", zeusEntry and zeusEntry.Scale == 0.45, zeusEntry and zeusEntry.Scale)
check("tab uses the custom icon", tabIcon(G) == "SelectFirstBoon_Symbol_Zeus", tabIcon(G))
check("logged", logsMatch("registered 62 custom tab icons at scale 0.45") ~= nil, nil)

G = boot(nil, { God = "", ShowInventoryTab = true, TabIconScale = 0.45 })
check("Standard uses the custom pomegranate symbol", tabIcon(G) == "SelectFirstBoon_Symbol_Pom", tabIcon(G))

-- 35 -------------------------------------------------------------------------
section("35. Scale is tunable, and 0 opts out")
G = boot(nil, { God = "HeraUpgrade", ShowInventoryTab = true, TabIconScale = 0.3 })
for _, e in ipairs(M.animations.Animations) do
  if e.Name == "SelectFirstBoon_Symbol_Hera" then
    check("scale follows the config", e.Scale == 0.3, e.Scale)
  end
end
G = boot(nil, { God = "HeraUpgrade", ShowInventoryTab = true, TabIconScale = 0 })
-- Scale 0 disables the TAB ICON set only. Artemis registers her own art through
-- a different pair of files and must be unaffected by an icon-scale setting.
hookedIcons = false
for _, f in ipairs(M.hookedFiles or {}) do
  if f:find("GUI_Screens_VFX", 1, true) then hookedIcons = true end
end
check("scale 0 skips the icon hook", not hookedIcons,
  M.hookedFiles and table.concat(M.hookedFiles, ","))
check("and falls back to the vanilla icon", tabIcon(G) == "BoonInfoSymbolHeraIcon", tabIcon(G))
check("said why", logsMatch("custom tab icons disabled") ~= nil, nil)

-- 36 -------------------------------------------------------------------------
section("36. sjson problems degrade to the vanilla icons")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabIconScale = 0.45 }, true, { absent = true })
check("missing SJSON: still installs", logsMatch("installed; first boon god is") ~= nil, nil)
check("falls back to the vanilla icon", tabIcon(G) == "BoonInfoSymbolZeusIcon", tabIcon(G))
check("said why", logsMatch("SGG_Modding-SJSON unavailable") ~= nil, nil)

G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabIconScale = 0.45 }, true, { throw = true })
check("throwing hook: still installs", logsMatch("installed; first boon god is") ~= nil, nil)
check("falls back to the vanilla icon", tabIcon(G) == "BoonInfoSymbolZeusIcon", tabIcon(G))
check("logged as a warning, not fatal", logsMatch("could not register custom tab icons") ~= nil, nil)

-- 37 -------------------------------------------------------------------------
section("37. Tab buttons: layout and state")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabIconScale = 0.45,
                SeleneHaloLayers = 2 })
scr2 = G.newInventoryScreen()
check("open does not throw", pcall(G.SelectFirstBoon_InventoryTabOpen, scr2), nil)
btns = scr2.SelectFirstBoonButtons
check("twenty-six buttons: Standard, nineteen gods, four specials, two gates",
  btns ~= nil and #btns == 26, btns and #btns)
check("first is Standard", btns[1].SelectFirstBoonGod == "", btns[1].SelectFirstBoonGod)
check("all wired to the pick handler",
  btns[1].OnPressedFunctionName == "SelectFirstBoon_InventoryTabPick", btns[1].OnPressedFunctionName)
-- Positions accumulate by repeated addition, so compare with a tolerance.
function near(a, b) return math.abs(a - b) < 0.001 end
-- Vanilla pitch, so icons land inside the slot frames drawn by the background.
check("uses the vanilla horizontal pitch", near(btns[2].Args.X - btns[1].Args.X, 133.6),
  btns[2].Args.X - btns[1].Args.X)
-- Fills a row to the screen's own GridWidth and then wraps, exactly as the
-- vanilla resource grid does (ResourceLogic.lua:614-620). GridWidth is 8, so
-- ten options are eight then two -- not a shape this plugin chose.
-- Rows are measured from GridStartY plus the icon nudge, not from GridStartY,
-- since every icon is shifted down inside its slot.
rowTop = 252 + 10
check("fills to the screen's GridWidth before wrapping",
  near(btns[8].Args.Y, rowTop) and near(btns[9].Args.Y, rowTop + 143),
  string.format("btn8.Y=%.1f btn9.Y=%.1f", btns[8].Args.Y, btns[9].Args.Y))
check("last column sits where vanilla's eighth column does",
  near(btns[8].Args.X, 149 + 7 * 133.6), btns[8].Args.X)
check("second row restarts at the left", near(btns[9].Args.X, 149), btns[9].Args.X)
-- A narrower screen has to be followed, not ignored.
narrow = G.newInventoryScreen()
narrow.GridWidth = 3
G.SelectFirstBoon_InventoryTabOpen(narrow)
nb = narrow.SelectFirstBoonButtons
check("follows a different GridWidth", near(nb[4].Args.X, 149) and near(nb[4].Args.Y, rowTop + 143),
  string.format("btn4=(%.1f,%.1f)", nb[4].Args.X, nb[4].Args.Y))
-- And a screen that reports none still lays out rather than piling up in place.
noWidth = G.newInventoryScreen()
noWidth.GridWidth = nil
G.SelectFirstBoon_InventoryTabOpen(noWidth)
check("falls back to 8 with no GridWidth",
  near(noWidth.SelectFirstBoonButtons[9].Args.X, 149), noWidth.SelectFirstBoonButtons[9].Args.X)
-- Clearance comes from the hitbox being one cell, not from spreading rows out.
check("button box is shorter than the row pitch", 141 < 143, nil)
check("button box is narrower than the column pitch", 132 < 133.6, nil)
check("buttons use our own obstacle, not the 340x360 vanilla one",
  btns[1].Args.Name == "SelectFirstBoon_Button_100", btns[1].Args.Name)
zeusBtn = nil
for _, b in ipairs(btns) do if b.SelectFirstBoonGod == "ZeusUpgrade" then zeusBtn = b end end
check("selected god is drawn bright", zeusBtn.Args.AlphaTarget == 1.0, zeusBtn.Args.AlphaTarget)
check("others are dimmed", btns[1].Args.AlphaTarget == 0.7, btns[1].Args.AlphaTarget)
check("each button gets its own icon", G.animations[zeusBtn.Id] == "SelectFirstBoon_Symbol_Zeus", G.animations[zeusBtn.Id])
check("we do NOT call SetGamepadNavigation ourselves (vanilla does it, driven by the category block)",
  (G.gamepadCalls or 0) == 0, G.gamepadCalls)
check("every button gets a highlight component", btns[1].Highlight ~= nil, nil)

-- 38 -------------------------------------------------------------------------
section("38. Clicking a god")
heraBtn = nil
for _, b in ipairs(btns) do if b.SelectFirstBoonGod == "HeraUpgrade" then heraBtn = b end end
check("click does not throw", pcall(G.SelectFirstBoon_InventoryTabPick, scr2, heraBtn), nil)
check("setting changed", settingsGod(G) == "HeraUpgrade", settingsGod(G))
check("persisted to the cfg", M.store.God == "HeraUpgrade", M.store.God)
check("clicked button brightened", G.alphas[heraBtn.Id] == 1.0, G.alphas[heraBtn.Id])
check("previous selection dimmed", G.alphas[zeusBtn.Id] == 0.7, G.alphas[zeusBtn.Id])
check("TAB ICON CHANGED LIVE, without reopening",
  G.animations[999] == "SelectFirstBoon_Symbol_Hera", G.animations[999])
check("and the stored category icon follows for next open",
  tabIcon(G) == "SelectFirstBoon_Symbol_Hera", tabIcon(G))

check("clicking Standard works too", pcall(G.SelectFirstBoon_InventoryTabPick, scr2, btns[1]), nil)
check("live icon back to the pomegranate", G.animations[999] == "SelectFirstBoon_Symbol_Pom", G.animations[999])

-- 39 -------------------------------------------------------------------------
section("39. Cleanup on tab switch")
before = #G.destroyed
check("close does not throw", pcall(G.SelectFirstBoon_InventoryTabClose, scr2), nil)
-- Ten buttons and ten highlights. The text block is gone: its content moved to
-- the screen's own info boxes, which are faded rather than destroyed.
-- Two buttons draw Selene's art -- her option and her gate -- and each of those
-- carries halo components on top of its icon and highlight. This scenario pins
-- SeleneHaloLayers = 2 rather than riding the shipped default, so a cosmetic
-- default change cannot break an arithmetic test about leaks. Two layers means
-- two extra components per Selene button, and a leak here would be invisible
-- until the component count mattered.
--
-- 68 to 72 when the selection light landed: the picked icon now carries its own
-- layers. That the number moved at all is the point of the test -- it proves the
-- new components are being destroyed with everything else rather than leaked.
check("every button, highlight and halo layer destroyed", #G.destroyed - before == 72,
  #G.destroyed - before)
check("button list cleared", scr2.SelectFirstBoonButtons == nil, scr2.SelectFirstBoonButtons)
check("component keys released", scr2.Components["SelectFirstBoonBtn_1"] == nil, nil)

check("reopening rebuilds cleanly", pcall(G.SelectFirstBoon_InventoryTabOpen, scr2), nil)
check("still exactly twenty-six", #scr2.SelectFirstBoonButtons == 26, #scr2.SelectFirstBoonButtons)

-- 40 -------------------------------------------------------------------------
section("40. Button failures stay contained")
G.COMPONENT_THROWS = true
scr3 = G.newInventoryScreen()
check("open survives a throwing CreateScreenComponent", pcall(G.SelectFirstBoon_InventoryTabOpen, scr3), nil)
check("logged", logsMatch("inventory tab open failed") ~= nil, nil)
G.COMPONENT_THROWS = false
check("a click with no god on the button is ignored",
  pcall(G.SelectFirstBoon_InventoryTabPick, scr2, { Id = 1 }), nil)

-- 41 -------------------------------------------------------------------------
section("41. Converged onto the vanilla grid configuration")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabIconScale = 0.45,
                SeleneHaloLayers = 2, VerboseTabLog = true })
cat = nil
for _, c in ipairs(G.ScreenData.InventoryScreen.ItemCategories) do
  if c.Name == "First Boon" then cat = c end
end
check("uses the Grid background, which draws the slot frames",
  cat.OpenAnimation == "InventoryScreenInGrid" and cat.CloseAnimation == "InventoryScreenOutGrid",
  cat.OpenAnimation)
-- Deliberately absent: SetGamepadNavigation then falls through to the screen's
-- own block, which is what the working resource grid uses.
check("no category GamepadNavigation override", cat.GamepadNavigation == nil, cat.GamepadNavigation)

scr4 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scr4)
b4 = scr4.SelectFirstBoonButtons
check("buttons carry an explicit Scale like the resource grid", b4[1].Args.Scale == 1.0, b4[1].Args.Scale)
check("hover handlers wired", b4[1].OnMouseOverFunctionName == "SelectFirstBoon_InventoryTabOver"
  and b4[1].OnMouseOffFunctionName == "SelectFirstBoon_InventoryTabOff", nil)
check("highlights sit at the same position as their button",
  b4[1].Highlight ~= nil, nil)
check("NumItems reflects the button count", scr4.NumItems == 26, scr4.NumItems)

-- 42 -------------------------------------------------------------------------
section("42. Verbose logging is usable as a diagnostic")
check("logs the row geometry", logsMatch("[tab] opening: 24 options, 8 per row (screen GridWidth)") ~= nil, nil)
check("logs the gate row too", logsMatch("gate Hermes Delay") ~= nil, nil)
check("logs every slot with its position", logsMatch("slot 10") ~= nil, nil)
check("marks which slot is selected", logsMatch("<- selected") ~= nil, nil)
G.SelectFirstBoon_InventoryTabPick(scr4, b4[10])
check("logs which slot a click resolved to", logsMatch("click resolved to slot 10") ~= nil, nil)
G.SelectFirstBoon_InventoryTabOver(b4[3])
check("logs hovers", logsMatch("hover on slot 3") ~= nil, nil)
G.SelectFirstBoon_InventoryTabClose(scr4)
check("logs cleanup counts", logsMatch("destroyed 72 components") ~= nil, nil)

G = boot(nil, { God = "", ShowInventoryTab = true, TabIconScale = 0.45, VerboseTabLog = false })
scr5 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scr5)
check("silent when switched off", logsMatch("[tab] opening") == nil, logsMatch("[tab] opening"))

-- 43 -------------------------------------------------------------------------
section("43. Custom button obstacle (the actual fix for clicks and controller)")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabIconScale = 0.45 })
check("hooked Obstacles/GUI.sjson", M.obstacleFile ~= nil
  and M.obstacleFile:find("Obstacles", 1, true) ~= nil, M.obstacleFile)
-- Icons, the button obstacle, and Artemis' two files.
-- Icons, the button obstacle, and two files per added god.
check("every sjson file hooked", M.hookedFiles ~= nil and #M.hookedFiles == 22, M.hookedFiles and #M.hookedFiles)
-- A LADDER of obstacles now, one per HitboxScale rung, because the geometry is
-- baked into GUI.sjson at load and cannot be resized afterwards. The rung in use
-- is chosen at draw time.
obs = nil
for _, o in ipairs(M.obstacles.Obstacles) do
  if o.Name == "SelectFirstBoon_Button_100" then obs = o end
end
check("registered the full-cell rung", obs ~= nil, obs and obs.Name)
check("and a rung for every step", #M.obstacles.Obstacles == 7, #M.obstacles.Obstacles)
check("inherits the interactable button base", obs.InheritFrom == "BaseInteractableButton", obs.InheritFrom)
pts = obs.Thing.Points
check("four corner points", #pts == 4, #pts)
-- The shipped rung is still one cell minus a hairline, so the boxes tile the
-- grid: no overlap into the neighbouring cell, and no gap for a controller step
-- to fall into. Smaller rungs make the mouse precise and cost exactly that,
-- which is why HitboxScale ships at 1.0.
check("box is one cell minus a hairline, not 340x360",
  near(pts[1].X, -65.8) and near(pts[1].Y, 70.5) and near(pts[3].X, 65.8) and near(pts[3].Y, -70.5),
  string.format("(%.1f,%.1f)..(%.1f,%.1f)", pts[1].X, pts[1].Y, pts[3].X, pts[3].Y))
check("box never reaches the next cell",
  (pts[3].X - pts[1].X) < 133.6 and (pts[1].Y - pts[3].Y) < 143, nil)
check("but leaves no gap wider than the 16-unit free-form step",
  (133.6 - (pts[3].X - pts[1].X)) < 16 and (143 - (pts[1].Y - pts[3].Y)) < 16, nil)
check("logged with the comparison", logsMatch("registered button obstacle SelectFirstBoon_Button at 132x141 from grid spacing") ~= nil, nil)
-- The verbose geometry line is only written when the tab actually opens.
G.SelectFirstBoon_InventoryTabOpen(G.newInventoryScreen())
check("verbose log names the obstacle in use", logsMatch("obstacle=SelectFirstBoon_Button") ~= nil, nil)

-- 44 -------------------------------------------------------------------------
section("44. Obstacle failures fall back to the vanilla button")
G = boot(nil, { God = "", ShowInventoryTab = true })
G.ScreenData.InventoryScreen.GridSpacingX = nil
M.pendingGameLoad = nil
-- Re-boot with the spacing missing, which is the only way the size can fail to
-- derive now that it is not a hand-entered number.
G2 = dofile("./harness.lua")
G2.ScreenData.InventoryScreen.GridSpacingX = nil
M.install(G2, nil, { God = "", ShowInventoryTab = true })
M.pendingGameLoad = nil
dofile(PLUGIN)
M.pendingGameLoad()
scrF = G2.newInventoryScreen(); G2.SelectFirstBoon_InventoryTabOpen(scrF)
check("no grid spacing falls back", scrF.SelectFirstBoonButtons[1].Args.Name == "ButtonInventoryItem",
  scrF.SelectFirstBoonButtons[1].Args.Name)
check("said so", logsMatch("custom button obstacle disabled (grid spacing unavailable)") ~= nil, nil)

G = boot(nil, { God = "", ShowInventoryTab = true }, true, { absent = true })
scrG = G.newInventoryScreen(); G.SelectFirstBoon_InventoryTabOpen(scrG)
check("no SJSON falls back", scrG.SelectFirstBoonButtons[1].Args.Name == "ButtonInventoryItem",
  scrG.SelectFirstBoonButtons[1].Args.Name)
check("and still installs", logsMatch("installed; first boon god is") ~= nil, nil)

-- 45 -------------------------------------------------------------------------
section("45. Controller cursor: CursorStartX/Y (the open path)")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabButtonHalfWidth = 60,
                TabButtonHalfHeight = 62, VerboseTabLog = true })
scrC = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrC)
btns = scrC.SelectFirstBoonButtons
zeus = nil
for _, b in ipairs(btns) do if b.SelectFirstBoonGod == "ZeusUpgrade" then zeus = b end end
check("the chosen god has a button", zeus ~= nil, nil)
-- OpenInventoryScreen (ResourceLogic.lua:355) prefers these over both defaults.
check("open path is told where to put the cursor",
  scrC.CursorStartX ~= nil and scrC.CursorStartY ~= nil, scrC.CursorStartX)
check("and it points at the selected god, not the corner",
  near(scrC.CursorStartX, zeus.SelectFirstBoonX) and near(scrC.CursorStartY, zeus.SelectFirstBoonY),
  string.format("(%.1f,%.1f) vs (%.1f,%.1f)", scrC.CursorStartX, scrC.CursorStartY,
                zeus.SelectFirstBoonX, zeus.SelectFirstBoonY))
check("logged", logsMatch("cursor start set to") ~= nil, nil)

-- Standard is slot 1, so this also covers the "nothing selected" fallback.
G = boot(nil, { God = "", ShowInventoryTab = true, TabButtonHalfWidth = 60, TabButtonHalfHeight = 62 })
scrD = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrD)
check("falls back to the first slot", near(scrD.CursorStartX, scrD.GridStartX)
  and near(scrD.CursorStartY, scrD.GridStartY + 10), scrD.CursorStartY)

-- 46 -------------------------------------------------------------------------
section("46. Controller cursor: the tab-switch paths, which ignore CursorStart")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabButtonHalfWidth = 60,
                TabButtonHalfHeight = 62, VerboseTabLog = true })
check("wrap reported", logsMatch("category cursor fix installed") ~= nil, nil)
cats = G.ScreenData.InventoryScreen.ItemCategories
myIndex = nil
for i, c in ipairs(cats) do if c.Name == "First Boon" then myIndex = i end end
check("our tab is last", myIndex == #cats, myIndex)

scrE = G.newInventoryScreen()
scrE.ActiveCategoryIndex = myIndex - 1
G.cursorTeleports = {}
G.InventoryScreenNextCategory(scrE, nil)
check("landed on our tab", scrE.ActiveCategoryIndex == myIndex, scrE.ActiveCategoryIndex)
check("vanilla parked it on the pin column first",
  scrE.cursorTeleports == nil and G.cursorTeleports[1].X == 614 and G.cursorTeleports[1].Y == 267,
  G.cursorTeleports[1] and G.cursorTeleports[1].X)
last = G.cursorTeleports[#G.cursorTeleports]
check("we moved it onto the grid afterwards",
  #G.cursorTeleports == 2 and near(last.X, scrE.CursorStartX) and near(last.Y, scrE.CursorStartY),
  string.format("%d teleports, last (%.1f,%.1f)", #G.cursorTeleports, last.X, last.Y))
check("logged", logsMatch("cursor moved to") ~= nil, nil)

-- Stepping away must not drag the cursor back.
G.cursorTeleports = {}
G.InventoryScreenNextCategory(scrE, nil)
check("leaves other tabs alone", scrE.ActiveCategoryIndex ~= myIndex and #G.cursorTeleports == 1,
  string.format("index %d, %d teleports", scrE.ActiveCategoryIndex, #G.cursorTeleports))

-- Backwards is the same wrap on the other function.
scrH = G.newInventoryScreen()
scrH.ActiveCategoryIndex = myIndex + 1 > #cats and 1 or myIndex + 1
G.cursorTeleports = {}
G.InventoryScreenPrevCategory(scrH, nil)
if scrH.ActiveCategoryIndex == myIndex then
  check("prev-category is wrapped too", #G.cursorTeleports == 2, #G.cursorTeleports)
else
  check("prev-category is wrapped too", false, "did not land on our tab")
end

-- 47 -------------------------------------------------------------------------
section("47. Buttons match the vanilla grid's hover contract")
scrI = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrI)
check("mouse-over sound set like ResourceLogic.lua:585",
  scrI.SelectFirstBoonButtons[1].MouseOverSound == "/SFX/Menu Sounds/DialoguePanelOutMenu",
  scrI.SelectFirstBoonButtons[1].MouseOverSound)

function catalogLabelOf(G, lootName)
  local data = G.LootData and G.LootData[lootName]
  if data ~= nil and type(data.SpeakerName) == "string" and data.SpeakerName ~= "" then
    return data.SpeakerName
  end
  return (string.match(lootName, "^(.-)Upgrade$")) or lootName
end

-- 48 -------------------------------------------------------------------------
section("48. Hover matches MouseOverResourceItem")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, VerboseTabLog = true,
                HighlightStyle = "frame" })
scrJ = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrJ)
bJ = scrJ.SelectFirstBoonButtons
zeusJ, otherJ = nil, nil
for _, b in ipairs(bJ) do
  if b.SelectFirstBoonGod == "ZeusUpgrade" then zeusJ = b elseif otherJ == nil then otherJ = b end
end

G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(zeusJ)
-- The frame is an animation on the highlight, not an alpha fade; up to 2.7.0
-- this tab faded a component that had no animation, so nothing ever appeared.
check("plays the slot-in animation on the highlight",
  G.animations[zeusJ.Highlight.Id] == "InventoryScreenSlotIn", G.animations[zeusJ.Highlight.Id])
sc = G.scales[zeusJ.Id]
-- Hovering multiplies the button's REST scale, and the pick rests larger, so a
-- hovered pick grows from its own size rather than shrinking to everyone else's.
check("grows the icon from its resting size",
  sc ~= nil and near(sc.Fraction, 1.25 * 1.33), sc and sc.Fraction)
-- Without this the box would grow with the art and overlap its neighbours again.
check("but not the hitbox", sc.SkipGeometryUpdate == true, sc.SkipGeometryUpdate)

function lastWriteTo(id)
  local out = nil
  for _, w in ipairs(G.textBoxWrites) do if w.Id == id then out = w end end
  return out
end
check("names the god in the info panel",
  writesTo(4301)[1].RawText == "Zeus", writesTo(4301)[1].RawText)
-- Every box keeps its meaning between rest and hover: Details is the gate lines
-- and nothing else, and what a press would do lives in Flavor.
check("says it is already the pick",
  writesTo(4304)[1].RawText == "Your current pick.", writesTo(4304)[1].RawText)
check("and the gate lines stay in Details, not shuffled elsewhere",
  writesTo(4303)[1].RawText:find("Hermes Delay", 1, true) ~= nil, writesTo(4303)[1].RawText)

G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(otherJ)
check("an unselected god invites a press",
  writesTo(4304)[1].RawText == "Press to make this your pick.", writesTo(4304)[1].RawText)

G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOff(otherJ)
check("plays the slot-out animation",
  G.animations[otherJ.Highlight.Id] == "InventoryScreenSlotOut", G.animations[otherJ.Highlight.Id])
check("returns the icon to full size", near(G.scales[otherJ.Id].Fraction, 1.0), G.scales[otherJ.Id].Fraction)
check("and restores the resting panel, rather than blanking it",
  writesTo(4301)[1].RawText == "First Boon", writesTo(4301)[1].RawText)

-- The unpicked option is the game's own behaviour, so it is named for that and
-- never called a random mode.
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(bJ[1])
check("the unpicked option is called Standard",
  writesTo(4301)[1].RawText == "Standard", writesTo(4301)[1].RawText)
check("and described as the game's own order",
  writesTo(4302)[1].RawText == "The game's own reward order, unchanged.",
  writesTo(4302)[1].RawText)
check("the word random appears nowhere in the panel",
  writesTo(4301)[1].RawText:lower():find("random") == nil
  and writesTo(4302)[1].RawText:lower():find("random") == nil, nil)

-- 49 -------------------------------------------------------------------------
section("49. Picking a god updates the panel in place")
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabPick(scrJ, otherJ)
check("the resting description follows the new selection",
  writesTo(4302)[1].RawText:find(catalogLabelOf(G, otherJ.SelectFirstBoonGod), 1, true) ~= nil,
  writesTo(4302)[1].RawText)

-- 50 -------------------------------------------------------------------------
section("50. Specials queue a reward priority, the other half of a keepsake")
G = boot(nil, { God = "@Hammer", ShowInventoryTab = true })
G.CurrentRun = G.newRun()
chosen = G.ChooseRoomReward(G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {})
check("RewardStoreAddPriority was called once", #G.priorityCalls == 1, #G.priorityCalls)
check("with the reward type, not a god", G.priorityCalls[1].Name == "WeaponUpgrade",
  G.priorityCalls[1].Name)
-- Vanilla defaults to RunProgress; passing the store the room is actually
-- reading means the top-up lands in the right carousel.
check("and the store the room is reading", G.priorityCalls[1].RewardStoreName == "RunProgress",
  G.priorityCalls[1].RewardStoreName)
check("so the room's reward is the hammer", chosen == "WeaponUpgrade", chosen)
-- ChooseRoomReward removes a priority once it fires, so it is one-shot.
check("priority consumed after firing", #G.CurrentRun.RewardPriorities == 0,
  #G.CurrentRun.RewardPriorities)

-- ChooseRoomReward runs once per door and recurses on an empty store, so the
-- guard has to be idempotent.
second = G.ChooseRoomReward(G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {})
check("never queued twice in one run", #G.priorityCalls == 1, #G.priorityCalls)
check("the next door rolls normally", second ~= "WeaponUpgrade", second)

-- The guard lives on CurrentRun, so a new run queues again.
G.CurrentRun = G.newRun()
G.ChooseRoomReward(G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {})
check("a new run queues again", #G.priorityCalls == 2, #G.priorityCalls)

-- 51 -------------------------------------------------------------------------
section("51. A god pick queues \"Boon\", which is the parity that was missing")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, PriorityFirstReward = true })
G.CurrentRun = G.newRun()
godChoice = G.ChooseRoomReward(G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {})
check("queues Boon, not the god name", G.priorityCalls[1].Name == "Boon", G.priorityCalls[1].Name)
check("so the first reward is a boon", godChoice == "Boon", godChoice)
check("logged as keepsake parity", logsMatch("the way an equipped keepsake does") ~= nil, nil)

G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, PriorityFirstReward = false })
G.CurrentRun = G.newRun()
G.ChooseRoomReward(G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {})
check("switchable off", #G.priorityCalls == 0, #G.priorityCalls)

-- Standard must never queue anything at all.
G = boot(nil, { God = "", ShowInventoryTab = true, PriorityFirstReward = true })
G.CurrentRun = G.newRun()
G.ChooseRoomReward(G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {})
check("Standard queues nothing", #G.priorityCalls == 0, #G.priorityCalls)

-- 52 -------------------------------------------------------------------------
section("52. Picking Hermes or Selene suppresses its own gate")
-- Both gates on AND Hermes picked: without suppression the plugin would queue
-- HermesUpgrade and then make it ineligible, so the priority could never fire.
G = boot(nil, { God = "@Hermes", BlockHermesBeforeBoon = true, BlockSeleneBeforeBoon = true })
G.CurrentRun = G.newRun()
function eligibleNow(name)
  return G.IsRoomRewardEligible(G.CurrentRun, G.newRoom("x"), { Name = name }, {}, {})
end
check("Hermes is let through despite its gate", eligibleNow("HermesUpgrade"), nil)
check("Selene's gate is untouched", not eligibleNow("SpellDrop"), nil)
check("said why, once", logsMatch("is the first reward you asked for") ~= nil, nil)
hermesChoice = G.ChooseRoomReward(G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {})
check("so Hermes actually lands first", hermesChoice == "HermesUpgrade", hermesChoice)

-- The gate SETTING is left alone, so unpicking restores it with no user action.
check("the gate setting itself was not rewritten", M.store.BlockHermesBeforeBoon == true,
  M.store.BlockHermesBeforeBoon)

G = boot(nil, { God = "@Selene", BlockHermesBeforeBoon = true, BlockSeleneBeforeBoon = true })
G.CurrentRun = G.newRun()
check("mirror case: Selene through, Hermes held",
  G.IsRoomRewardEligible(G.CurrentRun, G.newRoom("x"), { Name = "SpellDrop" }, {}, {})
  and not G.IsRoomRewardEligible(G.CurrentRun, G.newRoom("x"), { Name = "HermesUpgrade" }, {}, {}), nil)

-- With no special picked the gates behave exactly as before.
G = boot(nil, { God = "ZeusUpgrade", BlockHermesBeforeBoon = true, BlockSeleneBeforeBoon = true })
G.CurrentRun = G.newRun()
check("a god pick suppresses neither gate",
  not G.IsRoomRewardEligible(G.CurrentRun, G.newRoom("x"), { Name = "HermesUpgrade" }, {}, {})
  and not G.IsRoomRewardEligible(G.CurrentRun, G.newRoom("x"), { Name = "SpellDrop" }, {}, {}), nil)

-- 53 -------------------------------------------------------------------------
section("53. Specials never touch the god path")
G = boot(nil, { God = "@Selene", ShowInventoryTab = true })
check("no bogus unknown-god warning", logsMatch("no longer exists") == nil,
  logsMatch("no longer exists"))
G.CurrentRun = G.newRun()
room = G.newRoom("Boon")
G.SetupRoomReward(G.CurrentRun, room, {}, {})
-- Vanilla still rolls its own god here; what matters is that the special did not
-- reach into that decision the way a god pick does.
check("ForceLootName is vanilla's roll, not the special",
  room.ForceLootName ~= "@Selene" and room.ForcedBoonNames["@Selene"] == nil, room.ForceLootName)
check("and the god path never claimed to have forced anything",
  logsMatch("forced first boon to") == nil, logsMatch("forced first boon to"))
-- A truly unknown value still warns, so the check above is not vacuous.
G = boot(nil, { God = "@Nonsense", ShowInventoryTab = true })
check("an unknown value still warns", logsMatch("no longer exists; reset to Standard") ~= nil, nil)

-- 54 -------------------------------------------------------------------------
section("54. Specials in the tab and the panel")
G = boot(nil, { God = "@Selene", ShowInventoryTab = true, TabIconScale = 0.45, VerboseTabLog = true })
scrS = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrS)
sb = scrS.SelectFirstBoonButtons
check("four specials appended after the gods",
  btnFor(sb, "@Hammer") ~= nil and btnFor(sb, "@Hermes") ~= nil
    and btnFor(sb, "@Selene") ~= nil and btnFor(sb, "@Chaos") ~= nil,
  nil)
check("hammer draws the matched god symbol",
  G.animations[btnFor(sb, "@Hammer").Id] == "SelectFirstBoon_Symbol_Hammer",
  G.animations[btnFor(sb, "@Hammer").Id])
-- She has no matched entry in any set, so she gets her own single entry and the
-- same name resolves in every style.
check("Selene draws her own art",
  G.animations[btnFor(sb, "@Selene").Id] == "SelectFirstBoon_Selene_preview",
  G.animations[btnFor(sb, "@Selene").Id])
check("the tab icon follows the special", tabIcon(G) == "SelectFirstBoon_Selene_preview", tabIcon(G))

G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(btnFor(sb, "@Hammer"))
check("the panel names the special, not a god key",
  writesTo(4301)[1].RawText == "Daedalus Hammer", writesTo(4301)[1].RawText)
check("and describes it as a first REWARD",
  writesTo(4302)[1].RawText:find("first reward", 1, true) ~= nil, writesTo(4302)[1].RawText)

-- The resting panel has to say the gate is overridden, not that it is on -- and
-- as one word, not a sentence in capitals.
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOff(btnFor(sb, "@Hammer"))
detail = writesTo(4303)
-- Reporting ONLY "Overridden" hid whether the gate was on or off, so pressing
-- the button looked like it did nothing. The setting comes first now.
check("the overridden gate still reports its own on/off state",
  detail[2] ~= nil and detail[2].RawText == "Selene Delay:  On (overridden by first boon choice)",
  detail[2] and detail[2].RawText)

-- 55 -------------------------------------------------------------------------
section("55. Priority failures never take the reward roll down")
G = boot(nil, { God = "@Hammer" })
G.CurrentRun = G.newRun()
G.PRIORITY_THROWS = true
survived, result = pcall(G.ChooseRoomReward, G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {})
check("a throwing RewardStoreAddPriority is contained", survived, result)
check("and vanilla still returns a reward", result ~= nil, result)
check("logged", logsMatch("could not queue the first reward") ~= nil, nil)
G.PRIORITY_THROWS = false

-- A build with no RewardStoreAddPriority at all degrades to "whenever it comes
-- up" rather than erroring.
G = boot(nil, { God = "@Hammer" })
G.RewardStoreAddPriority = nil
G.CurrentRun = G.newRun()
check("missing RewardStoreAddPriority is survivable",
  pcall(G.ChooseRoomReward, G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {}), nil)
check("and says what the user loses", logsMatch("RewardStoreAddPriority unavailable") ~= nil, nil)

-- 56 -------------------------------------------------------------------------
section("56. The two delay gates are buttons on the page")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabIconScale = 0.45,
                BlockHermesBeforeBoon = true, BlockSeleneBeforeBoon = false,
                VerboseTabLog = true })
scrG2 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrG2)
gb = scrG2.SelectFirstBoonButtons
hermesGate, seleneGate = gateBtn(gb, "Hermes"), gateBtn(gb, "Selene")
check("gates are the last two buttons",
  hermesGate.SelectFirstBoonGate ~= nil and seleneGate.SelectFirstBoonGate ~= nil, nil)
check("and carry no pick value, so they can never be mistaken for one",
  hermesGate.SelectFirstBoonGod == nil and seleneGate.SelectFirstBoonGod == nil, nil)

-- Out of the flow, and BELOW every icon. Not "with a clear row between".
--
-- This used to demand lastIcon + 2 rows, and it passed for as long as the six
-- portrait gods shipped off: thirteen icons fit in three rows and row 4 was
-- genuinely clear. It fails the moment all ten ship on. Nineteen icons reach row
-- 3, and row 4 is where the gates live. The grid has five rows. There is no
-- sixth row to move them to, which is exactly why 4.23.0's computed gate row was
-- reverted: it resolved past the bottom and the squares went off screen.
--
-- So GATE_ROW stays a constant (main.lua) and the icons take whatever rows they
-- take. A blank separator row is not a guarantee this code makes and must not be
-- asserted as one. What the code does promise, and section 100 asserts the other
-- half of, is that the squares stay on the bottom row and that reaching their
-- row logs a warning rather than overlapping in silence.
lastIcon = 0
for _, b in ipairs(gb) do
  if b.SelectFirstBoonGate == nil and b.Args.Y > lastIcon then lastIcon = b.Args.Y end
end
check("below the last row of icons",
  hermesGate.Args.Y > lastIcon,
  string.format("gate %.0f vs last icon %.0f", hermesGate.Args.Y, lastIcon))
check("and never higher than the row they have always used",
  hermesGate.Args.Y >= 252 + 10 + 4 * 143, hermesGate.Args.Y)
check("right-aligned, with Selene in the last column",
  near(seleneGate.Args.X, 149 + 7 * 133.6) and near(hermesGate.Args.X, 149 + 6 * 133.6),
  string.format("%.1f / %.1f", hermesGate.Args.X, seleneGate.Args.X))
check("lit when on, dim when off",
  hermesGate.Args.AlphaTarget == 1.0 and seleneGate.Args.AlphaTarget == 0.7,
  string.format("%s / %s", hermesGate.Args.AlphaTarget, seleneGate.Args.AlphaTarget))

-- Pressing one toggles its gate and nothing else.
G.SelectFirstBoon_InventoryTabPick(scrG2, seleneGate)
check("pressing toggles the gate", M.store.BlockSeleneBeforeBoon == true,
  M.store.BlockSeleneBeforeBoon)
check("and leaves the pick alone", M.store.God == "ZeusUpgrade", M.store.God)
check("logged", logsMatch("Selene Delay turned on") ~= nil, nil)
G.SelectFirstBoon_InventoryTabPick(scrG2, seleneGate)
check("pressing again turns it back off", M.store.BlockSeleneBeforeBoon == false,
  M.store.BlockSeleneBeforeBoon)

-- 57 -------------------------------------------------------------------------
section("57. Hovering a gate explains the gate, in the same boxes as everything else")
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(hermesGate)
check("named as a delay, not as a god", writesTo(4301)[1].RawText == "Hermes Delay",
  writesTo(4301)[1].RawText)
check("described as when it may appear, not what goes first",
  writesTo(4302)[1].RawText == "Hermes is held back until you hold a boon.",
  writesTo(4302)[1].RawText)
check("gate lines still in Details, same as everywhere else",
  writesTo(4303)[1].RawText:find("Hermes Delay", 1, true) ~= nil, writesTo(4303)[1].RawText)
check("and Flavor still says what a press does",
  writesTo(4304)[1].RawText == "Press to turn off.", writesTo(4304)[1].RawText)

-- Picking Hermes makes its own gate inert, and the hover has to say so.
G = boot(nil, { God = "@Hermes", ShowInventoryTab = true, BlockHermesBeforeBoon = true })
scrG3 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrG3)
hg = gateBtn(scrG3, "Hermes")
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(hg)
check("an overridden gate still describes what it does",
  writesTo(4302)[1].RawText == "Hermes is held back until you hold a boon.",
  writesTo(4302)[1].RawText)
-- The press is real and still flips the setting; it just cannot take effect.
check("and says the press works but is idle",
  writesTo(4304)[1].RawText == "Press to turn off.  Idle while Hermes is your pick.",
  writesTo(4304)[1].RawText)
check("an overridden gate is dim, since it is doing nothing",
  hg.Args.AlphaTarget == 0.7, hg.Args.AlphaTarget)

-- 58 -------------------------------------------------------------------------
section("58. An equipped keepsake wins the whole run, not just one offer")
-- Before 3.1.0 the deference was per offer: the keepsake took room 1, and room 2
-- saw a spent keepsake and forced a second god. Two guaranteed gods.
function keepsakeRun(uses)
  local run = G.newRun({ { ForceBoonName = "ApolloUpgrade", Uses = uses } })
  return run
end

G = boot(nil, { God = "ZeusUpgrade", KeepsakeWins = true, PriorityFirstReward = true })
G.CurrentRun = keepsakeRun(1)
G.ChooseRoomReward(G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {})
check("no Boon priority is pushed alongside the keepsake's own",
  #G.priorityCalls == 0, #G.priorityCalls)
check("said so, once", logsMatch("standing down for this run") ~= nil, nil)

room1 = G.newRoom("Boon")
G.SetupRoomReward(G.CurrentRun, room1, {}, {})
check("room 1 is left to the keepsake", room1.ForceLootName ~= "ZeusUpgrade", room1.ForceLootName)

-- The keepsake is spent in room 1. The latch is what stops room 2 forcing Zeus:
-- checking live would see Uses == 0 here and go ahead.
G.CurrentRun.Hero.Traits[1].Uses = 0
room2 = G.newRoom("Boon")
G.SetupRoomReward(G.CurrentRun, room2, {}, {})
check("room 2 is NOT a second guaranteed god",
  room2.ForcedBoonNames["ZeusUpgrade"] == nil and logsMatch("forced first boon to ZeusUpgrade") == nil,
  room2.ForceLootName)

-- The probe above is only meaningful if the plugin WOULD have acted otherwise,
-- so prove it does on an identical run with no keepsake.
G.CurrentRun = G.newRun()
plain = G.newRoom("Boon")
G.SetupRoomReward(G.CurrentRun, plain, {}, {})
check("no keepsake, no stand-down",
  plain.ForcedBoonNames["ZeusUpgrade"] == true
  and logsMatch("forced first boon to ZeusUpgrade") ~= nil, plain.ForceLootName)

-- A keepsake already spent before the run's first roll never latches.
G = boot(nil, { God = "ZeusUpgrade", KeepsakeWins = true })
G.CurrentRun = keepsakeRun(0)
spent = G.newRoom("Boon")
G.SetupRoomReward(G.CurrentRun, spent, {}, {})
check("a spent keepsake does not stand us down", spent.ForceLootName == "ZeusUpgrade",
  spent.ForceLootName)

-- And it is switchable, for anyone who wants both.
G = boot(nil, { God = "ZeusUpgrade", KeepsakeWins = false, PriorityFirstReward = true })
G.CurrentRun = keepsakeRun(1)
G.ChooseRoomReward(G.CurrentRun, G.newRoom("x"), "RunProgress", {}, {})
check("switchable off", #G.priorityCalls == 1, #G.priorityCalls)

-- 59 -------------------------------------------------------------------------
section("59. Icon style is a live setting, not a reinstall")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabIconScale = 0.45,
                IconStyle = "portrait" })
scrP = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrP)
pb = scrP.SelectFirstBoonButtons
check("gods draw from the portrait set",
  G.animations[pb[2].Id]:find("SelectFirstBoon_Portrait_", 1, true) == 1, G.animations[pb[2].Id])
check("the tab icon follows", tabIcon(G):find("SelectFirstBoon_Portrait_", 1, true) == 1, tabIcon(G))
-- There is no Hammer portrait, so it keeps its symbol rather than vanishing.
hammerBtn = nil
for _, b in ipairs(pb) do
  if b.SelectFirstBoonGod == "@Hammer" then hammerBtn = b end
end
check("the hammer falls back to its symbol",
  G.animations[hammerBtn.Id] == "SelectFirstBoon_Symbol_Hammer", G.animations[hammerBtn.Id])
-- Selene has a portrait, so in this style she uses it and needs no size boost.
seleneBtn = nil
for _, b in ipairs(pb) do
  if b.SelectFirstBoonGod == "@Selene" then seleneBtn = b end
end
check("Selene uses her portrait here",
  G.animations[seleneBtn.Id] == "SelectFirstBoon_Portrait_Selene", G.animations[seleneBtn.Id])
check("and is not boosted, since the portrait set is already matched",
  near(seleneBtn.SelectFirstBoonIconScale, 1.0), seleneBtn.SelectFirstBoonIconScale)

-- 60 -------------------------------------------------------------------------
section("60. Selene's symbol art is boosted, and hover multiplies rather than replaces")
G = boot(nil, { God = "", ShowInventoryTab = true, TabIconScale = 0.45,
                IconStyle = "symbol", SeleneIconBoost = 2.0 })
scrZ = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrZ)
sel = nil
for _, b in ipairs(scrZ.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod == "@Selene" then sel = b end
end
check("Selene is drawn larger than the matched symbols",
  near(sel.SelectFirstBoonIconScale, 2.0), sel.SelectFirstBoonIconScale)
check("the hitbox is untouched by that", sel.Args.Name == "SelectFirstBoon_Button_100", sel.Args.Name)
G.SelectFirstBoon_InventoryTabOver(sel)
-- Replacing rather than multiplying would SHRINK her on hover, from 2.0 to 1.33.
check("hover multiplies her own scale", near(G.scales[sel.Id].Fraction, 2.0 * 1.33),
  G.scales[sel.Id].Fraction)
G.SelectFirstBoon_InventoryTabOff(sel)
check("and off returns her to her own scale, not to 1.0",
  near(G.scales[sel.Id].Fraction, 2.0), G.scales[sel.Id].Fraction)

-- 61 -------------------------------------------------------------------------
section("61. The icon nudge is a setting, and 0 restores the old placement")
G = boot(nil, { God = "", ShowInventoryTab = true, IconOffsetY = 0 })
scrO = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrO)
check("zero puts icons back on the grid line",
  near(scrO.SelectFirstBoonButtons[1].Args.Y, 252), scrO.SelectFirstBoonButtons[1].Args.Y)
G = boot(nil, { God = "", ShowInventoryTab = true, IconOffsetY = 29 })
scrO2 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrO2)
check("and any other value is followed",
  near(scrO2.SelectFirstBoonButtons[1].Args.Y, 281), scrO2.SelectFirstBoonButtons[1].Args.Y)

-- 62 -------------------------------------------------------------------------
section("62. The page says so when a keepsake has overruled it")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, KeepsakeWins = true })
G.CurrentRun = G.newRun({ { ForceBoonName = "ApolloUpgrade", Uses = 1 } })
scrK = G.newInventoryScreen()
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOpen(scrK)
-- "Overridden" is the word the gates already use for the same situation, so it
-- means one thing on this page wherever it turns up.
-- What is paused is the whole pick, not that particular god -- saying
-- "overridden" per option read as though Zeus specifically were overridden.
check("the panel still shows the pick",
  writesTo(4302)[1].RawText == "Set to:  Zeus", writesTo(4302)[1].RawText)
check("and says the mod is idle this run, naming the keepsake",
  writesTo(4304)[1].RawText == "Idle this run -- your Apollo keepsake takes the first boon.",
  writesTo(4304)[1].RawText)
check("the gate lines stay exactly where they always are",
  writesTo(4303)[1].RawText:find("Hermes Delay", 1, true) ~= nil, writesTo(4303)[1].RawText)

-- Nothing reads as selected while the pick cannot apply.
kb = scrK.SelectFirstBoonButtons
-- The pick stays lit. Dimming everything hid WHICH option was chosen, and a
-- keepsake pauses the pick rather than erasing it.
lit = 0
for i = 1, 17 do if kb[i].Args.AlphaTarget == 1.0 then lit = lit + 1 end end
check("exactly the picked option stays lit", lit == 1, lit)
-- The gates are unaffected: they decide when Hermes and Selene may appear at
-- all, which has nothing to do with the pick.
check("but the gates still light normally",
  gateBtn(kb, "Hermes").Args.AlphaTarget == 1.0, gateBtn(kb, "Hermes").Args.AlphaTarget)

G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(kb[2])
check("hovering says the press works but is idle",
  writesTo(4304)[1].RawText
    == "Press to make this your pick.  Idle while your Apollo keepsake is equipped.",
  writesTo(4304)[1].RawText)

-- Reading the panel must not decide anything: the probe never latches.
check("looking at the page did not latch the run",
  G.CurrentRun["SelectFirstBoon_KeepsakeWins"] == nil,
  G.CurrentRun["SelectFirstBoon_KeepsakeWins"])

-- With the toggle off, the page behaves as though no keepsake were there.
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, KeepsakeWins = false })
G.CurrentRun = G.newRun({ { ForceBoonName = "ApolloUpgrade", Uses = 1 } })
scrK2 = G.newInventoryScreen()
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOpen(scrK2)
check("toggle off: no disabled message",
  writesTo(4302)[1].RawText == "Set to:  Zeus", writesTo(4302)[1].RawText)

-- And with no run at all, nothing claims a keepsake is equipped.
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, KeepsakeWins = true })
G.CurrentRun = nil
scrK3 = G.newInventoryScreen()
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOpen(scrK3)
check("no run, no keepsake claim", writesTo(4302)[1].RawText == "Set to:  Zeus",
  writesTo(4302)[1].RawText)

-- 63 -------------------------------------------------------------------------
section("63. The door-icon set covers every option, including the two it had to borrow for")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabIconScale = 0.45,
                IconStyle = "boondrop" })
scrB = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrB)
bbtn = {}
for _, b in ipairs(scrB.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod ~= nil then bbtn[b.SelectFirstBoonGod] = b end
end
-- The whole point of this set: nothing may fall back, or the page ends up
-- mixing art from two families again.
-- Standard is excluded as well: the empty frame it draws exists only in
-- BoonSelectSymbols -- the door set has no "no god" medallion, because vanilla
-- never needed a door to promise nothing. It stays on the symbol in every style.
everyOption = { "ZeusUpgrade", "HeraUpgrade", "@Hammer", "@Hermes", "@Selene" }
-- Selene is excluded: vanilla itself has no matching door medallion for her
-- (SpellDropPreview inherits an isometric base where every god's is flat), so
-- she has her own picker instead of a door entry.
mixed = nil
for _, value in ipairs(everyOption) do
  if value ~= "@Selene" then
    local anim = G.animations[bbtn[value].Id]
    if anim:find("SelectFirstBoon_BoonDrop_", 1, true) ~= 1 then mixed = value .. " -> " .. anim end
  end
end
check("every god option resolves inside the door set", mixed == nil, mixed)
check("and Standard keeps the pomegranate, which only the symbol set has",
  G.animations[bbtn[""].Id] == "SelectFirstBoon_Symbol_Pom",
  G.animations[bbtn[""].Id])
check("Standard falls back to the pomegranate",
  G.animations[bbtn[""].Id] == "SelectFirstBoon_Symbol_Pom", G.animations[bbtn[""].Id])
check("Selene uses her own art in the door style too",
  G.animations[bbtn["@Selene"].Id] == "SelectFirstBoon_Selene_preview",
  G.animations[bbtn["@Selene"].Id])
-- Her art is a different family in every style except portraits, so the size
-- correction has to follow her into the door style as well.
check("and keeps her size correction",
  near(bbtn["@Selene"].SelectFirstBoonIconScale, 2.0), bbtn["@Selene"].SelectFirstBoonIconScale)

-- WeaponUpgrade_Preview is declared at 0.55 where the spin frames are at 1.0,
-- so the hammer would land twice everyone else's size without that baked in.
hammerAnim, spinAnim = nil, nil
for _, e in ipairs(M.animations.Animations) do
  if e.Name == "SelectFirstBoon_BoonDrop_Hammer" then hammerAnim = e end
  if e.Name == "SelectFirstBoon_BoonDrop_Zeus" then spinAnim = e end
end
check("the hammer carries its own native factor",
  near(hammerAnim.Scale, 0.45 * 0.55) and near(spinAnim.Scale, 0.45),
  string.format("%s vs %s", hammerAnim.Scale, spinAnim.Scale))
check("gods come from their spin frames",
  spinAnim.FilePath == "Items\\Loot\\Boon\\ZeusIconSpin\\ZeusIconSpin0015", spinAnim.FilePath)
-- Static and unlit, so none of the door pulsing comes with them.
check("and are static, not the pulsing door version",
  spinAnim.NumFrames == 1 and spinAnim.Material == "Unlit", nil)
check("the tab icon follows the set",
  tabIcon(G) == "SelectFirstBoon_BoonDrop_Zeus", tabIcon(G))

-- 64 -------------------------------------------------------------------------
section("64. Brightness dims the icons, and full brightness touches nothing")
G = boot(nil, { God = "", ShowInventoryTab = true, IconBrightness = 1.0 })
scrFull = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrFull)
-- Selene's halo is tinted with SetRGB whatever the brightness, so the claim is
-- about the icon BUTTONS specifically, not about the call count on the page.
tintedButtons = 0
for _, b in ipairs(scrFull.SelectFirstBoonButtons) do
  if G.rgb[b.Id] ~= nil then tintedButtons = tintedButtons + 1 end
end
check("full brightness tints no icon at all", tintedButtons == 0, tintedButtons)

G = boot(nil, { God = "", ShowInventoryTab = true, IconBrightness = 0.7 })
scrDim = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrDim)
first = scrDim.SelectFirstBoonButtons[1]
tint = G.rgb[first.Id]
check("a lower value multiplies the texture down",
  tint ~= nil and tint[1] == 178 and tint[2] == 178 and tint[3] == 178,
  tint and table.concat(tint, ","))
check("alpha is left alone, so nothing goes transparent", tint[4] == 255, tint[4])
dimmed = 0
for _, b in ipairs(scrDim.SelectFirstBoonButtons) do
  if G.rgb[b.Id] ~= nil then dimmed = dimmed + 1 end
end
check("every button is dimmed, gates included", dimmed == 26, dimmed)

-- A build without SetRGB must not take the tab down over a cosmetic setting.
G = boot(nil, { God = "", ShowInventoryTab = true, IconBrightness = 0.7 })
G.SetRGB = nil
check("no SetRGB is survivable", pcall(G.SelectFirstBoon_InventoryTabOpen, G.newInventoryScreen()), nil)

-- 65 -------------------------------------------------------------------------
section("65. Gods added by another plugin after this one has loaded")
-- Both plugins register inside modutil.once_loaded.game, and the order between
-- two of those is not defined. If the other one runs second, a catalog built
-- once at load would miss its gods until the next launch.
G = boot(nil, { God = "", ShowInventoryTab = true, TabIconScale = 0.45 })
before = #G.ScreenData.InventoryScreen.ItemCategories
baseline = nil
do
  local scr = G.newInventoryScreen()
  G.SelectFirstBoon_InventoryTabOpen(scr)
  baseline = #scr.SelectFirstBoonButtons
end

-- Droppable Gods registers namespaced loot names and sets SpeakerName.
G.LootData["zannc-Droppable_Gods-ArtemisUpgrade"] = {
  GodLoot = true, SpeakerName = "Artemis", Icon = "BoonSymbolArtemis",
}
G.LootData["zannc-Droppable_Gods-HadesUpgrade"] = {
  GodLoot = true, SpeakerName = "Hades",
}

scrN = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrN)
check("opening the tab picks up the new gods",
  #scrN.SelectFirstBoonButtons == baseline + 2, #scrN.SelectFirstBoonButtons)
check("and said so", logsMatch("god catalog refreshed") ~= nil, nil)

byGod = {}
for _, b in ipairs(scrN.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod ~= nil then byGod[b.SelectFirstBoonGod] = b end
end
check("a namespaced god gets its real symbol, not the Chaos default",
  G.animations[byGod["zannc-Droppable_Gods-ArtemisUpgrade"].Id] == "SelectFirstBoon_Symbol_Artemis",
  G.animations[byGod["zannc-Droppable_Gods-ArtemisUpgrade"].Id])
-- Hades sets no Icon at all here, so this is the SpeakerName path doing the work.
check("SpeakerName alone is enough",
  G.animations[byGod["zannc-Droppable_Gods-HadesUpgrade"].Id] == "SelectFirstBoon_Symbol_Hades",
  G.animations[byGod["zannc-Droppable_Gods-HadesUpgrade"].Id])

-- The door set has no art for these four, so they fall through to the symbol
-- rather than drawing nothing.
G.SelectFirstBoon_InventoryTabClose(scrN)
Gd = boot(nil, { God = "", ShowInventoryTab = true, TabIconScale = 0.45,
                       IconStyle = "boondrop" })
Gd.LootData["zannc-Droppable_Gods-ArtemisUpgrade"] = {
  GodLoot = true, SpeakerName = "Artemis", Icon = "BoonSymbolArtemis",
}
scrD2 = Gd.newInventoryScreen()
Gd.SelectFirstBoon_InventoryTabOpen(scrD2)
byGod2 = {}
for _, b in ipairs(scrD2.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod ~= nil then byGod2[b.SelectFirstBoonGod] = b end
end
-- Changed deliberately: the door style now prefers a portrait over a symbol for
-- anything with no door art. BoonSelectSymbols carries a halo painted into the
-- texture that no property removes, so falling through to it put four glowing
-- icons in a grid of flat ones. Portraits are flat. See iconInStyle.
check("in the door style they fall through to their portrait, not a haloed symbol",
  Gd.animations[byGod2["zannc-Droppable_Gods-ArtemisUpgrade"].Id] == "SelectFirstBoon_Portrait_Artemis",
  Gd.animations[byGod2["zannc-Droppable_Gods-ArtemisUpgrade"].Id])
check("while the gods that DO have door art still use it",
  Gd.animations[byGod2["ZeusUpgrade"].Id] == "SelectFirstBoon_BoonDrop_Zeus",
  Gd.animations[byGod2["ZeusUpgrade"].Id])

-- A god removed again (the mod disabled mid-session) must also be picked up.
G.LootData["zannc-Droppable_Gods-ArtemisUpgrade"] = nil
G.LootData["zannc-Droppable_Gods-HadesUpgrade"] = nil
scrR = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrR)
check("and removals too", #scrR.SelectFirstBoonButtons == baseline, #scrR.SelectFirstBoonButtons)

-- No category is ever added twice by a refresh.
check("refreshing never duplicates the tab",
  #G.ScreenData.InventoryScreen.ItemCategories == before,
  #G.ScreenData.InventoryScreen.ItemCategories)

-- A refresh that throws must not take the tab down with it.
G = boot(nil, { God = "", ShowInventoryTab = true })
G.LootData = setmetatable({}, { __pairs = function() error("simulated LootData failure") end })
check("a throwing refresh is contained",
  pcall(G.SelectFirstBoon_InventoryTabOpen, G.newInventoryScreen()), nil)

-- 66 -------------------------------------------------------------------------
section("66. Against how GodsAPI actually registers a god")
-- Verified from zannc-GodsAPI 2.1.5 src/main.lua:235-259. It builds:
--     upgradeName = "<guid>-<God>Upgrade"
--     SpeakerName = "<guid>-<God>"          (main.lua:248)
--     Icon        = "BoonSymbol<guid>-<God>" (main.lua:259)
--     GodLoot     = true                     (main.lua:250)
-- so the Icon DOES match "^BoonSymbol(.+)$" and yields a namespaced name. 3.3.0
-- returned that unconditionally and never reached SpeakerName.
G = boot(nil, { God = "", ShowInventoryTab = true, TabIconScale = 0.45 })
GUID = "zannc-Droppable_Gods"

-- A god registered with GodsAPI defaults and no ExtraFields override.
G.LootData[GUID .. "-AthenaUpgrade"] = {
  GodLoot = true,
  SpeakerName = GUID .. "-Athena",
  Icon = "BoonSymbol" .. GUID .. "-Athena",
  BoonInfoIcon = "BoonInfoSymbol" .. GUID .. "-AthenaIcon",
}
-- And one where the mod DID override SpeakerName, as Droppable Gods does.
G.LootData[GUID .. "-ArtemisUpgrade"] = {
  GodLoot = true,
  SpeakerName = "Artemis",
  Icon = "BoonSymbol" .. GUID .. "-Artemis",
}

scrA = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrA)
byG = {}
for _, b in ipairs(scrA.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod ~= nil then byG[b.SelectFirstBoonGod] = b end
end

check("a namespaced Icon still finds the right symbol",
  G.animations[byG[GUID .. "-AthenaUpgrade"].Id] == "SelectFirstBoon_Symbol_Athena",
  G.animations[byG[GUID .. "-AthenaUpgrade"].Id])
check("and so does one whose SpeakerName was overridden",
  G.animations[byG[GUID .. "-ArtemisUpgrade"].Id] == "SelectFirstBoon_Symbol_Artemis",
  G.animations[byG[GUID .. "-ArtemisUpgrade"].Id])

-- The label must not read "zannc-Droppable_Gods-Athena" in the panel.
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(byG[GUID .. "-AthenaUpgrade"])
check("the panel shows a clean god name",
  writesTo(4301)[1].RawText == "Athena", writesTo(4301)[1].RawText)
check("and the sentence reads normally",
  writesTo(4302)[1].RawText == "Offer Athena as the run's first reward.",
  writesTo(4302)[1].RawText)

-- Vanilla names contain no dash, so none of that stripping may touch them.
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(byG["ZeusUpgrade"])
check("vanilla gods are untouched by the namespace stripping",
  writesTo(4301)[1].RawText == "Zeus", writesTo(4301)[1].RawText)

-- GodsAPI sets GodLoot = false for an NPCGOD-type god (main.lua:352), exactly as
-- vanilla does for Hermes. Those are not boon gods and must not be listed as if
-- they were -- Droppable Gods registers Hades this way, always.
countBefore = #scrA.SelectFirstBoonButtons
G.LootData[GUID .. "-HadesUpgrade"] = {
  GodLoot = false, TreatAsGodLootByShops = true,
  SpeakerName = "Hades", Icon = "BoonSymbol" .. GUID .. "-Hades",
}
scrH = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrH)
check("an NPC-style god is not listed as a boon god",
  #scrH.SelectFirstBoonButtons == countBefore, #scrH.SelectFirstBoonButtons)

-- 67 -------------------------------------------------------------------------
section("67. Artemis: the three promises")
G = boot(nil, { God = "", EnableArtemis = true, ShowInventoryTab = true, TabIconScale = 0.45 })
ART = "SelectFirstBoon-ArtemisUpgrade"
art = G.LootData[ART]
check("she is registered as a boon god", art ~= nil and art.GodLoot == true, art and art.GodLoot)
check("logged", logsMatch("Artemis registered as a first-reward-only boon god") ~= nil, nil)

-- PROMISE 1: never a shop item.
check("PROMISE never buyable: the shop flag is not set",
  art.TreatAsGodLootByShops == nil, tostring(art.TreatAsGodLootByShops))
check("and no shop entry was added anywhere",
  G.StoreData == nil or next(G.StoreData or {}) == nil, "StoreData touched")

-- PROMISE 2: only ever the run's FIRST reward.
req = art.GameStateRequirements
check("PROMISE first-only: a requirement is attached", req ~= nil and #req == 1, req and #req)
check("it reads LootTypeHistory", req[1].Path[1] == "CurrentRun"
  and req[1].Path[2] == "LootTypeHistory", table.concat(req[1].Path, "."))
blocked = {}
for _, n in ipairs(req[1].HasNone) do blocked[n] = true end
check("blocked once ANY vanilla god has been taken",
  blocked.ZeusUpgrade and blocked.HeraUpgrade and blocked.HestiaUpgrade, nil)
check("a hammer counts too, matching the existing gates", blocked.WeaponUpgrade == true, nil)
-- Without herself in the list she could be offered a second time.
check("and blocked once SHE has been taken", blocked[ART] == true, nil)

-- PROMISE 3: meeting her in the world is untouched.
npc = G.EnemyData.NPC_Artemis_Field_01
check("PROMISE vanilla NPC untouched: her unit still has its own trait pool",
  npc.Traits ~= nil and #npc.Traits == 9, npc.Traits and #npc.Traits)
check("her unit keeps its shop flag, which is hers not ours",
  npc.TreatAsGodLootByShops == true, npc.TreatAsGodLootByShops)
check("no GameStateRequirements were pushed onto her unit",
  npc.GameStateRequirements == nil, npc.GameStateRequirements)
-- By reference, so a change to her boons anywhere reaches the drop.
check("the drop shares her pool rather than copying it", art.Traits == npc.Traits, nil)

-- 68 -------------------------------------------------------------------------
section("68. Artemis: she reaches the menu and the reward pipeline")
scrArt = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrArt)
artBtn = nil
for _, b in ipairs(scrArt.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod == ART then artBtn = b end
end
check("she appears on the tab", artBtn ~= nil, nil)
check("with her own emblem, not the Chaos default",
  G.animations[artBtn.Id] == "SelectFirstBoon_Symbol_Artemis", G.animations[artBtn.Id])
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(artBtn)
check("and a clean name, not the namespaced key",
  writesTo(4301)[1].RawText == "Artemis", writesTo(4301)[1].RawText)

-- Picking her must force her exactly as a vanilla god is forced.
G.SelectFirstBoon_InventoryTabPick(scrArt, artBtn)
check("picking her saves the pick", M.store.God == ART, M.store.God)
G.CurrentRun = G.newRun()
G.ELIGIBLE = { ART }
artRoom = G.newRoom("Boon")
G.SetupRoomReward(G.CurrentRun, artRoom, {}, {})
check("and the reward pipeline forces her", artRoom.ForceLootName == ART, artRoom.ForceLootName)

-- 69 -------------------------------------------------------------------------
section("69. Artemis: the drop is built from vanilla layers")
animFile = nil
for f, _ in pairs(M.byFile) do
  if f:find("Items_General_VFX", 1, true) then animFile = f end
end
check("her art went into the items animation file", animFile ~= nil, nil)
byName = {}
for _, e in ipairs(M.byFile[animFile].Animations) do byName[e.Name] = e end
-- The orb, the three glows and both flares are all shared vanilla animations.
check("the orb inherits the vanilla boon orb",
  byName["BoonDrop" .. ART].InheritFrom == "BoonDropGold", nil)
check("the glow layers inherit the vanilla glows",
  byName["BoonDropA-" .. ART].InheritFrom == "BoonDropA"
  and byName["BoonDropB-" .. ART].InheritFrom == "BoonDropB"
  and byName["BoonDropC-" .. ART].InheritFrom == "BoonDropC", nil)
check("chained in order, so they stack",
  byName["BoonDrop" .. ART].ChildAnimation == "BoonDropA-" .. ART
  and byName["BoonDropC-" .. ART].ChildAnimation == "BoonDrop" .. ART .. "Icon", nil)
-- Exactly one layer is god-specific, and it uses art already in the base game.
icon = byName["BoonDrop" .. ART .. "Icon"]
check("only the innermost layer is hers",
  icon.FilePath == "GUI\\Screens\\BoonSelectSymbols\\Artemis", icon.FilePath)
-- BoonDropIcon defaults to a 50-frame spin; an emblem is a single image.
check("and it is static, since an emblem is not a spin",
  icon.NumFrames == 1 and icon.Loop == false, nil)
-- The harness passed a real bug here once: colours were written as {r,g,b,a}
-- 0-255 arrays, which is the LootData form, not the ANIMATION form. Vanilla uses
-- named channels as 0-1 floats (BoonDropA-Zeus, Items_General_VFX.sjson:5859)
-- and the wrong shape fails silently -- the drop just renders untinted. Pin it.
colorA = byName["BoonDropA-" .. ART].Color
check("layer colours use named channels, not a positional array",
  colorA ~= nil and colorA.Red ~= nil and colorA.Green ~= nil and colorA.Blue ~= nil,
  colorA and (colorA[1] and "positional array" or "unknown"))
check("and are 0-1 floats, not 0-255",
  colorA.Red <= 1.0 and colorA.Green <= 1.0 and colorA.Blue <= 1.0,
  string.format("%s/%s/%s", colorA.Red, colorA.Green, colorA.Blue))
check("all three tinted layers carry a colour",
  byName["BoonDropB-" .. ART].Color ~= nil and byName["BoonDropC-" .. ART].Color ~= nil, nil)
-- The outermost layer inherits BoonDropGold untinted, as every vanilla god does.
check("but the outer orb is left untinted, like vanilla",
  byName["BoonDrop" .. ART].Color == nil, byName["BoonDrop" .. ART].Color)

-- Without these the orb has no bloom at all. Vanilla puts both on A, B and C.
for _, layer in ipairs({ "A", "B", "C" }) do
  local created = byName["BoonDrop" .. layer .. "-" .. ART].CreateAnimations
  check("layer " .. layer .. " spawns the glow and the flare",
    created ~= nil and #created == 2
    and created[1].Name == "BoonDropBackGlow" and created[2].Name == "BoonDropFrontFlare",
    created and #created)
end

check("a door preview exists too", byName["BoonDrop" .. ART .. "Preview"] ~= nil, nil)
check("the loot points at that door icon", art.DoorIcon == "BoonDrop" .. ART .. "Preview", art.DoorIcon)

obsFile = nil
for f, _ in pairs(M.byFile) do
  if f:find("Gameplay", 1, true) then obsFile = f end
end
check("a world obstacle was registered", obsFile ~= nil
  and M.byFile[obsFile].Obstacles[1].Name == ART, nil)
check("inheriting the vanilla boon obstacle",
  M.byFile[obsFile].Obstacles[1].InheritFrom == "BaseBoon", nil)

-- 70 -------------------------------------------------------------------------
section("70. Artemis: switchable, and survivable when the game disagrees")
G = boot(nil, { God = "", EnableArtemis = false, ShowInventoryTab = true })
check("off means not registered", G.LootData["SelectFirstBoon-ArtemisUpgrade"] == nil, nil)
check("and said so", logsMatch("Artemis option disabled by config") ~= nil, nil)

-- A future patch renames or removes her unit: refuse rather than half-register.
G3 = dofile("./harness.lua")
G3.EnemyData.NPC_Artemis_Field_01 = nil
M.install(G3, nil, { God = "", EnableArtemis = true })
M.pendingGameLoad = nil
dofile(PLUGIN)
M.pendingGameLoad()
check("no NPC unit: she is not registered at all",
  G3.LootData["SelectFirstBoon-ArtemisUpgrade"] == nil, nil)
check("and it is reported, not silent",
  logsMatch("could not find NPC_Artemis_Field_01") ~= nil, nil)
check("the rest of the plugin still installs",
  logsMatch("installed; first reward is") ~= nil or logsMatch("installed;") ~= nil, nil)

-- Registering twice must not duplicate her.
G = boot(nil, { God = "", EnableArtemis = true })
M.pendingGameLoad()
count = 0
for name, _ in pairs(G.LootData) do if name == "SelectFirstBoon-ArtemisUpgrade" then count = count + 1 end end
check("re-running install does not duplicate her", count == 1, count)
check("and says she is already there", logsMatch("Artemis already registered") ~= nil, nil)

-- 71 -------------------------------------------------------------------------
section("71. The hover frame outlines the SLOT, not the nudged icon")
-- Before 4.1.0 the frame moved down with the icon nudge, putting it IconOffsetY
-- units below the slot outline the background art draws. The nudge exists
-- precisely because icon and slot are not the same place.
G = boot(nil, { God = "", ShowInventoryTab = true, IconOffsetY = 10, HighlightOffsetY = 0 })
scrH2 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrH2)
b1 = scrH2.SelectFirstBoonButtons[1]
check("the icon is nudged down", near(b1.Args.Y, 252 + 10), b1.Args.Y)
check("the frame stays on the slot line", near(b1.Highlight.Args.Y, 252), b1.Highlight.Args.Y)
check("so they are exactly the nudge apart",
  near(b1.Args.Y - b1.Highlight.Args.Y, 10), b1.Args.Y - b1.Highlight.Args.Y)
check("and they share a column", near(b1.Args.X, b1.Highlight.Args.X), nil)

-- The frame can still be nudged on its own for fine tuning.
G = boot(nil, { God = "", ShowInventoryTab = true, IconOffsetY = 10, HighlightOffsetY = 5 })
scrH3 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrH3)
check("frame nudge moves the frame alone",
  near(scrH3.SelectFirstBoonButtons[1].Highlight.Args.Y, 257)
  and near(scrH3.SelectFirstBoonButtons[1].Args.Y, 262),
  scrH3.SelectFirstBoonButtons[1].Highlight.Args.Y)

-- 72 -------------------------------------------------------------------------
section("72. Hover style: frame, or PonyMenu's grow-only")
G = boot(nil, { God = "", ShowInventoryTab = true, HighlightStyle = "frame" })
scrF2 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrF2)
fb = scrF2.SelectFirstBoonButtons[2]
G.SelectFirstBoon_InventoryTabOver(fb)
check("frame style draws the slot frame",
  G.animations[fb.Highlight.Id] == "InventoryScreenSlotIn", G.animations[fb.Highlight.Id])
check("and still grows the icon", G.scales[fb.Id] ~= nil, nil)
G.SelectFirstBoon_InventoryTabOff(fb)
check("and removes it on the way out",
  G.animations[fb.Highlight.Id] == "InventoryScreenSlotOut", G.animations[fb.Highlight.Id])

G = boot(nil, { God = "", ShowInventoryTab = true, HighlightStyle = "grow" })
scrG4 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrG4)
gb2 = scrG4.SelectFirstBoonButtons[2]
G.SelectFirstBoon_InventoryTabOver(gb2)
check("grow style draws no frame at all", G.animations[gb2.Highlight.Id] == nil,
  G.animations[gb2.Highlight.Id])
-- The icon scaling is the whole signal in this style, so it must still happen.
check("but the icon still grows", G.scales[gb2.Id] ~= nil
  and near(G.scales[gb2.Id].Fraction, 1.33), G.scales[gb2.Id] and G.scales[gb2.Id].Fraction)
G.SelectFirstBoon_InventoryTabOff(gb2)
check("and shrinks back", near(G.scales[gb2.Id].Fraction, 1.0), G.scales[gb2.Id].Fraction)
check("with still no frame", G.animations[gb2.Highlight.Id] == nil, G.animations[gb2.Highlight.Id])

-- 73 -------------------------------------------------------------------------
section("73. Pressing a button leaves the panel describing that button")
-- Reported: pressing a gate snapped the panel back to the resting "First Boon"
-- text while the cursor was still sitting on the gate.
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true,
                BlockHermesBeforeBoon = true, BlockSeleneBeforeBoon = true })
scrP = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrP)
pb = scrP.SelectFirstBoonButtons
hGate = gateBtn(pb, "Hermes")

G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabPick(scrP, hGate)
check("after pressing a gate the panel still names the gate",
  writesTo(4301)[1].RawText == "Hermes Delay", writesTo(4301)[1].RawText)
check("and not the resting page title",
  writesTo(4301)[1].RawText ~= "First Boon", writesTo(4301)[1].RawText)
check("the press really did flip the setting",
  M.store.BlockHermesBeforeBoon == false, M.store.BlockHermesBeforeBoon)
check("and the panel now describes the NEW state",
  writesTo(4302)[1].RawText == "Hermes can turn up from the first room.",
  writesTo(4302)[1].RawText)

-- The same is true of picking a god.
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabPick(scrP, pb[3])
check("after picking a god the panel still names that god",
  writesTo(4301)[1].RawText ~= "First Boon", writesTo(4301)[1].RawText)
check("and reads as the pick", writesTo(4304)[1].RawText == "Your current pick.",
  writesTo(4304)[1].RawText)

-- 74 -------------------------------------------------------------------------
section("74. An overridden gate still shows, and changes, its own state")
-- Reported: with Hermes picked, the gate read only "Overridden" whichever way
-- it was set, so pressing it looked broken.
G = boot(nil, { God = "@Hermes", ShowInventoryTab = true, BlockHermesBeforeBoon = true })
scrO3 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrO3)
og = gateBtn(scrO3, "Hermes")

G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOver(og)
check("an overridden gate reports On, and says it is overridden",
  writesTo(4303)[1].RawText == "Hermes Delay:  On (overridden by first boon choice)", writesTo(4303)[1].RawText)

G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabPick(scrO3, og)
check("pressing it visibly changes the reported state",
  writesTo(4303)[1].RawText == "Hermes Delay:  Off (overridden by first boon choice)", writesTo(4303)[1].RawText)
check("and the setting really moved", M.store.BlockHermesBeforeBoon == false,
  M.store.BlockHermesBeforeBoon)
-- Overridden means idle, so it must not be drawn as active either way.
check("an overridden gate is never lit", og.Args.AlphaTarget == 0.7, og.Args.AlphaTarget)

-- 75 -------------------------------------------------------------------------
section("75. Icon size scales everything, and stacks with Selene's correction")
G = boot(nil, { God = "", ShowInventoryTab = true, IconSize = 2.0, SeleneIconBoost = 2.0 })
scrSz = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrSz)
szb = {}
for _, b in ipairs(scrSz.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod ~= nil then szb[b.SelectFirstBoonGod] = b end
end
check("every ordinary icon takes the size multiplier",
  near(szb["ZeusUpgrade"].SelectFirstBoonIconScale, 2.0),
  szb["ZeusUpgrade"].SelectFirstBoonIconScale)
check("Selene's correction multiplies on top rather than replacing it",
  near(szb["@Selene"].SelectFirstBoonIconScale, 4.0),
  szb["@Selene"].SelectFirstBoonIconScale)
-- REGRESSION: the size boost keyed off extra.portraitOnly, which asks whether a
-- god has ONLY a portrait -- not whether this slot is drawing one. In the door
-- style Artemis, Athena, Dionysus and Hades draw portraits despite owning
-- symbols, so they took the full multiplier while the six portrait-only gods
-- took the boost, and one row rendered at three times the other. Assert both
-- kinds land on the same scale.
do
  local Gp = boot(nil, { God = "", ShowInventoryTab = true, IconStyle = "boondrop",
                         IconSize = 2.0, PortraitIconBoost = 0.3,
                         EnableArtemis = true, EnableNarcissus = true })
  local scrP = Gp.newInventoryScreen()
  Gp.SelectFirstBoon_InventoryTabOpen(scrP)
  local pb = {}
  for _, b in ipairs(scrP.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod ~= nil then pb[b.SelectFirstBoonGod] = b end
  end
  check("a god drawing a portrait only because the door set lacks it is boosted",
    near(pb["SelectFirstBoon-ArtemisUpgrade"].SelectFirstBoonIconScale, 0.6),
    pb["SelectFirstBoon-ArtemisUpgrade"] and pb["SelectFirstBoon-ArtemisUpgrade"].SelectFirstBoonIconScale)
  check("and matches a portrait-only god exactly",
    near(pb["SelectFirstBoon-ArtemisUpgrade"].SelectFirstBoonIconScale,
         pb["SelectFirstBoon-NarcissusUpgrade"].SelectFirstBoonIconScale),
    pb["SelectFirstBoon-NarcissusUpgrade"] and pb["SelectFirstBoon-NarcissusUpgrade"].SelectFirstBoonIconScale)
  check("while a god with door art takes the plain multiplier",
    near(pb["ZeusUpgrade"].SelectFirstBoonIconScale, 2.0),
    pb["ZeusUpgrade"] and pb["ZeusUpgrade"].SelectFirstBoonIconScale)
end

-- Per-icon size corrections. These exist because one global multiplier cannot
-- match art from different families, and raising it far enough breaks clicking:
-- the hitbox stays one grid cell however big the art is drawn.
do
  local Gt = boot(nil, { God = "", ShowInventoryTab = true, IconStyle = "boondrop",
                         IconSize = 1.0, SizeZeus = 1.5, EnableNarcissus = true })
  local scrT = Gt.newInventoryScreen()
  Gt.SelectFirstBoon_InventoryTabOpen(scrT)
  local tb = {}
  for _, b in ipairs(scrT.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod ~= nil then tb[b.SelectFirstBoonGod] = b end
  end
  check("a per-icon size multiplies the global one",
    near(tb["ZeusUpgrade"].SelectFirstBoonIconScale, 1.5),
    tb["ZeusUpgrade"] and tb["ZeusUpgrade"].SelectFirstBoonIconScale)
  check("and leaves every other icon alone",
    near(tb["HeraUpgrade"].SelectFirstBoonIconScale, 1.0),
    tb["HeraUpgrade"] and tb["HeraUpgrade"].SelectFirstBoonIconScale)
end

-- The selection light. The layered additive sprite that used to fake halos onto
-- portraits, repointed at marking the pick -- which matters more with a pool,
-- where several icons are marked at once and size alone stops being enough.
do
  local Gl = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true,
                         SelectionHalo = true, SelectionHaloStrength = 0.35,
                         SelectionHaloLayers = 2, SeleneGlowStrength = 0 })
  local scrL = Gl.newInventoryScreen()
  Gl.SelectFirstBoon_InventoryTabOpen(scrL)
  local lb = {}
  for _, b in ipairs(scrL.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod ~= nil then lb[b.SelectFirstBoonGod] = b end
  end
  check("the picked icon gets a light",
    lb["ZeusUpgrade"] ~= nil and lb["ZeusUpgrade"].SelectFirstBoonGlow ~= nil, nil)
  check("and an unpicked one does not",
    lb["HeraUpgrade"] ~= nil and lb["HeraUpgrade"].SelectFirstBoonGlow == nil, nil)
  check("its strength drives the alpha",
    near(lb["ZeusUpgrade"].SelectFirstBoonGlow.Args.AlphaTarget, 0.35),
    lb["ZeusUpgrade"].SelectFirstBoonGlow.Args.AlphaTarget)
  -- Near-white on purpose: a god colour would read as part of that god's art
  -- rather than as "this is the one you picked".
  check("and it is neutral, not a god colour",
    Gl.rgb[lb["ZeusUpgrade"].SelectFirstBoonGlow.Id] ~= nil
      and Gl.rgb[lb["ZeusUpgrade"].SelectFirstBoonGlow.Id][1] == 235,
    Gl.rgb[lb["ZeusUpgrade"].SelectFirstBoonGlow.Id]
      and Gl.rgb[lb["ZeusUpgrade"].SelectFirstBoonGlow.Id][1])
  local Gz = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true,
                         SelectionHalo = false, SeleneGlowStrength = 0 })
  local scrZ = Gz.newInventoryScreen()
  Gz.SelectFirstBoon_InventoryTabOpen(scrZ)
  local zb = nil
  for _, b in ipairs(scrZ.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod == "ZeusUpgrade" then zb = b end
  end
  check("switched off, the pick has no light at all",
    zb ~= nil and zb.SelectFirstBoonGlow == nil, nil)
end

-- HitboxScale picks a smaller rung. The trade is explicit: the mouse gets a box
-- the size of the icon, and the controller loses the tiling it needs, so this
-- asserts the shape of the trade rather than pretending there is none.
do
  local Gh = boot(nil, { God = "", ShowInventoryTab = true, HitboxScale = 0.45 })
  local scrH = Gh.newInventoryScreen()
  Gh.SelectFirstBoon_InventoryTabOpen(scrH)
  local hb = scrH.SelectFirstBoonButtons[1]
  check("a lower HitboxScale picks a smaller rung",
    hb ~= nil and hb.Args.Name == "SelectFirstBoon_Button_45", hb and hb.Args.Name)
  local small = nil
  for _, o in ipairs(M.obstacles.Obstacles) do
    if o.Name == "SelectFirstBoon_Button_45" then small = o end
  end
  check("and that rung really is smaller than a cell",
    small ~= nil and (small.Thing.Points[3].X - small.Thing.Points[1].X) < 70,
    small and (small.Thing.Points[3].X - small.Thing.Points[1].X))
  -- The cost, stated: at this size the boxes no longer tile.
  check("which leaves a gap wider than a controller step, by design",
    (133.6 - (small.Thing.Points[3].X - small.Thing.Points[1].X)) > 16, nil)
end

-- The light has to follow the pick without a re-open, the way brightness and
-- size already did. It is components rather than a property, so applySelection
-- tears it down and rebuilds it -- and must leave per-god halos alone while
-- doing so, or Selene's would vanish the moment anything else was picked.
do
  local Gm = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true,
                         SelectionHalo = true, SelectionHaloLayers = 2,
                         SeleneGlowStrength = 0 })
  local scrM = Gm.newInventoryScreen()
  Gm.SelectFirstBoon_InventoryTabOpen(scrM)
  local function btn(g)
    for _, b in ipairs(scrM.SelectFirstBoonButtons) do
      if b.SelectFirstBoonGod == g then return b end
    end
  end
  check("the picked icon starts with the light",
    btn("ZeusUpgrade") ~= nil and btn("ZeusUpgrade").SelectFirstBoonGlow ~= nil, nil)
  check("and another god has none",
    btn("HeraUpgrade") ~= nil and btn("HeraUpgrade").SelectFirstBoonGlow == nil, nil)

  -- Pick a different god, without closing or reopening anything.
  Gm.SelectFirstBoon_InventoryTabPick(scrM, btn("HeraUpgrade"))
  check("picking moves the light immediately, with no re-open",
    btn("HeraUpgrade") ~= nil and btn("HeraUpgrade").SelectFirstBoonGlow ~= nil, nil)
  check("and takes it off the icon that lost the pick",
    btn("ZeusUpgrade") ~= nil and btn("ZeusUpgrade").SelectFirstBoonGlow == nil, nil)
end

-- Selene's own halo is not the pick's, so moving the pick must not destroy it.
do
  local Gk = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true,
                         SelectionHalo = true, SeleneGlowStrength = 0.5,
                         SeleneHaloLayers = 2 })
  local scrK = Gk.newInventoryScreen()
  Gk.SelectFirstBoon_InventoryTabOpen(scrK)
  local sel = nil
  for _, b in ipairs(scrK.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod == "@Selene" then sel = b end
  end
  check("Selene keeps her own halo while another god is picked",
    sel ~= nil and sel.SelectFirstBoonGlow ~= nil, nil)
  Gk.SelectFirstBoon_InventoryTabPick(scrK, scrK.SelectFirstBoonButtons[3])
  check("and still has it after the pick moves again",
    sel ~= nil and sel.SelectFirstBoonGlow ~= nil, nil)
end

-- Portraits take their own rung. Their iconScale is far lower than a symbol's
-- while the art renders larger, so one box cannot fit both.
do
  local Gp2 = boot(nil, { God = "", ShowInventoryTab = true, IconStyle = "boondrop",
                          HitboxScale = 0.55, HitboxScalePortrait = 0.85,
                          EnableNarcissus = true })
  local scrP2 = Gp2.newInventoryScreen()
  Gp2.SelectFirstBoon_InventoryTabOpen(scrP2)
  local function b2(g)
    for _, b in ipairs(scrP2.SelectFirstBoonButtons) do
      if b.SelectFirstBoonGod == g then return b end
    end
  end
  check("a god symbol uses the symbol rung",
    b2("ZeusUpgrade") ~= nil and b2("ZeusUpgrade").Args.Name == "SelectFirstBoon_Button_55",
    b2("ZeusUpgrade") and b2("ZeusUpgrade").Args.Name)
  check("and a portrait god uses the portrait rung",
    b2("SelectFirstBoon-NarcissusUpgrade") ~= nil
      and b2("SelectFirstBoon-NarcissusUpgrade").Args.Name == "SelectFirstBoon_Button_85",
    b2("SelectFirstBoon-NarcissusUpgrade") and b2("SelectFirstBoon-NarcissusUpgrade").Args.Name)
end

-- The selection light's layers spread rather than stack, so the light reads as a
-- ring rather than a hot spot over the art.
do
  local Gr = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true,
                         SelectionHalo = true, SelectionHaloLayers = 3,
                         SelectionHaloSize = 0.6, SelectionHaloStrength = 0.6,
                         SelectionHaloSpreadStep = 0.5, SeleneGlowStrength = 0 })
  local scrR = Gr.newInventoryScreen()
  Gr.SelectFirstBoon_InventoryTabOpen(scrR)
  local zb = nil
  for _, b in ipairs(scrR.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod == "ZeusUpgrade" then zb = b end
  end
  local g1 = zb and zb.SelectFirstBoonGlow
  local rest = g1 and g1.SelectFirstBoonGlowExtras or {}
  check("the inner layer keeps the set size and strength",
    g1 ~= nil and near(g1.Args.Scale, 0.6) and near(g1.Args.AlphaTarget, 0.6),
    g1 and g1.Args.Scale)
  check("each outer layer is bigger than the one inside it",
    rest[1] ~= nil and rest[1].Args.Scale > g1.Args.Scale, rest[1] and rest[1].Args.Scale)
  check("and dimmer, so the middle does not pile up",
    rest[1] ~= nil and rest[1].Args.AlphaTarget < g1.Args.AlphaTarget,
    rest[1] and rest[1].Args.AlphaTarget)
end

-- Tinting from the god, softened towards white so it still reads as a marker.
do
  local Gt2 = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true,
                          SelectionHalo = true, SelectionHaloTint = "god",
                          SelectionHaloTintMix = 1.0, SeleneGlowStrength = 0 })
  local scrT2 = Gt2.newInventoryScreen()
  Gt2.SelectFirstBoon_InventoryTabOpen(scrT2)
  local zb2 = nil
  for _, b in ipairs(scrT2.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod == "ZeusUpgrade" then zb2 = b end
  end
  local rgb = zb2 and Gt2.rgb[zb2.SelectFirstBoonGlow.Id]
  check("a tinted light takes the god's own colour",
    rgb ~= nil and rgb[1] == 250 and rgb[2] == 230, rgb and (rgb[1] .. "," .. rgb[2]))
  -- Half mix should land between white and the raw colour, not at either end.
  local Gh2 = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true,
                          SelectionHalo = true, SelectionHaloTint = "god",
                          SelectionHaloTintMix = 0.5, SeleneGlowStrength = 0 })
  local scrH2 = Gh2.newInventoryScreen()
  Gh2.SelectFirstBoon_InventoryTabOpen(scrH2)
  local zb3 = nil
  for _, b in ipairs(scrH2.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod == "ZeusUpgrade" then zb3 = b end
  end
  local rgb2 = zb3 and Gh2.rgb[zb3.SelectFirstBoonGlow.Id]
  check("and a half mix sits between white and the raw colour",
    rgb2 ~= nil and rgb2[2] > 230 and rgb2[2] < 255, rgb2 and rgb2[2])
  -- A god with no colour of its own falls back rather than drawing nothing.
  local Gn = boot(nil, { God = "HeraUpgrade", ShowInventoryTab = true,
                         SelectionHalo = true, SelectionHaloTint = "god",
                         SeleneGlowStrength = 0 })
  local scrN3 = Gn.newInventoryScreen()
  Gn.SelectFirstBoon_InventoryTabOpen(scrN3)
  local hb2 = nil
  for _, b in ipairs(scrN3.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod == "HeraUpgrade" then hb2 = b end
  end
  check("a god with no colour falls back to neutral",
    hb2 ~= nil and Gn.rgb[hb2.SelectFirstBoonGlow.Id][1] == 235,
    hb2 and Gn.rgb[hb2.SelectFirstBoonGlow.Id][1])
end

-- Every added god's light is its own colour, not one shared light.
--
-- This asserts the PROPERTY, not the implementation. haloColor is preferred in
-- godLightColor because it is the chain that was worked out for exactly this --
-- npc.LootColor or npc.LightingColor or npc.SubtitleColor -- and the six with
-- portraits have no LootColor of their own. In this harness the LootData
-- fallback happens to reach a distinct colour too, so this test does NOT
-- discriminate between the two paths; reverting the haloColor preference leaves
-- it green. It guards the thing that matters, which is that no two added gods
-- light up the same.
do
  local Gc = boot(nil, { God = "", ShowInventoryTab = true,
                         SelectionHalo = true, SelectionHaloTint = "god",
                         SelectionHaloTintMix = 1.0, SeleneGlowStrength = 0,
                         EnableNarcissus = true, EnableCirce = true })
  local function lightOf(godKey)
    saveTestGod = godKey
    local G2 = boot(nil, { God = godKey, ShowInventoryTab = true,
                           SelectionHalo = true, SelectionHaloTint = "god",
                           SelectionHaloTintMix = 1.0, SeleneGlowStrength = 0,
                           EnableNarcissus = true, EnableCirce = true })
    local sc = G2.newInventoryScreen()
    G2.SelectFirstBoon_InventoryTabOpen(sc)
    for _, b in ipairs(sc.SelectFirstBoonButtons) do
      if b.SelectFirstBoonGod == godKey and b.SelectFirstBoonGlow ~= nil then
        return G2.rgb[b.SelectFirstBoonGlow.Id]
      end
    end
  end
  local narc = lightOf("SelectFirstBoon-NarcissusUpgrade")
  local circe = lightOf("SelectFirstBoon-CirceUpgrade")
  check("a portrait god's light is not the neutral one",
    narc ~= nil and narc[1] ~= 235, narc and narc[1])
  check("and two portrait gods do not share one colour",
    narc ~= nil and circe ~= nil
      and not (narc[1] == circe[1] and narc[2] == circe[2] and narc[3] == circe[3]),
    narc and circe and (table.concat(narc, ",") .. "  vs  " .. table.concat(circe, ",")))
end

-- The hitbox must stay one grid cell however big the art gets.
check("and the hitbox is unchanged", szb["ZeusUpgrade"].Args.Name == "SelectFirstBoon_Button_100",
  szb["ZeusUpgrade"].Args.Name)

-- 76 -------------------------------------------------------------------------
-- Two, not four. Both world-drop variants were cut in 4.9.0: the beam is painted
-- into that texture and neither centring nor vanilla's own anchor keeps it out
-- of the slot. Confirmed in game, not inferred.
-- The art dropdown is gone in 4.10.0: it had a flat option, and leaving it there
-- meant the halo dials silently did nothing -- which is exactly what happened in
-- testing. One art, and the strength dial alone decides on the halo.
section("76. Selene has one art, whatever the cfg holds")
for _, stale in ipairs({ "preview-glow", "preview", "spin", "nonsense" }) do
  G = boot(nil, { God = "@Selene", ShowInventoryTab = true, SeleneIconSource = stale })
  check("a cfg holding " .. stale .. " still draws her art",
    tabIcon(G) == "SelectFirstBoon_Selene_preview", tabIcon(G))
end

do
-- 77 -------------------------------------------------------------------------
section("77. All four extra gods, on identical terms")
G = boot(nil, { God = "", ShowInventoryTab = true, TabIconScale = 0.45,
                EnableArtemis = true, EnableAthena = true,
                EnableDionysus = true, EnableHades = true })
for _, name in ipairs({ "Artemis", "Athena", "Dionysus", "Hades" }) do
  local loot = "SelectFirstBoon-" .. name .. "Upgrade"
  local entry = G.LootData[loot]
  check(name .. " is registered", entry ~= nil and entry.GodLoot == true, entry and entry.GodLoot)
  -- The same three promises Artemis proved, for each of them.
  check(name .. " is never buyable", entry.TreatAsGodLootByShops == nil, nil)
  check(name .. " is first-reward-only", entry.GameStateRequirements ~= nil
    and entry.GameStateRequirements[1].Path[2] == "LootTypeHistory", nil)
  check(name .. " shares its NPC's pool by reference",
    entry.Traits == G.EnemyData[({ Artemis = "NPC_Artemis_Field_01",
      Athena = "NPC_Athena_01", Dionysus = "NPC_Dionysus_01",
      Hades = "NPC_Hades_Field_01" })[name]].Traits, nil)
  check(name .. " uses its own base-game emblem",
    entry.Icon == "BoonSymbol" .. name, entry.Icon)
end

-- Each one must exclude ALL the others, or two could arrive in the same run.
artReq = G.LootData["SelectFirstBoon-ArtemisUpgrade"].GameStateRequirements[1].HasNone
blockedSet = {}
for _, n in ipairs(artReq) do blockedSet[n] = true end
for _, name in ipairs({ "Artemis", "Athena", "Dionysus", "Hades" }) do
  check("Artemis's leash also blocks on " .. name,
    blockedSet["SelectFirstBoon-" .. name .. "Upgrade"] == true, nil)
end

-- Hades is a full boon god here. GodsAPI forces him to NPC-style instead, which
-- is their choice and not the game's.
check("Hades is a boon god, not an NPC-style one",
  G.LootData["SelectFirstBoon-HadesUpgrade"].GodLoot == true, nil)

end

do
-- 78 -------------------------------------------------------------------------
section("78. Each god gets its own tinted drop chain")
animFile2 = nil
for f, _ in pairs(M.byFile) do
  if f:find("Items_General_VFX", 1, true) then animFile2 = f end
end
anims = {}
for _, e in ipairs(M.byFile[animFile2].Animations) do anims[e.Name] = e end
for _, name in ipairs({ "Artemis", "Athena", "Dionysus", "Hades" }) do
  local loot = "SelectFirstBoon-" .. name .. "Upgrade"
  check(name .. "'s orb inherits the vanilla one",
    anims["BoonDrop" .. loot].InheritFrom == "BoonDropGold", nil)
  local c = anims["BoonDropA-" .. loot].Color
  check(name .. "'s glow is tinted in the 0-1 named-channel form",
    c ~= nil and c.Red ~= nil and c.Red <= 1.0, c and c.Red)
  check(name .. "'s emblem is the base-game one",
    anims["BoonDrop" .. loot .. "Icon"].FilePath
      == "GUI\\Screens\\BoonSelectSymbols\\" .. name, nil)
end
-- Four gods must not share one colour by accident.
check("their glows are actually different colours",
  anims["BoonDropA-SelectFirstBoon-ArtemisUpgrade"].Color.Red
    ~= anims["BoonDropA-SelectFirstBoon-DionysusUpgrade"].Color.Red, nil)

end

do
-- 79 -------------------------------------------------------------------------
section("79. Each is switchable on its own")
G = boot(nil, { God = "", ShowInventoryTab = true, EnableArtemis = true,
                EnableAthena = false, EnableDionysus = false, EnableHades = false })
check("only the enabled one registers",
  G.LootData["SelectFirstBoon-ArtemisUpgrade"] ~= nil
  and G.LootData["SelectFirstBoon-AthenaUpgrade"] == nil
  and G.LootData["SelectFirstBoon-DionysusUpgrade"] == nil
  and G.LootData["SelectFirstBoon-HadesUpgrade"] == nil, nil)
check("and the others say why", logsMatch("Athena option disabled by config") ~= nil, nil)
-- A disabled god must not be left in anyone else's leash either.
soloReq = G.LootData["SelectFirstBoon-ArtemisUpgrade"].GameStateRequirements[1].HasNone
soloSet = {}
for _, n in ipairs(soloReq) do soloSet[n] = true end
check("a disabled god is still named in the leash, harmlessly",
  soloSet["SelectFirstBoon-AthenaUpgrade"] == true, nil)

end

do
-- 80 -------------------------------------------------------------------------
section("80. An added god must not burn a max-god slot")
-- A run caps how many gods it uses. Past the cap the game stops offering NEW
-- gods and only offers more from the ones you already hold. The count comes from
-- GetInteractedGodsThisRun (RunLogic.lua:1819-1829), which counts anything with
-- GodLoot -- so without filtering, the Artemis first boon would cost an Olympian
-- for the whole run AND never yield another Artemis boon, since she is leashed.
G = boot(nil, { God = "", EnableArtemis = true, EnableAthena = true,
                EnableDionysus = true, EnableHades = true })
G.CurrentRun = G.newRun()
G.CurrentRun.LootTypeHistory = {
  ZeusUpgrade = 1,
  HeraUpgrade = 1,
  ["SelectFirstBoon-ArtemisUpgrade"] = 1,
  ["SelectFirstBoon-HadesUpgrade"] = 1,
}
counted = G.GetInteractedGodsThisRun()
names = {}
for _, n in ipairs(counted) do names[n] = true end
check("the vanilla gods still count",
  names.ZeusUpgrade and names.HeraUpgrade, table.concat(counted, ","))
check("the added ones do not",
  not names["SelectFirstBoon-ArtemisUpgrade"] and not names["SelectFirstBoon-HadesUpgrade"],
  table.concat(counted, ","))
check("so the run counts two gods, not four", #counted == 2, #counted)

-- The ignoredGod argument has to keep working, since the encounter-loot picks
-- at RewardLogic.lua:267-273 rely on it to choose two different gods.
ignored = G.GetInteractedGodsThisRun("ZeusUpgrade")
check("the ignore argument still works", #ignored == 1 and ignored[1] == "HeraUpgrade",
  table.concat(ignored, ","))

-- A run holding only added gods must count as zero, not as capped.
G.CurrentRun.LootTypeHistory = { ["SelectFirstBoon-ArtemisUpgrade"] = 1 }
check("added gods alone count as no gods at all",
  #G.GetInteractedGodsThisRun() == 0, #G.GetInteractedGodsThisRun())

-- And the filter must never take the game down.
G.CurrentRun = nil
check("no run is survivable", pcall(G.GetInteractedGodsThisRun), nil)

end

do
-- 81 -------------------------------------------------------------------------
section("81. The override reads as what actually overrode it")
G = boot(nil, { God = "@Hermes", ShowInventoryTab = true, BlockHermesBeforeBoon = true })
scrOv = G.newInventoryScreen()
G.textBoxWrites = {}
G.SelectFirstBoon_InventoryTabOpen(scrOv)
check("the gate line names the cause",
  writesTo(4303)[1].RawText == "Hermes Delay:  On (overridden by first boon choice)",
  writesTo(4303)[1].RawText)

end

-- 82 -------------------------------------------------------------------------
-- Wrapped in a block: the file is near Lua's 200-local ceiling for a main chunk.
do
section("82. Selene's halo is a second sprite, not a material")
-- Take one was Material = "Emissive": visually identical to the flat art in
-- game, so that lever is dead.
--
-- Take two draws a separate additive sprite, which is what vanilla does for a
-- halo. It shipped in 4.9.0 and never ran once: the art dropdown still had a
-- flat option, it was set to flat, and makeSeleneGlow returned before drawing.
-- The whole session's log carried no halo line at all. 4.10.0 removes that
-- dropdown and makes every skip say why.
G = boot(nil, { God = "@Selene", ShowInventoryTab = true, SelectionHalo = false, TabIconScale = 0.45,
                SeleneGlowSource = "particle", SeleneGlowStrength = 0.45,
                SeleneGlowSize = 2.2, IconSize = 1.0, SeleneIconBoost = 2.0,
                SeleneHaloSpread = 0.2, VerboseTabLog = true })
seleneAnims = {}
for _, e in ipairs(M.animations.Animations) do
  if e.Name and e.Name:find("SelectFirstBoon_Selene", 1, true) == 1 then
    seleneAnims[e.Name] = e
  end
end
check("one Selene art, plain Unlit",
  seleneAnims["SelectFirstBoon_Selene_preview"].Material == "Unlit", nil)
check("the cut variants are gone",
  seleneAnims["SelectFirstBoon_Selene_spin"] == nil
    and seleneAnims["SelectFirstBoon_Selene_spin-anchored"] == nil
    and seleneAnims["SelectFirstBoon_Selene_preview-glow"] == nil, nil)
-- Every file-based halo source is registered every time, so stepping through
-- them costs a reopen rather than a rebuild.
check("the particle halo is registered",
  seleneAnims["SelectFirstBoon_SeleneGlow_particle"] ~= nil
    and seleneAnims["SelectFirstBoon_SeleneGlow_particle"].FilePath
      == "Particles\\particle_glow",
  seleneAnims["SelectFirstBoon_SeleneGlow_particle"]
    and seleneAnims["SelectFirstBoon_SeleneGlow_particle"].FilePath)
check("so are all three boon backings, from the folder the symbols already use",
  seleneAnims["SelectFirstBoon_SeleneGlow_backing-a"] ~= nil
    and seleneAnims["SelectFirstBoon_SeleneGlow_backing-b"] ~= nil
    and seleneAnims["SelectFirstBoon_SeleneGlow_backing-c"].FilePath
      == "GUI\\Screens\\BoonSelectSymbols\\BoonBackingC",
  seleneAnims["SelectFirstBoon_SeleneGlow_backing-c"]
    and seleneAnims["SelectFirstBoon_SeleneGlow_backing-c"].FilePath)
check("and the two vanilla sources register nothing of ours",
  seleneAnims["SelectFirstBoon_SeleneGlow_vanilla-glow"] == nil
    and seleneAnims["SelectFirstBoon_SeleneGlow_vanilla-flare"] == nil, nil)

scrGlow = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrGlow)
seleneBtn, godBtn = nil, nil
for _, b in ipairs(scrGlow.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod == "@Selene" then seleneBtn = b
  elseif b.SelectFirstBoonGod == "ZeusUpgrade" then godBtn = b end
end
check("Selene's button carries a halo", seleneBtn.SelectFirstBoonGlow ~= nil, nil)
check("nobody else does", godBtn.SelectFirstBoonGlow == nil, nil)
check("it goes in the additive menu group, where the hover frame already works",
  seleneBtn.SelectFirstBoonGlow.Args.Group == "Combat_Menu_Overlay_Additive",
  seleneBtn.SelectFirstBoonGlow.Args.Group)
-- The spread is the component scale DIRECTLY. 4.10.0 multiplied it by the icon
-- scale, which is why the smallest preset still covered a chunk of the screen:
-- particle_glow is a large texture and it was being enlarged twice over.
check("the spread is the scale, with nothing multiplied into it",
  near(seleneBtn.SelectFirstBoonGlow.Args.Scale, 0.2),
  seleneBtn.SelectFirstBoonGlow.Args.Scale)
check("strength drives the alpha",
  near(seleneBtn.SelectFirstBoonGlow.Args.AlphaTarget, 0.45),
  seleneBtn.SelectFirstBoonGlow.Args.AlphaTarget)
check("drawn with the selected source's animation",
  G.animations[seleneBtn.SelectFirstBoonGlow.Id] == "SelectFirstBoon_SeleneGlow_particle",
  G.animations[seleneBtn.SelectFirstBoonGlow.Id])
check("tinted with Selene's own LootColor",
  G.rgb[seleneBtn.SelectFirstBoonGlow.Id] ~= nil
    and G.rgb[seleneBtn.SelectFirstBoonGlow.Id][1] == 100,
  G.rgb[seleneBtn.SelectFirstBoonGlow.Id]
    and G.rgb[seleneBtn.SelectFirstBoonGlow.Id][1])
check("and it sits with the icon, below the slot line",
  near(seleneBtn.SelectFirstBoonGlow.Args.Y, seleneBtn.SelectFirstBoonY),
  seleneBtn.SelectFirstBoonGlow.Args.Y)
-- The log has to name the source, because which one is on screen is the whole
-- question and it cannot be read from here.
check("and the log names the source it used",
  logsMatch("icon halo drawn on") ~= nil
    and logsMatch("source=particle") ~= nil, nil)

-- Additive alpha stops at 1.0, so extra layers are the only way past it. Every
-- layer is a real component and every one has to be cleaned up.
do
G = boot(nil, { God = "@Selene", ShowInventoryTab = true, SelectionHalo = false,
                SeleneGlowSource = "particle", SeleneGlowStrength = 1.0,
                SeleneHaloSpread = 0.16, SeleneHaloLayers = 3 })
scrLayers = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrLayers)
layerBtn = nil
for _, b in ipairs(scrLayers.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod == "@Selene" then layerBtn = b end
end
check("three layers means two extras beyond the tracked one",
  #(layerBtn.SelectFirstBoonGlow.SelectFirstBoonGlowExtras or {}) == 2,
  #(layerBtn.SelectFirstBoonGlow.SelectFirstBoonGlowExtras or {}))
check("every layer sits at the same place and size",
  near(layerBtn.SelectFirstBoonGlow.SelectFirstBoonGlowExtras[1].Args.Scale, 0.16)
    and near(layerBtn.SelectFirstBoonGlow.SelectFirstBoonGlowExtras[1].Args.X,
             layerBtn.SelectFirstBoonGlow.Args.X), nil)
check("and the log says how many were drawn",
  logsMatch("layers=3") ~= nil, nil)

-- A silly layer count must be clamped, not honoured.
G = boot(nil, { God = "@Selene", ShowInventoryTab = true, SelectionHalo = false, SeleneHaloLayers = 99,
                SeleneGlowStrength = 0.8 })
scrClamp = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrClamp)
check("99 layers is clamped to 4", logsMatch("layers=4") ~= nil, nil)
end

-- An unknown source in a hand-edited cfg falls back rather than drawing nothing.
G = boot(nil, { God = "@Selene", ShowInventoryTab = true, SelectionHalo = false,
                SeleneGlowSource = "nonsense", SeleneGlowStrength = 0.6 })
scrBad = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrBad)
for _, b in ipairs(scrBad.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod == "@Selene" then
    check("an unknown source falls back to the first one",
      G.animations[b.SelectFirstBoonGlow.Id] == "SelectFirstBoon_SeleneGlow_particle",
      G.animations[b.SelectFirstBoonGlow.Id])
  end
end

-- Strength 0 is now the ONLY way to turn it off, and it has to say so.
G = boot(nil, { God = "@Selene", ShowInventoryTab = true, SelectionHalo = false,
                SeleneGlowStrength = 0, VerboseTabLog = true })
scrZero = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrZero)
noGlowZero = true
for _, b in ipairs(scrZero.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGlow ~= nil then noGlowZero = false end
end
check("a strength of zero draws no halo", noGlowZero, nil)
check("and says why, rather than skipping in silence",
  logsMatch("icon halo skipped: strength is 0") ~= nil, nil)
end

-- 83 -------------------------------------------------------------------------
do
section("83. The pick reads by size as well as brightness")
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true,
                SelectedIconScale = 1.25, UnselectedBrightness = 0.7, IconSize = 1.0 })
scrSz2 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrSz2)
pick, other = nil, nil
for _, b in ipairs(scrSz2.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod == "ZeusUpgrade" then pick = b
  elseif b.SelectFirstBoonGod == "HeraUpgrade" then other = b end
end
check("the pick is drawn larger", near(pick.Args.Scale, 1.25), pick.Args.Scale)
check("the rest are not", near(other.Args.Scale, 1.0), other.Args.Scale)
check("the pick is fully bright", pick.Args.AlphaTarget == 1.0, pick.Args.AlphaTarget)
check("and the rest sit at the configured level", other.Args.AlphaTarget == 0.7,
  other.Args.AlphaTarget)

-- Changing the pick has to move BOTH signals, not just the brightness.
G.SelectFirstBoon_InventoryTabPick(scrSz2, other)
-- Its live scale is the HOVER size, because pressing leaves the cursor on the
-- button; what matters is that its resting size is now the larger one.
check("the new pick's resting size grows",
  near(other.SelectFirstBoonRestScale, 1.25), other.SelectFirstBoonRestScale)
check("and it is currently drawn at hover size on top of that",
  near(G.scales[other.Id].Fraction, 1.25 * 1.33), G.scales[other.Id].Fraction)
check("the old one shrinks back", near(G.scales[pick.Id].Fraction, 1.0), G.scales[pick.Id].Fraction)
check("and the brightness follows too",
  G.alphas[other.Id] == 1.0 and G.alphas[pick.Id] == 0.7,
  string.format("%s / %s", G.alphas[other.Id], G.alphas[pick.Id]))

-- 1.0 means "same as the rest", and must not shrink anything.
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, SelectedIconScale = 1.0 })
scrFlat = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrFlat)
for _, b in ipairs(scrFlat.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGod == "ZeusUpgrade" then
    check("1.0 draws the pick the same size as the rest", near(b.Args.Scale, 1.0), b.Args.Scale)
  end
end

-- 84 -------------------------------------------------------------------------
section("84. The tab-strip icon gets Selene's correction too")
-- That icon is vanilla's, created in its category loop at CategoryIconScale
-- (0.45), so the per-button SetScale never reaches it and Selene came out tiny
-- up there while looking right in the grid.
--
-- 4.8.0 overcorrected: it reused the GRID's scale, and SetScale's Fraction is
-- absolute, so every tab icon -- Selene's and every god's -- jumped to more than
-- double vanilla's size. The base has to be the tab's own scale.
G = boot(nil, { God = "@Selene", ShowInventoryTab = true, SeleneIconBoost = 2.0,
                IconSize = 1.0, VerboseTabLog = true, TabIconBoost = 1.0 })
scrTab = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrTab)
stripIcon = scrTab.Components["CategoryIconFirst Boon"]
check("the strip icon exists to be scaled", stripIcon ~= nil, nil)
check("and takes Selene's correction on top of the TAB's scale, not the grid's",
  G.scales[stripIcon.Id] ~= nil and near(G.scales[stripIcon.Id].Fraction, 0.45 * 2.0),
  G.scales[stripIcon.Id] and G.scales[stripIcon.Id].Fraction)
check("logged", logsMatch("tab strip icon scaled to 0.90") ~= nil, nil)


-- The strip has to follow a per-icon size, or tuning an icon in the grid leaves
-- the tab showing the old one -- which is exactly what a tuning pass would hit.
do
  local Gs = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true,
                         IconStyle = "boondrop", IconSize = 1.0,
                         TabIconBoost = 1.0, SizeZeus = 1.5 })
  local scrS = Gs.newInventoryScreen()
  Gs.SelectFirstBoon_InventoryTabOpen(scrS)
  local si = scrS.Components["CategoryIconFirst Boon"]
  check("the tab strip icon takes the per-icon size too",
    si ~= nil and Gs.scales[si.Id] ~= nil
      and near(Gs.scales[si.Id].Fraction, 0.45 * 1.5),
    si and Gs.scales[si.Id] and Gs.scales[si.Id].Fraction)
end

-- A god needs no correction, so the strip icon goes back to plain.
G.SelectFirstBoon_InventoryTabPick(scrTab, scrTab.SelectFirstBoonButtons[2])
check("picking a god returns the strip icon to exactly vanilla's size",
  near(G.scales[stripIcon.Id].Fraction, 0.45), G.scales[stripIcon.Id].Fraction)

-- Vanilla's own tab icons read slightly small on this page, so one multiplier
-- lifts EVERY god including the ones needing no other correction. It stacks with
-- Selene's, and 1.0 means exactly vanilla.
G = boot(nil, { God = "", ShowInventoryTab = true, TabIconBoost = 1.15 })
scrBoost = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrBoost)
boostIcon = scrBoost.Components["CategoryIconFirst Boon"]
check("the boost lifts a plain god's tab icon off vanilla's 0.45",
  near(G.scales[boostIcon.Id].Fraction, 0.45 * 1.15), G.scales[boostIcon.Id].Fraction)

G = boot(nil, { God = "@Selene", ShowInventoryTab = true, TabIconBoost = 1.15,
                SeleneIconBoost = 2.0 })
scrBoth = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrBoth)
bothIcon = scrBoth.Components["CategoryIconFirst Boon"]
check("and stacks with Selene's own correction",
  near(G.scales[bothIcon.Id].Fraction, 0.45 * 1.15 * 2.0),
  G.scales[bothIcon.Id].Fraction)
-- And a build with no SetScale must not take the tab down.
G = boot(nil, { God = "@Selene", ShowInventoryTab = true })
G.SetScale = nil
check("no SetScale is survivable", pcall(G.SelectFirstBoon_InventoryTabOpen, G.newInventoryScreen()), nil)
end

-- 85 -------------------------------------------------------------------------
do
section("85. One Selene, one size: the gates match the grid")
-- Reported: the same Selene art appeared at three different sizes on one page.
-- The gate was the third, because gates were sized by their OWN on/off state
-- through the same "the pick is drawn bigger" rule, so an off gate shrank.
G = boot(nil, { God = "@Selene", ShowInventoryTab = true, SelectedIconScale = 1.25,
                SeleneIconBoost = 2.0, IconSize = 1.0 })
scrG = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrG)
seleneOption, hermesGate, seleneGate = nil, nil, nil
for _, b in ipairs(scrG.SelectFirstBoonButtons) do
  local gate = b.SelectFirstBoonGate
  if gate ~= nil and gate.who == "Hermes" then hermesGate = b
  elseif gate ~= nil and gate.who == "Selene" then seleneGate = b
  elseif b.SelectFirstBoonGod == "@Selene" then seleneOption = b end
end
check("the Selene gate is found", seleneGate ~= nil, nil)
-- Selene is the pick here, so her gate is overridden and therefore NOT lit --
-- which is exactly the case that used to shrink it.
check("the overridden gate is drawn dim", seleneGate.Args.AlphaTarget < 1.0,
  seleneGate.Args.AlphaTarget)
check("but at the same size as the picked icon",
  near(seleneGate.Args.Scale, seleneOption.Args.Scale),
  string.format("%s vs %s", seleneGate.Args.Scale, seleneOption.Args.Scale))
check("and the lit gate matches it too",
  near(hermesGate.Args.Scale, 1.0 * 1.25), hermesGate.Args.Scale)

-- Toggling a gate must not resize it either.
sizeBefore = seleneGate.SelectFirstBoonRestScale
G.SelectFirstBoon_InventoryTabPick(scrG, hermesGate)
check("toggling a gate leaves every gate the same size",
  near(seleneGate.SelectFirstBoonRestScale, sizeBefore),
  seleneGate.SelectFirstBoonRestScale)
end

-- 86 -------------------------------------------------------------------------
do
section("86. The pick is forgotten at launch unless told otherwise")
-- The pick lives in the config file, so without this it survives closing the
-- game -- which is right for a preference and wrong for a choice about one run.
G = boot(nil, { God = "ZeusUpgrade", KeepPickAfterRestart = false, LogDecisions = true })
check("a stored pick is cleared on launch", M.store.God == "", M.store.God)
check("and the reset is written to the cfg, not just to memory", M.saves > 0, M.saves)
check("logged, naming what it was", logsMatch("was ZeusUpgrade") ~= nil, nil)
-- The point of the reset is the RUN, not the cfg line: the first boon has to
-- come back as whatever vanilla rolled.
G.CurrentRun = G.newRun()
rReset = G.newRoom("Boon")
G.SetupRoomReward(G.CurrentRun, rReset, {}, {})
check("so the first boon is vanilla's own roll again",
  rReset.ForceLootName == "ApolloUpgrade", rReset.ForceLootName)

G = boot(nil, { God = "ZeusUpgrade", KeepPickAfterRestart = true, LogDecisions = true })
check("with the setting on, the pick survives", M.store.God == "ZeusUpgrade", M.store.God)
check("and says so", logsMatch("keeping last session's pick") ~= nil, nil)

-- Already vanilla: nothing to clear, and nothing to say about it.
G = boot(nil, { God = "", KeepPickAfterRestart = false, LogDecisions = true })
check("an unset pick is left alone quietly",
  M.store.God == "" and logsMatch("reset to Standard") == nil, M.store.God)
end

-- 87 -------------------------------------------------------------------------
do
section("87. The override squares' state style is a choice, not a verdict")
-- 4.9.0 pinned them to one size to stop the same Selene art appearing at two
-- sizes. That fixed one inconsistency and created another: picks change size,
-- gates only change brightness. Both readings are defensible, so it is a knob.
--
-- The comparison is the SAME gate with its setting on versus off -- not one gate
-- against the other, which would only measure Selene's art correction.
function gateOf(scr, who)
  for _, b in ipairs(scr.SelectFirstBoonButtons) do
    local g = b.SelectFirstBoonGate
    if g ~= nil and g.who == who then return b end
  end
end
function seleneGate(style, on)
  G = boot(nil, { God = "", ShowInventoryTab = true, GateStateStyle = style,
                  BlockSeleneBeforeBoon = on, BlockHermesBeforeBoon = true,
                  SelectedIconScale = 1.4, UnselectedBrightness = 0.6,
                  SeleneIconBoost = 2.0, IconSize = 1.0 })
  local scr = G.newInventoryScreen()
  G.SelectFirstBoon_InventoryTabOpen(scr)
  return gateOf(scr, "Selene"), scr
end

bOn = seleneGate("brightness", true)
bOff = seleneGate("brightness", false)
check("brightness style: the size does not move with the setting",
  near(bOn.Args.Scale, bOff.Args.Scale),
  string.format("%s vs %s", bOn.Args.Scale, bOff.Args.Scale))
check("but the brightness does",
  bOn.Args.AlphaTarget > bOff.Args.AlphaTarget,
  string.format("%s vs %s", bOn.Args.AlphaTarget, bOff.Args.AlphaTarget))
-- And it stays at the size a PICKED icon is drawn at, which is the whole point:
-- an off gate must not shrink below the grid.
check("and it sits at the picked size, not the unpicked one",
  near(bOff.Args.Scale, 2.0 * 1.4), bOff.Args.Scale)

sOn = seleneGate("size", true)
sOff = seleneGate("size", false)
check("size style: on is drawn larger than off",
  sOn.Args.Scale > sOff.Args.Scale,
  string.format("%s vs %s", sOn.Args.Scale, sOff.Args.Scale))
check("with the same 1.4 step a picked boon gets",
  near(sOn.Args.Scale, sOff.Args.Scale * 1.4),
  string.format("%s vs %s", sOn.Args.Scale, sOff.Args.Scale))
check("and the brightness still moves too",
  sOn.Args.AlphaTarget > sOff.Args.AlphaTarget, sOff.Args.AlphaTarget)

-- size-only: brightness frozen at the UNPICKED level -- the same dim an unpicked
-- boon sits at in the grid -- and the size carries the state alone. Frozen-at-
-- full is what "none" does; these two must not converge.
oOn, oOff, scrO = nil, nil, nil
oOn = seleneGate("size-only", true)
oOff, scrO = seleneGate("size-only", false)
check("size-only: both rest at the unpicked brightness, on or off",
  oOn.Args.AlphaTarget == 0.6 and oOff.Args.AlphaTarget == 0.6,
  string.format("%s / %s", oOn.Args.AlphaTarget, oOff.Args.AlphaTarget))
check("but the size still moves with the setting",
  oOn.Args.Scale > oOff.Args.Scale,
  string.format("%s vs %s", oOn.Args.Scale, oOff.Args.Scale))
-- The unpicked grid size for Selene is her icon scale with no picked-size step.
check("and an off square rests at exactly the unpicked grid size",
  (function()
    for _, b in ipairs(scrO.SelectFirstBoonButtons) do
      if b.SelectFirstBoonGod == "@Selene" then
        return near(oOff.Args.Scale, b.Args.Scale)
      end
    end
    return false
  end)(), oOff.Args.Scale)

nOn = seleneGate("none", true)
nOff, scrN = seleneGate("none", false)
check("none style: nothing moves, size or brightness",
  near(nOn.Args.Scale, nOff.Args.Scale)
    and nOn.Args.AlphaTarget == nOff.Args.AlphaTarget,
  string.format("%s/%s vs %s/%s", nOn.Args.Scale, nOn.Args.AlphaTarget,
                nOff.Args.Scale, nOff.Args.AlphaTarget))
check("and an off gate is drawn at full brightness",
  nOff.Args.AlphaTarget == 1.0, nOff.Args.AlphaTarget)
-- The two frozen-brightness styles must not collapse into each other.
check("which is what separates none from size-only",
  nOff.Args.AlphaTarget ~= oOff.Args.AlphaTarget,
  string.format("%s vs %s", nOff.Args.AlphaTarget, oOff.Args.AlphaTarget))
-- The press still works; only the drawing is frozen.
G.SelectFirstBoon_InventoryTabPick(scrN, nOff)
check("the press still flips the setting", M.store.BlockSeleneBeforeBoon == true,
  M.store.BlockSeleneBeforeBoon)

-- A hand-edited nonsense value must land on the default, not blank the page.
xOn = seleneGate("nonsense", true)
xOff = seleneGate("nonsense", false)
check("an unknown style behaves as brightness",
  near(xOn.Args.Scale, xOff.Args.Scale) and xOn.Args.AlphaTarget > xOff.Args.AlphaTarget,
  string.format("%s vs %s", xOn.Args.Scale, xOff.Args.Scale))
end

-- 88 -------------------------------------------------------------------------
do
section("88. The added gods' boons stay rarity-only, exactly as vanilla has them")
-- Reported: with the Hades-and-Persephone keepsake equipped, a boon taken from
-- one of our drops came out at level 4. These gods' boons cannot be levelled at
-- all in vanilla -- their power is rarity, not stacks.
G = boot(nil, { God = "", EnableArtemis = true, EnableAthena = true,
                EnableDionysus = true, EnableHades = true })

-- The data half: vanilla's own escape hatch, on the branch that adds BOTH the
-- bonus-rank levels and the keepsake's FatedBoonLevelBonus.
for _, name in ipairs({ "Artemis", "Athena", "Dionysus", "Hades" }) do
  check(name .. "'s loot refuses the stack boost",
    G.LootData["SelectFirstBoon-" .. name .. "Upgrade"].IgnoreStackBoost == true,
    G.LootData["SelectFirstBoon-" .. name .. "Upgrade"].IgnoreStackBoost)
end

-- The bigger half: registering a LootData entry with GodLoot flips FOUR vanilla
-- "which god owns this trait?" scans to yes for these traits, and that reaches
-- boons taken from the NPC in an ordinary room too -- the Pom of Power list, and
-- the requirement checks some Arcana read. Vanilla says no; so must we.
artemisTrait = G.EnemyData.NPC_Artemis_Field_01.Traits[1]
hadesTrait = G.EnemyData.NPC_Hades_Field_01.Traits[1]
check("an added god's trait is NOT a god trait, as in vanilla",
  G.IsGodTrait(artemisTrait) == false, G.IsGodTrait(artemisTrait))
check("nor is Hades'", G.IsGodTrait(hadesTrait) == false, G.IsGodTrait(hadesTrait))
-- ForShop is the one question vanilla answers yes to, through FieldLootData's
-- TreatAsGodLootByShops. That answer must not change either.
check("but ForShop still says yes, the way FieldLootData does",
  G.IsGodTrait(artemisTrait, { ForShop = true }) == true,
  G.IsGodTrait(artemisTrait, { ForShop = true }))
check("and the shop-side source is the NPC, not our shadow entry",
  G.GetGodSourceName(artemisTrait, { ForShop = true }) == "NPC_Artemis_Field_01",
  G.GetGodSourceName(artemisTrait, { ForShop = true }))
check("the boon-info source falls through to the NPC too",
  G.GetLootSourceName(artemisTrait, { ForBoonInfo = true, CheckEnemyData = true })
    == "NPC_Artemis_Field_01",
  G.GetLootSourceName(artemisTrait, { ForBoonInfo = true, CheckEnemyData = true }))
check("and nothing of ours appears in the all-sources list",
  G.GetAllLootSourceNames(artemisTrait, { ForBoonInfo = true })["SelectFirstBoon-ArtemisUpgrade"] == nil,
  nil)

-- A real Olympian must be untouched by all of that -- poms still work on him.
G.LootData.ZeusUpgrade.Traits = { "ZeusA", "ZeusB" }
G.LootData.ZeusUpgrade.TraitIndex = nil
check("a vanilla god's trait is still a god trait",
  G.IsGodTrait("ZeusA") == true, G.IsGodTrait("ZeusA"))

-- The hiding must not leak: LootData has to come back exactly as it was.
check("our entries are still in LootData after the scan",
  G.LootData["SelectFirstBoon-ArtemisUpgrade"] ~= nil
    and G.LootData["SelectFirstBoon-HadesUpgrade"] ~= nil, nil)

-- ... including when the game's own scan raises mid-way. A LootData entry that
-- throws on any field access is the cheapest way to force that.
G.LootData.PoisonUpgrade = setmetatable({ GodLoot = true },
  { __index = function() error("simulated trait scan failure") end })
-- A trait no god has, so the scan cannot short-circuit before reaching it.
raised = not pcall(G.IsGodTrait, "NoSuchTraitAnywhere")
check("a raising scan is re-raised, not swallowed", raised, raised)
check("but our entries are put back first",
  G.LootData["SelectFirstBoon-ArtemisUpgrade"] ~= nil
    and G.LootData["SelectFirstBoon-AthenaUpgrade"] ~= nil
    and G.LootData["SelectFirstBoon-DionysusUpgrade"] ~= nil
    and G.LootData["SelectFirstBoon-HadesUpgrade"] ~= nil, nil)
check("and the failure is named in the log",
  logsMatch("raised while our gods were hidden") ~= nil, nil)
G.LootData.PoisonUpgrade = nil
end

-- 89 -------------------------------------------------------------------------
do
section("89. The added gods' drop emblem is scaled down to match a vanilla boon")
-- BoonDropIcon is Scale 0.7 around Items\Loot\Boon\<God>IconSpin. Ours points
-- at the BoonSelectSymbols emblem instead, which is bigger art, so inheriting
-- that 0.7 put a visibly larger orb next to a vanilla one.
G = boot(nil, { God = "", EnableHades = true, DropIconScale = 0.3 })
dropIcon, dropPreview = nil, nil
for _, entries in pairs(M.byFile or {}) do
  for _, e in ipairs(entries.Animations or {}) do
    if e.Name == "BoonDropSelectFirstBoon-HadesUpgradeIcon" then dropIcon = e end
    if e.Name == "BoonDropSelectFirstBoon-HadesUpgradePreview" then dropPreview = e end
  end
end
check("the emblem layer carries an explicit scale",
  dropIcon ~= nil and dropIcon.Scale == 0.3, dropIcon and dropIcon.Scale)
check("and still points at the base game's own emblem art",
  dropIcon.FilePath == "GUI\\Screens\\BoonSelectSymbols\\Hades", dropIcon.FilePath)
-- The door preview is a different animation with a different base and was not
-- reported as wrong, so it is deliberately left alone.
check("the door preview is untouched by this setting",
  dropPreview ~= nil and dropPreview.Scale == nil, dropPreview and dropPreview.Scale)

do
-- The three glow layers, straight through and in vanilla's high-contrast shape.
-- Athena's drop came back unreadable in game: three near-identical golds behind
-- a gold emblem. Every base-game god uses three DIFFERENT saturated hues, and
-- the innermost one contrasts with the emblem -- Zeus is orange/orange/GREEN
-- (Items_General_VFX.sjson:5859, :5871, :5883).
G = boot(nil, { God = "", EnableAthena = true, EnableHades = true,
                DropGlowBrightness = 1.0 })
function layer(loot, which)
  for _, entries in pairs(M.byFile or {}) do
    for _, e in ipairs(entries.Animations or {}) do
      if e.Name == "BoonDrop" .. which .. "-SelectFirstBoon-" .. loot .. "Upgrade" then return e end
    end
  end
end
aA, aB, aC = layer("Athena", "A"), layer("Athena", "B"), layer("Athena", "C")
check("Athena's three layers are all present",
  aA ~= nil and aB ~= nil and aC ~= nil, nil)
-- Athena follows Hephaestus's structure (Items_General_VFX.sjson:5662-5686):
-- a DARK outer layer and the saturated hero colour at the core. That is much
-- less total light than three bright layers, and it puts gold where the emblem
-- sits -- 4.13.0's blue core made the whole orb read cold.
check("Athena's outer layer is dark, the way Hephaestus's and Ares's are",
  math.max(aA.Color.Red, aA.Color.Green, aA.Color.Blue) <= 0.35,
  string.format("%s/%s/%s", aA.Color.Red, aA.Color.Green, aA.Color.Blue))
check("and her core is a saturated gold, not a cold contrast",
  aC.Color.Red >= 0.9 and aC.Color.Red > aC.Color.Blue
    and aC.Color.Green > aC.Color.Blue,
  string.format("%s/%s/%s", aC.Color.Red, aC.Color.Green, aC.Color.Blue))
check("brightness rises inward, outer to core",
  aC.Color.Red > aB.Color.Red and aB.Color.Red > aA.Color.Red,
  string.format("%s -> %s -> %s", aA.Color.Red, aB.Color.Red, aC.Color.Red))
-- Hades was checked in game and approved. Undoing the old A/B swap must not have
-- moved a single channel of his.
hA, hB, hC = layer("Hades", "A"), layer("Hades", "B"), layer("Hades", "C")
check("Hades' approved colours survive the un-swap",
  near(hA.Color.Red, 0.10) and near(hB.Color.Red, 0.859) and near(hC.Color.Red, 0.16),
  string.format("%s / %s / %s", hA.Color.Red, hB.Color.Red, hC.Color.Red))
check("including the Opacity no vanilla drop carries",
  near(hB.Color.Opacity, 0.8), hB.Color.Opacity)

-- One dial takes the whole orb down without disturbing the hue relationships.
-- Per god here too: one shared glow value had the same defect as one shared
-- emblem value, and Athena is the only drop anyone has had to tune.
G = boot(nil, { God = "", EnableAthena = true, EnableHades = true,
                GlowBrightnessAthena = 0.5, GlowBrightnessHades = 1.0 })
dA, dC = layer("Athena", "A"), layer("Athena", "C")
check("a lower glow halves every colour channel",
  near(dA.Color.Red, 0.30 * 0.5) and near(dC.Color.Red, 1.0 * 0.5),
  string.format("%s / %s", dA.Color.Red, dC.Color.Red))
check("and the hue relationship is preserved, not flattened",
  dC.Color.Red > dC.Color.Green and dC.Color.Green > dC.Color.Blue,
  string.format("%s/%s/%s", dC.Color.Red, dC.Color.Green, dC.Color.Blue))
check("and another god's orb is untouched",
  near(layer("Hades", "B").Color.Red, 0.859), layer("Hades", "B").Color.Red)

-- Above 1.0 as well as below. Whether the renderer clamps is not knowable from
-- the data files, so the plugin must at least WRITE the larger number rather
-- than imposing a ceiling of its own and hiding the answer.
G = boot(nil, { God = "", EnableAthena = true, GlowBrightnessAthena = 1.5 })
check("and a value above 1.0 is written through, not clamped by us",
  near(layer("Athena", "C").Color.Red, 1.5), layer("Athena", "C").Color.Red)


-- Opacity is an alpha. Scaling it would fade the layer out instead of dimming it.
G = boot(nil, { God = "", EnableHades = true, DropGlowBrightness = 0.5 })
dimHades = layer("Hades", "B")
check("but Opacity is left alone, being an alpha rather than a colour",
  near(dimHades.Color.Opacity, 0.8), dimHades.Color.Opacity)
end

-- A nonsense value must not register Scale 0 and make the emblem vanish.
G = boot(nil, { God = "", EnableHades = true, DropIconScale = 0 })
zeroIcon = nil
for _, entries in pairs(M.byFile or {}) do
  for _, e in ipairs(entries.Animations or {}) do
    if e.Name == "BoonDropSelectFirstBoon-HadesUpgradeIcon" then zeroIcon = e end
  end
end
check("a zero scale falls back rather than hiding the emblem",
  zeroIcon.Scale == 0.4, zeroIcon.Scale)
end

-- 89b ------------------------------------------------------------------------
do
-- The emblem has its own brightness, and it must be a SEPARATE lever from the
-- glow dial: they test different hypotheses about why a drop washes out. The
-- BoonSelectSymbols art carries a painted halo (the menu proves it -- the nine
-- Olympians glow, Hammer and Hermes from the same folder do not), which vanilla's
-- <God>IconSpin drop art does not.
-- Per god, because the correction is a property of each TEXTURE. Athena's emblem
-- carries the most painted glow of the four and washed out inside the orb;
-- Artemis's and Hades's were checked in game at full and look right, so a single
-- shared value would have spoiled two drops to rescue one.
G = boot(nil, { God = "", EnableAthena = true, EnableHades = true,
                EmblemBrightnessAthena = 0.5, EmblemBrightnessHades = 1.0,
                DropGlowBrightness = 1.0 })
function emblemOf(loot)
  for _, entries in pairs(M.byFile or {}) do
    for _, e in ipairs(entries.Animations or {}) do
      if e.Name == "BoonDrop" .. loot .. "Icon" then return e end
    end
  end
end
check("a lower emblem brightness multiplies the emblem down",
  (function()
    local c = emblemOf("SelectFirstBoon-AthenaUpgrade").Color
    return c ~= nil and near(c.Red, 0.5) and near(c.Green, 0.5) and near(c.Blue, 0.5)
  end)(), emblemOf("SelectFirstBoon-AthenaUpgrade").Color)
check("and leaves the glow layers alone",
  near(layer("Athena", "A").Color.Red, 0.30), layer("Athena", "A").Color.Red)
check("and does not touch another added god's emblem",
  emblemOf("SelectFirstBoon-HadesUpgrade").Color == nil,
  emblemOf("SelectFirstBoon-HadesUpgrade").Color)

-- Full brightness must leave the entry exactly as it was, not write a white
-- Color that would quietly change how the sprite is drawn.
G = boot(nil, { God = "", EnableAthena = true, EmblemBrightnessAthena = 1.0 })
check("full brightness writes no Color at all",
  emblemOf("SelectFirstBoon-AthenaUpgrade").Color == nil,
  emblemOf("SelectFirstBoon-AthenaUpgrade").Color)

-- Athena starts dimmed out of the box; nobody else does. A fresh install has to
-- look right without anyone opening the settings.
G = boot(nil, { God = "", EnableArtemis = true, EnableAthena = true,
                EnableDionysus = true, EnableHades = true })
check("Athena's emblem is dimmed by default",
  (function()
    local c = emblemOf("SelectFirstBoon-AthenaUpgrade").Color
    return c ~= nil and near(c.Red, 0.7)
  end)(), emblemOf("SelectFirstBoon-AthenaUpgrade").Color)
for _, name in ipairs({ "Artemis", "Dionysus", "Hades" }) do
  check(name .. "'s emblem is left at full by default",
    emblemOf("SelectFirstBoon-" .. name .. "Upgrade").Color == nil,
    emblemOf("SelectFirstBoon-" .. name .. "Upgrade").Color)
end

-- The additive layer is the one that blows out. BoonDropB sets AddColor = true
-- (Items_General_VFX.sjson:5002); A and C inherit BoonDropA, which does not. So
-- B's colour is ADDED to the scene, and every vanilla B is a saturated colour --
-- never near-white. 4.12.0 put a pale gold there and got a white blob.
G = boot(nil, { God = "", EnableAthena = true, EnableDionysus = true })
function saturationOf(name)
  local c = layer(name, "B").Color
  return math.max(c.Red, c.Green, c.Blue) - math.min(c.Red, c.Green, c.Blue)
end
for _, name in ipairs({ "Athena", "Dionysus" }) do
  check(name .. "'s additive layer is a saturated colour, not near-white",
    saturationOf(name) >= 0.6, string.format("%.2f spread", saturationOf(name)))
end
end

-- 90 -------------------------------------------------------------------------
do
section("90. The pick's tooltip describes when it actually takes effect")
-- It used to say "at the next door unlock". That is only true of the very first
-- reward of a run: the priority is queued once per run, and markSpawned latches
-- the plugin off for the rest of it the moment the chosen boon spawns. So for
-- anyone reading the tooltip mid-run, the honest answer is "next run".
G = boot(nil, { God = "ZeusUpgrade" })
openWindow()
draw({})
tip = nil
for _, t in ipairs(M.tooltips or {}) do
  if t:find("the run opens with", 1, true) then tip = t end
end
if tip == nil then
  -- The mock ImGui reports IsItemHovered false, so tooltips are not captured.
  -- Assert against the behaviour the wording claims instead, which is the part
  -- that could actually drift.
  G.CurrentRun = G.newRun()
  local r1 = G.newRoom("Boon")
  G.SetupRoomReward(G.CurrentRun, r1, {}, {})
  check("the first reward of a run is forced", r1.ForceLootName == "ZeusUpgrade",
    r1.ForceLootName)
  G.GiveLoot({ ForceLootName = "ZeusUpgrade" })
  local r2 = G.newRoom("Boon")
  G.SetupRoomReward(G.CurrentRun, r2, {}, {})
  check("and nothing after it is, which is why the tooltip says next RUN",
    r2.ForceLootName ~= "ZeusUpgrade" or r2.ForceLootName == G.ROLL,
    r2.ForceLootName)
else
  check("the tooltip no longer promises the next door unlock",
    tip:find("door unlock", 1, true) == nil, tip)
end
end

-- 91 -------------------------------------------------------------------------
do
section("91. A setting's current value is always re-selectable")
-- 4.14.0 shipped Athena's emblem default at 0.7 while 0.7 was not in the preset
-- list. The combo showed 70%, but picking anything else meant never getting back
-- without hand-editing the cfg -- a one-way door. A default the menu cannot
-- re-select is a bug in the menu, not a reason to move the default.
G = boot(nil, { God = "", EnableArtemis = true, EnableAthena = true,
                EnableDionysus = true, EnableHades = true })
openWindow()
draw({ openCombo = true })

function offered(label)
  for _, call in ipairs(M.imguiCalls) do
    if call:find("Selectable:" .. label, 1, true) == 1 then return true end
  end
  return false
end

check("the shipped Athena emblem default is offered in its own list",
  offered("70%"), nil)
-- And a hand-edited value the presets have never heard of must survive too.
G = boot(nil, { God = "", EnableAthena = true, EmblemBrightnessAthena = 0.37 })
openWindow()
draw({ openCombo = true })
check("so is a hand-edited value that is in no preset list", offered("37%"), nil)

-- "Full" is 1.0 and nothing else. 4.14.0 labelled everything at or above 1.0 as
-- "Full", so the entire upper half of the glow list read identically and there
-- was no way to tell 1.25 from 2.0, or to know a pick had done anything.
G = boot(nil, { God = "", EnableAthena = true })
openWindow()
draw({ openCombo = true })
check("values above 1.0 show their real number", offered("150%") and offered("200%"),
  nil)
check("and exactly 1.0 is the only one called Full", offered("Full"), nil)
check("with nothing above it borrowing the word",
  (function()
    local seen = 0
    for _, call in ipairs(M.imguiCalls) do
      if call:find("Selectable:Full", 1, true) == 1 then seen = seen + 1 end
    end
    -- One per combo that has 1.0 in its list; what must not happen is several
    -- inside a SINGLE combo, which is what the old label did.
    return seen >= 1
  end)(), nil)
end

-- 92 -------------------------------------------------------------------------
do
section("92. The drop can use a keepsake portrait instead of an emblem")
-- Six more NPC gods (Narcissus, Arachne, Circe, Echo, Medea, Icarus) have a
-- keepsake portrait and NO entry in BoonSelectSymbols, so whether a portrait
-- renders inside a world orb decides whether they can ever have a drop. This
-- toggle answers that on a god who already works, for the price of one restart.
G = boot(nil, { God = "", EnableArtemis = true, EnableAthena = true,
                EnableHades = true, EmblemArtAthena = "portrait" })
-- The big variant, because the small one came back jagged in game -- it is small
-- art being drawn larger. The small one stays available as portrait-small.
check("the portrait variant points at the BIG keepsake-portrait art",
  emblemOf("SelectFirstBoon-AthenaUpgrade").FilePath
    == "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_big\\Athena",
  emblemOf("SelectFirstBoon-AthenaUpgrade").FilePath)

G = boot(nil, { God = "", EnableAthena = true, EmblemArtAthena = "portrait-small" })
check("and the small art is still reachable",
  emblemOf("SelectFirstBoon-AthenaUpgrade").FilePath
    == "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_small\\Athena",
  emblemOf("SelectFirstBoon-AthenaUpgrade").FilePath)

-- Emblem and portrait are different source sizes, so the scale is per ART
-- FAMILY. One number cannot serve both, and ten gods with one dial each would be
-- ten dials answering two questions.
G = boot(nil, { God = "", EnableArtemis = true, EnableAthena = true,
                EmblemArtAthena = "portrait", DropIconScale = 0.4,
                DropPortraitScale = 0.22 })
check("a portrait drop takes the portrait scale",
  near(emblemOf("SelectFirstBoon-AthenaUpgrade").Scale, 0.22),
  emblemOf("SelectFirstBoon-AthenaUpgrade").Scale)
check("and an emblem drop keeps the emblem scale",
  near(emblemOf("SelectFirstBoon-ArtemisUpgrade").Scale, 0.4),
  emblemOf("SelectFirstBoon-ArtemisUpgrade").Scale)

G = boot(nil, { God = "", EnableAthena = true, EmblemArtAthena = "portrait" })
check("and a god left on symbol is untouched",
  emblemOf("SelectFirstBoon-ArtemisUpgrade").FilePath
    == "GUI\\Screens\\BoonSelectSymbols\\Artemis",
  emblemOf("SelectFirstBoon-ArtemisUpgrade").FilePath)

-- Default is symbol for everyone: this is an experiment, not a new look.
G = boot(nil, { God = "", EnableAthena = true })
check("symbol is the default", emblemOf("SelectFirstBoon-AthenaUpgrade").FilePath
  == "GUI\\Screens\\BoonSelectSymbols\\Athena",
  emblemOf("SelectFirstBoon-AthenaUpgrade").FilePath)

-- The keepsake-portrait set has no plain Hades -- only HadesPersephone, which is
-- a picture of two other people. Asking for his portrait must fall back to the
-- emblem and SAY so, not silently draw the wrong god.
G = boot(nil, { God = "", EnableHades = true, EmblemArtHades = "portrait",
                LogDecisions = true })
check("Hades falls back to his emblem, having no portrait of his own",
  emblemOf("SelectFirstBoon-HadesUpgrade").FilePath == "GUI\\Screens\\BoonSelectSymbols\\Hades",
  emblemOf("SelectFirstBoon-HadesUpgrade").FilePath)
check("and says why rather than drawing the joint keepsake",
  logsMatch("has no keepsake portrait") ~= nil, nil)

-- No portrait combo is drawn for him either, so the cfg is the only way to ask.
openWindow()
draw({ openCombo = true })
check("and he is offered no drop-art combo at all",
  (function()
    for _, call in ipairs(M.imguiCalls) do
      if call:find("EmblemArtHades", 1, true) then return false end
    end
    return true
  end)(), nil)
end

-- 93 -------------------------------------------------------------------------
do
section("93. Narcissus, the first god with no emblem at all")
-- The portrait experiment came back positive in game, which is what makes a
-- portrait-only god possible: he has a keepsake portrait and no entry in
-- BoonSelectSymbols, so before that test he could not have had a drop.
G = boot(nil, { God = "", EnableNarcissus = true, ShowInventoryTab = true,
                DropPortraitScale = 0.22 })
check("he registers as a boon god", G.LootData["SelectFirstBoon-NarcissusUpgrade"] ~= nil, nil)
check("with his own trait pool, by reference",
  G.LootData["SelectFirstBoon-NarcissusUpgrade"].Traits
    == G.EnemyData.NPC_Narcissus_Field_01.Traits, nil)
check("and the same rarity-only promise as the others",
  G.LootData["SelectFirstBoon-NarcissusUpgrade"].IgnoreStackBoost == true, nil)

check("his orb draws the portrait, not a symbol he does not have",
  emblemOf("SelectFirstBoon-NarcissusUpgrade").FilePath
    == "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_big\\Narcissus",
  emblemOf("SelectFirstBoon-NarcissusUpgrade").FilePath)
check("at the portrait scale", near(emblemOf("SelectFirstBoon-NarcissusUpgrade").Scale, 0.22),
  emblemOf("SelectFirstBoon-NarcissusUpgrade").Scale)

-- No palette was hand-picked for him. It comes from his own LootColor by the
-- Hephaestus shape: dark outer, mid, saturated core.
check("his glow is derived from his own LootColor, brightest channel normalised",
  near(layer("Narcissus", "C").Color.Red, 1.0)
    and near(layer("Narcissus", "A").Color.Red, 0.30),
  string.format("A=%s C=%s", layer("Narcissus", "A").Color.Red,
                layer("Narcissus", "C").Color.Red))
check("and keeps his hue rather than going grey",
  layer("Narcissus", "C").Color.Red > layer("Narcissus", "C").Color.Blue,
  string.format("%s vs %s", layer("Narcissus", "C").Color.Red,
                layer("Narcissus", "C").Color.Blue))

-- The tab has to draw him in EVERY icon style, because there is no emblem to
-- fall back to and falling through the styles would leave him blank.
for _, style in ipairs({ "symbol", "boondrop", "portrait" }) do
  G = boot(nil, { God = "", EnableNarcissus = true, ShowInventoryTab = true,
                  IconStyle = style })
  local scrN = G.newInventoryScreen()
  G.SelectFirstBoon_InventoryTabOpen(scrN)
  local drawn
  for _, b in ipairs(scrN.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod == "SelectFirstBoon-NarcissusUpgrade" then
      drawn = G.animations[b.Id]
    end
  end
  check("in the " .. style .. " style he still draws his portrait",
    drawn == "SelectFirstBoon_Portrait_Narcissus", drawn)
end

-- Arachne is the second, and the one 4.17.0 got wrong. Her pool reads like
-- costumes -- AgilityCostume, ManaCostume -- so it was dismissed on the names.
-- But AgilityCostume carries full RarityLevels and a WeaponSpeedMultiplier
-- (TraitData_Arachne.lua:3-30): a rarity-scaled stat trait offered one-of-three,
-- with the costume riding along. That is a boon.
G = boot(nil, { God = "", EnableArachne = true, ShowInventoryTab = true })
check("Arachne registers too", G.LootData["SelectFirstBoon-ArachneUpgrade"] ~= nil, nil)
check("and her orb draws her portrait",
  emblemOf("SelectFirstBoon-ArachneUpgrade").FilePath
    == "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_big\\Arachne",
  emblemOf("SelectFirstBoon-ArachneUpgrade").FilePath)
-- She has no LootColor at all, never having had a drop. The palette falls back
-- to her voice colour rather than to grey.
check("her palette falls back to SubtitleColor, not to grey",
  layer("Arachne", "C").Color.Blue > layer("Arachne", "C").Color.Green,
  string.format("%s/%s/%s", layer("Arachne", "C").Color.Red,
                layer("Arachne", "C").Color.Green, layer("Arachne", "C").Color.Blue))

-- Both ship ON, like the rest of the added ten. They are still one switch each,
-- and switching one off has to actually remove it from LootData rather than
-- merely hiding the icon -- otherwise the god stays pickable through the config.
G = boot(nil, { God = "", ShowInventoryTab = true })
check("both are on by default",
  G.LootData["SelectFirstBoon-NarcissusUpgrade"] ~= nil
    and G.LootData["SelectFirstBoon-ArachneUpgrade"] ~= nil, nil)
G = boot(nil, { God = "", ShowInventoryTab = true,
                EnableNarcissus = false, EnableArachne = false })
check("and each has a switch that removes it",
  G.LootData["SelectFirstBoon-NarcissusUpgrade"] == nil
    and G.LootData["SelectFirstBoon-ArachneUpgrade"] == nil, nil)
end

-- 94 -------------------------------------------------------------------------
do
section("94. The candidate log answers who else could be added")
-- Six characters were suggested. Reading the data showed the real question is
-- whether a trait pool is a BOON pool: Arachne's are AgilityCostume, ManaCostume
-- and the rest. A costume vendor in a boon slot would be a real bug, so rather
-- than guess, the plugin reports what the running game actually holds.
G = boot(nil, { God = "", LogGodCandidates = true })
check("a boon-shaped candidate is listed with its traits",
  logsMatch("candidate: NPC_Narcissus_Field_01") ~= nil
    and logsMatch("NarcissusA") ~= nil, nil)
check("so is one whose pool gives it away as something else",
  logsMatch("candidate: NPC_Arachne_01") ~= nil
    and logsMatch("AgilityCostume") ~= nil, nil)
check("and the trait count comes with it",
  logsMatch("3 traits") ~= nil, nil)
-- The Field unit inherits from the plain one, so both would say the same thing.
check("each character is reported once, not once per unit",
  (function()
    local seen = 0
    for _, line in ipairs(M.logs) do
      if line:find("candidate: NPC_Narcissus", 1, true) then seen = seen + 1 end
    end
    return seen == 1
  end)(), nil)

G = boot(nil, { God = "", LogGodCandidates = false })
check("and it can be turned off", logsMatch("candidate: NPC_") == nil, nil)
end

-- 95 -------------------------------------------------------------------------
do
section("95. An added god is a pick, not a new resident of the reward pool")
-- Registering a god means a LootData entry with GodLoot = true, and
-- GetEligibleLootNames (RewardLogic.lua:186-200) keeps everything with that flag
-- whose requirements pass. Ours pass while no boon has been taken, so on the
-- run's first boon they sat in vanilla's candidate list beside Zeus -- and its
-- own roll could land on one, whatever the pick was, including on Standard.
G = boot(nil, { God = "", EnableArtemis = true, EnableAthena = true })
G.CurrentRun = G.newRun()
G.ELIGIBLE_EXTRA = { "SelectFirstBoon-ArtemisUpgrade", "SelectFirstBoon-AthenaUpgrade" }

function eligible()
  local set = {}
  for _, n in ipairs(G.GetEligibleLootNames()) do set[n] = true end
  return set
end

check("on Standard, no added god is offered to the game's own roll",
  eligible()["SelectFirstBoon-ArtemisUpgrade"] == nil
    and eligible()["SelectFirstBoon-AthenaUpgrade"] == nil, nil)
check("and the vanilla gods are all still there",
  eligible()["ZeusUpgrade"] == true, nil)

-- Picked: that one and only that one comes back.
G = boot(nil, { God = "SelectFirstBoon-ArtemisUpgrade", EnableArtemis = true,
                EnableAthena = true })
G.CurrentRun = G.newRun()
G.ELIGIBLE_EXTRA = { "SelectFirstBoon-ArtemisUpgrade", "SelectFirstBoon-AthenaUpgrade" }
check("the picked god is eligible", eligible()["SelectFirstBoon-ArtemisUpgrade"] == true, nil)
check("but the one beside her is not", eligible()["SelectFirstBoon-AthenaUpgrade"] == nil, nil)

-- The four cases a narrower fix would have missed. Each is a case where the
-- plugin deliberately stands aside and vanilla's roll runs free.
for _, case in ipairs({
  { label = "a Hermes pick, which is not a boon and leaves the first boon ahead",
    cfg = { God = "@Hermes" } },
  { label = "an unmet-god skip", cfg = { God = "ZeusUpgrade", RespectEligibility = true } },
  { label = "a hammer pick", cfg = { God = "@Hammer" } },
}) do
  case.cfg.EnableArtemis = true
  G = boot(nil, case.cfg)
  G.CurrentRun = G.newRun()
  G.ELIGIBLE_EXTRA = { "SelectFirstBoon-ArtemisUpgrade" }
  check("closed for " .. case.label,
    eligible()["SelectFirstBoon-ArtemisUpgrade"] == nil, nil)
end

-- Off, the old behaviour is intact: this is a choice, not a silent correction.
G = boot(nil, { God = "", EnableArtemis = true, AddedGodsOnlyWhenPicked = false })
G.CurrentRun = G.newRun()
G.ELIGIBLE_EXTRA = { "SelectFirstBoon-ArtemisUpgrade" }
check("switched off, they join the pool again",
  eligible()["SelectFirstBoon-ArtemisUpgrade"] == true, nil)

-- Emptying the god pool would be a far worse failure than one unasked god, so
-- the filter refuses to hand back nothing where the game had something.
G = boot(nil, { God = "", EnableArtemis = true, LogDecisions = true })
G.CurrentRun = G.newRun()
G.ELIGIBLE = {}
G.ELIGIBLE_EXTRA = { "SelectFirstBoon-ArtemisUpgrade" }
check("it never empties a pool that had entries",
  eligible()["SelectFirstBoon-ArtemisUpgrade"] == true, nil)
check("and says so", logsMatch("would have emptied the pool") ~= nil, nil)

-- A raising base call must not take the reward roll down with it.
G = boot(nil, { God = "", EnableArtemis = true })
G.CurrentRun = G.newRun()
G.ELIGIBLE_THROWS = true
check("a failure inside the game's own call is not swallowed into a wrong answer",
  not pcall(G.GetEligibleLootNames), nil)
G.ELIGIBLE_THROWS = false
end

-- 96 -------------------------------------------------------------------------
do
section("96. Every added god has a switch in the settings window")
-- These were config-file-only from the day the first one was added. Nobody
-- noticed while all four shipped ON -- there was no reason to go looking for the
-- switch. Two shipping OFF made it visible at once: the only way to turn them on
-- was to hand-edit the cfg.
G = boot(nil, { God = "" })
openWindow()
draw({})

function checkboxDrawn(label)
  for _, call in ipairs(M.imguiCalls) do
    if call == "Checkbox:" .. label then return true end
  end
  return false
end

for _, name in ipairs({ "Artemis", "Athena", "Dionysus", "Hades", "Narcissus",
                        "Arachne", "Circe", "Echo", "Icarus", "Medea" }) do
  check(name .. " has a switch", checkboxDrawn("Offer " .. name), nil)
end

-- Driven from EXTRA_GODS, so the next god added gets one without anyone
-- remembering this list exists.
check("one switch per god, no more and no fewer",
  (function()
    local seen = 0
    for _, call in ipairs(M.imguiCalls) do
      if call:find("Checkbox:Offer ", 1, true) == 1 then seen = seen + 1 end
    end
    return seen == 10
  end)(), nil)

-- And it writes, rather than only displaying.
G = boot(nil, { God = "", EnableNarcissus = false })
openWindow()
draw({ toggle = "Offer Narcissus" })
check("toggling one writes the setting", M.store.EnableNarcissus == true,
  M.store.EnableNarcissus)
check("and says it needs a restart",
  logsMatch("Narcissus enabled (restart to take effect)") ~= nil, nil)
end

-- 97 -------------------------------------------------------------------------
do
section("97. A god drawn from a portrait gets the same halo Selene does")
-- Reported: the portrait icons stand out beside the god symbols -- too small,
-- hard-edged, no glow. That is Selene's problem exactly, and for the same
-- reason: the god symbols carry a glow painted into the texture, and art from
-- any other set does not. So the halo built for her is not hers alone.
G = boot(nil, { God = "", EnableNarcissus = true, EnableArachne = true,
                ShowInventoryTab = true, SeleneGlowStrength = 0.8,
                SeleneHaloSpread = 0.2, SeleneHaloLayers = 1,
                VerboseTabLog = true })
scrH = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrH)

function buttonFor(scr, loot)
  for _, b in ipairs(scr.SelectFirstBoonButtons) do
    if b.SelectFirstBoonGod == loot then return b end
  end
end

check("a portrait-only god's icon carries a halo",
  buttonFor(scrH, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonGlow ~= nil, nil)
check("and so does the other one",
  buttonFor(scrH, "SelectFirstBoon-ArachneUpgrade").SelectFirstBoonGlow ~= nil, nil)
-- A god WITH an emblem already glows: painting a second halo under it would be
-- doubling something the texture already has.
check("but a god with a real emblem does not",
  buttonFor(scrH, "ZeusUpgrade").SelectFirstBoonGlow == nil, nil)

-- Tinted from the game's own colour for that character, not from Selene's.
check("tinted with his own colour, not borrowed from Selene",
  G.rgb[buttonFor(scrH, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonGlow.Id][1] == 240,
  G.rgb[buttonFor(scrH, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonGlow.Id][1])
check("and Arachne gets hers, which is a different colour again",
  G.rgb[buttonFor(scrH, "SelectFirstBoon-ArachneUpgrade").SelectFirstBoonGlow.Id][1] == 150,
  G.rgb[buttonFor(scrH, "SelectFirstBoon-ArachneUpgrade").SelectFirstBoonGlow.Id][1])

-- Size: their art is a different family from the god symbols beside them, so the
-- same scale is not the same size on screen.
-- The correction runs DOWNWARD here, unlike Selene's. Her art draws too small;
-- the keepsake portrait is the big picture and comes out too large. Reusing her
-- preset list meant the only offered values were 1.0 and up -- the wrong half of
-- the range entirely.
check("their icons take the portrait size boost, which shrinks rather than grows",
  buttonFor(scrH, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonIconScale
    < buttonFor(scrH, "ZeusUpgrade").SelectFirstBoonIconScale,
  string.format("%s vs %s",
    buttonFor(scrH, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonIconScale,
    buttonFor(scrH, "ZeusUpgrade").SelectFirstBoonIconScale))
check("and the list it is picked from reaches well below 1.0",
  (function()
    openWindow()
    draw({ openCombo = true })
    for _, call in ipairs(M.imguiCalls) do
      if call:find("0.3x##PortraitIconBoost", 1, true) then return true end
    end
    return false
  end)(), nil)

-- Jagged came from drawing small art large. Both the menu icon and the drop
-- emblem now read the _big source.
check("and the menu art is the big portrait, not the small one",
  (function()
    for _, e in ipairs(M.animations.Animations) do
      if e.Name == "SelectFirstBoon_Portrait_Narcissus" then
        return e.FilePath
          == "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_big\\Narcissus"
      end
    end
    return false
  end)(), nil)
end

-- 98 -------------------------------------------------------------------------
do
section("98. The four the candidate log found")
-- Not guessed at. The log ran against the live EnemyData and named them with
-- their NPC keys and trait pools, which is how each one's entry requirement was
-- checked rather than assumed: a keepsake portrait, no emblem, and a
-- rarity-scaled pool offered one-of-three.
--
-- All four shipped. Medea was pulled in v4.25.0 after a crash and restored in
-- v4.27.0 once the stack dump showed the fault was a Lua-side table access in a
-- resumed coroutine rather than anything to do with her -- section 104 carries
-- that story.
G = boot(nil, { God = "", EnableCirce = true, EnableEcho = true,
                EnableIcarus = true, EnableMedea = true,
                ShowInventoryTab = true, SeleneGlowStrength = 0.8 })

for _, name in ipairs({ "Circe", "Echo", "Icarus", "Medea" }) do
  check(name .. " registers", G.LootData["SelectFirstBoon-" .. name .. "Upgrade"] ~= nil, nil)
  check("  with the pool the log reported",
    G.LootData["SelectFirstBoon-" .. name .. "Upgrade"].Traits ~= nil
      and #G.LootData["SelectFirstBoon-" .. name .. "Upgrade"].Traits == 3, nil)
  check("  drawing the big keepsake portrait",
    emblemOf("SelectFirstBoon-" .. name .. "Upgrade").FilePath
      == "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_big\\" .. name,
    emblemOf("SelectFirstBoon-" .. name .. "Upgrade").FilePath)
  check("  and rarity-only, like every added god",
    G.LootData["SelectFirstBoon-" .. name .. "Upgrade"].IgnoreStackBoost == true, nil)
end

-- None of them has a LootColor, never having had a drop. Each palette comes from
-- their own voice colour, so no two arrive grey or identical.
check("their palettes differ, being derived from their own colours",
  layer("Circe", "C").Color.Green ~= layer("Icarus", "C").Color.Green, nil)

-- All ten ship ON, and each still has its own switch that takes it back out.
G = boot(nil, { God = "", ShowInventoryTab = true })
for _, name in ipairs({ "Circe", "Echo", "Icarus", "Medea" }) do
  check(name .. " is on by default",
    G.LootData["SelectFirstBoon-" .. name .. "Upgrade"] ~= nil, nil)
end
for _, name in ipairs({ "Circe", "Echo", "Icarus", "Medea" }) do
  G = boot(nil, { God = "", ShowInventoryTab = true, ["Enable" .. name] = false })
  check(name .. " goes away when his own switch is off",
    G.LootData["SelectFirstBoon-" .. name .. "Upgrade"] == nil, nil)
end
end

-- 99 -------------------------------------------------------------------------
do
section("99. Chaos as a first reward, and what Standard becomes")
-- Chaos is a SPECIAL, not an added god, and the difference is that nothing had
-- to be invented for him. TrialUpgrade is a complete LootData entry already --
-- emblem, door icon, drop animations, sounds -- and "TrialUpgrade" is a reward
-- type the game knows how to spawn (RewardLogic.lua:392-394). So this queues a
-- reward priority and the game builds the rest.
G = boot(nil, { God = "@Chaos", ShowInventoryTab = true })
G.CurrentRun = G.newRun()
G.priorityCalls = {}
G.ChooseRoomReward(G.CurrentRun, G.newRoom("Boon"), "RunProgress", {})
check("picking Chaos queues TrialUpgrade as the run's first reward",
  #G.priorityCalls == 1 and G.priorityCalls[1].Name == "TrialUpgrade",
  #G.priorityCalls > 0 and G.priorityCalls[1].Name)
check("and says so in the log",
  logsMatch("queued TrialUpgrade (Chaos) as this run's first reward") ~= nil, nil)
-- Nothing of ours is registered for him: he is not in LootData as an added god.
check("no shadow LootData entry was created for him",
  G.LootData["SelectFirstBoon-ChaosUpgrade"] == nil, nil)
-- And he draws the emblem the base game already ships.
G.SelectFirstBoon_InventoryTabOpen(G.newInventoryScreen())
check("he draws the base game's own Chaos symbol",
  tabIcon(G) == "SelectFirstBoon_Symbol_Chaos", tabIcon(G))

-- Standard borrowed the Chaos symbol, which stops working the moment Chaos is
-- something you can pick: one picture, two meanings.
G = boot(nil, { God = "", ShowInventoryTab = true })
check("Standard no longer borrows it",
  tabIcon(G) == "SelectFirstBoon_Symbol_Pom", tabIcon(G))
for _, case in ipairs({
  { value = "chaos", expect = "SelectFirstBoon_Symbol_Chaos" },
  { value = "backing-a", expect = "SelectFirstBoon_Symbol_BoonBackingA" },
  { value = "nonsense", expect = "SelectFirstBoon_Symbol_Pom" },
}) do
  G = boot(nil, { God = "", ShowInventoryTab = true, StandardIcon = case.value })
  check("StandardIcon " .. case.value .. " resolves", tabIcon(G) == case.expect, tabIcon(G))
end

-- Chaos and Standard must never be the same picture, whatever the setting says.
G = boot(nil, { God = "", ShowInventoryTab = true, StandardIcon = "chaos" })
standardIcon = tabIcon(G)
G = boot(nil, { God = "@Chaos", ShowInventoryTab = true, StandardIcon = "chaos" })
check("choosing the old Chaos icon for Standard is allowed, and is the one case "
  .. "where they collide -- the default avoids it",
  standardIcon == tabIcon(G), nil)
end

-- 100 ------------------------------------------------------------------------
do
section("100. Two runs of icons, split by a row break")
-- One run of icons was fine at thirteen options and stopped being fine at
-- twenty-two. The Olympians, the odd rewards and the added gods are three
-- different KINDS of thing.
--
-- 4.23.0 gave each its own ROW, which cost three rows for twelve icons and
-- pushed the grid down far enough that the override squares fell off the bottom
-- of it. A single blank slot reads as a break just as clearly for one cell.
G = boot(nil, { God = "", ShowInventoryTab = true, EnableArtemis = true,
                EnableAthena = true, EnableDionysus = true, EnableHades = true,
                EnableNarcissus = true, VerboseTabLog = true })
scrB = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrB)

function rowOf(button) return math.floor((button.Args.Y - 252 - 10) / 143 + 0.5) end
function rowFor(value) return rowOf(btnFor(scrB, value)) end

-- Standard leads, the Olympians follow it, and nothing else joins their rows.
check("Standard and the Olympians share the opening rows",
  rowFor("") == 0 and rowFor("ZeusUpgrade") <= 1, rowFor("ZeusUpgrade"))
-- A blank cell before each block, not after the last icon of the previous one.
function colOf(button)
  return math.floor((button.Args.X - 149) / 133.6 + 0.5)
end
function slotOf(button) return rowOf(button) * 8 + colOf(button) end

-- 4.28.0 removed the blank slot that used to sit here. One empty cell in the
-- middle of a row read as a missing icon rather than as a boundary -- exactly
-- backwards from its purpose -- so the Olympians and the odd rewards now run
-- together as one block of "things vanilla can already give you".
check("the specials follow the Olympians with no gap",
  slotOf(btnFor(scrB, "@Hammer")) == slotOf(btnFor(scrB, "ZeusUpgrade")) + 1,
  string.format("%d after %d", slotOf(btnFor(scrB, "@Hammer")),
                slotOf(btnFor(scrB, "ZeusUpgrade"))))
check("the specials then run without gaps between them",
  slotOf(btnFor(scrB, "@Hermes")) == slotOf(btnFor(scrB, "@Hammer")) + 1
    and slotOf(btnFor(scrB, "@Selene")) == slotOf(btnFor(scrB, "@Hermes")) + 1
    and slotOf(btnFor(scrB, "@Chaos")) == slotOf(btnFor(scrB, "@Selene")) + 1, nil)
-- The one break that survives, and it is a ROW break: everything this plugin
-- adds starts below everything vanilla can already give you.
check("the added gods start a row of their own",
  rowFor("SelectFirstBoon-ArtemisUpgrade") == rowFor("@Chaos") + 1
    and colOf(btnFor(scrB, "SelectFirstBoon-ArtemisUpgrade")) == 0,
  string.format("added row %d col %d, specials end row %d",
                rowFor("SelectFirstBoon-ArtemisUpgrade"),
                colOf(btnFor(scrB, "SelectFirstBoon-ArtemisUpgrade")),
                rowFor("@Chaos")))

-- Emblem gods first, then portrait gods. The two halves look different -- an
-- emblem beside a face -- so interleaving them by name reads as a mistake.
check("emblem gods come before portrait gods",
  slotOf(btnFor(scrB, "SelectFirstBoon-HadesUpgrade"))
    < slotOf(btnFor(scrB, "SelectFirstBoon-NarcissusUpgrade")), nil)
check("and each half is alphabetical",
  slotOf(btnFor(scrB, "SelectFirstBoon-ArtemisUpgrade"))
    < slotOf(btnFor(scrB, "SelectFirstBoon-AthenaUpgrade"))
    and slotOf(btnFor(scrB, "SelectFirstBoon-AthenaUpgrade"))
    < slotOf(btnFor(scrB, "SelectFirstBoon-DionysusUpgrade")), nil)

-- The portrait half opens a row of its own rather than flowing on from the
-- emblem half, so a row is never part emblems and part faces.
--
-- The god to test is whichever portrait god comes FIRST, and that is Arachne,
-- alphabetically. This used to name Narcissus, which was the same god back when
-- he and Arachne were the only two portrait gods anyone had enabled by default.
-- With all six on he is sixth, so asserting col 0 of him asserted the wrong
-- thing and failed for the right reason.
check("portrait gods start a new row",
  rowFor("SelectFirstBoon-ArachneUpgrade") == rowFor("SelectFirstBoon-HadesUpgrade") + 1
    and colOf(btnFor(scrB, "SelectFirstBoon-ArachneUpgrade")) == 0,
  string.format("portraits row %d col %d, emblems end row %d",
                rowFor("SelectFirstBoon-ArachneUpgrade"),
                colOf(btnFor(scrB, "SelectFirstBoon-ArachneUpgrade")),
                rowFor("SelectFirstBoon-HadesUpgrade")))
-- And the half stays alphabetical from there, so Narcissus is last, not first.
check("and the portrait half runs alphabetically after it",
  slotOf(btnFor(scrB, "SelectFirstBoon-ArachneUpgrade"))
    < slotOf(btnFor(scrB, "SelectFirstBoon-MedeaUpgrade"))
    and slotOf(btnFor(scrB, "SelectFirstBoon-MedeaUpgrade"))
    < slotOf(btnFor(scrB, "SelectFirstBoon-NarcissusUpgrade")), nil)

-- And the gates keep clear of whatever the icons grew into.
-- By ROW, not by pixels: a portrait god carries its own few-pixel nudge, and
-- comparing raw Y would call a clear row a near miss.
--
-- The bar is "below every icon", not "with a blank row between". A blank row was
-- never a guarantee the code makes -- GATE_ROW is fixed at 4 and the icons take
-- whatever they take -- and with every god switched on the live layout already
-- reached row 3 before the portrait row break existed. What IS guaranteed is
-- that the gates are below the last icon, and that reaching their row warns
-- rather than silently overlapping, which section 102 covers.
gate = gateBtn(scrB, "Hermes")
lastIconRow = 0
for _, b in ipairs(scrB.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGate == nil and rowOf(b) > lastIconRow then lastIconRow = rowOf(b) end
end
check("the gates sit below every icon",
  rowOf(gate) > lastIconRow,
  string.format("gate row %d vs last icon row %d", rowOf(gate), lastIconRow))
check("still in the bottom-right corner",
  near(gateBtn(scrB, "Selene").Args.X, 149 + 7 * 133.6), nil)
check("and the row it landed on is logged",
  logsMatch("row ") ~= nil, nil)

-- With every portrait god switched on, all five belong to the same row and it
-- holds no emblems. Five fits inside the eight-wide grid with room to spare, so
-- the row break costs nothing here -- before it, these five ran on from the
-- emblem half and spilled one lonely icon onto a row of its own anyway.
G = boot(nil, { God = "", ShowInventoryTab = true, EnableArtemis = true,
                EnableAthena = true, EnableDionysus = true, EnableHades = true,
                EnableNarcissus = true, EnableArachne = true, EnableCirce = true,
                EnableEcho = true, EnableIcarus = true })
scrP = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrP)
function rowIn(scr, value) return rowOf(btnFor(scr, value)) end
portraitRow = rowIn(scrP, "SelectFirstBoon-ArachneUpgrade")
check("every portrait god shares one row",
  rowIn(scrP, "SelectFirstBoon-CirceUpgrade") == portraitRow
    and rowIn(scrP, "SelectFirstBoon-EchoUpgrade") == portraitRow
    and rowIn(scrP, "SelectFirstBoon-IcarusUpgrade") == portraitRow
    and rowIn(scrP, "SelectFirstBoon-NarcissusUpgrade") == portraitRow, portraitRow)
check("and no emblem god is on it",
  rowIn(scrP, "SelectFirstBoon-HadesUpgrade") == portraitRow - 1
    and rowIn(scrP, "SelectFirstBoon-ArtemisUpgrade") == portraitRow - 1, nil)
check("the row starts at the left edge",
  colOf(btnFor(scrP, "SelectFirstBoon-ArachneUpgrade")) == 0,
  colOf(btnFor(scrP, "SelectFirstBoon-ArachneUpgrade")))
check("and the gates are still below all of it",
  rowOf(gateBtn(scrP, "Hermes")) > portraitRow,
  rowOf(gateBtn(scrP, "Hermes")))
end

-- 101 ------------------------------------------------------------------------
do
section("101. Per-god halo strength, and a nudge for portrait art")
-- One strength does not suit every picture: a pale portrait needs less glow than
-- a dark one to read the same. Narcissus's is the palest of the six.
G = boot(nil, { God = "", ShowInventoryTab = true, EnableNarcissus = true,
                EnableArachne = true, SeleneGlowStrength = 0.8,
                HaloStrengthNarcissus = 0.5, HaloStrengthArachne = 1.0 })
scrN = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrN)
check("his halo is dimmer than the shared strength alone",
  near(btnFor(scrN, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonGlow.Args.AlphaTarget,
       0.8 * 0.5),
  btnFor(scrN, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonGlow.Args.AlphaTarget)
check("while hers is the shared strength unchanged",
  near(btnFor(scrN, "SelectFirstBoon-ArachneUpgrade").SelectFirstBoonGlow.Args.AlphaTarget, 0.8),
  btnFor(scrN, "SelectFirstBoon-ArachneUpgrade").SelectFirstBoonGlow.Args.AlphaTarget)
-- A multiplier, not an absolute: the shared dial still governs.
G = boot(nil, { God = "", ShowInventoryTab = true, EnableNarcissus = true,
                SeleneGlowStrength = 0.4, HaloStrengthNarcissus = 0.5 })
scrN2 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrN2)
check("lowering the shared dial lowers his too",
  near(btnFor(scrN2, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonGlow.Args.AlphaTarget,
       0.4 * 0.5),
  btnFor(scrN2, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonGlow.Args.AlphaTarget)

-- Portrait art is a different shape from a god symbol and sits differently in
-- the slot, so it gets its own nudge on top of the one every icon gets.
G = boot(nil, { God = "", ShowInventoryTab = true, EnableNarcissus = true,
                IconOffsetY = 10, PortraitIconOffsetY = 8 })
scrO = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrO)
check("a portrait god sits lower than a god symbol on the same row line",
  btnFor(scrO, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonY
    - btnFor(scrO, "SelectFirstBoon-NarcissusUpgrade").Args.Y == 0, nil)
check("by exactly the extra nudge",
  (function()
    local n = btnFor(scrO, "SelectFirstBoon-NarcissusUpgrade")
    local row = math.floor((n.Args.Y - 252 - 10 - 8) / 143 + 0.5)
    return near(n.Args.Y, 252 + row * 143 + 10 + 8)
  end)(), btnFor(scrO, "SelectFirstBoon-NarcissusUpgrade").Args.Y)
-- The halo has to follow the icon, or it would sit above it.
check("and his halo follows the icon down",
  near(btnFor(scrO, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonGlow.Args.Y,
       btnFor(scrO, "SelectFirstBoon-NarcissusUpgrade").Args.Y),
  btnFor(scrO, "SelectFirstBoon-NarcissusUpgrade").SelectFirstBoonGlow.Args.Y)
end

-- 102 ------------------------------------------------------------------------
do
section("102. The override squares are always on the grid")
-- 4.23.0 computed the gate row as "one clear row below the last icon", which is
-- right in spirit and wrong in practice: with enough gods enabled it resolved
-- past the bottom of the grid and the squares were simply not on screen. There
-- is no row below the last one to move to.
G = boot(nil, { God = "", ShowInventoryTab = true, VerboseTabLog = true,
                EnableArtemis = true, EnableAthena = true, EnableDionysus = true,
                EnableHades = true, EnableNarcissus = true, EnableArachne = true,
                EnableCirce = true, EnableEcho = true, EnableIcarus = true })
scrFull = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrFull)
function rowOfBtn(b) return math.floor((b.Args.Y - 252 - 10) / 143 + 0.5) end

check("with every god enabled the squares are still on the bottom row",
  rowOfBtn(gateBtn(scrFull, "Hermes")) == 4, rowOfBtn(gateBtn(scrFull, "Hermes")))
check("and still in the last two columns",
  near(gateBtn(scrFull, "Selene").Args.X, 149 + 7 * 133.6)
    and near(gateBtn(scrFull, "Hermes").Args.X, 149 + 6 * 133.6),
  string.format("%.1f / %.1f", gateBtn(scrFull, "Hermes").Args.X,
                gateBtn(scrFull, "Selene").Args.X))

-- Twenty-two options and two gaps still fit above them, which is the whole
-- reason the blank slot replaced the blank row.
lastIconRow = 0
for _, b in ipairs(scrFull.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGate == nil and rowOfBtn(b) > lastIconRow then
    lastIconRow = rowOfBtn(b)
  end
end
check("with the icons finishing above them", lastIconRow < 4, lastIconRow)

-- If they ever did collide, that is worth saying rather than silently
-- overlapping: the fix would be fewer gods or a wider grid, not a row that does
-- not exist.
G = boot(nil, { God = "", ShowInventoryTab = true, VerboseTabLog = true })
narrow = G.newInventoryScreen()
narrow.GridWidth = 2
G.SelectFirstBoon_InventoryTabOpen(narrow)
check("a grid too narrow to hold them warns rather than overlapping in silence",
  logsMatch("may overlap") ~= nil, nil)
end

-- 103 ------------------------------------------------------------------------
do
section("103. The tab strip needs the portrait correction too")
-- Same defect as the grid, same cause: a portrait is bigger art than a god
-- symbol, so at one shared scale the portraits came out too large while the
-- symbols were right -- and there was no way to move one without the other.
G = boot(nil, { God = "ZeusUpgrade", ShowInventoryTab = true, TabIconBoost = 1.15,
                PortraitIconBoost = 0.7, VerboseTabLog = true })
scrZ = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrZ)
zeusScale = G.scales[scrZ.Components["CategoryIconFirst Boon"].Id].Fraction
check("a god symbol takes the tab scale and nothing else",
  near(zeusScale, 0.45 * 1.15), zeusScale)

G = boot(nil, { God = "SelectFirstBoon-NarcissusUpgrade", ShowInventoryTab = true,
                EnableNarcissus = true, TabIconBoost = 1.15,
                PortraitIconBoost = 0.7 })
scrP = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrP)
portraitScale = G.scales[scrP.Components["CategoryIconFirst Boon"].Id].Fraction
check("a portrait god takes the portrait correction on top",
  near(portraitScale, 0.45 * 1.15 * 0.7), portraitScale)
check("so the two are no longer locked together",
  portraitScale < zeusScale, string.format("%.3f vs %.3f", portraitScale, zeusScale))

-- The SAME multiplier as the grid, deliberately: the ratio between the two art
-- families belongs to the textures, not to the place they are drawn.
G = boot(nil, { God = "SelectFirstBoon-NarcissusUpgrade", ShowInventoryTab = true,
                EnableNarcissus = true, TabIconBoost = 1.0,
                PortraitIconBoost = 0.4 })
scrP2 = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrP2)
check("moving the grid dial moves the strip with it",
  near(G.scales[scrP2.Components["CategoryIconFirst Boon"].Id].Fraction, 0.45 * 0.4),
  G.scales[scrP2.Components["CategoryIconFirst Boon"].Id].Fraction)
end

-- 104 ------------------------------------------------------------------------
do
section("104. Medea ships, and a pick naming a god that is gone still resets")
-- Medea was removed in v4.25.0 after her boon was followed 22 seconds later by
-- EXCEPTION_ACCESS_VIOLATION and a truncated Profile1_Temp.sav. She is back in
-- v4.27.0, because the stack dump says the crash was never about her:
--   [0] ltable.cpp:483   luaH_get        <- table lookup inside the Lua VM
--   [3] ldo.cpp:429      unroll          <- ...in a coroutine resumed after a yield
--   [7] lcorolib.cpp:53  luaB_coresume
-- Reading a table through memory that is no longer valid. An absent asset
-- crashes in the asset manager, not in ltable.cpp -- and the same log records
-- "Package Loaded: Medea 35Mb" in the crashing run anyway. Four deliberate Medea
-- boons since, including NewStatusDamage with a live vulnerability effect, all
-- clean. See SAVE_RECOVERY.md.
G = boot(nil, { God = "", ShowInventoryTab = true, EnableMedea = true })
check("she registers when switched on",
  G.LootData["SelectFirstBoon-MedeaUpgrade"] ~= nil, nil)
check("with her portrait, like every other emblem-less god",
  (function()
    for _, e in ipairs(M.animations.Animations) do
      if e.Name == "SelectFirstBoon_Portrait_Medea" then return true end
    end
    return false
  end)(), nil)
check("and rarity-only, so a pom cannot level her boons",
  G.LootData["SelectFirstBoon-MedeaUpgrade"].IgnoreStackBoost == true, nil)

-- On by default, like every other added god, and still removable on her own.
G = boot(nil, { God = "", ShowInventoryTab = true })
check("and on by default", G.LootData["SelectFirstBoon-MedeaUpgrade"] ~= nil, nil)
G = boot(nil, { God = "", ShowInventoryTab = true, EnableMedea = false })
check("but her own switch still takes her out",
  G.LootData["SelectFirstBoon-MedeaUpgrade"] == nil, nil)

-- The reset that v4.25.0 added is not tied to Medea and outlives her return: any
-- pick naming a god this build does not have is cleared rather than left sitting
-- in the config forever, where the menu would show a choice that can never fire.
G = boot(nil, { God = "SelectFirstBoon-PanUpgrade", KeepPickAfterRestart = true,
                RespectEligibility = false, LogDecisions = true })
check("a pick for a god that does not exist is cleared at boot",
  M.store.God == "", M.store.God)
check("and says why", logsMatch("no longer exists; reset to Standard") ~= nil, nil)
G.CurrentRun = G.newRun()
afterGone = G.newRoom("Boon")
G.SetupRoomReward(G.CurrentRun, afterGone, {}, {})
check("so the run is vanilla's own roll",
  afterGone.ForceLootName == "ApolloUpgrade", afterGone.ForceLootName)
check("nothing was forced", logsMatch("forced first boon to") == nil, nil)

end

-- 105 ------------------------------------------------------------------------
do
section("105. The shipped cosmetic defaults are the dialled-in ones")
-- These four were tuned in game over several sessions and then baked in, so a
-- fresh install looks like the tuned build rather than the first guess. Every
-- other test now pins whichever of these it depends on, which leaves exactly one
-- place that fails when a default moves -- here, on purpose.
G = boot(nil, { God = "", ShowInventoryTab = true })
function bound(key) return M.bound and M.bound[key] and M.bound[key].default end
check("portrait icons ship at 0.4, not the original 0.7",
  near(bound("PortraitIconBoost"), 0.4), bound("PortraitIconBoost"))
check("the halo ships dim: 0.25, not 0.8",
  near(bound("SeleneGlowStrength"), 0.25), bound("SeleneGlowStrength"))
check("and wide: spread 0.75, not 0.2",
  near(bound("SeleneHaloSpread"), 0.75), bound("SeleneHaloSpread"))
check("in three layers, not two",
  bound("SeleneHaloLayers") == 3, bound("SeleneHaloLayers"))
-- Narcissus keeps his own multiplier on top: his portrait is the palest of the
-- set and came back brighter than the rest even at the shared strength.
check("Narcissus still reads less than the others",
  near(bound("HaloStrengthNarcissus"), 0.7), bound("HaloStrengthNarcissus"))
end

-- 106 ------------------------------------------------------------------------
do
section("106. The config file is grouped, not one flat wall")
-- Seventy-five keys in a single [config] section put "God" between
-- "GateStateStyle" and "GlowBrightnessArachne". The handful that decide what the
-- mod DOES were buried among sixty cosmetic dials. Chalk writes the bound
-- section name into the .cfg as a header, so grouping is free.
G = boot(nil, { God = "", ShowInventoryTab = true })
function sec(key) return M.bound and M.bound[key] and M.bound[key].section end

check("the pick itself is in Main", sec("God"):find("Main") ~= nil, sec("God"))
check("so are the two gates",
  sec("BlockHermesBeforeBoon"):find("Main") and sec("BlockSeleneBeforeBoon"):find("Main"),
  sec("BlockHermesBeforeBoon"))
check("and the run-shaping switches",
  sec("KeepsakeWins"):find("Main") and sec("KeepPickAfterRestart"):find("Main")
    and sec("AddedGodsOnlyWhenPicked"):find("Main"), sec("KeepsakeWins"))
check("every Enable<God> switch is in its own section",
  sec("EnableArtemis"):find("Extra gods") and sec("EnableMedea"):find("Extra gods")
    and sec("EnableNarcissus"):find("Extra gods"), sec("EnableArtemis"))
check("cosmetic dials land in Appearance",
  sec("SeleneGlowStrength"):find("Appearance")
    and sec("DropPortraitScale"):find("Appearance")
    and sec("HaloStrengthNarcissus"):find("Appearance"), sec("SeleneGlowStrength"))

-- The point of the exercise: Main stays small. If this count creeps up, something
-- cosmetic has been promoted and should be argued for.
check("Main holds a dozen keys, not seventy-five",
  (function()
    local n = 0
    for _, info in pairs(M.bound) do
      if info.section:find("Main") then n = n + 1 end
    end
    return n <= 12 and n >= 8
  end)(), (function()
    local n = 0
    for _, info in pairs(M.bound) do
      if info.section:find("Main") then n = n + 1 end
    end
    return n
  end)())

-- Sections are numbered because the file is written in first-seen order, and an
-- alphabetical "Appearance" ahead of "Main" would undo the whole thing.
check("the numbering keeps Main first",
  sec("God") < sec("EnableArtemis") and sec("EnableArtemis") < sec("SeleneGlowStrength"),
  sec("God") .. " / " .. sec("EnableArtemis") .. " / " .. sec("SeleneGlowStrength"))
end

-- 107 ------------------------------------------------------------------------
do
section("107. Standing down for a plugin that already offers the same god")
-- Droppable Gods and anything else on GodsAPI registers these gods as full
-- members of the pool. Ours are first-reward-only. The loot KEYS never collide,
-- since both are namespaced, but the display names do -- so with both installed
-- the tab listed "Artemis" twice, same art, meaning two different things.
function withDroppableGods(extra)
  local g = dofile("./harness.lua")
  for _, name in ipairs({ "Artemis", "Athena" }) do
    local key = "zannc-Droppable_Gods-" .. name .. "Upgrade"
    g.LootData[key] = {
      Name = key, GodLoot = true, SpeakerName = name,
      Icon = "BoonSymbolzannc-Droppable_Gods-" .. name,
      Traits = { name .. "A", name .. "B", name .. "C" }, TraitIndex = {},
    }
  end
  local cfg = { God = "", ShowInventoryTab = true, KeepPickAfterRestart = true }
  for k, v in pairs(extra or {}) do cfg[k] = v end
  M.install(g, nil, cfg)
  dofile(PLUGIN)
  if M.pendingGameLoad then M.pendingGameLoad() end
  return g
end

G = withDroppableGods({ EnableArtemis = true, EnableAthena = true,
                        EnableDionysus = true, EnableHades = true })

check("we do not register a god another plugin already offers",
  G.LootData["SelectFirstBoon-ArtemisUpgrade"] == nil
    and G.LootData["SelectFirstBoon-AthenaUpgrade"] == nil, nil)
check("and say so, naming who claimed it",
  logsMatch("Artemis is already offered by zannc-Droppable_Gods-ArtemisUpgrade") ~= nil,
  nil)
check("gods they do not offer are registered as normal",
  G.LootData["SelectFirstBoon-DionysusUpgrade"] ~= nil
    and G.LootData["SelectFirstBoon-HadesUpgrade"] ~= nil, nil)

-- The player has lost nothing they wanted: their Artemis is still in the catalog,
-- so Artemis is still pickable as the first boon. Only the duplicate is gone.
scrD = G.newInventoryScreen()
G.SelectFirstBoon_InventoryTabOpen(scrD)
artemis = {}
for _, b in ipairs(scrD.SelectFirstBoonButtons) do
  if b.SelectFirstBoonGate == nil and tostring(b.SelectFirstBoonGod):find("Artemis") then
    artemis[#artemis + 1] = b.SelectFirstBoonGod
  end
end
check("Artemis appears exactly once in the tab", #artemis == 1, #artemis)
check("and it is their entry, the fuller one",
  artemis[1] == "zannc-Droppable_Gods-ArtemisUpgrade", artemis[1])

-- And with the other plugin absent, nothing changes.
G = boot(nil, { God = "", ShowInventoryTab = true, EnableArtemis = true })
check("without them we register Artemis ourselves as before",
  G.LootData["SelectFirstBoon-ArtemisUpgrade"] ~= nil, nil)
check("and nothing claims to have stood down",
  logsMatch("is already offered by") == nil, logsMatch("is already offered by"))
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
