-- Mock of the Hades II globals the plugin touches, faithful to the real source.
local G = {}

-- UtilityLogic-style helper
function G.Contains(t, v)
  if t == nil then return false end
  for _, x in ipairs(t) do if x == v then return true end end
  return false
end

G.ELIGIBLE = { "ApolloUpgrade","DemeterUpgrade","PoseidonUpgrade","ZeusUpgrade","HeraUpgrade","AresUpgrade","HestiaUpgrade","AphroditeUpgrade","HephaestusUpgrade" }
G.ELIGIBLE_THROWS = false

-- RunLogic.lua:1835. Once true, GetEligibleLootNames narrows to gods already
-- met this run, which is what made v2.1.0 mislabel unlocked gods as locked.
G.MAXED = false
function G.ReachedMaxGods(excludedGods)
  if G.CurrentRun == nil then error("ReachedMaxGods: CurrentRun is nil") end
  return G.MAXED
end

-- RewardLogic.lua:187-208
function G.GetEligibleLootNames(excludeLootNames)
  if G.ELIGIBLE_THROWS then error("simulated failure inside GetEligibleLootNames") end
  if G.MAXED then
    local met = {}
    for name in pairs(G.CurrentRun.LootTypeHistory or {}) do met[#met+1] = name end
    return met
  end
  local out = {}
  for _, n in ipairs(G.ELIGIBLE) do
    if not G.Contains(excludeLootNames or {}, n) then out[#out+1] = n end
  end
  -- The added gods sit in this list too in the real game: they are LootData
  -- entries with GodLoot set, and that is all GetEligibleLootNames asks for.
  for _, n in ipairs(G.ELIGIBLE_EXTRA or {}) do
    if not G.Contains(excludeLootNames or {}, n) then out[#out+1] = n end
  end
  return out
end

-- deterministic stand-in for ChooseLoot's GetRandomValue
G.ROLL = "DemeterUpgrade"

-- RewardLogic.lua:210-275, boon branch only, verbatim in structure
function G.SetupRoomReward(currentRun, room, previouslyChosenRewards, args)
  args = args or {}
  local chosenRewardType = args.ChosenRewardType or room.ChosenRewardType
  if chosenRewardType == "Empty" then return end
  if chosenRewardType == "Boon" and (args.AlwaysSetupForceLootName or not room.ForceLootName) then
    local excludeLootNames = {}
    if previouslyChosenRewards ~= nil then
      for _, data in pairs(previouslyChosenRewards) do
        if data.RewardType == "Boon" and data.ForceLootName ~= nil then
          table.insert(excludeLootNames, data.ForceLootName)
        end
      end
    end
    local lootData = { Name = G.ROLL }
    for _, n in ipairs(G.ELIGIBLE) do
      if not G.Contains(excludeLootNames, n) then lootData = { Name = n } break end
    end
    if not args.IgnoreForceLootName then
      for _, trait in ipairs(currentRun.Hero.Traits) do
        if trait ~= nil and trait.ForceBoonName ~= nil and trait.Uses > 0
           and not G.Contains(excludeLootNames, trait.ForceBoonName) then
          lootData = { Name = trait.ForceBoonName }
          room.ForcedBoonNames[trait.ForceBoonName] = true
          room.ForceBoonChosenTrait = trait
          break
        end
      end
    end
    room.ForceLootName = lootData.Name
  end
end

-- RoomLogic.lua:2058-2070
function G.GiveLoot(args)
  args = args or {}
  local name = args.ForceLootName or G.ROLL
  return { Name = name, ObjectId = 1 }
end

-- LootData, as assembled from LootSetData.* in LootData_*.lua
G.LootData = {
  -- Icon -> BoonSymbol<God>, the matched BoonSelectSymbols set (Scale 1).
  -- BoonInfoIcon -> BoonInfoSymbol<God>Icon, per-god boon-drop spin frames.
  AphroditeUpgrade  = { GodLoot = true,  SpeakerName = "Aphrodite",  Icon = "BoonSymbolAphrodite",  BoonInfoIcon = "BoonInfoSymbolAphroditeIcon" },
  ApolloUpgrade     = { GodLoot = true,  SpeakerName = "Apollo",     Icon = "BoonSymbolApollo",     BoonInfoIcon = "BoonInfoSymbolApolloIcon" },
  AresUpgrade       = { GodLoot = true,  SpeakerName = "Ares",       Icon = "BoonSymbolAres",       BoonInfoIcon = "BoonInfoSymbolAresIcon" },
  DemeterUpgrade    = { GodLoot = true,  SpeakerName = "Demeter",    Icon = "BoonSymbolDemeter",    BoonInfoIcon = "BoonInfoSymbolDemeterIcon" },
  HephaestusUpgrade = { GodLoot = true,  SpeakerName = "Hephaestus", Icon = "BoonSymbolHephaestus", BoonInfoIcon = "BoonInfoSymbolHephaestusIcon" },
  HeraUpgrade       = { GodLoot = true,  SpeakerName = "Hera",       Icon = "BoonSymbolHera",       BoonInfoIcon = "BoonInfoSymbolHeraIcon" },
  HestiaUpgrade     = { GodLoot = true,  SpeakerName = "Hestia",     Icon = "BoonSymbolHestia",     BoonInfoIcon = "BoonInfoSymbolHestiaIcon" },
  PoseidonUpgrade   = { GodLoot = true,  SpeakerName = "Poseidon",   Icon = "BoonSymbolPoseidon",   BoonInfoIcon = "BoonInfoSymbolPoseidonIcon" },
  -- LootColor as vanilla boon gods carry it: the selection light can tint from
  -- it, and without one here that path would never be exercised.
  ZeusUpgrade       = { GodLoot = true,  SpeakerName = "Zeus",       Icon = "BoonSymbolZeus",       BoonInfoIcon = "BoonInfoSymbolZeusIcon", LootColor = { 250, 230, 90, 255 } },
  HermesUpgrade     = { GodLoot = false, SpeakerName = "Hermes",     Icon = "BoonSymbolHermes" },
  TrialUpgrade      = { GodLoot = false, Icon = "BoonSymbolChaos" },
  SpellDrop         = { },
  BaseLoot          = { GodLoot = true, DebugOnly = true },
}

-- RewardLogic.lua:34. The real one applies duplicate/EligibleRewards/
-- GameStateRequirements filtering; the plugin only ever narrows its result, so
-- the mock exposes the answer as a switch.
-- RewardLogic.lua:513-533 and :163-171, cut to what the plugin touches: a
-- priority is pushed onto CurrentRun.RewardPriorities, the store is topped up if
-- the name is not in the carousel, and ChooseRoomReward takes the first eligible
-- priority and REMOVES it, so a priority is one-shot.
G.priorityCalls = {}
function G.RewardStoreAddPriority(args)
  if G.PRIORITY_THROWS then error("simulated RewardStoreAddPriority failure") end
  G.priorityCalls[#G.priorityCalls + 1] = args
  local run = G.CurrentRun
  if run == nil then return end
  run.RewardPriorities = run.RewardPriorities or {}
  table.insert(run.RewardPriorities, args.Name)
  local storeName = args.RewardStoreName or "RunProgress"
  run.RewardStores = run.RewardStores or {}
  local store = run.RewardStores[storeName]
  if store == nil then return end
  local present = false
  for _, reward in ipairs(store) do
    if reward.Name == args.Name then present = true break end
  end
  if not present then
    store[#store + 1] = { Name = args.Name, AddedByRefill = true }
  end
end

G.chooseCalls = 0
function G.ChooseRoomReward(run, room, rewardStoreName, previouslyChosenRewards, args)
  G.chooseCalls = G.chooseCalls + 1
  local store = (run and run.RewardStores and run.RewardStores[rewardStoreName]) or {}
  local eligible = {}
  for i, reward in ipairs(store) do
    if G.IsRoomRewardEligible(run, room, reward, previouslyChosenRewards, args or {}) then
      eligible[#eligible + 1] = reward
    end
  end
  for _, priorityName in ipairs((run and run.RewardPriorities) or {}) do
    for _, reward in ipairs(eligible) do
      if reward.Name == priorityName then
        for i, name in ipairs(run.RewardPriorities) do
          if name == priorityName then table.remove(run.RewardPriorities, i) break end
        end
        return priorityName
      end
    end
  end
  return eligible[1] and eligible[1].Name or nil
end

G.ELIGIBLE_BASE = true
function G.IsRoomRewardEligible(run, room, reward, previouslyChosenRewards, args)
  return G.ELIGIBLE_BASE
end

function G.newRoom(rewardType, overrides)
  local r = { ChosenRewardType = rewardType, ForcedBoonNames = {} }
  for k, v in pairs(overrides or {}) do r[k] = v end
  return r
end

function G.newRun(traits)
  return {
    Hero = { Traits = traits or {} }, CurrentRoom = {}, LootTypeHistory = {},
    RewardPriorities = {},
    -- A cut-down RunProgress carousel: the three reward types this plugin can
    -- queue, plus a Boon, which is what a god pick queues.
    RewardStores = {
      RunProgress = {
        { Name = "MaxHealthDrop" },
        { Name = "WeaponUpgrade" },
        { Name = "HermesUpgrade" },
        { Name = "SpellDrop" },
        { Name = "Boon", AllowDuplicates = true },
      },
    },
  }
end

-- ResourceData.lua ScreenData.InventoryScreen, cut down to what the tab touches.
G.ScreenData = {
  InventoryScreen = {
    -- ResourceData.lua:3968-3975. These live on the screen data, which is what
    -- lets the button box be derived at load time, before any screen exists.
    GridStartX = 149, GridStartY = 252,
    GridSpacingX = 133.6, GridSpacingY = 143, GridWidth = 8,
    IconMouseOverScale = 1.33,
    ItemCategories = {
      { Name = "InventoryScreen_ResourcesTab" },
      { Name = "InventoryScreen_PinTab", OpenFunctionName = "InventoryScreenDisplayPins" },
    },
  },
}

-- ResourceLogic.lua:645-650 / 670-675. The branch that matters: a category with
-- an OpenFunctionName gets the cursor parked at PinStart, never at CursorStart.
-- Reproduced faithfully so the plugin's wrap is tested against the real defect
-- rather than against a convenient mock.
G.cursorTeleports = {}
function G.TeleportCursor(args)
  G.cursorTeleports[#G.cursorTeleports + 1] = { X = args.OffsetX, Y = args.OffsetY }
end

local function vanillaCategoryStep(screen, step)
  local cats = screen.ItemCategories
  local index = screen.ActiveCategoryIndex or 1
  index = index + step
  if index > #cats then index = 1 end
  if index < 1 then index = #cats end
  screen.ActiveCategoryIndex = index
  local category = cats[index]
  if category.OpenFunctionName ~= nil then
    G[category.OpenFunctionName](screen)
    G.TeleportCursor({ OffsetX = screen.PinStartX, OffsetY = screen.PinStartY, ForceUseCheck = true })
  else
    G.TeleportCursor({ OffsetX = screen.GridStartX, OffsetY = screen.GridStartY, ForceUseCheck = true })
  end
end
function G.InventoryScreenNextCategory(screen, button) vanillaCategoryStep(screen, 1) end
function G.InventoryScreenPrevCategory(screen, button) vanillaCategoryStep(screen, -1) end

-- NPCData_Artemis.lua:1856-1935, trimmed to what the plugin reads. She already
-- gives a 1-of-3 boon choice in vanilla; what she has no version of is a drop.
G.EnemyData = {
  NPC_Artemis_Field_01 = {
    Traits = { "SupportingFireBoon", "CritBonusBoon", "DashOmegaBuffBoon",
               "HighHealthCritBoon", "InsideCastCritBoon", "OmegaCastVolleyBoon",
               "TimedCritVulnerabilityBoon", "FocusCritBoon", "SorceryCritBoon" },
    RarityChances = { Rare = 0.0, Epic = 0.0 },
    RarityRollOrder = { "Common", "Rare", "Epic" },
    MenuTitle = "UpgradeChoiceMenu_Artemis",
    Speaker = "NPC_Artemis_01",
    Portrait = "Portrait_Artemis_Default_01",
    OverlayAnim = "ArtemisOverlay",
    Gender = "Female",
    SpawnSound = "/SFX/ArtemisBoonArrow",
    UpgradeSelectedSound = "/SFX/ArtemisBoonChoice",
    LootRejectionAnimation = "BoonDissipateA_Artemis",
    LoadPackages = { "NPC_Artemis_Field_01", "Artemis" },
    Icon = "BoonSymbolArtemis",
    TreatAsGodLootByShops = true,
  },
}

-- The other three NPC gods, same shape as Artemis.
G.EnemyData.NPC_Athena_01 = {
  Traits = { "AthenaA", "AthenaB", "AthenaC" },
  MenuTitle = "UpgradeChoiceMenu_Athena", Speaker = "NPC_Athena_01",
  Portrait = "Portrait_Athena_Default_01", Gender = "Female",
}
G.EnemyData.NPC_Dionysus_01 = {
  Traits = { "DionysusA", "DionysusB", "DionysusC" },
  MenuTitle = "UpgradeChoiceMenu_Dionysus", Speaker = "NPC_Dionysus_01",
  Portrait = "Portrait_Dionysus_Default_01", Gender = "Male",
}
-- A portrait-only god: boon-shaped traits, a keepsake portrait, and no entry in
-- BoonSelectSymbols. LootColor is what the derived-palette formula reads.
G.EnemyData.NPC_Narcissus_Field_01 = {
  Traits = { "NarcissusA", "NarcissusB", "NarcissusC" },
  LootColor = { 240, 220, 120, 255 },
  MenuTitle = "NarcissusGiftsMenu_Title", Speaker = "NPC_Narcissus_01",
  Portrait = "Portrait_Narcissus_Default_01", Gender = "Male",
}

-- Not a boon-giver: her pool is costumes. Present so the candidate log has
-- something to be right about, and so nothing quietly adds her.
-- Her pool reads like costumes, but AgilityCostume carries full RarityLevels and
-- a WeaponSpeedMultiplier (TraitData_Arachne.lua:3-30) -- a rarity-scaled stat
-- trait offered one-of-three, with the costume riding along. She has no
-- LootColor either, having never had a drop; SubtitleColor is what the derived
-- palette falls back to.
G.EnemyData.NPC_Arachne_01 = {
  Traits = { "AgilityCostume", "ManaCostume", "VitalityCostume" },
  SubtitleColor = { 150, 90, 200, 255 },
}

-- The four the candidate log found, with the pools it reported. Their trait names
-- are the evidence: run modifiers, repeats and curses, all rarity-scaled and all
-- offered one-of-three, which is what a boon is here.
G.EnemyData.NPC_Circe_01 = {
  -- DoubleFamiliarTrait included on purpose: it is the real trait that crashed
  -- the game when taken as a first boon, and the pool has to contain it for the
  -- filter that removes it to be worth anything.
  Traits = { "CirceShrinkTrait", "CirceEnlargeTrait", "ArcanaRarityTrait",
             "DoubleFamiliarTrait" },
  SubtitleColor = { 120, 200, 90, 255 },
}

-- TraitData, as far as the plugin reads it: only MergeTooltipDataFromSession,
-- which marks a trait whose tooltip is assembled from state that some other
-- system was supposed to prepare. UpgradeChoiceLogic.lua:399 indexes that state
-- without checking, so offering such a trait outside its own encounter is a
-- crash rather than a cosmetic problem.
G.TraitData = {
  CirceShrinkTrait = {},
  CirceEnlargeTrait = {},
  ArcanaRarityTrait = {},
  DoubleFamiliarTrait = {
    MergeTooltipDataFromSession = { Old = "OldFamiliarTrait", New = "NewFamiliarTrait" },
  },
}
G.EnemyData.NPC_Echo_01 = {
  Traits = { "EchoLastReward", "EchoLastRunBoon", "EchoDeathDefianceRefill" },
  SubtitleColor = { 200, 200, 230, 255 },
}
G.EnemyData.NPC_Icarus_01 = {
  Traits = { "FocusAttackDamageTrait", "FocusSpecialDamageTrait", "OmegaExplodeBoon" },
  SubtitleColor = { 230, 170, 60, 255 },
}
G.EnemyData.NPC_Medea_01 = {
  Traits = { "HealingOnDeathCurse", "MoneyOnDeathCurse", "ManaOverTimeCurse" },
  SubtitleColor = { 90, 200, 120, 255 },
}

G.EnemyData.NPC_Hades_Field_01 = {
  Traits = { "HadesA", "HadesB", "HadesC" },
  MenuTitle = "UpgradeChoiceMenu_Hades", Speaker = "NPC_Hades_01",
  Portrait = "Portrait_Hades_Default_01", Gender = "Male",
}

-- TraitLogic.lua:1547-1607, the four "which god owns this trait?" scans, cut to
-- the branches that matter. FieldLootData is how the base game records an NPC
-- god: TreatAsGodLootByShops set, GodLoot UNSET -- which is exactly why vanilla
-- says these traits are not god traits unless the caller asked ForShop.
G.FieldLootData = {}
for _, npcName in ipairs({ "NPC_Artemis_Field_01", "NPC_Athena_01",
                           "NPC_Dionysus_01", "NPC_Hades_Field_01" }) do
  local index = {}
  for _, traitName in ipairs(G.EnemyData[npcName].Traits or {}) do index[traitName] = true end
  G.FieldLootData[npcName] = {
    Name = npcName, TraitIndex = index, TreatAsGodLootByShops = true,
  }
end

-- The plugin's LootData entries are added at install time with no TraitIndex --
-- the game builds that in SetupRunData -- so the mock builds it on demand, the
-- same way the real data pass does (RunData.lua:972).
local function traitIndexOf(lootData)
  if lootData.TraitIndex ~= nil then return lootData.TraitIndex end
  local index = {}
  for _, traitName in ipairs(lootData.Traits or {}) do index[traitName] = true end
  lootData.TraitIndex = index
  return index
end

function G.IsGodTrait(traitName, args)
  args = args or {}
  for _, god in pairs(G.LootData) do
    if (god.GodLoot or (args.ForShop and god.TreatAsGodLootByShops))
      and not god.DebugOnly and traitIndexOf(god)[traitName] then
      return true
    end
  end
  for _, god in pairs(G.FieldLootData) do
    if traitIndexOf(god)[traitName]
      and (god.GodLoot or (args.ForShop and god.TreatAsGodLootByShops)) then
      return true
    end
  end
  return false
end

function G.GetGodSourceName(traitName, args)
  args = args or {}
  for _, god in pairs(G.LootData) do
    if (god.GodLoot or (args.ForShop and god.TreatAsGodLootByShops))
      and not god.DebugOnly and traitIndexOf(god)[traitName] then
      return god.Name
    end
  end
  for _, god in pairs(G.FieldLootData) do
    if traitIndexOf(god)[traitName]
      and (god.GodLoot or (args.ForShop and god.TreatAsGodLootByShops)) then
      return god.Name
    end
  end
end

function G.GetLootSourceName(traitName, args)
  args = args or {}
  for lootName, god in pairs(G.LootData) do
    if (god.GodLoot or god.TreatAsGodLootByShops or args.ForBoonInfo)
      and not god.DebugOnly and traitIndexOf(god)[traitName] then
      return lootName
    end
  end
  if args.CheckEnemyData then
    for enemyName, enemyData in pairs(G.EnemyData) do
      for _, name in ipairs(enemyData.Traits or {}) do
        if name == traitName then return enemyName end
      end
    end
  end
  return nil
end

function G.GetAllLootSourceNames(traitName, args)
  args = args or {}
  local out = {}
  for _, god in pairs(G.LootData) do
    if (god.GodLoot or god.TreatAsGodLootByShops or args.ForBoonInfo)
      and not god.DebugOnly and traitIndexOf(god)[traitName] then
      out[god.Name or "?"] = true
    end
  end
  return out
end

-- RunLogic.lua:1819-1829. Counts any LootTypeHistory entry whose LootData has
-- GodLoot, and feeds the max-gods cap.
function G.GetInteractedGodsThisRun(ignoredGod)
  local out = {}
  if G.CurrentRun ~= nil and G.CurrentRun.LootTypeHistory ~= nil then
    for lootName, _ in pairs(G.CurrentRun.LootTypeHistory) do
      local d = G.LootData[lootName]
      if d and d.GodLoot and (ignoredGod == nil or lootName ~= ignoredGod) then
        out[#out + 1] = lootName
      end
    end
  end
  table.sort(out)
  return out
end

G.textBoxWrites = {}
function G.ModifyTextBox(args)
  if G.TEXTBOX_THROWS then error("simulated ModifyTextBox failure") end
  G.textBoxWrites[#G.textBoxWrites + 1] = args
end
G.visibilityCalls = 0
function G.InventoryScreenUpdateVisibility(screen) G.visibilityCalls = G.visibilityCalls + 1 end

-- ResourceData.lua grid constants.
function G.newInventoryScreen(withHint)
  local s = {
    NumItems = 3, Components = {},
    GridStartX = 149, GridStartY = 252,
    GridSpacingX = 133.6, GridSpacingY = 143, GridWidth = 8,
    PinStartX = 614, PinStartY = 267,
    IconMouseOverScale = 1.33,
    -- ResourceData.lua:3931. The tab strip draws its category icons at this,
    -- which is a fraction of the grid's scale -- the thing 4.8.0 got wrong.
    CategoryIconScale = 0.45,
    ItemCategories = G.ScreenData.InventoryScreen.ItemCategories,
    ActiveCategoryIndex = 1,
  }
  if withHint ~= false then s.Components.EmptyCategoryHint = { Id = 4242 } end
  -- The four right-hand info boxes belong to the screen, not to a category
  -- (ResourceData.lua:4428-4500), so they exist regardless of which tab is open.
  s.Components.InfoBoxName        = { Id = 4301 }
  s.Components.InfoBoxDescription = { Id = 4302 }
  s.Components.InfoBoxDetails     = { Id = 4303 }
  s.Components.InfoBoxFlavor      = { Id = 4304 }
  s.Components["CategoryIconFirst Boon"] = { Id = 999 }
  return s
end

G.nextId = 5000
G.destroyed = {}
G.animations = {}
G.alphas = {}
-- Components are registered by Id so SetScale can update the one it names.
-- The plugin creates a button at Scale 1.0 and then sets its real size with
-- SkipGeometryUpdate, because a Scale passed to CreateScreenComponent shrinks
-- the obstacle's BOUNDS as well as the art. Args.Scale alone therefore no
-- longer describes how big a thing is drawn; the effective scale does.
G.components = {}
function G.CreateScreenComponent(args)
  if G.COMPONENT_THROWS then error("simulated CreateScreenComponent failure") end
  G.nextId = G.nextId + 1
  local c = { Id = G.nextId, Args = args }
  G.components[c.Id] = c
  return c
end
G.Color = { White = {255,255,255,255} }
G.textBoxes = {}
function G.CreateTextBox(args) G.textBoxes[args.Id] = args end
function G.SetAnimation(args) G.animations[args.DestinationId] = args.Name end
function G.SetAlpha(args) G.alphas[args.Id] = args.Fraction end
G.rgb = {}
function G.SetRGB(args) G.rgb[args.Id] = args.Color end
G.scales = {}
function G.SetScale(args)
  G.scales[args.Id] = args
  -- Mirror it onto the component, so Args.Scale keeps meaning "how big is this".
  local c = G.components[args.Id]
  if c ~= nil and args.Fraction ~= nil then c.Args.Scale = args.Fraction end
end
function G.Destroy(args) G.destroyed[#G.destroyed + 1] = args.Id end
function G.SetGamepadNavigation(screen) G.gamepadCalls = (G.gamepadCalls or 0) + 1 end

-- Runs for every category the screen displays, including the one it opens on.
-- Present so the tab-strip sizing wrap has something to wrap: without it the
-- wrap silently attaches to nil and the fix goes untested, which is how the
-- strip icon shipped wrong once already.
function G.InventoryScreenDisplayCategory(screen, categoryIndex, args)
  G.displayedCategory = categoryIndex
  return screen
end

-- PresetEventArgs.<God>Choices.UpgradeOptions -- the offer lists the gods' own
-- encounters read. Shapes and gates copied from NPCData.lua, not invented:
-- DoubleFamiliarTrait really is gated on PathTrue { "MapState", "FamiliarUnit" },
-- and ArcanaRarityTrait really is gated on GameState.MetaUpgradeCostCache > 0.
G.PresetEventArgs = {
  CirceBlessingChoices = {
    UpgradeOptions = {
      { Type = "Trait", ItemName = "CirceShrinkTrait", Rarity = "Common" },
      { Type = "Trait", ItemName = "CirceEnlargeTrait", Rarity = "Common" },
      { Type = "Trait", ItemName = "ArcanaRarityTrait", Rarity = "Common",
        GameStateRequirements = {
          { Path = { "GameState", "MetaUpgradeCostCache" }, Comparison = ">", Value = 0 },
        } },
      { Type = "Trait", ItemName = "DoubleFamiliarTrait", Rarity = "Common",
        GameStateRequirements = {
          { PathTrue = { "MapState", "FamiliarUnit" } },
        } },
    },
  },
  EchoBenefitChoices = {
    UpgradeOptions = {
      { Type = "Trait", ItemName = "EchoLastReward", Rarity = "Common" },
      { Type = "Trait", ItemName = "EchoLastRunBoon", Rarity = "Common" },
      { Type = "Trait", ItemName = "EchoDeathDefianceRefill", Rarity = "Common",
        GameStateRequirements = {
          { FunctionName = "HasDeathDefianceMissing" },
        } },
    },
  },
}

-- Set true to make every gate throw, standing in for a FunctionName the game
-- resolves at call time that is missing or broken.
G.ELIGIBLE_THROWS_GATE = false

-- IsGameStateEligible, covering the requirement forms our five offer tables
-- actually use. RequirementsLogic.lua:9-12 shows source is read only for its
-- Name, so the real thing is equally happy with a bare table.
function G.IsGameStateEligible(source, requirements, args)
  if G.ELIGIBLE_THROWS_GATE then error("simulated failure inside IsGameStateEligible") end
  G.eligibilityChecks = (G.eligibilityChecks or 0) + 1
  if requirements == nil or next(requirements) == nil then return true end
  for _, requirement in ipairs(requirements) do
    if requirement.FunctionName ~= nil then
      local fn = G[requirement.FunctionName]
      if type(fn) ~= "function" or not fn(source) then return false end
    end
    if requirement.PathTrue ~= nil then
      local value = G
      for _, step in ipairs(requirement.PathTrue) do
        value = type(value) == "table" and value[step] or nil
      end
      if not value then return false end
    end
    if requirement.Path ~= nil and requirement.Comparison ~= nil then
      local value = G
      for _, step in ipairs(requirement.Path) do
        value = type(value) == "table" and value[step] or nil
      end
      if type(value) ~= "number" then return false end
      if requirement.Comparison == ">" and not (value > requirement.Value) then return false end
    end
  end
  return true
end

-- GetEligibleUpgrades, standing in for UpgradeChoiceLogic.lua:899. Vanilla's own
-- filtering is not modelled -- what is under test is the gating we add on top --
-- so this just turns the pool into the {ItemName, Type} list the real one returns.
-- Present so the wrap has a base: without it the wrap attaches to nil and the
-- gating ships untested.
function G.GetEligibleUpgrades(upgradeOptions, lootData, upgradeChoiceData)
  local upgrades = {}
  local traits = (upgradeChoiceData or lootData or {}).Traits or {}
  for _, name in ipairs(traits) do
    upgrades[#upgrades + 1] = { ItemName = name, Type = "Trait" }
  end
  return upgrades
end

-- ModUtil.Path.Wrap, matching ModUtil.Extra.lua semantics for a flat global path
G.ModUtil = { Path = { Wrap = function(path, wrap)
  local base = G[path]
  G[path] = function(...) return wrap(base, ...) end
end } }

return G
