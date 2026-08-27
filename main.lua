-- =============================================================================
-- SelectFirstBoon (v4.31.0) -- logs the run seed and the offered traits at spawn,
-- to settle a report of identical boon options across re-rolled seeds.
-- =============================================================================
-- Forces the first boon reward of a run to come from one chosen god.
--
-- This is NOT a boon spawner. The run plays normally: you still walk into the
-- boon room, still get three options, still at the normal time. The only thing
-- that changes is WHICH god that first boon reward belongs to.
--
-- Phase 1 hardcoded the god in a constant. Phase 2 keeps that logic byte-for-
-- byte and puts a dropdown in front of it. The decision function reads the
-- setting at the moment a reward is set up, so changing the dropdown mid-run
-- takes effect at the very next door unlock -- no restart, no new run.
--
-- The default is None: vanilla randomness, with Hermes and Selene held back
-- until you hold a boon. Pick a god -- or switch the gates off -- in the
-- ReturnOfModding menu bar under "SelectFirstBoon", or edit
-- Adicon-SelectFirstBoon.cfg in the config folder.
--
-- -----------------------------------------------------------------------------
-- THE NEVER-FIRST GATES (v2.1.0)
-- -----------------------------------------------------------------------------
--
-- Hermes and Selene are not boons. HermesUpgrade is GodLoot = false
-- (LootData_Hermes.lua:10) and Selene's reward is SpellDrop; both sit in
-- RewardStoreData.RunProgress as their own reward TYPES, siblings of "Boon".
-- So the god dropdown above can never affect them -- it only runs when
-- chosenRewardType == "Boon". Holding them back is a separate mechanism.
--
-- This replaces two things: the standalone NoHermesFirstBoon plugin, and
-- adamantSpeedrun-Gameplay_QoL's DisableSeleneBeforeBoon. Both of those work by
-- appending a requirement to game data -- the Selene module to the shared
-- NamedRequirementsData.SpellDropRequirements, the Hermes plugin to the
-- RunProgress HermesUpgrade entry's own GameStateRequirements.
--
-- This one wraps IsRoomRewardEligible (RewardLogic.lua:34) instead, and that is
-- a deliberate upgrade on both counts:
--
--   * No shared data is mutated at all, so there is no blast radius to reason
--     about. NamedRequirementsData.SpellDropRequirements has two consumers
--     (LootData.lua:864 and :1685); HermesUpgradeRequirements has seventeen
--     (RunProgress, HubRewards, and fifteen entries in BountyData.lua).
--   * RewardLogic.lua:20 InitializeRewardStores deep-copies RewardStoreData into
--     run.RewardStores at run start, so a data patch only affects runs started
--     afterwards. A wrap is consulted live, so toggling these takes effect at
--     the next door unlock like every other setting here.
--   * A wrap filters at eligibility time rather than in one store's data, so it
--     holds for every reward store, not just RunProgress.
--
-- IsRoomRewardEligible has exactly one caller, ChooseRoomReward at
-- RewardLogic.lua:142 -- verified by grep across all game scripts -- so the wrap
-- cannot reach anything else.
--
-- The gate releases once CurrentRun.LootTypeHistory holds any of the nine boon
-- gods or WeaponUpgrade, which is the list both replaced modules use.
-- LootTypeHistory is incremented in HandleLootPickup (InteractLogic.lua:717), so
-- it counts boons actually PICKED UP, not merely offered. That is what makes
-- "until you hold a boon" work rather than "until one is on a door".
--
-- Starvation was checked: no room restricts EligibleRewards to HermesUpgrade or
-- SpellDrop, so filtering them can never empty the eligible pool. Rooms that
-- force a reward outright (room.ForcedReward, roomData.ForcedRewards) bypass
-- IsRoomRewardEligible entirely and are unaffected -- the same blind spot the
-- two replaced modules have, since GameStateRequirements is skipped there too.
--
-- -----------------------------------------------------------------------------
-- THE VANILLA MECHANISM BEING MIRRORED
-- -----------------------------------------------------------------------------
--
-- RewardLogic.lua:228-258, inside SetupRoomReward:
--
--     if chosenRewardType == "Boon" and ( args.AlwaysSetupForceLootName or not room.ForceLootName ) then
--         local excludeLootNames = {}
--         if previouslyChosenRewards ~= nil then
--             for i, data in pairs( previouslyChosenRewards ) do
--                 if data.RewardType == "Boon" then
--                     table.insert( excludeLootNames, data.ForceLootName )
--                 end
--             end
--         end
--         local lootData = ChooseLoot( excludeLootNames )
--         if not args.IgnoreForceLootName then
--             for k, trait in ipairs( CurrentRun.Hero.Traits ) do
--                 if trait ~= nil and trait.ForceBoonName ~= nil and trait.Uses > 0
--                    and not Contains(excludeLootNames, trait.ForceBoonName) then
--                     lootData = { Name = trait.ForceBoonName }
--                     room.ForcedBoonNames[trait.ForceBoonName] = true
--                     room.ForceBoonChosenTrait = trait
--                     break
--                 end
--             end
--         end
--         ...
--         room.ForceLootName = lootData.Name
--     end
--
-- Consumption is NOT here. It happens at spawn time, in RoomLogic.lua:2058-2069
-- inside GiveLoot, where a matching keepsake gets ReduceTraitUses. So a keepsake
-- keeps forcing until a boon of that god actually SPAWNS -- not until you pick it
-- up, and not merely because a door previewed it. This plugin copies that exact
-- consumption point.
--
-- -----------------------------------------------------------------------------
-- WHAT IS DELIBERATELY NOT REPRODUCED, AND WHY
-- -----------------------------------------------------------------------------
--
-- room.ForceBoonChosenTrait -- vanilla sets it so the door preview can play the
--   keepsake flash. Verified reader: RewardPresentation.lua:18-21, which threads
--   ForceBoonChosenPresentation( room.ForceBoonChosenTrait ). That is the only
--   read of the field anywhere in the 52 game scripts checked. We have no trait
--   to flash, so it stays nil and no flash plays. Correct: there is no keepsake.
--
-- room.ForcedBoonNames[name] -- set anyway, purely to match vanilla state. It is
--   initialised in RunLogic.lua:589 (RoomInit) and, in the scripts checked, is
--   never read by anything.
--
-- The Devotion branch (RewardLogic.lua:259-274) also consults ForceBoonName
--   traits. Not mirrored -- a Devotion encounter is not "the first boon".
--
-- Rooms with DeferReward or PersistentExitDoorRewards are skipped entirely.
--   Vanilla evaluates its `not room.ForceLootName` guard AFTER CheckPreviousReward
--   (RunLogic.lua:752) may have assigned that field, and a post-wrap cannot see
--   that intermediate state. Rather than guess, the plugin stands down. Both flags
--   mean "re-offer what was already promised", so this can only cost a force,
--   never corrupt one.
--
-- -----------------------------------------------------------------------------
-- PHASE 2 NOTES
-- -----------------------------------------------------------------------------
--
-- Settings persist through ReturnOfModding's own config API -- the same
-- rom.config.config_file / bind / get / set / save primitives SGG_Modding-Chalk
-- is built on, used directly. v2.0.0 went through Chalk and failed to load:
-- chalk.auto calls envy.import to read a config.lua from the plugin folder, and
-- that import could not find the file even though it was sitting right there.
-- The plugin lives in a nested folder (plugins\Adamant\...) whose leaf name is
-- what ReturnOfModding uses as the plugin guid, so guid-based path resolution
-- and the real path disagree. Rather than pin down exactly where that resolution
-- goes wrong, the import step is gone: defaults are declared inline below and
-- there is no second file to find. If the config API is unavailable the plugin
-- still runs, using in-memory settings that reset when the game closes.
--
-- Logging goes exclusively through rom.log.info, with severity as text. This is
-- not stylistic: rom.log.error RAISES a Lua error rather than logging one. In
-- v2.0.0 the Chalk failure above was reported with rom.log.error inside the main
-- chunk, which turned a handled, recoverable condition into a module that failed
-- to load outright. The stack traceback read "[C]: in function 'error'".
--
-- The god list is built from the game's own LootData rather than hardcoded, so
-- a patch that adds an Olympian picks it up for free. LootData entries inherit
-- from a BaseLoot template that carries DebugOnly = true, and InheritFrom is
-- resolved engine-side -- not in any Lua script -- so whether DebugOnly reaches
-- the individual gods cannot be settled by reading the source. The catalog
-- builder therefore filters on DebugOnly, and if that filter empties the list it
-- retries without it, then falls back to a static list read out of the
-- LootData_*.lua files. Whichever path is taken is logged at startup.
--
-- All ImGui work is wrapped so that a UI failure cannot take the game down, and
-- Begin/End, BeginCombo/EndCombo and BeginMenu/EndMenu are paired to ImGui's
-- rules (End is unconditional after Begin; EndCombo and EndMenu only when their
-- Begin returned true).
-- =============================================================================

local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

local modutil = mods["SGG_Modding-ModUtil"]
local sjson = mods["SGG_Modding-SJSON"]

-- Field written onto CurrentRun to record that the forced boon has already
-- spawned. Living on CurrentRun rather than in a plugin local means it survives
-- save-and-quit mid-run: reloading will not hand out a second forced boon.
local USED_FIELD = "SelectFirstBoon_Spawned"

local NONE_VALUE = ""
-- "Standard", not "random". The unpicked option is not a new randomised mode; it
-- is the game's own behaviour with nothing touched, and how random that is
-- underneath is the game's business, not something for this plugin to claim.
local STANDARD_LABEL = "Standard"
local NONE_LABEL = STANDARD_LABEL

-- Last-resort catalog, read out of Content/Scripts/LootData_*.lua. Only used if
-- LootData cannot be walked at all. HermesUpgrade and TrialUpgrade (Chaos) are
-- deliberately absent: both are GodLoot = false and travel as their own reward
-- types, not as boons.
local FALLBACK_GODS = {
    "AphroditeUpgrade", "ApolloUpgrade", "AresUpgrade", "DemeterUpgrade",
    "HephaestusUpgrade", "HeraUpgrade", "HestiaUpgrade", "PoseidonUpgrade",
    "ZeusUpgrade",
}

-- Records that this run has already had its reward priority pushed. On
-- CurrentRun, like USED_FIELD, so a save-and-quit mid-run cannot push a second.
local PRIORITY_FIELD = "SelectFirstBoon_PriorityAdded"

-- Latched when a run starts with a boon keepsake equipped. See standDownForKeepsake.
local KEEPSAKE_FIELD = "SelectFirstBoon_KeepsakeWins"

-- ---------------------------------------------------------------------------
-- Hammer, Hermes and Selene are NOT boons. Each is its own reward type in the
-- reward store (LootData.lua RunProgress: WeaponUpgrade, HermesUpgrade,
-- SpellDrop), so room.ForceLootName -- the whole god mechanism above -- cannot
-- reach them. A different lever is needed, and vanilla already has one.
--
-- Every god keepsake does TWO things, not one (TraitData_Keepsake.lua:2593-2604):
--
--     ForceBoonName       = "<God>Upgrade"        -- WHICH god, once a Boon is chosen
--     AcquireFunctionName = "RewardStoreAddPriority"
--     AcquireFunctionArgs = { Name = "Boon" }     -- that the first reward IS a Boon
--
-- This plugin has only ever mirrored the first. RewardStoreAddPriority
-- (RewardLogic.lua:513-533) pushes a reward NAME onto CurrentRun.RewardPriorities
-- and tops the store up if that name is not currently in the carousel.
-- ChooseRoomReward then walks the priority list (RewardLogic.lua:163-171), takes
-- the first entry that is eligible at that moment, and RemoveValueAndCollapse's
-- it -- so a priority is one-shot and self-consuming, which is exactly the shape
-- this feature needs and exactly how a keepsake behaves.
--
-- For the three specials the priority name IS the reward type. For a god it is
-- "Boon", which is the half of keepsake parity that was missing.
--
-- Values are @-prefixed so they can never collide with a LootData key, and so a
-- config written by an older version is trivially told apart.
local SPECIALS = {
    {
        value  = "@Hammer",
        label  = "Daedalus Hammer",
        reward = "WeaponUpgrade",
        symbol = "Hammer",
        blurb  = "Offer a Daedalus Hammer as the run's first reward.",
    },
    {
        value  = "@Hermes",
        label  = "Hermes",
        reward = "HermesUpgrade",
        symbol = "Hermes",
        gate   = "BlockHermesBeforeBoon",
        blurb  = "Offer Hermes as the run's first reward.",
    },
    {
        value  = "@Selene",
        label  = "Selene",
        reward = "SpellDrop",
        -- No Selene in GUI\Screens\BoonSelectSymbols -- that set has no moon
        -- symbol at all. This is the door-preview art instead, from a different
        -- folder, so it is registered separately and has its own scale knob.
        -- Selene is the odd one out in VANILLA, not just here. Every god's door
        -- icon is BoonDrop<God>Preview inheriting BoonDropRoomRewardIconPreviewBase
        -- from <God>IconSpin0015 -- a flat, squared-up medallion
        -- (Items_General_VFX.sjson:5636). Hers is SpellDropPreview inheriting
        -- BoonSymbolBaseIsometric (:1063), a DIFFERENT base, which is why it sits
        -- at an angle next to the others. Her world drop carries a beam of light
        -- on top of that, painted into the texture, which ruled it out in
        -- testing -- so this art plus an optional halo is what is left.
        file   = "Items\\Loot\\SpellDrop_Preview",
        portrait = "Selene",
        gate   = "BlockSeleneBeforeBoon",
        blurb  = "Offer Selene's path as the run's first reward.",
    },
    {
        -- Chaos fits here rather than among the added gods, and the difference
        -- matters. Those needed a LootData entry inventing; Chaos already has a
        -- complete one -- TrialUpgrade, with its own emblem, door icon, drop
        -- animations and sounds (LootData_Chaos.lua). It is GodLoot = false, so
        -- it never enters the god pool, exactly like Hermes and Selene.
        --
        -- "TrialUpgrade" is a reward TYPE the game already knows how to spawn
        -- (RewardLogic.lua:392-394), so the existing machinery does the work:
        -- queue it as this run's first reward priority and the game builds it.
        -- Nothing here forces a loot name or registers any art.
        --
        -- What this changes about the run: normally Chaos is met only through a
        -- Chaos gate. This offers that reward once, at the start, and only when
        -- picked -- everywhere else the gates behave exactly as they always did.
        value  = "@Chaos",
        label  = "Chaos",
        reward = "TrialUpgrade",
        symbol = "Chaos",
        blurb  = "Offer a Chaos boon as the run's first reward.",
    },
}

local SPECIAL_BY_VALUE = {}
for _, special in ipairs(SPECIALS) do SPECIAL_BY_VALUE[special.value] = special end

local function specialFor(value)
    if value == nil then return nil end
    return SPECIAL_BY_VALUE[value]
end

local LOG_PREFIX = "[SelectFirstBoon] "

-- =============================================================================
-- Settings
-- =============================================================================

local settings = {
    values = {
        God = NONE_VALUE,
        RespectEligibility = false,
        LogDecisions = true,
        BlockHermesBeforeBoon = true,
        BlockSeleneBeforeBoon = true,
        ShowInventoryTab = true,
        TabIconScale = 0.45,
        VerboseTabLog = true,
        -- A slot is roughly 133.6 x 143, so these sit just inside one.
        TabButtonBoxWidth = 0,
        TabButtonBoxHeight = 0,
        AlwaysFirst = false,
        KeepsakeWins = true,
        KeepPickAfterRestart = false,
        AddedGodsOnlyWhenPicked = true,
        -- Presentation, all live: they are read when the tab opens, so changing
        -- one and reopening the inventory is enough. No restart, no redeploy.
        IconStyle = "boondrop",
        StandardIcon = "pom-flat",
        PortraitIconOffsetY = 6,
        IconOffsetY = 10,
        SeleneIconBoost = 2.0,
        PortraitIconBoost = 0.4,
        DropIconScale = 0.4,
        DropPortraitScale = 0.22,
        DoorEmblemScale = 1.0,
        DoorPortraitScale = 0.27,
        GlowBrightnessArtemis = 0.6,
        GlowBrightnessAthena = 0.6,
        GlowBrightnessDionysus = 0.6,
        GlowBrightnessHades = 0.6,
        -- Athena alone starts dimmed: her emblem is the one that came back
        -- unreadable inside the orb. The other three were checked in game at
        -- full and are left there.
        EmblemArtArtemis = "symbol",
        EmblemArtAthena = "symbol",
        EmblemArtDionysus = "symbol",
        EmblemArtHades = "symbol",
        EmblemBrightnessArtemis = 1.0,
        EmblemBrightnessAthena = 0.7,
        EmblemBrightnessDionysus = 1.0,
        EmblemBrightnessHades = 1.0,
        SeleneGlowSource = "particle",
        SeleneGlowStrength = 0,
        HitboxScale = 1.0,
        HitboxScalePortrait = 1.0,
        SelectionHalo = true,
        SelectionHaloStrength = 0.22,
        SelectionHaloSize = 0.55,
        SelectionHaloSpreadStep = 0.1,
        SelectionHaloCore = 1.0,
        SelectionHaloWhiten = 1.0,
        SelectionHaloFollowsIcon = 1.0,
        SelectionHaloTint = "god",
        SelectionHaloTintMix = 1.0,
        SelectionHaloLayers = 3,
        SeleneHaloSpread = 0.75,
        SeleneHaloLayers = 3,
        TabIconBoost = 1.15,
        BoldGateWords = true,
        GateStateStyle = "size",
        IconSize = 1.0,
        UnselectedBrightness = 0.7,
        SelectedIconScale = 1.25,
        IconBrightness = 1.0,
        HighlightStyle = "grow",
        HighlightOffsetY = 0,
        EnableArtemis = true,
        EnableAthena = true,
        EnableDionysus = true,
        EnableHades = true,
        -- The two portrait-only gods ship OFF, not because either is risky but
        -- because "on by default" is a claim about art nobody has looked at yet.
        -- The other four each earned their default by being checked in game
        -- first. One flip each in settings, and they earn theirs the same way.
        -- Narcissus's portrait is the palest of the six and his halo came back
        -- brighter than it needed to be. A multiplier rather than an absolute,
        -- so the shared strength dial still governs and this only says "less
        -- than the others".
        HaloStrengthNarcissus = 0.7,
        HaloStrengthArachne = 1.0,
        HaloStrengthCirce = 1.0,
        HaloStrengthEcho = 1.0,
        HaloStrengthIcarus = 1.0,
        HaloStrengthMedea = 1.0,
        EnableNarcissus = true,
        EmblemBrightnessNarcissus = 1.0,
        GlowBrightnessNarcissus = 0.6,
        EnableArachne = true,
        EnableCirce = true,
        EmblemBrightnessCirce = 1.0,
        GlowBrightnessCirce = 0.6,
        EnableEcho = true,
        EmblemBrightnessEcho = 1.0,
        GlowBrightnessEcho = 0.6,
        EnableIcarus = true,
        EmblemBrightnessIcarus = 1.0,
        GlowBrightnessIcarus = 0.6,
        EnableMedea = true,
        EmblemBrightnessMedea = 1.0,
        GlowBrightnessMedea = 0.6,
        EmblemBrightnessArachne = 1.0,
        GlowBrightnessArachne = 0.6,
        LogGodCandidates = true,
    },
    entries = {},
    file = nil,
    persistent = false,
}

local function log(message)
    if not settings.values.LogDecisions then return end
    if rom and rom.log and rom.log.info then
        rom.log.info(LOG_PREFIX .. tostring(message))
    end
end

local function logAlways(message)
    if rom and rom.log and rom.log.info then
        rom.log.info(LOG_PREFIX .. tostring(message))
    end
end

-- Deliberately rom.log.info, never rom.log.error: in this ReturnOfModding build
-- rom.log.error raises rather than logs, so using it to report a handled failure
-- turns that failure fatal. Severity is carried in the text instead.
local function logWarn(message)
    if rom and rom.log and rom.log.info then
        rom.log.info(LOG_PREFIX .. "WARNING: " .. tostring(message))
    end
end

-- WHICH SECTION EACH SETTING LIVES IN
--
-- Everything used to bind to one section called "config", which produced a flat
-- alphabetical wall of seventy-five keys where "God" sat between "GateStateStyle"
-- and "GlowBrightnessArachne". The three settings that decide how the mod behaves
-- were buried among sixty cosmetic dials nobody should have to scroll past.
--
-- Chalk writes the section name into the .cfg as a [header], so sections are all
-- it takes to fix that. Numbered because the file is written in the order the
-- sections are first seen, and "Appearance" sorting above "Main" would defeat the
-- point.
--
-- One table rather than several locals: this file is close enough to Lua's
-- 200-local ceiling per function that adding four more broke the parse.
local CONFIG = {
    MAIN       = "1 - Main",
    GODS       = "2 - Extra gods",
    APPEARANCE = "3 - Appearance (you can ignore all of this)",
    -- Deliberately short. If a setting changes what the mod DOES it belongs in
    -- Main; if it changes how something looks it does not, however much time was
    -- spent on it.
    mainKeys = {
        God = true,
        KeepPickAfterRestart = true,
        BlockHermesBeforeBoon = true,
        BlockSeleneBeforeBoon = true,
        KeepsakeWins = true,
        AlwaysFirst = false,
        RespectEligibility = true,
        AddedGodsOnlyWhenPicked = true,
        ShowInventoryTab = true,
        LogDecisions = true,
        LogGodCandidates = true,
        VerboseTabLog = true,
    },
}

function CONFIG.sectionFor(key)
    if CONFIG.mainKeys[key] then return CONFIG.MAIN end
    if key:sub(1, 6) == "Enable" then return CONFIG.GODS end
    return CONFIG.APPEARANCE
end

-- Every line follows the same shape: what it does, what the values mean if that
-- is not obvious, and when a change takes effect. That last clause is not
-- decoration -- three different things happen depending on the key, and getting
-- it wrong sends someone hunting for a bug that is really just a stale tab.
--
--   nothing         read at the moment it matters, so a change applies at once
--   "Next run."     latched per run, so an in-progress run keeps its answer
--   "Reopen ..."    read when the inventory tab is built
--   "Restart ..."   baked into game data at load, via sjson
local CONFIG_DESCRIPTIONS = {
    God = "What the run's first reward is. Empty means the game's own order, "
        .. "untouched. Otherwise a god's loot name -- ZeusUpgrade, HeraUpgrade, "
        .. "HestiaUpgrade and so on -- or one of @Hammer, @Hermes, @Selene. "
        .. "Anything else is ignored and logged. Next reward rolled.",

    AlwaysFirst = "Off: your pick waits its turn. The game chooses the first "
        .. "reward, and anything it has scripted -- a Chaos Trial's opening boon, "
        .. "a story beat -- happens as designed; yours lands on the next boon "
        .. "after that. On: your pick goes first no matter what, overriding both. "
        .. "WARNING: that breaks encounters built around a specific opening boon, "
        .. "and it breaks them quietly. Next run.",

    KeepsakeWins = "Whether an equipped boon keepsake beats the pick. On, the "
        .. "keepsake wins and this plugin sits out the whole run. Off, you get "
        .. "both: the keepsake takes the first boon and the pick takes the "
        .. "second, so two guaranteed gods. Next run.",

    RespectEligibility = "On, a god you have not met cannot be your first boon and "
        .. "the pick is ignored. Off, you get them regardless, which is what an "
        .. "equipped keepsake does. A safeguard, off by default. Next reward "
        .. "rolled.",

    AddedGodsOnlyWhenPicked = "On, the gods this plugin adds can only turn up as "
        .. "the first boon when you have actually picked one of them; the rest of "
        .. "the time you meet them by talking to them, as the base game intends. "
        .. "Off, they join the pool the game's own first-boon roll draws from, so "
        .. "one can appear without being asked for. Next reward rolled.",

    KeepPickAfterRestart = "On, your pick is still there next time you launch the "
        .. "game. Off, every launch starts at Standard and picking a god is "
        .. "something you do on purpose that session. Off by default. Takes "
        .. "effect at the next launch.",

    BlockHermesBeforeBoon = "Hold Hermes out of the reward pool until you hold a "
        .. "boon or a hammer. Ignored while Hermes is your pick. Next reward rolled.",

    BlockSeleneBeforeBoon = "Hold Selene out of the reward pool until you hold a "
        .. "boon or a hammer. Ignored while Selene is your pick. Next reward rolled.",

    ShowInventoryTab = "Whether to add the First Boon tab to the inventory "
        .. "screen. Off leaves the settings window as the only way in. Restart "
        .. "the game.",

    PortraitIconOffsetY = "How far to nudge the menu icon of a god drawn from a "
        .. "keepsake portrait, on top of the nudge every icon gets. That art is a "
        .. "different shape from the god symbols, so it does not sit at the same "
        .. "height in the slot. Reopen the inventory.",

    StandardIcon = "Which picture the Standard option shows. It used to borrow the "
        .. "Chaos symbol, which stopped working when Chaos became something you "
        .. "can pick. None of these was drawn to mean \"no pick\", so they are "
        .. "offered as a list to step through rather than one answer. Reopen the "
        .. "inventory.",

    IconStyle = "Which art the tab draws. \"boondrop\" is the flat icon a door "
        .. "shows, used for the thirteen that have one; the rest fall back to "
        .. "keepsake portraits, which are also flat. \"symbol\" is the god "
        .. "symbols, which carry a glow painted into the art. Reopen the "
        .. "inventory.",

    DoorEmblemScale = "How big an added god's icon is drawn ON THE DOOR, for the "
        .. "gods using an emblem. 1.0 is what vanilla states for its own. "
        .. "Restart the game.",
    DoorPortraitScale = "The same, for the gods drawn from a keepsake portrait. "
        .. "Their art is far larger than a medallion, so it needs taking down or "
        .. "it swamps the door. Restart the game.",
    DropPortraitScale = "How big a keepsake portrait is drawn inside the boon orb, "
        .. "for the gods drawing one. Separate from the emblem size because they "
        .. "are different source art. Restart the game.",

    DropIconScale = "How big the god's emblem is drawn inside the boon orb on the "
        .. "ground, for the four gods this plugin adds. Their emblem art is "
        .. "larger than the art vanilla boons use, so it needs scaling down to "
        .. "match. 0.7 is what a vanilla boon uses for ITS art. Restart the "
        .. "game.",

    GlowBrightnessArtemis = "How bright the three tinted glow layers around "
        .. "Artemis's boon orb are. Goes above 1.0 as well as below. Restart the "
        .. "game.",
    GlowBrightnessAthena = "How bright the three tinted glow layers around "
        .. "Athena's boon orb are. Goes above 1.0 as well as below. Restart the "
        .. "game.",
    GlowBrightnessDionysus = "How bright the three tinted glow layers around "
        .. "Dionysus's boon orb are. Goes above 1.0 as well as below. Restart the "
        .. "game.",
    GlowBrightnessHades = "How bright the three tinted glow layers around Hades's "
        .. "boon orb are. Goes above 1.0 as well as below. Restart the game.",

    EmblemArtArtemis = "Which picture goes inside Artemis's boon orb: \"symbol\" is "
        .. "her emblem, \"portrait\" is her keepsake portrait. Restart the game.",
    EmblemArtAthena = "Which picture goes inside Athena's boon orb: \"symbol\" is "
        .. "her emblem, \"portrait\" is her keepsake portrait. Restart the game.",
    EmblemArtDionysus = "Which picture goes inside Dionysus's boon orb: \"symbol\" "
        .. "is his emblem, \"portrait\" is his keepsake portrait. Restart the game.",
    EmblemArtHades = "Which picture goes inside Hades's boon orb. Only \"symbol\" "
        .. "is available for him -- the keepsake-portrait set has no plain Hades, "
        .. "only the joint Hades-and-Persephone picture. Restart the game.",

    HitboxScalePortrait = "The same, for the gods drawn from a keepsake "
        .. "portrait. Separate because portrait art renders larger than a god "
        .. "symbol at a much lower scale, so one box cannot fit both. Restart "
        .. "the game.",
    HitboxScale = "How big a slot's clickable box is, as a fraction of one grid "
        .. "cell. 1.0 tiles the grid with no gaps, which is what controller "
        .. "stick navigation needs. Lower it and you have to click the icon "
        .. "itself rather than anywhere in its cell -- better with a mouse, and "
        .. "it can leave gaps a controller cannot cross. Restart the game.",
    SelectionHalo = "Draw a soft light behind the icon you have picked, so the "
        .. "choice reads at a glance and not only by size. Reopen the inventory.",
    SelectionHaloStrength = "How bright the picked icon's light is. Low is the "
        .. "point -- it marks the pick without becoming the loudest thing on the "
        .. "page. Reopen the inventory.",
    SelectionHaloTint = "What colour the picked icon's light is. \"neutral\" is "
        .. "a near-white that reads as \"you picked this\"; \"god\" borrows that "
        .. "god's own colour, which is prettier and a little less legible. "
        .. "Reopen the inventory.",
    SelectionHaloTintMix = "How far towards the god's own colour the light goes "
        .. "when tinting. 0 is white, 1 is the raw colour, which is usually too "
        .. "much. Reopen the inventory.",
    SelectionHaloFollowsIcon = "How much the picked light scales with the icon "
        .. "it is behind. 1.0 keeps it looking the same on a big icon and a "
        .. "small one -- a gate that grows when it is on otherwise gets a "
        .. "visibly different light from the same god in the grid. 0 draws every "
        .. "light at one fixed size. Reopen the inventory.",
    SelectionHaloWhiten = "How much whiter each layer of the picked light gets "
        .. "towards the middle. The outermost keeps the god's colour; higher "
        .. "values whiten the inner ones, so where colour turns to white is "
        .. "yours to place rather than wherever the additive blend clips. 0 "
        .. "keeps every layer one colour. Reopen the inventory.",
    SelectionHaloCore = "How bright the innermost layer of the picked light is, "
        .. "the one directly behind the art. Lower it to hollow the middle out "
        .. "and leave a ring: thin or pale icons stay readable inside it. 1.0 "
        .. "is a solid glow. Reopen the inventory.",
    SelectionHaloSpreadStep = "How much bigger each layer of the picked icon's "
        .. "light is than the one before. 0 stacks them all in the same place, "
        .. "which piles brightness into the middle; higher pushes the light out "
        .. "into a ring around the art instead. Reopen the inventory.",
    SelectionHaloSize = "How far the picked icon's light spreads. Reopen the inventory.",
    SelectionHaloLayers = "How many copies of the light are stacked. More is "
        .. "brighter and softer at the edge. Reopen the inventory.",

    HaloStrengthNarcissus = "How strong Narcissus's menu halo is, as a multiplier on "
        .. "the shared halo strength. 1.0 is the same as everyone else. Reopen "
        .. "the inventory.",
    HaloStrengthArachne = "How strong Arachne's menu halo is, as a multiplier on "
        .. "the shared halo strength. 1.0 is the same as everyone else. Reopen "
        .. "the inventory.",
    HaloStrengthCirce = "How strong Circe's menu halo is, as a multiplier on "
        .. "the shared halo strength. 1.0 is the same as everyone else. Reopen "
        .. "the inventory.",
    HaloStrengthEcho = "How strong Echo's menu halo is, as a multiplier on "
        .. "the shared halo strength. 1.0 is the same as everyone else. Reopen "
        .. "the inventory.",
    HaloStrengthIcarus = "How strong Icarus's menu halo is, as a multiplier on "
        .. "the shared halo strength. 1.0 is the same as everyone else. Reopen "
        .. "the inventory.",
    HaloStrengthMedea = "How strong Medea's menu halo is, as a multiplier on "
        .. "the shared halo strength. 1.0 is the same as everyone else. Reopen "
        .. "the inventory.",

    EnableNarcissus = "Whether Narcissus can be picked as the run's first boon. "
        .. "His drop uses a keepsake portrait with a glow added at runtime rather "
        .. "than a painted boon symbol. Restart the game.",

    EnableCirce = "Whether Circe can be picked as the run's first boon. Her drop "
        .. "uses a keepsake portrait with a glow added at runtime rather than a "
        .. "painted boon symbol. Restart the game.",
    EmblemBrightnessCirce = "How bright Circe's portrait is inside the boon orb. "
        .. "Restart the game.",
    GlowBrightnessCirce = "How bright the three tinted glow layers around Circe's boon "
        .. "orb are. Restart the game.",

    EnableEcho = "Whether Echo can be picked as the run's first boon. Her drop "
        .. "uses a keepsake portrait with a glow added at runtime rather than a "
        .. "painted boon symbol. Restart the game.",
    EmblemBrightnessEcho = "How bright Echo's portrait is inside the boon orb. "
        .. "Restart the game.",
    GlowBrightnessEcho = "How bright the three tinted glow layers around Echo's boon "
        .. "orb are. Restart the game.",

    EnableIcarus = "Whether Icarus can be picked as the run's first boon. His drop "
        .. "uses a keepsake portrait with a glow added at runtime rather than a "
        .. "painted boon symbol. Restart the game.",

    EnableMedea = "Whether Medea can be picked as the run's first boon. Her boon "
        .. "was once held responsible for a crash that cost a save "
        .. "during development; the crash was later traced to a Lua-side memory "
        .. "fault with nothing pointing at her, and four deliberate tests since "
        .. "have been clean. See SAVE_RECOVERY.md. Restart the game.",
    EmblemBrightnessMedea = "How bright Medea's portrait is inside the boon orb. "
        .. "Restart the game.",
    GlowBrightnessMedea = "How bright the three tinted glow layers around Medea's boon "
        .. "orb are. Restart the game.",
    EmblemBrightnessIcarus = "How bright Icarus's portrait is inside the boon orb. "
        .. "Restart the game.",
    GlowBrightnessIcarus = "How bright the three tinted glow layers around Icarus's boon "
        .. "orb are. Restart the game.",

    EnableArachne = "Whether Arachne can be picked as the run's first boon. Her "
        .. "drop uses a keepsake portrait with a glow added at runtime. Note "
        .. "that her boons come with a costume, so picking her first changes "
        .. "Melinoe's outfit for the run -- that is how her boons work in the "
        .. "base game, not something this adds. Restart the game.",

    EmblemBrightnessArachne = "How bright Arachne's portrait is inside her boon "
        .. "orb. Above 1.0 pushes it through the glow drawn over it. Restart the "
        .. "game.",

    GlowBrightnessArachne = "How bright the three tinted glow layers around "
        .. "Arachne's boon orb are. Restart the game.",

    EmblemBrightnessNarcissus = "How bright Narcissus's portrait is inside his "
        .. "boon orb. Above 1.0 pushes it through the glow drawn over it. Restart "
        .. "the game.",

    GlowBrightnessNarcissus = "How bright the three tinted glow layers around "
        .. "Narcissus's boon orb are. Restart the game.",

    LogGodCandidates = "Writes one line per NPC that has both a keepsake portrait "
        .. "and a trait pool, naming the traits it would offer. This is how to "
        .. "tell a boon-giver from a costume or gift vendor without guessing. "
        .. "Restart the game.",

    EmblemBrightnessArtemis = "How bright Artemis's emblem is inside her boon orb. "
        .. "1.0 leaves the art alone. Restart the game.",
    EmblemBrightnessAthena = "How bright Athena's emblem is inside her boon orb. "
        .. "Hers carries the most painted glow of the four and washes out at full, "
        .. "so it starts lower. Restart the game.",
    EmblemBrightnessDionysus = "How bright Dionysus's emblem is inside his boon "
        .. "orb. 1.0 leaves the art alone. Restart the game.",
    EmblemBrightnessHades = "How bright Hades's emblem is inside his boon orb. "
        .. "1.0 leaves the art alone. Restart the game.",

    SeleneGlowSource = "Which texture Selene's halo is drawn from. She has no "
        .. "emblem in the game, so her icon is the flat art a door shows and the "
        .. "halo is added underneath it. If one source shows nothing, try the "
        .. "next -- they are listed most-likely first. Reopen the inventory.",

    SeleneGlowStrength = "How bright each layer of Selene's halo is, 0 to 1. 0 "
        .. "turns the halo off entirely. Reopen the inventory.",

    SeleneHaloSpread = "How big Selene's halo is drawn, as a plain scale. This is "
        .. "the number the game uses, not a multiplier on anything else. Around "
        .. "0.2 fills a slot and the range runs up to 1.8, which is well past "
        .. "one. Reopen the inventory.",

    SeleneHaloLayers = "How many copies of the halo are drawn on top of each "
        .. "other. Additive brightness stops at one layer's worth, so this is "
        .. "the only way to make it glow harder than 100%. 1 to 4. Reopen the "
        .. "inventory.",

    TabIconBoost = "Size of the icon on the tab strip itself, as a multiplier on "
        .. "the size the game draws every other tab's icon at. 1.0 is exactly "
        .. "vanilla. Reopen the inventory.",

    BoldGateWords = "Whether \"can\" and \"cannot\" are drawn bold in the two "
        .. "delay lines. Turn off if the braces show up as literal text rather "
        .. "than as formatting.",
    GateStateStyle = "How the two override squares in the bottom-right show "
        .. "whether they are on. \"brightness\" keeps one size and lets "
        .. "brightness carry it; \"size-only\" holds them at the same dimmed "
        .. "level an unpicked boon sits at and lets the size carry it; \"size\" "
        .. "moves both, the way a picked boon does; \"none\" leaves them alone "
        .. "entirely. Reopen the inventory.",

    IconSize = "Size of every icon on the page, as a multiplier. 1.0 is the size "
        .. "the art was registered at. Reopen the inventory.",

    UnselectedBrightness = "How visible the options you have NOT picked are, 0 to 1. "
        .. "The pick is always fully bright. Reopen the inventory.",
    SelectedIconScale = "How much larger the picked icon is drawn than the rest, so "
        .. "the choice reads at a glance. 1.0 draws it the same size. Reopen the "
        .. "inventory.",

    IconBrightness = "Dims every icon, which takes the edge off the glow the god "
        .. "symbols carry. 1.0 leaves them alone; 0.5 is half. Reopen the inventory.",

    IconOffsetY = "How far to nudge every icon down inside its slot. The vanilla "
        .. "grid leaves room under each icon for a quantity number this tab has "
        .. "none of, so 0 looks high. Reopen the inventory.",

    PortraitIconBoost = "Size multiplier for the menu icons of gods who have no "
        .. "emblem and so are drawn from their keepsake portrait. That art is "
        .. "larger than the god symbols beside them, so this mostly wants to go "
        .. "BELOW 1.0. Reopen the inventory.",

    SeleneIconBoost = "Size multiplier for Selene's icon in the \"symbol\" style "
        .. "only, where her art comes from another folder and draws smaller than "
        .. "the god symbols. Ignored in the other styles. Reopen the inventory.",

    TabIconScale = "Size of the icon on the tab itself, and the base size of "
        .. "every icon on the page. 0 falls back to the game's own icons and "
        .. "registers none of ours. Restart the game.",

    TabButtonBoxWidth = "Width of a tab button's clickable box, in screen units. "
        .. "0 derives it from the screen's own grid spacing, which is almost "
        .. "always what you want. Restart the game.",

    TabButtonBoxHeight = "Height of a tab button's clickable box, in screen "
        .. "units. 0 derives it from the screen's own grid spacing, which is "
        .. "almost always what you want. Restart the game.",

    HighlightStyle = "What hovering a button does. \"frame\" draws the slot frame "
        .. "every vanilla tab uses. \"grow\" draws no frame at all and lets the icon "
        .. "growing be the only signal, as PonyMenu does. Reopen the inventory.",
    HighlightOffsetY = "Nudge the hover frame up or down independently of the icon. "
        .. "0 keeps it on the slot, which is where the background art draws the "
        .. "slot outline. Reopen the inventory.",

    EnableArtemis = "Offer Artemis as a first-boon option. She is NOT added to the "
        .. "run: her drop can only ever be the very first reward, never appears in "
        .. "shops, and meeting her in the world is untouched. Restart the game.",
    EnableAthena = "Offer Athena as a first-boon option, on the same terms as Artemis. Restart the game.",
    EnableDionysus = "Offer Dionysus as a first-boon option, on the same terms as Artemis. Restart the game.",
    EnableHades = "Offer Hades as a first-boon option, on the same terms as Artemis. Restart the game.",

    LogDecisions = "Write one line to the ReturnOfModding log for each decision "
        .. "this plugin makes, and each one it declines to make.",

    VerboseTabLog = "Log the tab's layout, hovers and clicks in detail. For "
        .. "diagnosing a display problem, not for everyday play.",
}


-- =============================================================================
-- NATIVE INVENTORY TAB
-- =============================================================================
--
-- The game supports custom inventory tabs outright. InventoryScreenDisplayCategory
-- (ResourceLogic.lua:438) ends with:
--
--     if category.OpenFunctionName ~= nil then
--         CallFunctionName( category.OpenFunctionName, screen )
--         return
--     end
--
-- and its cleanup path (line 381) calls prevCategory.CloseFunctionName the same
-- way. Two shipped tabs already rely on this -- InventoryScreen_PinTab and
-- InventoryScreen_LineHistoryTab (ResourceData.lua:4210 and :4234) -- so this is
-- a supported mechanism rather than a discovered one.
--
-- That matters because PonyMenu, the obvious template, does NOT use it: it does
-- ModUtil.Path.Override("InventoryScreenDisplayCategory", ...) with a full copy
-- of the vanilla function plus four small edits, and draws its menu inside that
-- copy. An override of a 200-line render function goes stale on any game patch
-- and collides with any other mod touching the same function. Adding a category
-- with OpenFunctionName costs one table.insert and overrides nothing.
--
-- Compatibility with PonyMenu was checked directly: its copy preserves the
-- OpenFunctionName branch, so this tab works whether or not PonyMenu is loaded.
--
-- Three mechanics worth recording:
--
--   * CallFunctionName resolves through _G (EventLogic.lua:66), so the two
--     handlers must be assigned onto rom.game, not left in this plugin's ENVY
--     scope where the game cannot see them.
--   * OpenInventoryScreen does `local screen = DeepCopyTable( screenData )`
--     (ResourceLogic.lua:228), so inserting the category once at load is picked
--     up by every subsequent open.
--   * table.insert on rom.game's proxied tables is safe here. A previous plugin
--     hit "Optional has no value" errors reading proxied game data with pairs()
--     and #, so this is not free of doubt in general -- but PonyMenu performs
--     this exact insert on this exact table, which is direct evidence.
--
-- STEP 1 IS READ-ONLY ON PURPOSE. None of this can be exercised by the test
-- harness -- screen components, animations and gamepad navigation are all
-- render-side. So step 1 proves only the plumbing: that the tab appears, opens,
-- draws text, and cleans up. It writes text into the screen's existing
-- EmptyCategoryHint component (ResourceData.lua:4545, centred at 620,480)
-- rather than creating components of its own, so there is as little new
-- machinery as possible between "it works" and "it doesn't". Buttons come in
-- step 2, once this much is confirmed in game.
--
-- If the tab misbehaves badly enough to break the inventory screen, set
-- ShowInventoryTab = false in Adicon-SelectFirstBoon.cfg and relaunch. The
-- category is inserted at load, so that setting only takes effect on restart.

local TAB_CATEGORY_NAME = "First Boon"
local TAB_OPEN_FN = "SelectFirstBoon_InventoryTabOpen"
local TAB_CLOSE_FN = "SelectFirstBoon_InventoryTabClose"
local TAB_PICK_FN = "SelectFirstBoon_InventoryTabPick"
local TAB_OVER_FN = "SelectFirstBoon_InventoryTabOver"
local TAB_OFF_FN = "SelectFirstBoon_InventoryTabOff"

-- The tab icon is an ANIMATION name, not a texture path: the tab bar does
-- SetAnimation({ DestinationId = categoryButtonIcon.Id, Name = category.Icon })
-- at ResourceLogic.lua:290, scaled by CategoryIconScale = 0.45.
--
-- v2.2.0 used "GUI\\Screens\\Inventory\\Icon-Log", which is the dialogue
-- tab's own icon, so the two were indistinguishable. All six vanilla inventory
-- icons (Resources, Reagents, Gifts, Fish, ForgetMeNots, Log) are already spoken
-- for, and PonyMenu has taken GUI\Screens\Codex\Icon-Unseen, so the icon has
-- to come from somewhere else.
--
-- It comes from LootData[god].Icon rather than a hardcoded list, so the tab
-- shows the god it is currently set to and a god added by a future patch works
-- with no change here. With no god chosen it shows BoonSymbolChaos -- apt, since
-- Chaos is thematically the god of randomness.
--
-- WHY THIS FIELD AND NOT BoonInfoIcon
--
-- Resolved by reading Content/Game/Animations/GUI_Screens_VFX.sjson, not by
-- guessing at art. The two candidate fields point at completely different sets:
--
--   LootData[god].Icon         -> BoonSymbol<God>
--                                 InheritFrom "BoonSymbolBase", Scale = 1,
--                                 FilePath GUI\Screens\BoonSelectSymbols\<God>
--
--   LootData[god].BoonInfoIcon -> BoonInfoSymbol<God>Icon
--                                 InheritFrom "BoonInfoSymbolBase", Scale = 1.3,
--                                 FilePath Items\Loot\Boon\<God>IconSpin\<God>IconSpin0015
--
-- BoonInfoIcon resolves to frame 15 of the spinning icon that hovers over a boon
-- lying on the ground. Those are per-god animation frames, never designed as a
-- matched icon set, which is exactly why v2.2.1-2.2.3 rendered each god at a
-- different size. BoonSelectSymbols is a purpose-made set -- one folder, one
-- scale, every god -- drawn for the boon-choice screen where symbols must sit
-- together and match.
--
-- Two other rejected alternatives, recorded so they are not retried:
--
--   * "GUI\\Screens\\Inventory\\Icon-Log" (v2.2.0) is the dialogue tab's own
--     icon, so the two tabs were indistinguishable.
--   * The Keepsake_<God> family (v2.2.2) is not symbol art at all --
--     Keepsake_Hephaestus is the god's PORTRAIT, Keepsake_Random a pink ribbon.
--
-- v2.2.4 used LootData[god].Icon -> BoonSymbol<God>, which is the uniform art,
-- but it inherits BoonSymbolBase and that base carries Loop = true,
-- Duration = 2.5 and PingPongShiftOverDuration with EndOffsetZ = 5.0. In a tab
-- that reads as a large glowing icon bobbing up and down. Reverted.
--
-- So the two shipped sets each have one half of what a tab icon needs:
--
--   BoonInfoSymbol<God>Icon  static (NumFrames = 1) but per-god spin frames,
--                            so the gods do not match each other in size
--   BoonSymbol<God>          uniform BoonSelectSymbols art, but animated
--
-- Neither is right on its own. The proper fix is a custom static animation
-- pointing at the uniform art -- which is precisely the recipe
-- BoonInfoSymbolBase already uses (FilePath GUI\Screens\BoonSelectSymbols\Zeus
-- with NumFrames = 1) -- registered through an sjson hook. Pending a decision;
-- until then this uses the static set and accepts the size variance.
local DEFAULT_TAB_ICON = "BoonInfoSymbolChaosIcon"
-- Chaos used to stand in for "no pick", which stops working the moment Chaos is
-- something you can pick: the tab would show the same picture for Standard and
-- for Chaos. BoonBackingA is the plate the boon-choice screen draws BEHIND a
-- god symbol (GUI_Screens_VFX.sjson:8171) -- from the same folder, so it matches
-- the others for size and glow, and it is the one image in that set that is not
-- anybody. A frame with no god in it is a fair picture of "leave it alone".
-- BoonBackingA was the reasoned choice and it came back wrong on screen -- which
-- is the risk with any of these: they are art nobody has drawn for this purpose,
-- judged from a filename. So this is a list to step through rather than a verdict.
--
-- Pom leads because it is the safest bet, not the cleverest: it is a real
-- BoonSelectSymbols icon that certainly renders at this size with the right glow,
-- it is not a god, and nothing else in this menu uses it -- the Pom of Power is
-- not an option here, so there is no collision to worry about. The backings are
-- the plates the boon-choice screen draws behind a symbol; B and C are the other
-- two layers of the same chain and may well behave differently from A.
local STANDARD_ICON_PRESETS = {
    { value = "pom",       symbol = "Pom",          label = "Pomegranate" },
    { value = "pom-flat",  symbol = "PomFlat",      label = "Pomegranate (flat, no glow)" },
    { value = "chaos",     symbol = "Chaos",        label = "Chaos symbol (what it used to be)" },
    { value = "backing-a", symbol = "BoonBackingA", label = "Backing plate A" },
    { value = "backing-b", symbol = "BoonBackingB", label = "Backing plate B" },
    { value = "backing-c", symbol = "BoonBackingC", label = "Backing plate C" },
    { value = "hammer",    symbol = "Hammer",       label = "Hammer symbol" },
}

local function standardSymbol()
    local chosen = settings.values.StandardIcon
    for _, preset in ipairs(STANDARD_ICON_PRESETS) do
        if preset.value == chosen then return preset.symbol end
    end
    return "Pom"
end

-- Reward-store entry name -> the setting that gates it. These are reward TYPES,
-- not gods: LootData_Hermes.lua has GodLoot = false, and Selene's reward is
-- SpellDrop, so neither can ever come out of ChooseLoot for a "Boon".
local GATED_REWARDS = {
    HermesUpgrade = "BlockHermesBeforeBoon",
    SpellDrop     = "BlockSeleneBeforeBoon",
}

-- What counts as "you hold a boon". Same list DisableSeleneBeforeBoon and
-- NoHermesFirstBoon use, WeaponUpgrade (a Daedalus hammer) included.
local COUNTS_AS_A_BOON = {
    "AphroditeUpgrade", "ApolloUpgrade", "AresUpgrade", "DemeterUpgrade",
    "HephaestusUpgrade", "HeraUpgrade", "HestiaUpgrade", "PoseidonUpgrade",
    "ZeusUpgrade", "WeaponUpgrade",
}

local BLOCK_LOG_FIELD = "SelectFirstBoon_BlockLogged"

-- These are the primitives Chalk itself is built on (see its main.lua): bind a
-- key with a default, read it with :get(), write it with :set(), flush with
-- :save(). Going straight to them means no second file to import and no
-- dependency on how the plugin folder's name maps back to a path on disk.
local function loadSettings()
    local ok, err = pcall(function()
        if rom.config == nil or rom.config.config_file == nil then
            logWarn("rom.config unavailable; settings will not persist between sessions")
            return
        end
        local configDir = rom.paths and rom.paths.config and rom.paths.config() or nil
        if configDir == nil then
            logWarn("config directory unavailable; settings will not persist between sessions")
            return
        end

        local guid = (_PLUGIN and _PLUGIN.guid) or "Adicon-SelectFirstBoon"
        local path = rom.path.combine(configDir, guid .. ".cfg")
        local file = rom.config.config_file:new(path, true)

        for key, default in pairs(settings.values) do
            settings.entries[key] = file:bind(CONFIG.sectionFor(key), key, default, CONFIG_DESCRIPTIONS[key] or "")
        end

        -- Only adopt a stored value whose type matches the default, so a
        -- hand-edited .cfg cannot put a string where a boolean is expected.
        for key, entry in pairs(settings.entries) do
            local stored = entry:get()
            if type(stored) == type(settings.values[key]) then
                settings.values[key] = stored
            end
        end

        settings.file = file
        settings.persistent = true
    end)

    if not ok then
        logWarn("config load failed, using in-memory settings: " .. tostring(err))
    end
end

local function saveSetting(key, value)
    settings.values[key] = value

    local entry = settings.entries[key]
    if entry == nil then return end

    local ok, err = pcall(function()
        entry:set(value)
        if settings.file ~= nil and type(settings.file.save) == "function" then
            settings.file:save()
        end
    end)
    if not ok then
        logWarn("failed to persist " .. tostring(key) .. ": " .. tostring(err))
    end
end

-- The pick is stored in the config file, so without this it survives closing the
-- game -- which is right for a preference and wrong for a choice about one run.
-- Default is to forget: the game starts vanilla, and picking a god is a thing
-- you do on purpose each session rather than something left switched on from
-- last night. Turning KeepPickAfterRestart on restores the old behaviour.
--
-- Runs at boot, before the UI is built, so the menu opens showing what the game
-- will actually do.
local function resetPickOnLaunch()
    if settings.values.KeepPickAfterRestart == true then
        if settings.values.God ~= NONE_VALUE then
            logAlways("keeping last session's pick: " .. tostring(settings.values.God))
        end
        return
    end
    if settings.values.God == NONE_VALUE then return end

    local previous = settings.values.God
    saveSetting("God", NONE_VALUE)
    logAlways("first boon reset to Standard for this session (was "
        .. tostring(previous) .. "); turn on \"Keep my pick after a restart\" to stop this")
end

-- =============================================================================
-- God catalog
-- =============================================================================

local catalog = {
    names = {},        -- ordered list of LootData keys
    labels = {},       -- LootData key -> display name
    index = {},        -- LootData key -> true
}

-- GodsAPI defaults SpeakerName to "<plugin guid>-<GodName>" (its main.lua:248),
-- and a mod only gets a clean name here if it overrides that through ExtraFields
-- -- Droppable Gods does, but nothing forces it to. So a namespaced name gets
-- its last segment taken, which is the god's real name in every scheme seen so
-- far. Vanilla loot names contain no dash, so vanilla is untouched.
local function stripNamespace(name)
    if type(name) ~= "string" then return name end
    local tail = string.match(name, "^.*%-(.+)$")
    return tail or name
end

local function displayNameFor(game, lootName)
    local lootData = game.LootData and game.LootData[lootName] or nil
    if lootData ~= nil and type(lootData.SpeakerName) == "string" and lootData.SpeakerName ~= "" then
        return stripNamespace(lootData.SpeakerName)
    end
    -- Every god key in LootData_*.lua is "<Name>Upgrade".
    local stripped = string.match(lootName, "^(.-)Upgrade$")
    return stripNamespace(stripped or lootName)
end

local function collectGods(game, applyDebugOnlyFilter)
    local found = {}
    if type(game.LootData) ~= "table" then return found end
    for lootName, lootData in pairs(game.LootData) do
        if type(lootName) == "string" and type(lootData) == "table" and lootData.GodLoot == true then
            if not applyDebugOnlyFilter or not lootData.DebugOnly then
                found[#found + 1] = lootName
            end
        end
    end
    return found
end

-- Load order between two plugins' once_loaded.game callbacks is not defined, and
-- a plugin that adds gods registers in its own. Building the catalog once at load
-- is therefore a coin flip: if the other plugin runs second, its gods are missing
-- from this one's list until the next launch.
--
-- So the catalog is also rebuilt on demand, at the two moments a stale list would
-- actually be seen -- opening the tab, and opening the settings window. Both are
-- rare user actions, so the cost is irrelevant, and the count check means a
-- rebuild only happens when the answer has genuinely changed.
local function countGodLoot(game)
    if type(game.LootData) ~= "table" then return 0 end
    local n = 0
    for lootName, lootData in pairs(game.LootData) do
        if type(lootName) == "string" and type(lootData) == "table" and lootData.GodLoot == true then
            n = n + 1
        end
    end
    return n
end

local function buildCatalog(game)
    local names, source = collectGods(game, true), "LootData (GodLoot, not DebugOnly)"

    if #names == 0 then
        names, source = collectGods(game, false), "LootData (GodLoot only; DebugOnly filter emptied the list)"
    end
    if #names == 0 then
        names, source = {}, "static fallback list"
        for _, n in ipairs(FALLBACK_GODS) do names[#names + 1] = n end
    end

    catalog.names, catalog.labels, catalog.index = {}, {}, {}
    for _, lootName in ipairs(names) do
        catalog.labels[lootName] = displayNameFor(game, lootName)
        catalog.index[lootName] = true
        catalog.names[#catalog.names + 1] = lootName
    end
    table.sort(catalog.names, function(a, b)
        return (catalog.labels[a] or a) < (catalog.labels[b] or b)
    end)

    catalog.godLootCount = countGodLoot(game)
    -- Whether this list is authoritative. The static fallback fires when LootData
    -- is not readable yet, and a pick must never be judged against a guess.
    catalog.fromLootData = (source ~= "static fallback list")
    logAlways("god catalog built from " .. source .. ": " .. #catalog.names .. " entries")

    -- A god saved by a previous version, typed into the .cfg by hand, or removed
    -- from this plugin between versions (Medea, v4.25.0) would otherwise sit in
    -- the config forever: every guard downstream declines it silently, so the
    -- menu would show a pick that can never fire. Clear it, and only against a
    -- real LootData read -- never against the fallback list.
    local chosen = settings.values.God
    if chosen ~= NONE_VALUE and specialFor(chosen) == nil and not catalog.index[chosen] then
        if catalog.fromLootData then
            saveSetting("God", NONE_VALUE)
            logWarn("configured god '" .. tostring(chosen) .. "' no longer exists; reset to Standard")
        else
            logWarn("configured god '" .. tostring(chosen)
                .. "' is not in the fallback list; leaving it alone until LootData can be read")
        end
    end
end

-- Safe to call from anywhere: it only does work when the number of god loots has
-- changed since the last build, and it never lets a failure escape -- a stale
-- list is a much smaller problem than a screen that will not open.
local function refreshCatalog(game)
    if game == nil then return end
    local ok, changed = pcall(function()
        local now = countGodLoot(game)
        if now == catalog.godLootCount then return false end
        buildCatalog(game)
        return true
    end)
    if not ok then
        logWarn("could not refresh the god catalog, keeping the current one: " .. tostring(changed))
        return
    end
    if changed then
        logAlways("god catalog refreshed -- another plugin has added or removed gods")
    end
end

-- =============================================================================
-- Logic  (unchanged from Phase 1 except that the god is read from settings)
-- =============================================================================

-- Rebuild the exclusion list exactly as RewardLogic.lua:230-237 does. One
-- difference: vanilla calls table.insert unguarded, relying on the engine
-- tolerating a nil. We skip nils explicitly -- semantically identical, since a
-- nil was never going to match a god name, but it cannot throw.
local function buildExcludeLootNames(previouslyChosenRewards)
    local excludeLootNames = {}
    if previouslyChosenRewards ~= nil then
        for _, data in pairs(previouslyChosenRewards) do
            if data ~= nil and data.RewardType == "Boon" and data.ForceLootName ~= nil then
                table.insert(excludeLootNames, data.ForceLootName)
            end
        end
    end
    return excludeLootNames
end

-- Would a real equipped keepsake have claimed this reward? Same test vanilla
-- runs at RewardLogic.lua:241-248. If yes, we stand down: an actual keepsake the
-- player chose to equip outranks a dropdown setting.
local function keepsakeWouldClaim(game, currentRun, excludeLootNames)
    local hero = currentRun.Hero
    if hero == nil or hero.Traits == nil then return nil end
    for _, trait in ipairs(hero.Traits) do
        if trait ~= nil and trait.ForceBoonName ~= nil and trait.Uses ~= nil and trait.Uses > 0
            and not game.Contains(excludeLootNames, trait.ForceBoonName) then
            return trait.ForceBoonName
        end
    end
    return nil
end

-- A keepsake and this plugin want the same thing, and before 3.1.0 they could
-- both get it. The deference below was per OFFER: a keepsake claimed room 1, the
-- plugin stood down for that offer, and then room 2 saw a spent keepsake
-- (GiveLoot drops Uses to 0) and forced a second god. Two guaranteed gods at the
-- start of a run, which is one more than this plugin is for -- and 3.0.0 made it
-- worse, since the keepsake and the plugin would each push a "Boon" priority and
-- the first TWO rewards would both be boons.
--
-- So the stand-down is per RUN, and it latches. Latching is the whole point:
-- checking live would unlatch in room 2 the moment the keepsake was spent.
local function standDownForKeepsake(game, currentRun)
    if not settings.values.KeepsakeWins then return false end
    if currentRun == nil then return false end
    if currentRun[KEEPSAKE_FIELD] ~= nil then return currentRun[KEEPSAKE_FIELD] end

    local claimed = nil
    local hero = currentRun.Hero
    if hero ~= nil and hero.Traits ~= nil then
        for _, trait in ipairs(hero.Traits) do
            if trait ~= nil and trait.ForceBoonName ~= nil and trait.Uses ~= nil and trait.Uses > 0 then
                claimed = trait.ForceBoonName
                break
            end
        end
    end

    currentRun[KEEPSAKE_FIELD] = claimed ~= nil
    if claimed ~= nil then
        logAlways("standing down for this run: the equipped keepsake forces "
            .. tostring(claimed) .. " and an equipped keepsake outranks a menu pick")
    end
    return claimed ~= nil
end

-- The same question as standDownForKeepsake, asked without answering it: no
-- latch, no write. Used only to say so on screen. Keeping the two separate
-- matters -- reading the panel must never decide anything about the run, and a
-- player who opened the inventory before the first room and then swapped
-- keepsakes would otherwise have been latched by having looked.
local function equippedForcedGod(game)
    if not settings.values.KeepsakeWins then return nil end
    local currentRun = game ~= nil and game.CurrentRun or nil
    if currentRun == nil then return nil end
    -- Once the run has latched, report what it decided rather than what is
    -- equipped now: the keepsake may already have been spent.
    if currentRun[KEEPSAKE_FIELD] == false then return nil end
    local hero = currentRun.Hero
    if hero == nil or hero.Traits == nil then return nil end
    for _, trait in ipairs(hero.Traits) do
        if trait ~= nil and trait.ForceBoonName ~= nil then
            if (trait.Uses ~= nil and trait.Uses > 0) or currentRun[KEEPSAKE_FIELD] == true then
                return trait.ForceBoonName
            end
        end
    end
    return nil
end

-- Runs AFTER vanilla SetupRoomReward has already picked a god, so every decision
-- vanilla makes is intact; we only replace the final room.ForceLootName
-- assignment from RewardLogic.lua:258.
local function applyForcedGod(game, currentRun, room, previouslyChosenRewards, args, forceLootNameBeforeBase)
    local desiredGod = settings.values.God
    if desiredGod == nil or desiredGod == NONE_VALUE then return end
    if not catalog.index[desiredGod] then return end

    if room == nil then return end

    currentRun = currentRun or game.CurrentRun
    if currentRun == nil then return end

    if currentRun[USED_FIELD] then return end
    if standDownForKeepsake(game, currentRun) then return end

    args = args or {}

    local chosenRewardType = args.ChosenRewardType or room.ChosenRewardType
    if chosenRewardType ~= "Boon" then return end

    -- Vanilla's entry guard, RewardLogic.lua:228. If ForceLootName was already
    -- set on the way in, vanilla skipped its whole boon block -- something else
    -- (a room's ForcedRewards table, a bounty, a story beat) already decided
    -- which god this is.
    --
    -- AlwaysFirst walks through it anyway. That is the destructive option and it
    -- ships off: a Chaos Trial built around opening with Hera stops working, and
    -- silently, because the run still plays. It exists because the alternative
    -- reads as the mod being broken -- you named a first boon, the game handed
    -- you something else, and nothing said why.
    if not (args.AlwaysSetupForceLootName or not forceLootNameBeforeBase) then
        if settings.values.AlwaysFirst then
            logAlways("overriding a pre-forced reward ("
                .. tostring(forceLootNameBeforeBase) .. ") because AlwaysFirst is on"
                .. " -- scripted encounters like Chaos Trials will not play as designed")
        else
            log("declined: ForceLootName was already " .. tostring(forceLootNameBeforeBase) .. " on entry (pre-forced reward)")
            return
        end
    end

    -- Vanilla's keepsake guard, RewardLogic.lua:240. Callers that pass this are
    -- explicitly asking for an unforced boon.
    if args.IgnoreForceLootName then
        log("declined: caller passed IgnoreForceLootName")
        return
    end

    local currentRoom = currentRun.CurrentRoom
    if currentRoom ~= nil and (currentRoom.DeferReward or currentRoom.PersistentExitDoorRewards) then
        log("declined: current room re-offers a previously promised reward (DeferReward / PersistentExitDoorRewards)")
        return
    end

    local excludeLootNames = buildExcludeLootNames(previouslyChosenRewards)

    -- Another door in this same unlock already took our god. Vanilla's keepsake
    -- stands down here too, which is what stops two doors showing the same god.
    if game.Contains(excludeLootNames, desiredGod) then
        log("declined: " .. desiredGod .. " already offered by another door in this unlock")
        return
    end

    local keepsakeGod = keepsakeWouldClaim(game, currentRun, excludeLootNames)
    if keepsakeGod ~= nil then
        log("declined: equipped keepsake is forcing " .. tostring(keepsakeGod) .. " and takes priority")
        return
    end

    if settings.values.RespectEligibility then
        local eligible = game.GetEligibleLootNames(excludeLootNames)
        if not game.Contains(eligible, desiredGod) then
            log("declined: " .. desiredGod .. " is not currently eligible (GameStateRequirements unmet, or max gods reached)")
            return
        end
    end

    local replaced = room.ForceLootName
    room.ForceLootName = desiredGod
    room.ForcedBoonNames = room.ForcedBoonNames or {}
    room.ForcedBoonNames[desiredGod] = true

    log("forced first boon to " .. desiredGod .. " (vanilla had rolled " .. tostring(replaced) .. ")")
end

-- Consumption, mirroring RoomLogic.lua:2058-2069. The forced boon is spent when
-- a boon of that god actually spawns in the world -- not when a door offers it,
-- and not when the player picks it up. Shop purchases do not consume, exactly as
-- vanilla's `if not args.BoughtFromShop` excludes them.
local function markSpawned(game, args, loot)
    local desiredGod = settings.values.God
    if desiredGod == nil or desiredGod == NONE_VALUE then return end

    local currentRun = game.CurrentRun
    if currentRun == nil or currentRun[USED_FIELD] then return end
    if loot == nil or loot.Name ~= desiredGod then return end
    if args ~= nil and args.BoughtFromShop then return end

    currentRun[USED_FIELD] = true
    log(desiredGod .. " boon spawned; plugin is done for this run")

    -- RNG DIAGNOSTIC (v4.31.0)
    --
    -- Reported: with a god picked, re-rolling the run seed gives the same three
    -- trait options every time, only their rarity moving. Vanilla with a keepsake
    -- does not behave that way.
    --
    -- The trait roll is a pure function of NextSeeds[1] and the loot's trait list
    -- (CreateLoot calls RandomSynchronize with no offset, and RandomSynchronize
    -- RESEEDS from NextSeeds rather than advancing a stream -- RandomLogic.lua:66).
    -- So there are two candidate explanations and this tells them apart without
    -- anyone having to guess:
    --
    --   NextSeeds[1] identical across runs  -> the reseed is not happening
    --   DebugRNGSeed non-zero               -> Rng:Seed is overriding every seed
    --                                          with a fixed one (RandomLogic:11),
    --                                          which is nothing to do with us
    --
    -- Logged unconditionally rather than behind VerboseTabLog: it is three lines
    -- once per run, and the whole point is that it is there when someone reports
    -- this without having to ask them to switch something on first.
    local ok, err = pcall(function()
        local seed = "unreadable"
        if type(game.NextSeeds) == "table" and game.NextSeeds[1] ~= nil then
            seed = tostring(game.NextSeeds[1])
        end

        local debugSeed = "unreadable"
        if type(game.GetConfigOptionValue) == "function" then
            debugSeed = tostring(game.GetConfigOptionValue({ Name = "DebugRNGSeed" }))
        end

        local offered = {}
        if type(loot.UpgradeOptions) == "table" then
            for _, option in ipairs(loot.UpgradeOptions) do
                offered[#offered + 1] = tostring(option.ItemName or option.Name or "?")
                    .. (option.Rarity and (":" .. tostring(option.Rarity)) or "")
            end
        end

        logAlways("[rng] NextSeeds[1]=" .. seed
            .. "  DebugRNGSeed=" .. debugSeed
            .. "  NumRerolls=" .. tostring(currentRun.NumRerolls))
        logAlways("[rng] offered: " .. (#offered > 0 and table.concat(offered, ", ")
            or "(UpgradeOptions not set on the loot at spawn time)"))
    end)
    if not ok then
        logWarn("rng diagnostic failed, ignoring: " .. tostring(err))
    end
end

-- =============================================================================
-- Reward priority  (what makes the pick land on the FIRST reward)
-- =============================================================================

-- The priority name for the current selection, or nil if there is nothing to
-- push. A special contributes its own reward type; a god contributes "Boon",
-- which is what a god keepsake pushes.
local function priorityNameFor()
    local chosen = settings.values.God
    if chosen == nil or chosen == NONE_VALUE then return nil end

    local special = specialFor(chosen)
    if special ~= nil then return special.reward, special end

    -- NOT gated on AlwaysFirst. Pushing "Boon" only schedules a boon reward, the
    -- same thing an equipped keepsake does; it decides nothing about WHICH god,
    -- and it overrides nothing. AlwaysFirst governs the separate question of
    -- walking through a reward the game already forced, and it is applied where
    -- that decision is actually made.
    --
    -- These were briefly the same flag. With AlwaysFirst off by default that
    -- stopped the push entirely, so with a keepsake equipped the keepsake took
    -- the one scheduled boon and the pick waited for a second boon nothing had
    -- asked for. Two guaranteed gods is the whole point of KeepsakeWins = false.
    if not catalog.index[chosen] then return nil end
    return "Boon", nil
end

-- Call the game's own RewardStoreAddPriority rather than reimplement it: it also
-- tops the store up when the name is not currently in the carousel
-- (RewardLogic.lua:518-532), and reimplementing that would be one more thing to
-- drift out of sync with a patch. Vanilla defaults the store to "RunProgress";
-- we pass the store ChooseRoomReward is actually reading, so the top-up lands in
-- the right carousel when a room draws from a different one.
--
-- Once per run. ChooseRoomReward recurses on an empty store (RewardLogic.lua
-- :154) and is called once per door, so the guard has to be idempotent, and it
-- has to live on CurrentRun so a save-and-quit cannot push a second copy.
local function addRewardPriority(game, currentRun, rewardStoreName)
    if currentRun == nil then return end
    if currentRun[PRIORITY_FIELD] then return end
    if currentRun[USED_FIELD] then return end
    -- Latched here as well as in applyForcedGod: ChooseRoomReward runs first, and
    -- the keepsake's own "Boon" priority must not be doubled by ours.
    if standDownForKeepsake(game, currentRun) then
        currentRun[PRIORITY_FIELD] = true
        return
    end

    local priorityName, special = priorityNameFor()
    if priorityName == nil then return end

    if type(game.RewardStoreAddPriority) ~= "function" then
        logWarn("RewardStoreAddPriority unavailable; the pick will apply whenever "
            .. priorityName .. " next comes up rather than first")
        currentRun[PRIORITY_FIELD] = true
        return
    end

    currentRun[PRIORITY_FIELD] = true
    game.RewardStoreAddPriority({ Name = priorityName, RewardStoreName = rewardStoreName })

    if special ~= nil then
        log("queued " .. priorityName .. " (" .. special.label .. ") as this run's first reward")
    else
        log("queued Boon as this run's first reward, the way an equipped keepsake does")
    end
end

-- =============================================================================
-- Never-first gating
-- =============================================================================

-- Mirrors the PathTrue guard the replaced modules rely on: RequirementsLogic.lua
-- :170-177 treats a missing or falsy value as failure, and an empty table as
-- truthy. A run with no pickups yet has an empty LootTypeHistory, not a nil one
-- (RunLogic.lua:398), but guarding costs nothing.
local function hasBoonThisRun(currentRun)
    local history = currentRun and currentRun.LootTypeHistory
    if type(history) ~= "table" then return false end
    for _, name in ipairs(COUNTS_AS_A_BOON) do
        if history[name] then return true end
    end
    return false
end

-- IsRoomRewardEligible runs for every entry in the store on every roll, dozens
-- of times per door, so this logs the first block of each reward per run and
-- then stays quiet. The record lives on CurrentRun, so it resets with the run.
local function noteBlocked(currentRun, rewardName)
    local logged = currentRun[BLOCK_LOG_FIELD]
    if logged == nil then
        logged = {}
        currentRun[BLOCK_LOG_FIELD] = logged
    end
    if logged[rewardName] then return end
    logged[rewardName] = true
    log("holding " .. rewardName .. " out of the reward pool -- no boon taken yet this run")
end

-- The gates and the specials are the same two reward types seen from opposite
-- ends, so picking Hermes or Selene first while its gate is on would have the
-- plugin fight itself: the priority is queued, then this wrap makes the reward
-- ineligible and the priority never fires. Choosing one suppresses its own gate
-- for as long as it is chosen. The gate setting is left alone rather than
-- rewritten, so unpicking restores it without the user having to.
local function gateSuppressedBy(rewardName)
    local special = specialFor(settings.values.God)
    if special == nil then return false end
    return special.reward == rewardName
end

local function shouldBlockReward(game, reward)
    if type(reward) ~= "table" then return false end

    local settingKey = GATED_REWARDS[reward.Name]
    if settingKey == nil then return false end
    if not settings.values[settingKey] then return false end

    if gateSuppressedBy(reward.Name) then
        local currentRun = game.CurrentRun
        if currentRun ~= nil then
            local logged = currentRun[BLOCK_LOG_FIELD]
            if logged == nil then logged = {}; currentRun[BLOCK_LOG_FIELD] = logged end
            if not logged["suppress:" .. reward.Name] then
                logged["suppress:" .. reward.Name] = true
                log("ignoring the " .. settingKey .. " gate: " .. reward.Name
                    .. " is the first reward you asked for")
            end
        end
        return false
    end

    local currentRun = game.CurrentRun
    if currentRun == nil then return false end
    if hasBoonThisRun(currentRun) then return false end

    noteBlocked(currentRun, reward.Name)
    return true
end

-- =============================================================================
-- ARTEMIS  (a first-reward-only boon god)
-- =============================================================================
--
-- Artemis already gives boons in vanilla: you meet her in the field, she offers
-- one of three from a trait list, exactly as an Olympian does. What she has no
-- version of is a boon lying on the ground for a door to promise -- because
-- nothing in vanilla ever creates one.
--
-- That gap is a single missing table. The pipeline is:
--
--     CreateLoot({ Name = X })  ->  builds the loot from LootData[X]
--                               ->  HandleLootPickup      (InteractLogic.lua:693)
--                               ->  OpenUpgradeChoiceMenu (InteractLogic.lua:733)
--
-- and there is no LootData.ArtemisUpgrade for CreateLoot to build from. So we
-- add one. Everything of substance in it points at things the base game already
-- ships -- the trait pool from her own NPC unit, her emblem, her menu title,
-- her portrait, her colours. We are wiring, not authoring.
--
-- THREE PROMISES THIS KEEPS, and each is a specific line below:
--
--   1. She is never a shop item. TreatAsGodLootByShops is left unset and no
--      StoreData entry is added, which is where GodsAPI would have put her.
--   2. She can only ever be the run's FIRST reward. FIRST_REWARD_ONLY below is
--      a GameStateRequirement checked by IsGameStateEligible, which
--      GetEligibleLootNames runs (RewardLogic.lua:187-200). Once any boon is in
--      LootTypeHistory she stops being eligible, for the rest of the run.
--   3. Meeting her in the world is untouched. That path runs off
--      EnemyData.NPC_Artemis_Field_01, a different table, which this never
--      writes to. She shows up where she always did and behaves as she always
--      did -- including still offering boons after her drop was taken, since
--      the two are separate objects.
-- The four NPC gods that already give a 1-of-3 boon choice in vanilla and have a
-- BoonSelectSymbols emblem in the base game. Those two facts together are the
-- whole entry requirement, and they are exactly why these four and no others:
-- Narcissus, Arachne, Circe, Echo, Medea and Icarus have the trait pool but no
-- emblem, so they would need art that does not exist.
--
-- Colours are the drop's glow layers, in the game's own 0-1 named-channel form,
-- written straight through: dropA is what BoonDropA-<loot> gets, and so on down
-- to the emblem. Up to 4.11.0 A and B were swapped on the way in -- inherited
-- from Droppable Gods' table shape -- which made this block impossible to read
-- against the vanilla entries it is copying.
--
-- THE VANILLA PATTERNS, plural. 4.12.0's comment here claimed the innermost
-- layer ALWAYS contrasts. That was overstated -- it is true of five gods and
-- false of three, and the three are the ones worth copying here:
--
--   Contrasting        Zeus      orange  -> orange -> GREEN   (:5859, :5871, :5883)
--                      Hera      blue    -> green  -> YELLOW  (:5992, :6004, :6016)
--                      Hestia    crimson -> pink   -> PURPLE  (:6058, :6070, :6082)
--                      Apollo    red     -> yellow -> CYAN    (:5925, :5937, :5949)
--                      Poseidon  teal    -> green  -> VIOLET  (:5794, :5806, :5818)
--
--   One family,        Aphrodite pink    -> magenta-> peach   (:5342, :5354, :5366)
--   DARK outward       Hephaestus 0.30 grey -> tan  -> RED     (:5662, :5674, :5686)
--                      Ares      0.30 grey -> pink  -> RED     (:5729, :5741, :5753)
--
-- The second shape is the useful one. Hephaestus and Ares start DARK on the
-- outer layer -- around 0.30 on every channel -- and put the saturated hero
-- colour innermost. That is much less total light than three bright layers, and
-- it puts the god's own colour where the emblem sits.
--
-- Athena needed exactly that. The 4.13.0 contrasting palette read cold and white
-- in game -- gold outside, blue at the core -- against a reference showing her
-- drop as gold-dominant. She now follows the Hephaestus structure in gold.
-- Dionysus keeps the contrasting shape: nothing has been reported about his, and
-- churning an untested drop would only lose the thread on which change did what.
--
-- Artemis's and Hades's values are UNCHANGED, down to the Opacity fields no
-- vanilla drop carries. Both were checked in game and approved, so the swap is
-- undone by writing what they already resolved to, not by re-picking them.
--
-- Athena's and Dionysus's hues are a judgement call. They follow the pattern
-- above rather than a measurement, and DropGlowBrightness exists to take the
-- whole orb down without another build.
local EXTRA_GODS = {
    {
        name = "Artemis", setting = "EnableArtemis",
        emblemSetting = "EmblemBrightnessArtemis",
        glowSetting = "GlowBrightnessArtemis",
        emblemArtSetting = "EmblemArtArtemis",
        hasPortrait = true,
        npc = "NPC_Artemis_Field_01",
        -- Unchanged from 4.11.0, written out post-swap.
        dropA = { Red = 0.28, Green = 0.46, Blue = 0.12, Opacity = 0.91 },
        dropB = { Red = 0.39, Green = 0.52, Blue = 0.21, Opacity = 0.93 },
        dropC = { Red = 0.23, Green = 0.57, Blue = 0.31, Opacity = 1.0 },
        lootColor = { 20, 120, 7, 255 },
    },
    {
        name = "Athena", setting = "EnableAthena",
        emblemSetting = "EmblemBrightnessAthena",
        glowSetting = "GlowBrightnessAthena",
        emblemArtSetting = "EmblemArtAthena",
        hasPortrait = true,
        npc = "NPC_Athena_01",
        -- Hephaestus's structure (:5662, :5674, :5686), in gold: a DARK outer
        -- layer, a mid one, and the saturated hero colour at the core where the
        -- emblem sits. Two earlier attempts failed here and both are worth
        -- keeping in view -- 4.12.0's near-white pale gold on the additive B
        -- layer, which is how you get a white blob, and 4.13.0's blue core,
        -- which made the whole orb read cold.
        dropA = { Red = 0.30, Green = 0.26, Blue = 0.10 },
        dropB = { Red = 0.88, Green = 0.66, Blue = 0.22 },
        dropC = { Red = 1.0, Green = 0.68, Blue = 0.05 },
        lootColor = { 194, 163, 41, 255 },
    },
    {
        name = "Dionysus", setting = "EnableDionysus",
        emblemSetting = "EmblemBrightnessDionysus",
        glowSetting = "GlowBrightnessDionysus",
        emblemArtSetting = "EmblemArtDionysus",
        hasPortrait = true,
        npc = "NPC_Dionysus_01",
        -- Wine out, vine in. Same additive-layer correction as Athena's: the
        -- old B was {0.86, 0.45, 1.0}, pale enough to wash.
        dropA = { Red = 0.62, Green = 0.16, Blue = 0.85 },
        dropB = { Red = 0.72, Green = 0.20, Blue = 1.0 },
        dropC = { Red = 0.35, Green = 1.0, Blue = 0.45 },
        lootColor = { 166, 41, 194, 255 },
    },
    {
        -- Hades is registered as a full boon god here. GodsAPI forces him to be
        -- an NPC-style god instead (its main.lua:352 clears GodLoot), which is
        -- why Droppable Gods cannot offer him as a boon -- that was their choice,
        -- not the game's, and nothing in the game requires it.
        name = "Hades", setting = "EnableHades",
        emblemSetting = "EmblemBrightnessHades",
        glowSetting = "GlowBrightnessHades",
        emblemArtSetting = "EmblemArtHades",
        -- The keepsake-portrait set has no plain Hades. It carries
        -- HadesPersephone -- the joint keepsake -- and that is a different
        -- picture of two people, not him. So the portrait option is not offered
        -- for him at all rather than silently drawing the wrong god.
        hasPortrait = false,
        npc = "NPC_Hades_Field_01",
        -- Unchanged from 4.11.0, written out post-swap.
        dropA = { Red = 0.10, Green = 0.10, Blue = 0.12 },
        dropB = { Red = 0.859, Green = 0.859, Blue = 0.776, Opacity = 0.8 },
        dropC = { Red = 0.16, Green = 0.16, Blue = 0.18 },
        lootColor = { 219, 219, 198, 255 },
    },
    {
        -- The first PORTRAIT-ONLY god, and the reason the portrait experiment
        -- was worth running: he has a keepsake portrait and no entry in
        -- BoonSelectSymbols, so before that test he could not have had a drop
        -- at all.
        --
        -- His traits are boon-shaped -- NarcissusA through NarcissusI, each with
        -- RarityLevels in TraitData_Narcissus.lua -- which is what separates him
        -- from Arachne, whose "Traits" are AgilityCostume, ManaCostume and the
        -- rest. Costumes in a boon slot would be a real bug, so she is not here.
        --
        -- DEFAULT OFF, unlike the other four. Those were each checked in game
        -- before shipping on; this one has not been, and an added god can turn
        -- up on vanilla's own first-reward roll, so switching him on is a choice
        -- rather than something that happens to you.
        --
        -- No dropA/B/C: the palette is derived from his own LootColor by the
        -- formula above, rather than three hues invented here.
        name = "Narcissus", setting = "EnableNarcissus",
        npc = "NPC_Narcissus_Field_01",
        offers = "NarcissusBenefitChoices",
        emblemSetting = "EmblemBrightnessNarcissus",
        glowSetting = "GlowBrightnessNarcissus",
        haloSetting = "HaloStrengthNarcissus",
        portraitOnly = true,
        hasPortrait = true,
    },
    {
        -- 4.17.0 left her out on the grounds that AgilityCostume, ManaCostume
        -- and the rest are "costumes, not boons". That was reading the names and
        -- stopping. AgilityCostume carries full RarityLevels -- Common through
        -- Heroic multipliers -- and a WeaponSpeedMultiplier
        -- (TraitData_Arachne.lua:3-30). It is a rarity-scaled stat trait offered
        -- one-of-three, which is a boon; the costume rides along with it.
        --
        -- Worth knowing rather than discovering: taking one DOES change
        -- Melinoe's model for the run (Costume = Models/Melinoe/...). That is
        -- vanilla behaviour when you take it from Arachne herself, not something
        -- added here, but picking her first means picking an outfit too.
        name = "Arachne", setting = "EnableArachne",
        npc = "NPC_Arachne_01",
        offers = "ArachneCostumeChoices",
        emblemSetting = "EmblemBrightnessArachne",
        glowSetting = "GlowBrightnessArachne",
        haloSetting = "HaloStrengthArachne",
        portraitOnly = true,
        hasPortrait = true,
    },
    -- The four below came out of the candidate log rather than out of guesswork.
    -- It ran against the LIVE EnemyData and named them with their NPC keys and
    -- trait pools, which is how their entry requirement was checked instead of
    -- assumed. Each has a keepsake portrait, no emblem, and a rarity-scaled pool
    -- offered one-of-three.
    {
        -- Nine traits, and not a boon name among them: CirceShrinkTrait,
        -- CirceEnlargeTrait, ArcanaRarityTrait, RandomArcanaTrait,
        -- RemoveShrineTrait. They are run modifiers -- she closes vows and
        -- opens Arcana -- and every one carries RarityLevels, so they scale
        -- and are offered one-of-three exactly as a boon is.
        name = "Circe", setting = "EnableCirce",
        npc = "NPC_Circe_01",
        offers = "CirceBlessingChoices",
        emblemSetting = "EmblemBrightnessCirce",
        glowSetting = "GlowBrightnessCirce",
        haloSetting = "HaloStrengthCirce",
        portraitOnly = true,
        hasPortrait = true,
    },
    {
        -- EchoLastReward, EchoLastRunBoon, EchoDeathDefianceRefill. Hers repeat
        -- things rather than granting them, which makes her an interesting
        -- FIRST pick in particular: last run's boon, first thing this run.
        name = "Echo", setting = "EnableEcho",
        npc = "NPC_Echo_01",
        offers = "EchoBenefitChoices",
        emblemSetting = "EmblemBrightnessEcho",
        glowSetting = "GlowBrightnessEcho",
        haloSetting = "HaloStrengthEcho",
        portraitOnly = true,
        hasPortrait = true,
    },
    {
        -- FocusAttackDamageTrait, FocusSpecialDamageTrait, OmegaExplodeBoon. The
        -- most conventionally boon-like of the four.
        name = "Icarus", setting = "EnableIcarus",
        npc = "NPC_Icarus_01",
        offers = "IcarusBenefitChoices",
        emblemSetting = "EmblemBrightnessIcarus",
        glowSetting = "GlowBrightnessIcarus",
        haloSetting = "HaloStrengthIcarus",
        portraitOnly = true,
        hasPortrait = true,
    },
    {
        -- MEDEA IS IN, and the story of why she nearly was not is worth keeping,
        -- because it is the most expensive wrong turn in this plugin's history.
        --
        -- Taking her boon as a first reward was followed, twenty-two seconds
        -- later, by EXCEPTION_ACCESS_VIOLATION and a truncated Profile1_Temp.sav
        -- that would not load ("can't load: extra data at end", then
        -- SaveErrorCorrupt). She was pulled from this list on the strength of
        -- that single event.
        --
        -- What the crash actually was, read off the stack dump in the
        -- ReturnOfModding backup log rather than guessed at:
        --
        --     [0] ltable.cpp:483    luaH_get
        --     [1] lvm.cpp:116       luaV_gettable
        --     [2] lvm.cpp:546       luaV_execute
        --     [3] ldo.cpp:429       unroll
        --     [5] ldo.cpp:535       lua_resume
        --     [7] lcorolib.cpp:53   luaB_coresume
        --
        -- A table lookup inside the Lua VM, inside a coroutine being resumed
        -- after a yield, reading through memory that was no longer valid. Not an
        -- asset fault -- a missing texture or projectile crashes in the asset
        -- manager or the renderer, not in ltable.cpp. Causes of that shape are
        -- GC reclaiming something still referenced, a thread resumed after its
        -- state went away, or heap corruption from elsewhere. All of them are
        -- timing-dependent, which is why it has never reproduced.
        --
        -- The same log also shows "Package Loaded: Medea 35Mb" at 16:54:21 in the
        -- crashing run, which disposes of the theory that her assets were absent.
        --
        -- Four Medea boons since, in deliberate tests, all clean -- including
        -- NewStatusDamage, the trait that was accused, with a real vulnerability
        -- effect landing on an enemy to trigger its handler. The whole case
        -- against her had come down to "she was the boon in the run that
        -- crashed", and that is superstition, not evidence.
        --
        -- She ships. The crash was real and the save loss was real, and neither
        -- has a fix in this plugin because neither belongs to it -- that class of
        -- fault can land on any run. SAVE_RECOVERY.md documents how to get a save
        -- back if it ever happens to anyone.
        name = "Medea", setting = "EnableMedea",
        npc = "NPC_Medea_01",
        emblemSetting = "EmblemBrightnessMedea",
        glowSetting = "GlowBrightnessMedea",
        haloSetting = "HaloStrengthMedea",
        portraitOnly = true,
        hasPortrait = true,
    },
}

-- Deliberately tied to the MOD, not to the author. These strings end up in the
-- player's config and in save data, so anything that churns them costs users a
-- reset; naming them after a handle would mean a rename churns them for no
-- gameplay reason at all. "SelectFirstBoon-" is unique enough to not collide and
-- stable for as long as the mod is called this.
local LOOT_PREFIX = "SelectFirstBoon-"
local function lootNameFor(godName) return LOOT_PREFIX .. godName .. "Upgrade" end


-- WHICH PICTURE goes inside the orb.
--
-- "symbol" is GUI\Screens\BoonSelectSymbols\<God> -- the emblem, and what every
-- one of these gods has used so far.
--
-- "portrait" is the keepsake portrait, GUI\Screens\AwardMenu\KeepsakeMaxGift\
-- KeepsakeMaxGift_small\<God>. It exists here for one reason: six more NPC gods
-- (Narcissus, Arachne, Circe, Echo, Medea, Icarus) have a portrait and NO emblem,
-- so whether a portrait renders inside a world orb decides whether they can ever
-- have a drop. Testing that on a god who already works costs one restart;
-- building six gods on the assumption costs a great deal more.
--
-- Two things are being asked at once and they are separate questions:
--
--   1. Does it RENDER? A texture that is not in a package loaded for the current
--      context comes back BLANK rather than erroring -- exactly how
--      SeleneBoonMoonParticle and BiomeMap_Moon_01 failed. No Lua script
--      references the KeepsakeMaxGift folder at all, so this cannot be settled
--      from the data files. In its favour: the inventory tab already draws that
--      same folder mid-run in the portrait icon style.
--   2. Does it LOOK right? It is a rectangular headshot sized for a menu row,
--      where every other drop in the game is a round medallion. Expectations
--      should be low, and that is a separate answer from the first.
--
-- If it renders blank, the fix to try is packages: CreateLoot calls
-- LoadPackages with this loot's own LoadPackages list (RoomLogic.lua), and ours
-- already inherits the NPC's -- { "NPC_Artemis_Field_01", "Artemis" } and so on.
-- A missing texture would mean adding whichever package holds it to that list.
-- CONFIRMED IN GAME: a portrait does render inside a world orb. That settles the
-- question the toggle existed to ask, and it is what makes portrait-only gods
-- possible at all.
--
-- Two things were wrong with the first look, and each has its own answer:
--
--   jagged      KeepsakeMaxGift_small is small art being drawn larger. The same
--               folder ships a _big variant, so "portrait" now means the big one
--               and the small one stays available as portrait-small.
--   washed out  The face took the boon's colour. That is not a property of the
--               emblem -- BoonDropIcon sets ColorFromOwner = "Ignore"
--               (:4907) -- it is BoonDropFrontFlare being drawn OVER it, on
--               GroupName "FX_Add_Top" (:4525). Nothing can stop that layer
--               painting over the picture, but two dials change the balance:
--               that god's glow down, or that god's emblem brightness UP, which
--               is why emblem brightness now goes above 1.0.
local EMBLEM_ART_PATHS = {
    symbol = "GUI\\Screens\\BoonSelectSymbols\\",
    portrait = "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_big\\",
    ["portrait-small"] =
        "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_small\\",
}

local function emblemArtStyleFor(god)
    -- A god with no emblem has nothing to fall back TO, so the portrait is not a
    -- choice for them -- it is the only art there is.
    if god ~= nil and god.portraitOnly then return "portrait" end

    local key = god ~= nil and god.emblemArtSetting or nil
    local chosen = key ~= nil and settings.values[key] or nil
    if chosen == "portrait" or chosen == "portrait-small" then
        if god.hasPortrait then return chosen end
        logWarn(god.name .. " has no keepsake portrait; using the emblem instead")
    end
    return "symbol"
end

local function emblemArtPathFor(god)
    local style = emblemArtStyleFor(god)
    return (EMBLEM_ART_PATHS[style] or EMBLEM_ART_PATHS.symbol) .. god.name
end

-- How big the picture inside the orb is drawn. See the registration below for
-- why this cannot just inherit vanilla's 0.7.
--
-- Per ART FAMILY rather than per god: an emblem and a keepsake portrait are
-- different source sizes, so one number cannot serve both, while every god using
-- the same family wants the same number. Ten gods times one dial each would be
-- ten dials answering two questions.
local function dropIconScale(god)
    local portrait = emblemArtStyleFor(god) ~= "symbol"
    local key = portrait and "DropPortraitScale" or "DropIconScale"
    local fallback = portrait and 0.22 or 0.4
    local value = tonumber(settings.values[key])
    if value == nil or value <= 0 then return fallback end
    return value
end

-- The door preview's scale, by art family.
--
-- Vanilla states 1.0 for its own previews, and the emblem four look right there
-- because their art is a medallion of about that size. A portrait god's source
-- is a full keepsake portrait and needs taking down by the same ratio the orb
-- already uses for exactly this reason.
function CONFIG.doorPreviewScale(god)
    local portrait = emblemArtStyleFor(god) ~= "symbol"
    local key = portrait and "DoorPortraitScale" or "DoorEmblemScale"
    -- 0.22, not a ratio off the emblem scale.
    --
    -- The first attempt derived 0.55 from DropIconScale 0.4 against
    -- DropPortraitScale 0.22, reasoning that portrait art wants 55% of what
    -- emblem art gets. In game that was still enormous -- a keepsake portrait
    -- filling a doorway next to a normal-sized hammer.
    --
    -- The orb is the better anchor: it draws THIS SAME ART at 0.22 and looks
    -- right. Same texture, same target size, so start where that ended up
    -- rather than deriving from the emblem, whose art is nothing like as large.
    local fallback = portrait and 0.22 or 1.0
    local value = tonumber(settings.values[key])
    if value == nil or value <= 0 then return fallback end
    return value
end

-- A flat grey multiplier on the emblem, or nil at full brightness so the entry
-- stays exactly as it was. Grey rather than a tint on purpose: this is meant to
-- take the art down without changing its hue.
--
-- PER GOD, not one dial for all four, because the thing being corrected is a
-- property of each TEXTURE rather than of "added gods" as a class. The
-- BoonSelectSymbols art carries a painted halo, and how much varies: Athena's is
-- a bright gold Olympian emblem and washes out inside the orb, while Artemis's
-- and Hades's were checked in game and look right untouched. A single value
-- cannot be right for all four -- dimming to rescue Athena would spoil two that
-- are already correct.
local function emblemColor(god)
    local key = god ~= nil and god.emblemSetting or nil
    if key == nil then return nil end
    local value = tonumber(settings.values[key])
    -- Exactly 1.0 writes nothing, so the entry stays as it was. Anything else --
    -- above or below -- is written through.
    if value == nil or value <= 0 or value == 1.0 then return nil end
    return { Red = value, Green = value, Blue = value }
end

local EXTRA_GOD_LOOT = {}
local EXTRA_GOD_BY_LOOT = {}
for _, god in ipairs(EXTRA_GODS) do
    EXTRA_GOD_LOOT[lootNameFor(god.name)] = true
    EXTRA_GOD_BY_LOOT[lootNameFor(god.name)] = god
end

-- "No boon has been taken yet this run." Same idea as the Hermes/Selene gates,
-- expressed as data so the game's own eligibility pass enforces it rather than
-- this plugin having to police every reward roll.
local function firstRewardOnlyRequirement(game, selfLoot)
    local taken = {}
    for _, name in ipairs(COUNTS_AS_A_BOON) do taken[#taken + 1] = name end
    -- Every god this plugin adds counts, including this one -- without itself in
    -- the list a god could be offered a second time.
    for _, god in ipairs(EXTRA_GODS) do taken[#taken + 1] = lootNameFor(god.name) end
    -- And any god another plugin has added, or "first boon" would quietly mean
    -- "first vanilla boon".
    if type(game.LootData) == "table" then
        for lootName, lootData in pairs(game.LootData) do
            if type(lootName) == "string" and type(lootData) == "table"
                and lootData.GodLoot == true then
                local seen = false
                for _, existing in ipairs(taken) do
                    if existing == lootName then seen = true break end
                end
                if not seen then taken[#taken + 1] = lootName end
            end
        end
    end
    return { { Path = { "CurrentRun", "LootTypeHistory" }, HasNone = taken } }
end

-- The drop's look, assembled the way vanilla assembles every boon drop.
--
-- A boon on the ground is not one picture -- it is a chain of generic layers
-- with exactly ONE god-specific layer at the centre
-- (Items_General_VFX.sjson:4905, and GodsAPI mirrors this shape):
--
--     BoonDrop<God>       <- BoonDropGold      the orb
--       BoonDropA-<God>   <- BoonDropA         outer glow, tinted
--       BoonDropB-<God>   <- BoonDropB         mid glow, tinted
--       BoonDropC-<God>   <- BoonDropC         inner glow, tinted
--       BoonDrop<God>Icon <- BoonDropIcon      THE ONLY GOD-SPECIFIC ART
--
-- The orb, both flares and all three glows are shared vanilla animations, so the
-- only thing any of these gods is missing is the innermost image -- and every
-- one of their emblems is already in the base game under BoonSelectSymbols.
--
-- Colours here are NOT the {r,g,b,a} 0-255 tables used in LootData. Animation
-- colours are named channels as 0-1 floats, which is how every vanilla entry
-- writes them (BoonDropA-Zeus: Color = { Red = 1.0 Green = 0.59 Blue = 0.22 },
-- Items_General_VFX.sjson:5859). Getting it wrong is SILENT -- the drop just
-- renders untinted -- which is why the tests pin the shape.
local COLOR_ORDER = { "Red", "Green", "Blue", "Opacity" }

-- The glow and flare each layer spawns. Vanilla puts these on A, B and C alike
-- (Items_General_VFX.sjson:5854-5884); without them the orb has no bloom.
local DROP_SUB_ANIMATIONS = { "BoonDropBackGlow", "BoonDropFrontFlare" }

-- The three layer colours, when a god has no hand-picked palette.
--
-- Hand-picked literals win where they exist: the first four gods have values
-- that were looked at in game and approved, and no formula should overwrite
-- those. For a NEW god, deriving from the game's own LootColor beats inventing
-- three hues -- it is the colour the base game already associates with them.
--
-- The shape is Hephaestus's (Items_General_VFX.sjson:5662-5686): dark outer,
-- mid, saturated core. The hue is normalised so its brightest channel is 1.0
-- first, otherwise a dim LootColor would produce three near-black layers.
-- SubtitleColor is in the chain because several of these characters have no
-- LootColor at all -- they never had a boon on the ground, so nothing needed one
-- -- but every one of them has a voice colour, which is the game's own answer to
-- "what colour is this character".
local function derivedDropColors(npc)
    local source = npc ~= nil
        and (npc.LootColor or npc.LightingColor or npc.SubtitleColor) or nil
    if type(source) ~= "table" or type(source[1]) ~= "number" then return nil end

    local r, g, b = source[1] / 255, source[2] / 255, source[3] / 255
    local peak = math.max(r, g, b)
    if peak <= 0 then return nil end
    r, g, b = r / peak, g / peak, b / peak

    return { Red = r * 0.30, Green = g * 0.30, Blue = b * 0.30 },
           { Red = r * 0.85, Green = g * 0.85, Blue = b * 0.85 },
           { Red = r, Green = g, Blue = b }
end

local function registerGodArt(god, npc)
    if sjson == nil or type(sjson.hook) ~= "function"
        or rom.path == nil or rom.paths == nil or rom.paths.Content == nil then
        logWarn("SJSON unavailable; " .. god.name .. " cannot be registered")
        return false
    end

    local loot = lootNameFor(god.name)
    local ok, err = pcall(function()
        local obstacleFile = rom.path.combine(rom.paths.Content, "Game/Obstacles/Gameplay.sjson")
        local animFile = rom.path.combine(rom.paths.Content, "Game/Animations/Items_General_VFX.sjson")

        local thing = sjson.to_object({
            EditorOutlineDrawBounds = false,
            Graphic = "BoonDrop" .. loot,
        }, { "EditorOutlineDrawBounds", "Graphic" })
        local obstacle = sjson.to_object({
            Name = loot,
            InheritFrom = "BaseBoon",
            DisplayInEditor = false,
            Thing = thing,
        }, { "Name", "InheritFrom", "DisplayInEditor", "Thing" })
        sjson.hook(obstacleFile, function(data)
            table.insert(data.Obstacles, obstacle)
        end)

        local order = { "Name", "InheritFrom", "ChildAnimation", "CreateAnimations",
                        "FilePath", "Color", "EndFrame", "NumFrames", "StartFrame",
                        "Loop", "Scale" }
        -- One dial for the whole orb. Every vanilla drop writes plain 0-1
        -- channels with no Opacity, so the honest way to make a drop dimmer is
        -- to scale the channels themselves -- which is what a lower value here
        -- does, uniformly across all three layers so the hue relationships that
        -- keep the emblem legible survive.
        local glow = tonumber(settings.values[god.glowSetting or ""])
        if glow == nil or glow <= 0 then glow = 1.0 end
        -- No upper clamp of our own. If the renderer clamps channels at 1.0 then
        -- values above it simply stop helping, which is information; clamping
        -- here would hide that behind our own ceiling instead.
        local derivedA, derivedB, derivedC = derivedDropColors(npc)
        local dropA = god.dropA or derivedA or { Red = 0.30, Green = 0.30, Blue = 0.30 }
        local dropB = god.dropB or derivedB or { Red = 0.85, Green = 0.85, Blue = 0.85 }
        local dropC = god.dropC or derivedC or { Red = 1.0, Green = 1.0, Blue = 1.0 }

        local function colorOf(c)
            if glow == 1.0 then return sjson.to_object(c, COLOR_ORDER) end
            local scaled = {}
            for _, channel in ipairs(COLOR_ORDER) do
                local value = c[channel]
                if value ~= nil then
                    -- Opacity is an alpha, not a colour channel; scaling it too
                    -- would fade the layer out instead of dimming it.
                    if channel == "Opacity" then
                        scaled[channel] = value
                    else
                        scaled[channel] = value * glow
                    end
                end
            end
            return sjson.to_object(scaled, COLOR_ORDER)
        end
        -- Deliberately NOT colorOf: the emblem is not a glow layer, and running
        -- it through the glow dial would make one setting move two things.
        local function rawColorOf(c)
            if c == nil then return nil end
            return sjson.to_object(c, COLOR_ORDER)
        end
        local function subAnimations()
            local out = {}
            for _, name in ipairs(DROP_SUB_ANIMATIONS) do
                out[#out + 1] = sjson.to_object({ Name = name }, { "Name" })
            end
            return out
        end
        local emblem = emblemArtPathFor(god)

        local entries = {
            -- No Color on the outermost layer: it inherits BoonDropGold, exactly
            -- as every vanilla god's does (BoonDropZeus, :5845-5848).
            { Name = "BoonDrop" .. loot, InheritFrom = "BoonDropGold",
              ChildAnimation = "BoonDropA-" .. loot },
            { Name = "BoonDropA-" .. loot, InheritFrom = "BoonDropA",
              ChildAnimation = "BoonDropB-" .. loot,
              CreateAnimations = subAnimations(), Color = colorOf(dropA) },
            { Name = "BoonDropB-" .. loot, InheritFrom = "BoonDropB",
              ChildAnimation = "BoonDropC-" .. loot,
              CreateAnimations = subAnimations(), Color = colorOf(dropB) },
            { Name = "BoonDropC-" .. loot, InheritFrom = "BoonDropC",
              ChildAnimation = "BoonDrop" .. loot .. "Icon",
              CreateAnimations = subAnimations(), Color = colorOf(dropC) },
            -- The one god-specific layer. Static, because an emblem is not a
            -- spin -- and explicitly scaled, because it is not the same ART.
            --
            -- BoonDropIcon is Scale 0.7 (Items_General_VFX.sjson:4917) around
            -- Items\Loot\Boon\<God>IconSpin, the spinning medallion. Ours
            -- inherits that 0.7 but points at GUI\Screens\BoonSelectSymbols\
            -- <God>, a bigger source texture, so the orb came out visibly
            -- larger than a vanilla boon lying beside it. Reported from a Hades
            -- drop next to a Zeus one.
            --
            -- The right number is a measurement I cannot take from here -- the
            -- textures are inside .pkg files -- so it is a setting with a
            -- deliberately small default rather than a guess baked in.
            --
            -- AND a brightness, for a reason particular to this art. The
            -- BoonSelectSymbols textures carry a painted halo -- established
            -- from the menu, where the nine Olympians glow and Hammer and Hermes,
            -- from the same folder, do not. Vanilla's drop emblems come from
            -- <God>IconSpin, which has no such halo. So this puts a
            -- bloom-painted picture inside a glowing orb, and Athena's came back
            -- as a white blob.
            --
            -- BoonDropIcon sets no AddColor (:4905-4920), so Color here
            -- MULTIPLIES: below 1.0 it dims the emblem and its painted halo
            -- together, without touching the orb around it. That is what makes
            -- this and DropGlowBrightness a pair of independent tests rather
            -- than two ways of saying "dimmer".
            { Name = "BoonDrop" .. loot .. "Icon", InheritFrom = "BoonDropIcon",
              FilePath = emblem, EndFrame = 1, NumFrames = 1, StartFrame = 1,
              Loop = false, Scale = dropIconScale(god),
              Color = rawColorOf(emblemColor(god)) },
            -- What a door shows for the room behind it.
            --
            -- Shaped to match vanilla's own, which is the reference for both
            -- bugs this entry used to have. BoonDropAphroditePreview reads:
            --
            --     InheritFrom = BoonDropRoomRewardIconPreviewBase
            --     NumFrames = 1
            --     Scale = 1.0
            --     ColorFromOwner = "Maintain"
            --     AngleFromOwner = "Ignore"
            --
            -- and crucially does NOT set Loop. The base is Loop = true with
            -- Duration = 2.5, so overriding it to false made the door art play
            -- once and stop -- which is why it appeared and then vanished after
            -- a couple of seconds.
            --
            -- Scale was missing entirely, where vanilla states 1.0. That is
            -- fine for the emblem four, whose art is a small medallion, and
            -- badly wrong for the portrait gods, whose source is a full
            -- keepsake portrait. The orb already solved the same problem with
            -- the same ratio -- DropIconScale 0.4 against DropPortraitScale
            -- 0.22 -- so a portrait wants roughly 0.55 of what an emblem gets.
            -- ColorFromOwner and AngleFromOwner are NOT set, though vanilla's own
            -- previews carry them: neither name is in the field-order list this
            -- file serialises by, so sjson.to_object drops them on the floor.
            -- Adding them looked right and did nothing. If they turn out to
            -- matter, the order list has to gain them first.
            { Name = "BoonDrop" .. loot .. "Preview",
              InheritFrom = "BoonDropRoomRewardIconPreviewBase",
              FilePath = emblem, NumFrames = 1,
              Scale = CONFIG.doorPreviewScale(god) },
        }

        local objects = {}
        for _, entry in ipairs(entries) do
            objects[#objects + 1] = sjson.to_object(entry, order)
        end
        logAlways(("%s door preview registered at scale %.2f (%s art)")
            :format(god.name, CONFIG.doorPreviewScale(god),
                    emblemArtStyleFor(god) == "symbol" and "emblem" or "portrait"))

        sjson.hook(animFile, function(data)
            for _, object in ipairs(objects) do
                table.insert(data.Animations, object)
            end
        end)
    end)

    if not ok then
        logWarn(god.name .. " art registration failed: " .. tostring(err))
        return false
    end
    return true
end

-- The loot god itself. Deliberately thin: every substantial field is a pointer
-- at something the base game already has.
-- SOME BOONS CANNOT BE OFFERED OUTSIDE THEIR OWN ENCOUNTER.
--
-- Circe's DoubleFamiliarTrait crashed the game when taken as a first boon:
-- UpgradeChoiceLogic.lua:399 does
--
--     for extractAs, value in pairs( SessionMapState[sessionKey].ExtractData )
--
-- and SessionMapState.OldFamiliarTrait was nil. That state is set up in
-- EventLogic.lua:1150, inside Circe's OWN encounter, when she offers the boon
-- herself. Offering it through the normal reward pipeline never runs that code.
--
-- The game does gate that boon: NPCData.lua:5247 offers it only when
-- MapState.FamiliarUnit is set, so you have to have a familiar out. But that
-- requirement sits on CIRCE'S OWN OFFER LIST, not on the trait, and this plugin
-- reads npc.Traits from EnemyData -- a flat list of names carrying no
-- requirements at all. So the gate is bypassed simply by taking a different
-- route to the same trait.
--
-- Satisfying it would not help anyway. SessionMapState is populated by that
-- encounter and by nothing else, so the field is nil on our path whether or not
-- a familiar exists. And on the run's FIRST reward there is no familiar to
-- double in the first place, which is what the gate was protecting against.
--
-- MergeTooltipDataFromSession is the marker for the whole class: a trait whose
-- tooltip is assembled from state some other system was supposed to prepare.
-- We cannot guarantee that state, so we do not offer those traits. Only Circe's
-- has it today; the filter is written against the field rather than the name so
-- a patch adding another is handled without us noticing.
function CONFIG.offerableTraits(game, npc, god)
    local traits = npc ~= nil and npc.Traits or nil
    if type(traits) ~= "table" then return traits end

    local traitData = game ~= nil and game.TraitData or nil
    if type(traitData) ~= "table" then return traits end

    local excluded = nil
    for _, name in ipairs(traits) do
        local data = type(name) == "string" and traitData[name] or nil
        if type(data) == "table" and data.MergeTooltipDataFromSession ~= nil then
            excluded = excluded or {}
            excluded[name] = true
        end
    end
    -- Nothing to drop: hand back the live table, not a snapshot of it.
    if excluded == nil then return traits end

    local kept = {}
    for _, name in ipairs(traits) do
        if not excluded[name] then kept[#kept + 1] = name end
    end
    for name in pairs(excluded) do
        logAlways(("%s: not offering %s -- its tooltip is built from session state "
            .. "that only its own encounter sets up"):format(god.name, name))
    end
    return kept
end

-- Vanilla never offers one of these gods' whole trait pool. Each has an
-- encounter that reads PresetEventArgs.<Table>.UpgradeOptions and puts every
-- entry's GameStateRequirements through IsGameStateEligible before it will show
-- that option: Circe withholds DoubleFamiliarTrait unless a familiar is out,
-- Narcissus gates six of his nine, Arachne five of eight. 24 gates across the
-- five gods that have such a table.
--
-- npc.Traits is that same pool with none of the gating attached -- checked, not
-- assumed: NPC_Circe_01.Traits is the same nine names as CirceBlessingChoices'
-- ItemNames, just without the requirements. Handing it over wholesale is why we
-- kept meeting boons the game had not set itself up to give.
--
-- COLLECTED at registration, because the requirement tables are static.
-- EVALUATED at offer time, because their answers are not: at load there is no
-- run, no familiar and no Arcana, so anything decided here would be decided
-- wrong. That split is the whole point of doing it this way.
--
-- None of the five tables uses ChanceToPlay -- grepped -- so evaluating them
-- draws no random numbers and cannot move the run's seed.
CONFIG.offerGates = {}

function CONFIG.collectOfferGates(game, god)
    local key = god ~= nil and god.offers or nil
    if type(key) ~= "string" then return nil end
    local preset = game ~= nil and game.PresetEventArgs or nil
    local args = type(preset) == "table" and preset[key] or nil
    local options = type(args) == "table" and args.UpgradeOptions or nil
    if type(options) ~= "table" then
        logWarn(god.name .. ": " .. key .. " has no UpgradeOptions; offering the pool ungated")
        return nil
    end

    local gates = nil
    local count = 0
    for _, option in ipairs(options) do
        if type(option) == "table" and type(option.ItemName) == "string"
            and option.GameStateRequirements ~= nil then
            gates = gates or {}
            gates[option.ItemName] = option.GameStateRequirements
            count = count + 1
        end
    end
    log(("%s: %d of %d offers carry eligibility gates"):format(god.name, count, #options))
    return gates
end

-- True when this trait may be offered right now.
function CONFIG.offerPasses(game, loot, traitName)
    local gates = CONFIG.offerGates[loot]
    local requirements = gates ~= nil and gates[traitName] or nil
    if requirements == nil then return true end

    local eligible = game ~= nil and game.IsGameStateEligible or nil
    if type(eligible) ~= "function" then return true end

    -- IsGameStateEligible only reads source.Name, for its own logging
    -- (RequirementsLogic.lua:9-12), so a name is all it wants from us.
    --
    -- A requirement can name a FunctionName the game resolves as it runs --
    -- HasAnyCirceRemovableShrineUpgrade is one. If that throws we withhold the
    -- option rather than offer one whose gate never answered.
    local called, result = pcall(eligible, { Name = loot }, requirements)
    if not called then
        logWarn(("%s: eligibility check for %s errored (%s); withholding it")
            :format(loot, traitName, tostring(result)))
        return false
    end
    return result and true or false
end

-- Applied to the finished eligible-upgrade list rather than to lootData.Traits,
-- so the registered pool stays a live reference and vanilla's own filtering
-- (TraitRequirements, HeroHasTrait, IsTraitEligible) runs first as it always has.
function CONFIG.filterOffers(game, lootData, upgrades)
    local loot = type(lootData) == "table" and lootData.Name or nil
    if type(loot) ~= "string" then return upgrades end
    if CONFIG.offerGates[loot] == nil then return upgrades end
    if type(upgrades) ~= "table" then return upgrades end

    local kept = {}
    local dropped = nil
    for _, upgrade in ipairs(upgrades) do
        local name = type(upgrade) == "table" and upgrade.ItemName or nil
        if name == nil or CONFIG.offerPasses(game, loot, name) then
            kept[#kept + 1] = upgrade
        else
            dropped = dropped or {}
            dropped[#dropped + 1] = name
        end
    end
    if dropped ~= nil then
        log(("%s: withheld %s -- the gates its own encounter applies")
            :format(loot, table.concat(dropped, ", ")))
        if #kept == 0 then
            logWarn(loot .. ": every option was gated out. Each of these gods keeps "
                .. "at least three ungated offers, so an empty pool means something "
                .. "upstream is wrong.")
        end
    end
    return kept
end

local function registerGod(game, god)
    if not settings.values[god.setting] then
        logAlways(god.name .. " option disabled by config")
        return
    end
    local loot = lootNameFor(god.name)
    -- Static tables, read once. The answers get worked out at offer time.
    CONFIG.offerGates[loot] = CONFIG.collectOfferGates(game, god)
    if type(game.LootData) ~= "table" then
        logWarn("LootData unavailable; " .. god.name .. " not registered")
        return
    end
    if game.LootData[loot] ~= nil then
        logAlways(god.name .. " already registered")
        return
    end

    -- ANOTHER PLUGIN GOT HERE FIRST
    --
    -- Droppable Gods, and anything else built on GodsAPI, registers these same
    -- gods as full members of the pool, droppable for the whole run. Ours is
    -- deliberately narrower: first reward only. With both installed the tab lists
    -- the god twice, under the same name and the same art, meaning two different
    -- things, and nothing on screen tells them apart.
    --
    -- So we stand down, which is what this plugin does everywhere else something
    -- has already decided. Nothing is lost that the player wanted: their entry is
    -- in the catalog, so picking that god as the first boon still works. The only
    -- casualty is our "and never again afterwards" restriction, and installing a
    -- mod whose entire purpose is to lift that restriction is not an accident.
    --
    -- Matched on DISPLAY NAME, not on loot key. The keys never collide, since
    -- theirs is namespaced by their guid and ours by this mod. It is precisely
    -- what the player reads that collides.
    local claimedBy = nil
    if type(game.LootData) == "table" then
        for otherName, otherData in pairs(game.LootData) do
            if otherName ~= loot and type(otherData) == "table"
                and otherData.GodLoot == true and not otherData.DebugOnly
                and displayNameFor(game, otherName) == god.name then
                claimedBy = otherName
                break
            end
        end
    end
    if claimedBy ~= nil then
        logAlways(god.name .. " is already offered by " .. claimedBy
            .. "; standing down so the list does not show two of him")
        return
    end

    local npc = game.EnemyData and game.EnemyData[god.npc]
    if npc == nil or npc.Traits == nil then
        logWarn("could not find " .. god.npc .. " or its trait pool; "
            .. god.name .. " not registered")
        return
    end

    -- Stashed for the tab, which needs a tint for a portrait icon long after
    -- this function has finished. The chain is the same one the drop palette
    -- uses: several of these characters have no LootColor at all, never having
    -- had a boon on the ground, but every one has a voice colour.
    god.haloColor = npc.LootColor or npc.LightingColor or npc.SubtitleColor

    if not registerGodArt(god, npc) then return end

    local ok, err = pcall(function()
        game.LootData[loot] = {
            InheritFrom = { "BaseLoot", "BaseSoundPackage" },
            Name = loot,
            GodLoot = true,
            -- Left unset ON PURPOSE. This is the flag that puts a god in shops,
            -- and these are meant to be a first-boon choice, not a thing you can
            -- buy later.
            TreatAsGodLootByShops = nil,

            -- These gods' boons are rarity-based; vanilla never lets a pom level
            -- them. Reported: with the Hades-and-Persephone keepsake equipped,
            -- boons from our drop came out at level 4.
            --
            -- UpgradeChoiceLogic.lua:295 gates the whole stack-boost block on
            --     not upgradeData.BlockStacking
            --     and IsGodTrait(itemData.ItemName)
            --     and not lootData.IgnoreStackBoost
            -- and lootData there is a DeepCopyTable of THIS table
            -- (RoomLogic.lua:2247), so this flag lands exactly on the branch
            -- that adds both MaxBonusBoonRank levels and FatedBoonLevelBonus.
            --
            -- The field is vanilla's own and is read in exactly one place in the
            -- entire game script set -- grepped, not assumed. It is unused by
            -- the base game, which is why it reads like an escape hatch: it is.
            IgnoreStackBoost = true,

            GameStateRequirements = firstRewardOnlyRequirement(game, loot),

            -- Their own pool, by reference where possible -- if the game or
            -- another plugin changes these boons, the drop follows. A filtered
            -- copy only when something actually has to come out, so the common
            -- case keeps the live reference.
            Traits = CONFIG.offerableTraits(game, npc, god),
            WeaponUpgrades = npc.WeaponUpgrades,
            RarityChances = npc.RarityChances,
            RarityRollOrder = npc.RarityRollOrder,

            Icon = "BoonSymbol" .. god.name,
            BoonInfoIcon = "BoonInfoSymbol" .. god.name .. "Icon",
            DoorIcon = "BoonDrop" .. loot .. "Preview",

            MenuTitle = npc.MenuTitle,
            Speaker = npc.Speaker,
            SpeakerName = god.name,
            Gender = npc.Gender,
            Portrait = npc.Portrait,
            OverlayAnim = npc.OverlayAnim,
            FlavorTextIds = npc.FlavorTextIds,

            Color = npc.LootColor or god.lootColor,
            LootColor = npc.LootColor or god.lootColor,
            SubtitleColor = npc.SubtitleColor,

            SpawnSound = npc.SpawnSound,
            UpgradeSelectedSound = npc.UpgradeSelectedSound,
            LootRejectionAnimation = npc.LootRejectionAnimation,
            LoadPackages = npc.LoadPackages,
        }
    end)

    if not ok then
        game.LootData[loot] = nil
        logWarn(god.name .. " registration failed, removed: " .. tostring(err))
        return
    end

    logAlways(god.name .. " registered as a first-reward-only boon god (" .. loot .. ")")
end

-- Every name in GUI\Screens\AwardMenu\KeepsakeMaxGift, which is the set of
-- characters with a portrait -- the only art a god without an emblem can use in
-- an orb. Listing it costs nothing and it is art filenames, not gameplay data.
local PORTRAIT_CHARACTERS = {
    "Aphrodite", "Apollo", "Arachne", "Ares", "Artemis", "Athena", "Chaos",
    "Charon", "Chronos", "Circe", "Demeter", "Dionysus", "Dora", "Echo", "Eris",
    "Hecate", "Hephaestus", "Hera", "Heracles", "Hermes", "Hestia", "Icarus",
    "Medea", "Moros", "Narcissus", "Nemesis", "Odysseus", "Poseidon", "Selene",
    "Skelly", "Zagreus", "Zeus",
}

-- WHO ELSE COULD BE ADDED, answered from the game rather than from guesswork.
--
-- Six characters were suggested as candidates. Reading the data files showed the
-- question is not "do they have art" but "is their trait pool a BOON pool":
-- Arachne's Traits are AgilityCostume, ManaCostume and so on -- costumes, not
-- boons -- while Narcissus's are NarcissusA through NarcissusI with RarityLevels.
-- Putting a costume vendor in a boon slot would be a real bug.
--
-- Rather than guess at the rest, this logs what the running game actually holds:
-- one line per character who has both a portrait and a trait pool, naming the
-- first few traits. Trait names give the answer away -- anything ending in
-- Costume or Gift is not a boon -- and it reads the live EnemyData, not the
-- subset that happened to be to hand while writing this.
local function logGodCandidates(game)
    if not settings.values.LogGodCandidates then return end
    if type(game.EnemyData) ~= "table" then return end

    for _, name in ipairs(PORTRAIT_CHARACTERS) do
        for _, suffix in ipairs({ "_Field_01", "_01" }) do
            local npc = game.EnemyData["NPC" .. "_" .. name .. suffix]
            local traits = npc ~= nil and npc.Traits or nil
            if type(traits) == "table" and #traits > 0 then
                local sample = {}
                for index = 1, math.min(3, #traits) do sample[index] = traits[index] end
                logAlways(("candidate: NPC_%s%s -- %d traits (%s%s)")
                    :format(name, suffix, #traits, table.concat(sample, ", "),
                            #traits > 3 and ", ..." or ""))
                -- The Field unit inherits from the plain one, so reporting both
                -- would just say everything twice.
                break
            end
        end
    end
end

local function registerExtraGods(game)
    for _, god in ipairs(EXTRA_GODS) do
        local ok, err = pcall(registerGod, game, god)
        if not ok then
            logWarn(god.name .. " setup failed, continuing without: " .. tostring(err))
        end
    end
end

-- =============================================================================
-- Custom static tab icons
-- =============================================================================
--
-- Neither shipped symbol set works as a tab icon on its own:
--
--   BoonInfoSymbol<God>Icon  static (NumFrames = 1, no Loop) but its FilePath is
--                            Items\Loot\Boon\<God>IconSpin\<God>IconSpin0015 --
--                            a frame of the spinning icon that hovers over a boon
--                            on the ground. Per-god art, never a matched set, so
--                            the gods render at visibly different sizes.
--
--   BoonSymbol<God>          points at GUI\Screens\BoonSelectSymbols\<God>, which
--                            IS a matched set (one folder, Scale 1 across every
--                            god), but inherits BoonSymbolBase -- and that base
--                            carries Loop = true, Duration = 2.5 and
--                            PingPongShiftOverDuration with EndOffsetZ = 5.0. In
--                            a tab it reads as a big glowing icon bobbing.
--
-- The animation is on the BASE, not on the god entries. So the fix is to define
-- our own leaves: matched BoonSelectSymbols art, no animated base, NumFrames = 1,
-- at a scale we choose. That is not an invention -- it is exactly the recipe
-- BoonInfoSymbolBase already uses (FilePath GUI\Screens\BoonSelectSymbols\Zeus
-- with EndFrame/NumFrames/StartFrame = 1), just not exposed per god.
--
-- Registered with sjson.hook, the same mechanism PonyMenu uses to add its
-- Box_FullScreen graphic to Game/Obstacles/GUI.sjson. This is the first time this
-- plugin has hooked an sjson file and the first time an Animations file has been
-- hooked here at all, so every step is guarded and the vanilla icon path stays
-- as a fallback.
--
-- Names come from the BoonSelectSymbols folder, confirmed present in
-- GUI_Screens_VFX.sjson:8253-8368. They are art filenames, not gameplay data, so
-- listing them is appropriate -- a god whose symbol is not here simply falls
-- back. Hammer and Hermes are in that same matched set, which is why those two
-- specials cost nothing extra; Selene is not in it at all (the set has no moon
-- symbol) and is registered separately from its door-preview art.
-- Artemis, Athena, Dionysus and Hades are in this folder in the BASE GAME even
-- though they never drop as boons there. That costs nothing to register and means
-- a plugin that makes them droppable -- zannc-Droppable_Gods does exactly this --
-- gets correct symbols here for free.
--
-- Deliberately NOT added to the door set: that art (<God>IconSpin) does not exist
-- in the base game for these four, and is shipped by the plugin that adds them.
-- Registering a FilePath that may not exist is a risk taken on behalf of every
-- user who does not have that plugin, for no gain -- iconInStyle already falls
-- through to the symbol when the chosen set has no entry.
-- BoonBackingA and Pom are in this folder too and are not gods: the backing
-- plate and the pomegranate. They are here so Standard has something to be that
-- is not a god's emblem -- see standardSymbol.
local SYMBOL_NAMES = {
    "Aphrodite", "Apollo", "Ares", "Artemis", "Athena", "BoonBackingA",
    "BoonBackingB", "BoonBackingC", "Chaos", "Demeter", "Dionysus", "Hades",
    "Hammer", "Hephaestus", "Hera", "Hermes", "Hestia", "Pom", "Poseidon",
    "Zeus",
}

-- Set form, so the lookup does not depend on the game's Contains helper being
-- reachable from this plugin's ENVY scope.
local SYMBOL_SET = {}
for _, symbol in ipairs(SYMBOL_NAMES) do SYMBOL_SET[symbol] = true end

-- The SECOND matched set, and the only glow-free one in the game.
--
-- The halo under each god symbol is not something this plugin adds and not
-- something any property removes: BoonSymbolBase already carries
-- Material = "Unlit" (GUI_Screens_VFX.sjson:8156-8168), exactly as these entries
-- do, and everything else it adds is motion, which is stripped here. The halo is
-- coloured per god -- purple for Aphrodite, yellow for Zeus -- which no
-- component property would produce. It is painted into the texture, because on
-- the boon-choice screen that is how these symbols are meant to look.
--
-- So the only real lever is different art, and there is exactly one other set
-- that is genuinely matched: the keepsake portraits at
-- GUI\Screens\AwardMenu\KeepsakeMaxGift\KeepsakeMaxGift_small (GUI_Boons_VFX
-- .sjson:109-410), one folder, one purpose, static and Unlit
-- (KeepsakeMax_Corner, :92-99). It covers all nine gods plus Hermes, Selene and
-- Chaos. There is no Hammer portrait, so the hammer keeps its symbol.
-- Arachne and Narcissus are here for a different reason from the rest: for them
-- the portrait is not an alternative STYLE, it is the only picture of them the
-- game has. A portrait-only god falls back to this entry in every style (see
-- tabIconFor), so leaving one out here would draw nothing at all.
local PORTRAIT_NAMES = {
    "Aphrodite", "Apollo", "Arachne", "Ares", "Artemis", "Athena", "Chaos",
    "Circe", "Demeter", "Dionysus", "Echo", "Hades", "Hephaestus", "Hera",
    "Hermes", "Hestia", "Icarus", "Medea", "Narcissus", "Poseidon", "Selene",
    "Zeus",
}

-- Where the picture is not filed under the god's own name. Hades shares a
-- portrait with Persephone -- KeepsakeMaxGift_big has HadesPersephone and no
-- Hades -- so the set name and the file name part ways for him alone.
local PORTRAIT_FILE_OVERRIDE = { Hades = "HadesPersephone" }
local PORTRAIT_SET = {}
for _, name in ipairs(PORTRAIT_NAMES) do PORTRAIT_SET[name] = true end
-- The _big variant, not _small. Small art drawn at tab size came back jagged --
-- the same defect the drop emblem had, from the same cause. There is no reason
-- to prefer the smaller source when both exist.
local PORTRAIT_PATH = "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_big\\"

-- The THIRD set, and the one that finally makes sense of the glow.
--
-- 3.1.0 concluded the halo was painted into the BoonSelectSymbols textures. That
-- was wrong, and the counter-example was on the page the whole time: Hammer and
-- Hermes come from that SAME folder and do not glow. The halo is per FILE, not
-- per folder -- the nine Olympians carry their own colour, and the two that have
-- no god colour do not.
--
-- Which means a different file is a real fix, not a wish. This is the art a DOOR
-- shows for the reward behind it, and it covers every option:
--
--     nine gods, Chaos, Hermes, Selene   Items\Loot\Boon\<Name>IconSpin\<Name>IconSpin0015
--     Hammer                             Items\Loot\WeaponUpgrade_Preview
--
-- The game already treats the god half of this as a matched set: every
-- BoonInfoSymbol<God>Icon inherits BoonInfoSymbolBase with Scale = 1.3 and
-- NOTHING else (GUI_Screens_VFX.sjson:8089-8154) -- no per-god scale override
-- anywhere. An earlier note in this file claimed these render at visibly
-- different sizes; that was inferred, and the absence of a single per-god Scale
-- is evidence against it.
--
-- The pulsing on a real door comes from BoonSymbolBaseIsometric's AddColor and
-- PingPongColor (Items_General_VFX.sjson:1039-1053), which are not inherited
-- here: these entries are static, single-frame and Unlit like the rest.
local BOONDROP_SPIN = {
    "Aphrodite", "Apollo", "Ares", "Chaos", "Demeter", "Hephaestus",
    "Hera", "Hermes", "Hestia", "Poseidon", "Selene", "Zeus",
}
local BOONDROP_SET = {}
for _, name in ipairs(BOONDROP_SPIN) do BOONDROP_SET[name] = true end

-- WeaponUpgrade_Preview is declared at Scale 0.55 where the spin frames are at
-- 1.0 (Items_General_VFX.sjson:1144-1148), so the hammer needs that baked in or
-- it lands twice the size of everything else.
local BOONDROP_EXTRA = {
    { name = "Hammer", file = "Items\\Loot\\WeaponUpgrade_Preview", factor = 0.55 },
    -- The flat pomegranate. Every StandardIcon option came from
    -- BoonSelectSymbols, and all of that art has a halo painted in, so the
    -- Standard square glowed while the door icons beside it did not.
    -- GUI\\Icons is where the game keeps its unglowing UI art.
    { name = "PomFlat", file = "GUI\\Icons\\Pom", factor = 1.0 },
}

-- The extras are registered from their own file paths but still have to be
-- findable by name, or iconInStyle returns nil and the slot falls through to
-- some other icon entirely.
for _, e in ipairs(BOONDROP_EXTRA) do BOONDROP_SET[e.name] = true end

-- One size correction per icon, registered here rather than written out in the
-- DEFAULTS table because the names come from the icon sets themselves and would
-- otherwise be a list to keep in sync by hand. They bind like any other setting
-- (loadSettings walks settings.values) and land in the Appearance section.
--
-- TEMPORARY. These exist to dial each icon in against the others in game, which
-- is the only place the answer is visible. Once the numbers are known they get
-- burned into the table below as defaults and the sliders come out.
-- DIALLED IN BY EYE, in game, against each other.
--
-- Every icon here comes from a different art family at a different native size,
-- so there is no formula that produces these -- they were set one at a time
-- until the grid read as one set. Anything not listed sits at 1.0.
--
-- The portrait gods are deliberately absent: they are governed by
-- PortraitIconBoost as a family, and listing them at 1.0 would imply a
-- measurement that never happened.
CONFIG.tuneSizeDefaults = {
    Aphrodite = 1.6, Apollo = 1.95, Arachne = 0.97, Ares = 2.1,
    Artemis = 1.1, Chaos = 2.0, Circe = 1.1, Demeter = 2.2,
    Echo = 1.17, Hades = 1.15, Hammer = 1.6, Hephaestus = 1.85,
    Hera = 1.9, Hermes = 2.1, Hestia = 1.92, PomFlat = 2.4,
    Poseidon = 2.3, Selene = 0.87, Zeus = 2.05,
}

-- Hermes' wing and Selene's moon are thin and pale, and an additive glow
-- directly behind them washes them out where a solid emblem is untouched.
-- Hollowing just their middles keeps the ring and the readability both.
CONFIG.tuneCoreDefaults = { Hermes = 0.1, Selene = 0.1 }

CONFIG.tuneNames = {}
do
    local seen = {}
    local function add(name)
        if name == nil or seen[name] then return end
        seen[name] = true
        CONFIG.tuneNames[#CONFIG.tuneNames + 1] = name
        settings.values["Size" .. name] = CONFIG.tuneSizeDefaults[name] or 1.0
        CONFIG_DESCRIPTIONS["Size" .. name] =
            "Size correction for " .. name .. "'s icon, on top of the global "
            .. "icon size. 1.0 leaves it alone. Reopen the inventory."
        -- Some art fights the selection light. Thin, pale shapes -- Hermes'
        -- wing is the clear case -- sit on top of an additive glow and wash
        -- out, while a solid emblem is unaffected at the same strength. That
        -- is a property of the texture, so it gets a per-texture dial rather
        -- than a special case in the drawing code.
        -- Per-icon centre, for art that survives an outer ring but not a glow
        -- directly behind it. Turning the whole light down instead costs the
        -- pop; this keeps the ring and hollows only the middle.
        settings.values["Core" .. name] = CONFIG.tuneCoreDefaults[name] or 1.0
        CONFIG_DESCRIPTIONS["Core" .. name] =
            "How bright the middle of the selection light is behind " .. name
            .. "'s icon, as a multiplier on the global centre. Lower it for art "
            .. "the light shines through. 1.0 leaves it alone. Reopen the "
            .. "inventory."
        settings.values["Light" .. name] = 1.0
        CONFIG_DESCRIPTIONS["Light" .. name] =
            "How strong the selection light is behind " .. name .. "'s icon, "
            .. "as a multiplier on the global strength. Lower it for art the "
            .. "light washes out. 1.0 leaves it alone. Reopen the inventory."
    end
    for _, n in ipairs(BOONDROP_SPIN) do add(n) end
    for _, e in ipairs(BOONDROP_EXTRA) do add(e.name) end
    for _, n in ipairs(SYMBOL_NAMES) do add(n) end
    for _, n in ipairs(PORTRAIT_NAMES) do add(n) end
    table.sort(CONFIG.tuneNames)
end

local CUSTOM_ICON_PREFIX = "SelectFirstBoon_Symbol_"
local customIconsRegistered = false

local PORTRAIT_ICON_PREFIX = "SelectFirstBoon_Portrait_"
local BOONDROP_ICON_PREFIX = "SelectFirstBoon_BoonDrop_"
local SELENE_ICON_PREFIX = "SelectFirstBoon_Selene_"

-- Three genuinely different pictures of Selene, none of which matches the god
-- medallions, so the choice is handed over rather than guessed at.
-- There is no Selene entry in BoonSelectSymbols. Not "hard to find" -- the folder
-- has Aphrodite through Zeus plus Hammer and Pom, and no moon of any kind. She is
-- a Hex giver rather than an Olympian, and the game never needed an emblem for
-- her because nothing ever offers her as a boon on the ground.
--
-- Four candidates were tried and cut, on evidence rather than taste:
--   GUI\Icons\Attributes\Hex          renders as a sheep -- it is the hexed
--                                      STATUS icon, not a Selene emblem
--   SeleneBoonMoonParticle             blank; particle art is not addressable here
--   GUI\BiomeMap\BiomeMap_Moon_01      blank, same reason
--   BoonIcons\Selene_100               one specific hex, not Selene
--
-- What is left is her two real pictures, each with one lever:
--
--   preview  the icon a DOOR shows. Flat but angled, because vanilla draws it
--            from BoonSymbolBaseIsometric where every god's uses a flat base.
--            The glow lever matters most here -- this art has no bloom of its
--            own, which is exactly why it looks out of place next to gods whose
--            bloom is painted in.
--   spin     her world drop. CUT. The beam is part of the TEXTURE, not a
--            separate animation (SpellDrop's children are a glow emitter and an
--            orb spawn, no beam), so it cannot be switched off, and anchoring it
--            on the medallion (OriginX 120 / OriginY 400,
--            Items_General_VFX.sjson:1496-1497) still leaves the beam running up
--            out of the slot. Tested in game: unusable either way.
--
-- THE HALO
--
-- Take one was Material = "Emissive". Identical to the flat art in game: dead.
--
-- Take two is a second sprite drawn additively, which is what vanilla actually
-- does when it wants a halo -- BoonDropBackGlow (Items_General_VFX.sjson:5087)
-- and BoonSymbolGlow (GUI_Screens_VFX.sjson:8220) are both exactly that.
--
-- Take two shipped in 4.9.0 and was never actually exercised. The art dropdown
-- was still on the flat variant, so makeSeleneGlow returned before it drew
-- anything, and turning the strength dial could not have done a thing. The log
-- proves it: not one "Selene halo" line across the whole session. That trap is
-- gone -- there is one Selene art now, and the strength dial alone decides
-- whether it carries a halo.
--
-- Which TEXTURE the halo uses is still open, so it is a setting rather than a
-- guess baked in. Ordered by confidence:
--
--   particle    Particles\particle_glow -- vanilla's own halo texture, used by
--               both entries above. Principled choice; the risk is that particle
--               art may not be addressable from a menu screen (SeleneBoonMoon-
--               Particle came back blank when tried as an icon).
--   backing-a/b/c
--               GUI\Screens\BoonSelectSymbols\BoonBacking[ABC] -- the glowy
--               plates the boon-choice screen draws behind each god symbol.
--               Lower risk than particle art for one concrete reason: this is
--               the SAME FOLDER every god symbol on this page already renders
--               from, so the package is demonstrably loaded here.
-- Settled in testing: the particle IS what draws, and it draws well -- it was
-- only enormous, because particle_glow is a big texture and the size was being
-- multiplied by the icon scale on top of that. The two "use the game's own
-- animation by name" diagnostics (BoonSymbolGlow, BoonSymbolFlare) did their job
-- -- they proved nothing was wrong with the texture path -- and are cut, because
-- as ART in a grid slot they make no sense. The backings stay: they were never
-- fairly judged at the wrong size.
local SELENE_GLOW_ANIM = "SelectFirstBoon_SeleneGlow"

-- Selene's own colour, straight from LootData_Selene.lua:64 (LootColor), in the
-- 0-255 form SetRGB takes.
local SELENE_GLOW_COLOR = { 100, 25, 255, 255 }

local SELENE_GLOW_SOURCES = {
    { key = "particle",  file = "Particles\\particle_glow" },
    { key = "backing-a", file = "GUI\\Screens\\BoonSelectSymbols\\BoonBackingA" },
    { key = "backing-b", file = "GUI\\Screens\\BoonSelectSymbols\\BoonBackingB" },
    { key = "backing-c", file = "GUI\\Screens\\BoonSelectSymbols\\BoonBackingC" },
}

local function seleneGlowSource()
    local key = settings.values.SeleneGlowSource
    for _, source in ipairs(SELENE_GLOW_SOURCES) do
        if source.key == key then return source end
    end
    return SELENE_GLOW_SOURCES[1]
end

-- One art, no variants: the flat/glow split was the trap described above.
local SELENE_ICON_NAME = SELENE_ICON_PREFIX .. "preview"
local SELENE_ICON_FILE = "Items\\Loot\\SpellDrop_Preview"

local function seleneIconName()
    return SELENE_ICON_NAME
end

local function customIconName(symbol)
    return CUSTOM_ICON_PREFIX .. symbol
end

local function portraitIconName(name)
    return PORTRAIT_ICON_PREFIX .. name
end

local function boonDropIconName(name)
    return BOONDROP_ICON_PREFIX .. name
end

local function usingPortraits()
    return settings.values.IconStyle == "portrait"
end

local function usingBoonDrops()
    return settings.values.IconStyle == "boondrop"
end

-- LootData[god].Icon is "BoonSymbol<Name>"; the suffix is the folder name.
--
-- A god added by another plugin carries a namespaced loot name -- Droppable Gods
-- registers "zannc-Droppable_Gods-ArtemisUpgrade" -- and there is no guarantee it
-- sets Icon in the shape this expects. It does set SpeakerName, and that is
-- exactly the art folder name, so that is the fallback: it costs one comparison
-- and it is the difference between a correct symbol and the Chaos default.
-- Every candidate is checked against art we actually have, and the first one
-- that hits wins. 3.3.0 returned the Icon-derived name unconditionally, which
-- looked right against vanilla and is wrong against GodsAPI: that library builds
-- Icon as "BoonSymbol" .. guid .. "-" .. godName (its main.lua:259), so the match
-- SUCCEEDS and yields "zannc-Droppable_Gods-Artemis" -- a name no set carries.
-- Returning early on it meant SpeakerName, which Droppable Gods does set to the
-- real "Artemis" through ExtraFields, was never reached.
local function haveArtFor(name)
    if name == nil or name == "" then return false end
    return SYMBOL_SET[name] or BOONDROP_SET[name] or PORTRAIT_SET[name] or false
end

local function symbolNameFor(game, god)
    local lootData = game.LootData and game.LootData[god]
    if lootData == nil then return nil end

    local candidates = {}
    if type(lootData.Icon) == "string" then
        candidates[#candidates + 1] = string.match(lootData.Icon, "^BoonSymbol(.+)$")
    end
    if type(lootData.SpeakerName) == "string" then
        candidates[#candidates + 1] = lootData.SpeakerName
    end

    -- A namespaced name has the real one after the last dash. Vanilla loot names
    -- never contain a dash, so this can only ever fire on a modded god.
    local extra = {}
    for _, name in ipairs(candidates) do
        local tail = string.match(name, "^.*%-(.+)$")
        if tail ~= nil then extra[#extra + 1] = tail end
    end
    for _, name in ipairs(extra) do candidates[#candidates + 1] = name end

    for _, name in ipairs(candidates) do
        if haveArtFor(name) then return name end
    end
    -- Nothing matched any set. Hand back the first candidate anyway so the
    -- caller can still try the god's own BoonInfoIcon.
    return candidates[1]
end

-- The rungs, as a fraction of one grid cell. Coarse on purpose: every rung is a
-- real obstacle in GUI.sjson, and a box within a tenth of the art is close
-- enough to feel right.
CONFIG.boxSteps = { 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 1.0, 1.15, 1.3, 1.6, 2.0, 2.5, 3.0 }

function CONFIG.boxObstacleName(step)
    return "SelectFirstBoon_Button_" .. tostring(math.floor(step * 100 + 0.5))
end

-- Which rung to use.
--
-- NOT the icon's own scale, deliberately. Controller free-form selection
-- resolves against obstacle BOUNDS, so the boxes have to tile the grid: a gap
-- wider than the 16-unit step is dead space a stick cannot cross. At one cell
-- they tile exactly, which is why that was the original size.
--
-- Shrinking them makes the mouse precise -- you have to click the icon rather
-- than its cell -- and costs controller navigation. That is a real trade and not
-- one to make on someone's behalf, so it is a dial that ships at 1.0.
-- Which rungs actually made it into GUI.sjson this session. Asking for one that
-- did not is not a small mistake: the obstacle simply is not there, the button
-- gets no usable bounds, and it reads as "the setting does nothing". That
-- happens whenever the ladder gains a rung and the game has not been restarted
-- since, so the choice is clamped to what exists rather than trusted.
CONFIG.boxRegistered = {}

function CONFIG.boxNameFor(isPortrait)
    -- Portraits get their own rung. Their iconScale is far lower than a god
    -- symbol's -- that is what PortraitIconBoost is -- while the art still
    -- renders large, so a box sized for the symbols is tight around a face.
    -- Same reason portraits already carry their own size boost and nudge.
    local key = isPortrait and "HitboxScalePortrait" or "HitboxScale"
    local want = tonumber(settings.values[key]) or 1.0
    if want <= 0 then want = 1.0 end
    local best, bestGap = nil, nil
    for _, step in ipairs(CONFIG.boxSteps) do
        if CONFIG.boxRegistered[step] then
            local gap = math.abs(step - want)
            if bestGap == nil or gap < bestGap then best, bestGap = step, gap end
        end
    end
    if best == nil then return BUTTON_OBSTACLE end
    return CONFIG.boxObstacleName(best)
end

local BUTTON_OBSTACLE = "SelectFirstBoon_Button"
local FALLBACK_OBSTACLE = "ButtonInventoryItem"
local buttonObstacleName = FALLBACK_OBSTACLE
local obstacleSizeNote = "not registered"

-- Points wind the same way the vanilla entries do. Each point is its own sjson
-- object so the array serialises as a list of objects rather than a flat table.
-- Size the box from the grid it has to sit in, rather than from numbers picked
-- by eye. ScreenData.InventoryScreen carries the pitch (GridSpacingX 133.6,
-- GridSpacingY 143 at ResourceData.lua:3968-3972), so one cell minus a hairline
-- is the box that tiles the grid with no gap between cells and no overlap into
-- the neighbour. Both halves of that matter: overlap is what sent clicks to the
-- wrong row up to 2.5.0, and gaps are what let a controller step land on nothing
-- in 2.6.0, since vanilla's own boxes overlap and therefore never have a gap to
-- fall into.
local function buttonBoxSize(game)
    local override = {
        tonumber(settings.values.TabButtonBoxWidth) or 0,
        tonumber(settings.values.TabButtonBoxHeight) or 0,
    }
    if override[1] > 0 and override[2] > 0 then
        return override[1], override[2], "config override"
    end

    local screenData = game ~= nil and game.ScreenData and game.ScreenData.InventoryScreen or nil
    local pitchX = screenData ~= nil and tonumber(screenData.GridSpacingX) or nil
    local pitchY = screenData ~= nil and tonumber(screenData.GridSpacingY) or nil
    if pitchX == nil or pitchY == nil or pitchX <= 0 or pitchY <= 0 then
        return nil, nil, "grid spacing unavailable"
    end
    return pitchX - 2, pitchY - 2, "grid spacing"
end

local function registerButtonObstacle(game)
    local width, height, source = buttonBoxSize(game)
    if width == nil then
        logAlways("custom button obstacle disabled (" .. source .. "); using " .. FALLBACK_OBSTACLE)
        return
    end
    local halfWidth = width / 2
    local halfHeight = height / 2
    if sjson == nil or type(sjson.hook) ~= "function"
        or rom.path == nil or rom.paths == nil or rom.paths.Content == nil then
        logWarn("cannot register the button obstacle; using " .. FALLBACK_OBSTACLE)
        return
    end

    local ok, err = pcall(function()
        local guiFile = rom.path.combine(rom.paths.Content, "Game/Obstacles/GUI.sjson")
        local pointOrder = { "X", "Y" }
        local function point(x, y) return sjson.to_object({ X = x, Y = y }, pointOrder) end

        -- A LADDER OF SIZES, not one box.
        --
        -- One cell was right when every icon was drawn at one size. Now each has
        -- its own correction, so a single box is far larger than most of the art
        -- in it -- you can point well above an icon and still hit it, which is
        -- what was reported. The box has to follow the art.
        --
        -- It cannot follow it by scaling: SkipGeometryUpdate is set on every
        -- SetScale precisely so growing art does not grow its bounds back into
        -- its neighbours, which is the overlap bug the one-cell box was added to
        -- fix. And the geometry is baked into GUI.sjson at load, so it cannot be
        -- resized later either.
        --
        -- So register the whole ladder up front and let each button pick the rung
        -- matching its own scale. Tuning a size then changes its hitbox with it,
        -- live, with no restart and no overlap.
        local obstacles = {}
        for _, step in ipairs(CONFIG.boxSteps) do
            local hw, hh = halfWidth * step, halfHeight * step
            local thing = sjson.to_object({
                EditorOutlineDrawBounds = false,
                Points = {
                    point(-hw,  hh),
                    point( hw,  hh),
                    point( hw, -hh),
                    point(-hw, -hh),
                },
            }, { "EditorOutlineDrawBounds", "Points" })

            CONFIG.boxRegistered[step] = true
            obstacles[#obstacles + 1] = sjson.to_object({
                Name = CONFIG.boxObstacleName(step),
                InheritFrom = "BaseInteractableButton",
                DisplayInEditor = false,
                Thing = thing,
            }, { "Name", "InheritFrom", "DisplayInEditor", "Thing" })
        end

        sjson.hook(guiFile, function(data)
            for _, obstacle in ipairs(obstacles) do
                table.insert(data.Obstacles, obstacle)
            end
        end)
    end)

    if not ok then
        logWarn("button obstacle registration failed, using " .. FALLBACK_OBSTACLE .. ": " .. tostring(err))
        return
    end

    buttonObstacleName = BUTTON_OBSTACLE
    obstacleSizeNote = ("%.0fx%.0f from %s"):format(width, height, source)
    local rungs = {}
    for _, step in ipairs(CONFIG.boxSteps) do
        if CONFIG.boxRegistered[step] then rungs[#rungs + 1] = string.format("%.2f", step) end
    end
    logAlways(("registered button obstacles at %s, rungs %s (vanilla %s is 340x360)")
        :format(obstacleSizeNote, table.concat(rungs, " "), FALLBACK_OBSTACLE))
    logAlways(("hitbox rung in use: symbols %s, portraits %s")
        :format(CONFIG.boxNameFor(false), CONFIG.boxNameFor(true)))
end

local function registerCustomIcons()
    local scale = tonumber(settings.values.TabIconScale) or 0
    if scale <= 0 then
        logAlways("custom tab icons disabled (TabIconScale = 0); using the vanilla static set")
        return
    end
    if sjson == nil or type(sjson.hook) ~= "function" then
        logWarn("SGG_Modding-SJSON unavailable; falling back to the vanilla static icons")
        return
    end
    if rom.path == nil or rom.paths == nil or rom.paths.Content == nil then
        logWarn("rom.paths.Content unavailable; falling back to the vanilla static icons")
        return
    end

    local registered = 0
    local ok, err = pcall(function()
        local animFile = rom.path.combine(rom.paths.Content, "Game/Animations/GUI_Screens_VFX.sjson")

        -- Key order only affects how the rewritten sjson reads; it mirrors the
        -- order the vanilla entries use.
        local order = { "Name", "FilePath", "EndFrame", "NumFrames", "StartFrame", "Material", "Scale" }

        local newEntries = {}
        for _, symbol in ipairs(SYMBOL_NAMES) do
            newEntries[#newEntries + 1] = sjson.to_object({
                Name = customIconName(symbol),
                FilePath = "GUI\\Screens\\BoonSelectSymbols\\" .. symbol,
                EndFrame = 1,
                NumFrames = 1,
                StartFrame = 1,
                Material = "Unlit",
                Scale = scale,
            }, order)
        end

        -- Specials whose art lives outside BoonSelectSymbols. Same treatment:
        -- NumFrames 1 and Unlit, so no loop and no pulsing tint. Size is handled
        -- at draw time now (see iconScaleFor) rather than baked in here, so it
        -- can be tuned without a restart.
        for _, special in ipairs(SPECIALS) do
            if special.file ~= nil then
                newEntries[#newEntries + 1] = sjson.to_object({
                    Name = customIconName(special.value),
                    FilePath = special.file,
                    EndFrame = 1,
                    NumFrames = 1,
                    StartFrame = 1,
                    Material = "Unlit",
                    Scale = scale,
                }, order)
            end
        end

        for _, name in ipairs(BOONDROP_SPIN) do
            newEntries[#newEntries + 1] = sjson.to_object({
                Name = boonDropIconName(name),
                FilePath = "Items\\Loot\\Boon\\" .. name .. "IconSpin\\" .. name .. "IconSpin0015",
                EndFrame = 1,
                NumFrames = 1,
                StartFrame = 1,
                Material = "Unlit",
                Scale = scale,
            }, order)
        end
        for _, extra in ipairs(BOONDROP_EXTRA) do
            newEntries[#newEntries + 1] = sjson.to_object({
                Name = boonDropIconName(extra.name),
                FilePath = extra.file,
                EndFrame = 1,
                NumFrames = 1,
                StartFrame = 1,
                Material = "Unlit",
                Scale = scale * extra.factor,
            }, order)
        end

        newEntries[#newEntries + 1] = sjson.to_object({
            Name = SELENE_ICON_NAME,
            FilePath = SELENE_ICON_FILE,
            EndFrame = 1,
            NumFrames = 1,
            StartFrame = 1,
            Material = "Unlit",
            Scale = scale,
        }, order)

        -- One halo entry per file-based source, all registered every time, so
        -- stepping through them is a setting rather than a reinstall. The two
        -- vanilla sources register nothing: they are the game's own animations,
        -- used by name. Scale 1 because the component sets its own size at draw
        -- time from SeleneHaloSpread.
        for _, source in ipairs(SELENE_GLOW_SOURCES) do
            if source.file ~= nil then
                newEntries[#newEntries + 1] = sjson.to_object({
                    Name = SELENE_GLOW_ANIM .. "_" .. source.key,
                    FilePath = source.file,
                    EndFrame = 1,
                    NumFrames = 1,
                    StartFrame = 1,
                    Material = "Unlit",
                    Scale = 1,
                }, order)
            end
        end

        -- Every set is registered every time, so switching between them is a
        -- setting rather than a reinstall.
        for _, name in ipairs(PORTRAIT_NAMES) do
            newEntries[#newEntries + 1] = sjson.to_object({
                Name = portraitIconName(name),
                FilePath = PORTRAIT_PATH .. (PORTRAIT_FILE_OVERRIDE[name] or name),
                EndFrame = 1,
                NumFrames = 1,
                StartFrame = 1,
                Material = "Unlit",
                Scale = scale,
            }, order)
        end

        sjson.hook(animFile, function(data)
            for _, entry in ipairs(newEntries) do
                table.insert(data.Animations, entry)
            end
        end)

        registered = #newEntries
        customIconsRegistered = true
    end)

    if not ok then
        logWarn("could not register custom tab icons, falling back to the vanilla set: " .. tostring(err))
        return
    end
    logAlways("registered " .. registered .. " custom tab icons at scale " .. tostring(scale))
end

-- =============================================================================
-- Native inventory tab
-- =============================================================================
--
-- LAYOUT AND HIT-TESTING
--
-- The buttons are "ButtonInventoryItem", whose hitbox is defined in
-- Content/Game/Obstacles/GUI.sjson as:
--
--     Points = [ {X=-170 Y=220} {X=170 Y=220} {X=170 Y=-140} {X=-170 Y=-140} ]
--
-- 340 wide by 360 tall, and asymmetric about the origin: 220 one side, 140 the
-- other, so the box's centre is 40 units off the icon it draws. Against
-- GridSpacingX 133.6 and GridSpacingY 143, boxes overlap their neighbours in
-- both axes -- badly enough vertically that a click near a second-row button can
-- resolve to the first-row one above it.
--
-- Vanilla's own resource grid uses this same button at this same spacing and
-- behaves, so the overlap is not sufficient on its own; the engine resolves it.
-- v2.4.0 differed from that working setup in several ways at once, so rather
-- than guess which one mattered, this version matches it on all of them:
--
--   * InventoryScreenInGrid background instead of InBlank. This is also what
--     gives the slot frames behind each icon -- the slots are part of the
--     background art, not per-button components, which is why empty cells still
--     show a frame. PonyMenu's tab uses InGrid for the same reason.
--   * A per-button Highlight component in Combat_Menu_Overlay_Additive, assigned
--     to button.Highlight, exactly as the resource grid does.
--   * An explicit Scale on the button.
--   * MouseOver / MouseOff handlers, so hover state exists at all.
--   * GamepadNavigation declared on the category itself, copied from
--     InventoryScreen_PinTab. SetGamepadNavigation only pushes config options
--     (UILogic.lua:1091) and is called by vanilla BEFORE OpenFunctionName, so
--     the category needs to carry its own settings rather than have this code
--     call it again afterwards -- which is what v2.4.0 did.
--
-- v2.4.1 still mis-resolved clicks, and measuring it in game pinned the cause
-- exactly. The box spans -140 to +220 around the button origin, so with rows at
-- GridStartY 252 and GridSpacingY 143:
--
--     row 1 button at y=252  ->  hitbox 112 .. 472
--     row 2 button at y=395  ->  hitbox 255 .. 615
--
-- A click on a row-2 icon at y=395 is inside BOTH boxes, and row 1 wins. The
-- only unambiguous part of row 2's box is below 472 -- a full cell lower than
-- its icon, which is exactly what it felt like.
--
-- v2.4.2 put all ten on one row at a tighter pitch. Clicks became reliable, but
-- the icons no longer sat in the slot frames: those frames are background art
-- drawn at the vanilla 133.6 pitch and cannot follow a custom one.
--
-- v2.5.0 kept the vanilla pitch and bought the clearance by SKIPPING a slot row,
-- five per row at y = GridStartY and y = GridStartY + 2 * GridSpacingY. Both of
-- those were workarounds for an oversized hitbox rather than layouts anyone
-- would choose, and both are gone: once the box is one cell (see BUTTON
-- OBSTACLE) there is nothing left to work around, so v2.9.0 fills a row to the
-- screen's own GridWidth and wraps, exactly as the resource grid does.

-- =============================================================================
-- BUTTON OBSTACLE
-- =============================================================================
--
-- Every version up to 2.5.0 used ButtonInventoryItem, whose hitbox is declared in
-- Content/Game/Obstacles/GUI.sjson as 340 wide by 360 tall:
--
--     Points = [ {X=-170 Y=220} {X=170 Y=220} {X=170 Y=-140} {X=-170 Y=-140} ]
--
-- Against a grid pitch of 133.6 x 143 that means every point on the panel lies
-- inside two to six button boxes at once. Two symptoms follow from that one
-- fact, and both were reported: clicks land on a neighbour rather than the icon
-- under the cursor, and controller free-form selection cannot move sensibly
-- because directional stepping has nothing to disambiguate.
--
-- v2.4.1 and v2.5.0 both tried to fix the controller by changing
-- FreeFormSelect* settings. That was the wrong layer entirely -- free-form
-- selection resolves against obstacle BOUNDS, so no navigation tuning can help
-- while the bounds overlap. Geometry had to change.
--
-- So this version registers its own obstacle, sized to a single slot, through
-- the same sjson.hook path already used for the icons. PonyMenu performs this
-- exact insert into data.Obstacles for its Box_FullScreen graphic, so the
-- mechanism is proven; only the payload is new. Half-extents are configurable
-- because the right numbers can only be judged in game.
--
-- If the obstacle cannot be registered for any reason, button creation falls
-- back to ButtonInventoryItem and says so -- degraded hit-testing, but working.
local BUTTON_KEY_PREFIX = "SelectFirstBoonBtn_"
local BUTTON_LIST_FIELD = "SelectFirstBoonButtons"
local SELECTED_ALPHA = 1.0

-- 0.4 was hard to read: an unpicked god was nearly invisible against the slot.
-- The pick is signalled by size as well as brightness now (see restScaleFor), so
-- the unpicked ones no longer have to be pushed that far down to stay distinct.
local function unselectedAlpha()
    local value = tonumber(settings.values.UnselectedBrightness)
    if value == nil or value < 0 or value > 1 then return 0.7 end
    return value
end

local INFO_KEYS = { "InfoBoxName", "InfoBoxDescription", "InfoBoxDetails", "InfoBoxFlavor" }

-- Size is a component scale set at draw time, not a number baked into the sjson
-- animation. PonyMenu does the same (its ready.lua:390), and it buys two things:
-- the size becomes tunable without a restart, and SkipGeometryUpdate means the
-- art can grow while the hitbox stays exactly one grid cell.
--
-- Selene needs it. Her art is the SpellDrop door preview, from a different
-- folder than the god symbols, and it draws visibly smaller at the same scale.
-- The size a button sits at when nothing is hovering it. The picked one stays
-- larger, so the choice reads at a glance rather than only by brightness -- and
-- hovering multiplies from here rather than from 1.0, so a hovered pick grows
-- from its own size instead of shrinking to everyone else's.
local function restScaleFor(baseScale, lit)
    if not lit then return baseScale end
    local grow = tonumber(settings.values.SelectedIconScale) or 1.0
    if grow <= 0 then grow = 1.0 end
    return baseScale * grow
end

-- ICON SIZE TUNING
--
-- Every icon in the grid comes from a different art family and none are drawn at
-- a comparable native size, so one global multiplier cannot make them match --
-- push it high enough for the small ones and the large ones overflow their slot
-- and their hitbox with it. These are per-icon corrections applied on top of the
-- global size, so the global one can stay at 1.0 where hit-testing behaves.
--
-- Keyed on the icon's own name, recovered from the resolved animation name,
-- because that is the thing whose art size is wrong -- not the god, who may draw
-- different art in different styles.
--
-- Hung off CONFIG rather than declared as its own local: main.lua sits at
-- exactly Lua's 200-local ceiling for the main chunk, so ANY new top-level local
-- fails to parse. See CLAUDE.md. Assignment into an existing table costs none.
CONFIG.tune = {
    prefixes = {
        BOONDROP_ICON_PREFIX, PORTRAIT_ICON_PREFIX,
        CUSTOM_ICON_PREFIX, SELENE_ICON_PREFIX,
    },
}

function CONFIG.tune.baseName(resolvedIcon)
    if type(resolvedIcon) ~= "string" then return nil end
    -- Her own entry is named after its art file (..._preview), not after her, so
    -- stripping the prefix yields "preview" and looks up a setting that does not
    -- exist. Everyone else's entry already carries their name.
    if resolvedIcon == SELENE_ICON_NAME then return "Selene" end
    for _, prefix in ipairs(CONFIG.tune.prefixes) do
        if resolvedIcon:sub(1, #prefix) == prefix then
            return resolvedIcon:sub(#prefix + 1)
        end
    end
    return nil
end

function CONFIG.tune.coreFor(resolvedIcon)
    local base = CONFIG.tune.baseName(resolvedIcon)
    if base == nil then return 1.0 end
    local value = tonumber(settings.values["Core" .. base])
    if value == nil or value < 0 then return 1.0 end
    return value
end

function CONFIG.tune.lightFor(resolvedIcon)
    local base = CONFIG.tune.baseName(resolvedIcon)
    if base == nil then return 1.0 end
    local value = tonumber(settings.values["Light" .. base])
    if value == nil or value < 0 then return 1.0 end
    return value
end

function CONFIG.tune.sizeFor(resolvedIcon)
    local base = CONFIG.tune.baseName(resolvedIcon)
    if base == nil then return 1.0 end
    local value = tonumber(settings.values["Size" .. base])
    if value == nil or value <= 0 then return 1.0 end
    return value
end

-- drawsPortrait is passed in rather than worked out here: the answer depends on
-- iconInStyle, which is defined below. It matters because the boost used to key
-- off extra.portraitOnly -- "this god has nothing but a portrait" -- and that is
-- no longer the same question as "this slot is drawing a portrait". Artemis,
-- Athena, Dionysus and Hades have symbols, so they are not portraitOnly, but in
-- the door style they draw portraits and need the same correction.
local function iconScaleFor(option, drawsPortrait)
    local size = tonumber(settings.values.IconSize) or 1.0
    if size <= 0 then size = 1.0 end

    local special = option ~= nil and option.special or nil
    -- Her art comes from a different family in every style except portraits, so
    -- the correction applies everywhere except there.
    local per = CONFIG.tune.sizeFor(option ~= nil and option.icon or nil)

    if special ~= nil and special.file ~= nil and not usingPortraits() then
        local boost = tonumber(settings.values.SeleneIconBoost) or 0
        if boost > 0 then return size * boost * per end
    end

    -- A portrait-only god has the same problem for the same reason: different
    -- source art from the god symbols beside him, so the same size at the same
    -- scale is not the same size on screen.
    local extra = option ~= nil and option.value ~= nil
        and EXTRA_GOD_BY_LOOT[option.value] or nil
    -- Only when the portrait is the odd one out. In the portrait style every
    -- slot is a portrait, so there is no mismatch to correct -- same reason the
    -- Selene branch above guards on it.
    if (drawsPortrait and not usingPortraits()) or (extra ~= nil and extra.portraitOnly) then
        local boost = tonumber(settings.values.PortraitIconBoost) or 0.7
        if boost > 0 then return size * boost * per end
    end
    return size * per
end


-- Row width comes from the screen, not from us. The vanilla resource grid fills
-- a row to screen.GridWidth and then wraps (ResourceLogic.lua:614-620); with
-- GridWidth 8 that is eight across, then the remainder on the next row -- which
-- is what every other tab looks like. Earlier versions hard-coded 5 per row to
-- buy clearance between the oversized hitboxes; that reason is gone now the box
-- is one cell (see BUTTON OBSTACLE), so this just does what the screen says.
local FALLBACK_ROW_WIDTH = 8

local function rowWidthFor(screen)
    local width = screen ~= nil and tonumber(screen.GridWidth) or nil
    if width == nil or width < 1 then return FALLBACK_ROW_WIDTH end
    return math.floor(width)
end

-- Adjacent rows are fine once the hitbox is slot-sized; see BUTTON OBSTACLE.
local ROW_STRIDE = 1

-- The two delay gates sit in the LAST two slots of the grid's bottom row, as far
-- from the flowing icons as the panel allows. They are a different kind of
-- control -- when Hermes and Selene may appear at all, not what goes first -- and
-- with fourteen-plus options now filling two rows, a gap alone no longer reads as
-- separation. Opposite corner does.
local GATE_ROW = 4


-- No GamepadNavigation block on the category deliberately. v2.4.1 copied the
-- one from InventoryScreen_PinTab, but that tab is a vertical list; this is a
-- grid, and the grid that demonstrably works with a controller is the resource
-- grid, which uses the SCREEN's own block (ResourceData.lua:3999). Notably its
-- FreeFormSelectSuccessDistanceStep is 1, against the Pin tab's 8 -- a much
-- finer search. Omitting the category block makes SetGamepadNavigation fall
-- through to the screen's settings.

local function verbose(message)
    if settings.values.VerboseTabLog then
        logAlways("[tab] " .. tostring(message))
    end
end

-- Selene's halo, as a second component rather than a property of the first.
--
-- Returns the component, or nil when there is nothing to draw -- every icon on
-- the page except Selene's, and Selene's too at a strength of 0. Matching on the
-- animation NAME rather than on the option is deliberate: whichever style is
-- active, if the art that landed here is Selene's stand-in then it is the art
-- that wants the halo.
--
-- Every step is logged, and loudly. 4.9.0's halo silently never ran, and the
-- only reason that was findable at all is that the ABSENCE of a line was itself
-- evidence -- so now the skip says why it skipped.
-- SIZE, and why the knob was renamed.
--
-- 4.10.0 multiplied the spread by the icon's own scale, on the theory that a
-- bigger icon wants a bigger halo. With Selene's boost at 1.5 the SMALLEST
-- preset came out at 1.8, and particle_glow is a large texture: the halo covered
-- a serious fraction of the screen rather than the slot. Every art option looked
-- "too big" because every art option was being sized the same wrong way.
--
-- The spread is now the component scale directly. Nothing is multiplied into it,
-- so the number in the menu is the number the game uses, and it lives under a
-- NEW key -- an existing config still holding 3.5 under the old one would have
-- reproduced the same wall of light against the new presets.
local SELENE_HALO_DEFAULT_SPREAD = 0.2

-- Additive alpha stops at 1.0, and one layer of it read fainter than the bloom
-- painted into the god symbols. Drawing the same sprite more than once is how
-- additive light gets brighter past that ceiling -- vanilla does the same thing
-- with BoonDropA/B/C, three glow layers on one orb.
local SELENE_HALO_MAX_LAYERS = 4

-- WHICH ICONS WANT A HALO, and in what colour.
--
-- Built for Selene, and it generalises because her problem was never hers alone:
-- the god symbols carry a glow painted into the texture, and any icon drawn from
-- a different set does not. Beside them it reads flat and out of place -- which
-- is exactly what a keepsake portrait does, as the gods with no emblem of their
-- own now demonstrate.
--
-- Returns the tint, or nil for an icon that already glows on its own.
-- Returns the tint AND a per-god multiplier on the halo's strength, because one
-- strength does not suit every picture: a pale portrait needs less glow than a
-- dark one to read the same. The multiplier is 1.0 for anyone with nothing to
-- say about it, so the shared dial keeps meaning what it says.
local function iconHaloFor(iconName)
    if iconName == seleneIconName() then return SELENE_GLOW_COLOR, 1.0 end

    for _, god in ipairs(EXTRA_GODS) do
        if god.portraitOnly and PORTRAIT_SET[god.name]
            and iconName == portraitIconName(god.name) then
            local scale = tonumber(settings.values[god.haloSetting or ""]) or 1.0
            if scale < 0 then scale = 0 end
            -- Stashed at registration from the game's own colour for them; see
            -- registerGod. Falls back to Selene's rather than to nothing, so a
            -- god the game gave no colour still gets a halo.
            return god.haloColor or SELENE_GLOW_COLOR, scale
        end
    end
    return nil, 1.0
end

-- The god's own colour, for the selection light when it is set to tint.
--
-- LootColor is what the game itself uses for that god's drop; the fallbacks
-- exist because several characters never had a boon on the ground and so have
-- no LootColor, but every one has a voice colour.
--
-- Softened towards white rather than used raw: at full saturation this stops
-- reading as "picked" and starts reading as part of the art, which is the whole
-- reason the neutral light is the default.
function CONFIG.godLightColor(game, god, mix)
    if game == nil or god == nil then return nil end

    -- haloColor first, for the added gods. It was worked out at registration
    -- from npc.LootColor or npc.LightingColor or npc.SubtitleColor, and that
    -- third step is what makes it distinct for the six with portraits: they
    -- never had a boon on the ground so have no LootColor, and the entry this
    -- mod writes for them falls back to one SHARED colour. Reading LootData
    -- here would hand all six the same light. The chain that already solved
    -- this is the one to use.
    local extra = EXTRA_GOD_BY_LOOT[god]
    local source = extra ~= nil and extra.haloColor or nil

    if source == nil then
        local data = game.LootData and game.LootData[god] or nil
        source = data ~= nil
            and (data.LootColor or data.LightingColor or data.SubtitleColor) or nil
    end
    if type(source) ~= "table" or type(source[1]) ~= "number" then return nil end
    local blend = tonumber(mix) or 0.5
    if blend < 0 then blend = 0 end
    if blend > 1 then blend = 1 end
    local out = {}
    for i = 1, 3 do
        local c = tonumber(source[i]) or 255
        out[i] = math.floor(c * blend + 255 * (1 - blend) + 0.5)
    end
    out[4] = 255
    return out
end

-- A near-white light, deliberately not a god colour. This one means "picked",
-- and a tint borrowed from a god would read as part of that god's art instead.
CONFIG.selectionHaloColor = { 235, 235, 245, 255 }

local function makeIconHalo(game, screen, index, spec, iconScale)
    local tint, perGod, spread, layers, strength

    -- SELECTION LIGHT
    --
    -- The same layered additive sprite that used to fake a halo onto portraits,
    -- pointed at a job worth doing: marking the pick. Size alone carried that
    -- signal before (see restScaleFor), which is thin on a page of icons and
    -- gets thinner with a multi-god pool, where several are marked at once.
    --
    -- Checked before the per-god path and returns instead of falling through:
    -- once no art carries a painted halo of its own, a light on the page means
    -- one thing, and two kinds of glow would put that back.
    -- Whatever is lit gets the light, gates included. One rule and no switch:
    -- a switch here was only ever a way for the squares to end up dark by
    -- accident.
    local isSelection = false
    if spec.lit and settings.values.SelectionHalo then
        isSelection = true
        tint = CONFIG.selectionHaloColor
        if settings.values.SelectionHaloTint == "god" then
            tint = CONFIG.godLightColor(game, spec.god,
                       tonumber(settings.values.SelectionHaloTintMix) or 0.5)
                   or CONFIG.selectionHaloColor
        end
        strength = (tonumber(settings.values.SelectionHaloStrength) or 0)
            * CONFIG.tune.lightFor(spec.icon)
        spread = tonumber(settings.values.SelectionHaloSize) or 0
        layers = math.floor(tonumber(settings.values.SelectionHaloLayers) or 1)
    else
        tint, perGod = iconHaloFor(spec.icon)
        if tint == nil then return nil end
        strength = (tonumber(settings.values.SeleneGlowStrength) or 0) * perGod
        spread = tonumber(settings.values.SeleneHaloSpread) or 0
        layers = math.floor(tonumber(settings.values.SeleneHaloLayers) or 1)
    end

    if strength <= 0 then
        verbose("icon halo skipped: strength is 0")
        return nil
    end
    if strength > 1 then strength = 1 end

    if spread <= 0 then spread = SELENE_HALO_DEFAULT_SPREAD end

    if layers < 1 then layers = 1 end
    if layers > SELENE_HALO_MAX_LAYERS then layers = SELENE_HALO_MAX_LAYERS end

    if type(game.CreateScreenComponent) ~= "function" then return nil end
    local source = seleneGlowSource()
    local animName = SELENE_GLOW_ANIM .. "_" .. source.key
    local x = spec.x
    local y = spec.glowY or spec.y

    -- Only the first layer is returned and tracked as button.SelectFirstBoonGlow;
    -- the rest are held in the same list so cleanup destroys all of them.
    local first = nil
    local extras = nil
    for layer = 1, layers do
        -- LAYERS THAT SPREAD, NOT LAYERS THAT STACK.
        --
        -- The per-god halo draws every layer at one size and place, so they pile
        -- up. The glow texture is a radial gradient, and piling it up multiplies
        -- the middle -- where it is already brightest -- while the edges, near
        -- zero, stay near zero. The result is a hot spot over the art rather
        -- than a ring around it.
        --
        -- For the selection light each layer instead grows and fades: the outer
        -- ones carry the halo outwards without adding to the centre. Only for
        -- the selection light; the per-god path is left as it was, and a test
        -- asserts its layers still sit at the same place and size.
        -- THE LIGHT FOLLOWS THE ICON.
        --
        -- spread is an absolute size, so the same light covers proportionally
        -- less of a large icon than a small one. The clearest case is a gate,
        -- which grows when it is on: identical settings, visibly different
        -- result, next to the same god's icon in the grid. Scaling by the
        -- icon's own size makes the light read the same wherever it is drawn.
        --
        -- What arrives here is the LIT MULTIPLIER -- how much bigger this is
        -- drawn than its own resting size -- not the icon's absolute scale.
        --
        -- The absolute scale was the wrong thing and for the second time: it is
        -- a per-art-family correction, not a measure of rendered size. Portraits
        -- sit near 0.4 while drawing large, symbols near 1.7, so scaling the
        -- light by it made the light vanish on portraits and balloon on symbols.
        -- The same confusion put the hitbox bug in.
        --
        -- The per-icon sizes are tuned so everything renders about the same, so
        -- the light wants to be the same too. The one thing it should follow is
        -- a thing growing because it is picked, or because a gate is on.
        local followScale = 1.0
        if isSelection then
            local follow = tonumber(settings.values.SelectionHaloFollowsIcon)
            if follow == nil then follow = 1.0 end
            local litMul = tonumber(iconScale) or 1.0
            if litMul <= 0 then litMul = 1.0 end
            followScale = 1 + (litMul - 1) * follow
        end

        local layerScale, layerAlpha = spread * followScale, strength
        if isSelection then
            if layer > 1 then
                local step = tonumber(settings.values.SelectionHaloSpreadStep) or 0.35
                layerScale = spread * followScale * (1 + (layer - 1) * step)
                layerAlpha = strength / layer
            else
                -- The innermost layer is the one sitting directly behind the
                -- art, and it is what makes thin shapes unreadable: a pale gold
                -- wing on a gold glow has almost no contrast left, while a solid
                -- emblem is barely touched at the same strength. Dropping this
                -- towards 0 hollows the middle out and leaves a ring, which the
                -- art then sits inside rather than on top of.
                local core = tonumber(settings.values.SelectionHaloCore)
                if core == nil then core = 1.0 end
                if core < 0 then core = 0 end
                layerAlpha = strength * core * CONFIG.tune.coreFor(spec.icon)
            end
        end
        local glow = game.CreateScreenComponent({
            Name = "BlankObstacle",
            Group = "Combat_Menu_Overlay_Additive",
            Scale = layerScale,
            X = x,
            Y = y,
            Alpha = 0.0,
            AlphaTarget = layerAlpha,
            AlphaTargetDuration = 0.2,
        })
        -- SetAnimation on a name the game does not know is the one failure mode
        -- that would leave a live but blank component, so it is caught and named
        -- rather than left to look like "the texture did not render".
        local animOk, animErr = pcall(game.SetAnimation,
            { DestinationId = glow.Id, Name = animName })
        if not animOk then
            logWarn("Selene halo animation " .. animName .. " was rejected: " .. tostring(animErr))
        end
        if type(game.SetRGB) == "function" then
            local layerTint = tint
            -- A RAMP, not one colour for every layer.
            --
            -- These layers are additive, so where they overlap -- the middle --
            -- the channels saturate and clip to white on their own. On a thin
            -- pale icon that white reaches out further than the art, and the
            -- god's colour only survives at the very edge.
            --
            -- Ramping the tint pushes back: the outermost layer stays the god's
            -- colour and each one inward is mixed further towards white by hand,
            -- so where the transition happens is a setting rather than whatever
            -- the blend mode does. 0 keeps every layer the same colour.
            if isSelection and layers > 1 then
                local whiten = tonumber(settings.values.SelectionHaloWhiten) or 0
                if whiten > 0 then
                    -- 1 at the innermost layer, 0 at the outermost.
                    local t = (layers - layer) / (layers - 1) * whiten
                    layerTint = {}
                    for i = 1, 3 do
                        local c = tonumber(tint[i]) or 255
                        layerTint[i] = math.floor(c * (1 - t) + 255 * t + 0.5)
                    end
                    layerTint[4] = tint[4] or 255
                end
            end
            game.SetRGB({ Id = glow.Id, Color = layerTint })
        end
        if screen ~= nil and screen.Components ~= nil then
            local key = BUTTON_KEY_PREFIX .. index .. "Glow"
            if layer > 1 then key = key .. layer end
            screen.Components[key] = glow
        end
        if layer == 1 then
            first = glow
        else
            extras = extras or {}
            extras[#extras + 1] = glow
        end
    end

    if first ~= nil then
        first.SelectFirstBoonGlowExtras = extras
        -- Which kind of light this is. applySelection tears down and rebuilds
        -- the selection one as the pick moves, and must not touch a per-god halo
        -- -- Selene's lives on her button whether she is picked or not.
        first.SelectFirstBoonIsSelectionLight = isSelection
    end
    verbose(("icon halo drawn on %s: source=%s anim=%s strength=%.0f%% spread=%.2f layers=%d at (%.1f, %.1f)")
        :format(tostring(spec.icon), source.key, animName, strength * 100, spread,
                layers, x, y))
    return first
end

local function setTabIcon(game, iconName)
    local screenData = game.ScreenData and game.ScreenData.InventoryScreen
    if screenData == nil or type(screenData.ItemCategories) ~= "table" then return end
    for _, category in ipairs(screenData.ItemCategories) do
        if category.Name == TAB_CATEGORY_NAME then
            category.Icon = iconName
            return
        end
    end
end

-- Resolve an option to an art name in whichever set is selected, falling back
-- one step at a time: chosen set -> the other set -> the game's own icon.
local function iconInStyle(name)
    if not customIconsRegistered then return nil end
    if usingBoonDrops() then
        if BOONDROP_SET[name] then return boonDropIconName(name) end
        if name == "Hammer" then return boonDropIconName("Hammer") end
        -- Nothing flat in the door set for this one. Take the portrait ahead of
        -- the symbol: BoonSelectSymbols art has a halo painted into the texture
        -- that no property removes, and four glowing icons among nineteen flat
        -- ones read worse than a portrait does. Artemis, Athena, Dionysus and
        -- Hades land here -- they have symbols, but only haloed ones.
        if PORTRAIT_SET[name] then return portraitIconName(name) end
    end
    if usingPortraits() and PORTRAIT_SET[name] then
        return portraitIconName(name)
    end
    if SYMBOL_SET[name] then
        return customIconName(name)
    end
    -- Asked for a name the chosen set does not carry: fall through the others
    -- rather than draw nothing.
    if PORTRAIT_SET[name] then return portraitIconName(name) end
    if BOONDROP_SET[name] then return boonDropIconName(name) end
    return nil
end

-- True when this slot will actually draw a portrait, whatever the reason. Used
-- for both the size boost and the vertical nudge, which were keyed off the god's
-- classification and are now keyed off the art.
--
-- Takes the RESOLVED icon name, not a god name. option.icon is already the
-- output of tabIconFor, so feeding it back through iconInStyle -- which keys on
-- raw god names -- returned nil every time and this quietly answered false for
-- everything.
local function drawsPortraitIcon(resolvedIcon)
    return type(resolvedIcon) == "string"
        and resolvedIcon:sub(1, #PORTRAIT_ICON_PREFIX) == PORTRAIT_ICON_PREFIX
end

local function tabIconFor(game, god)
    local special = specialFor(god)
    if special ~= nil then
        if customIconsRegistered then
            -- Order matters. In the symbol style Selene has no symbol, so she
            -- must fall to her OWN entry rather than borrow a portrait; in the
            -- other two styles she is named in the set like everyone else.
            if not usingPortraits() and not usingBoonDrops() then
                if special.symbol ~= nil and SYMBOL_SET[special.symbol] then
                    return customIconName(special.symbol)
                end
                if special.file ~= nil then
                    return seleneIconName()
                end
            end
            -- Portraits are the one style where she has a real matched entry.
            if usingPortraits() and special.portrait ~= nil and PORTRAIT_SET[special.portrait] then
                return portraitIconName(special.portrait)
            end
            if special.file ~= nil then
                return seleneIconName()
            end
            local named = iconInStyle(special.portrait or special.symbol)
            if named ~= nil then return named end
        end
        return DEFAULT_TAB_ICON
    end
    -- A portrait-only god has no emblem in any set, so the icon style does not
    -- apply to him -- there is one picture and this is it. Checked before the
    -- style branches rather than after, so he does not fall through them all and
    -- come out blank.
    local extra = EXTRA_GOD_BY_LOOT[god]
    if extra ~= nil and extra.portraitOnly and customIconsRegistered
        and PORTRAIT_SET[extra.name] then
        return portraitIconName(extra.name)
    end

    if god ~= nil and god ~= NONE_VALUE then
        local lootData = game.LootData and game.LootData[god]
        local symbol = symbolNameFor(game, god)
        if symbol ~= nil then
            local named = iconInStyle(symbol)
            if named ~= nil then return named end
        end
        if lootData ~= nil and type(lootData.BoonInfoIcon) == "string" and lootData.BoonInfoIcon ~= "" then
            return lootData.BoonInfoIcon
        end
    end
    local named = iconInStyle(standardSymbol())
    if named ~= nil then return named end
    return DEFAULT_TAB_ICON
end

-- The icon on the TAB STRIP is not one of our buttons: vanilla creates it in its
-- category loop (ResourceLogic.lua:290) at screen.CategoryIconScale, which is
-- 0.45 (ResourceData.lua:3931) -- a fraction of the size the grid draws at.
--
-- 4.8.0 got this wrong by reusing the grid's scale here. SetScale's Fraction is
-- ABSOLUTE, not a multiplier (ResourcePresentation.lua:105 resets a button to
-- its base with it), so handing it the grid's 1.0 blew every tab icon up to more
-- than double the size vanilla draws it -- which is exactly what was reported,
-- for Selene and for everyone else.
--
-- So the base here is the tab's own scale, and the ONLY thing layered on top is
-- Selene's correction, because her art really is smaller than the god symbols.
-- Every other god is left exactly where vanilla put it, untouched.
local function scaleTabStripIcon(game, screen, god)
    local components = screen ~= nil and screen.Components or nil
    local icon = components ~= nil and components["CategoryIcon" .. TAB_CATEGORY_NAME] or nil
    if icon == nil or type(game.SetScale) ~= "function" then return end

    local base = tonumber(screen.CategoryIconScale)
    if base == nil or base <= 0 then base = tonumber(settings.values.TabIconScale) or 0.45 end
    if base <= 0 then base = 0.45 end

    -- Vanilla's own tab icons read a touch small on this page, so there is one
    -- multiplier that applies to EVERY god including the ones needing no other
    -- correction. 1.0 is exactly vanilla.
    local tabBoost = tonumber(settings.values.TabIconBoost) or 0
    if tabBoost <= 0 then tabBoost = 1.0 end

    -- Set unconditionally rather than skipped for gods who need no correction:
    -- switching the pick from Selene to a god has to put the strip icon BACK,
    -- and a skip would leave her boost applied to his art.
    local special = specialFor(god)
    local boost = 1.0
    if special ~= nil and special.file ~= nil and not usingPortraits() then
        boost = tonumber(settings.values.SeleneIconBoost) or 0
        if boost <= 0 then boost = 1.0 end
    end

    -- The strip had the same defect as the grid and needed the same correction:
    -- a portrait is bigger art than a god symbol, so at one shared scale the
    -- portraits came out too large while the symbols were right, with no way to
    -- move one without the other.
    --
    -- The SAME multiplier as the grid, deliberately. The ratio between the two
    -- art families is a property of the textures, identical wherever they are
    -- drawn; only the base scale differs. A second dial would be a second place
    -- to tune the same fact.
    -- Resolved here for the same reason the grid does it: what matters is the
    -- art this god actually draws, not what art the god owns. Keying the
    -- portrait correction off extra.portraitOnly missed Artemis, Athena,
    -- Dionysus and Hades, who own symbols but draw portraits in the door style.
    local resolved = tabIconFor(game, god)

    local extra = EXTRA_GOD_BY_LOOT[god]
    if (drawsPortraitIcon(resolved) and not usingPortraits())
        or (extra ~= nil and extra.portraitOnly) then
        local portrait = tonumber(settings.values.PortraitIconBoost) or 0
        if portrait > 0 then boost = boost * portrait end
    end

    -- The per-icon correction applies here too, by the same argument the comment
    -- above makes about the portrait multiplier: the size of a texture relative
    -- to its neighbours is a property of the texture, identical wherever it is
    -- drawn. Only the base scale differs between the strip and the grid. Without
    -- this, tuning an icon in the grid leaves the strip showing the old size.
    local per = CONFIG.tune.sizeFor(resolved)

    local scale = base * tabBoost * boost * per
    game.SetScale({ Id = icon.Id, Fraction = scale, Duration = 0.0,
                    SkipGeometryUpdate = true })
    verbose(("tab strip icon scaled to %.2f (%.2f base x %.2f tab x %.2f god x %.2f per-icon)")
        :format(scale, base, tabBoost, boost, per))
end

local function refreshTabIcon(game)
    if not settings.values.ShowInventoryTab then return end
    local ok, err = pcall(function()
        setTabIcon(game, tabIconFor(game, settings.values.God))
    end)
    if not ok then logWarn("could not update the tab icon: " .. tostring(err)) end
end

-- THREE BLOCKS, each starting on its own row.
--
-- One long run of icons was fine at thirteen options and stopped being fine at
-- twenty-two: the Olympians, the odd rewards and the added gods are three
-- different KINDS of thing, and reading them as one list makes you check every
-- icon to find the one you want. Wrapping mid-block made it worse -- a row could
-- end with two Olympians and begin with a hammer.
--
--     Standard, then the nine Olympians   as many rows as they need
--     Hammer, Hermes, Selene, Chaos       one row, on their own
--     everything this plugin adds         as many rows as they need
--
-- Separated by one BLANK SLOT rather than by a row break. A row per block cost
-- three rows for twelve icons and pushed the whole grid down far enough to shove
-- the override squares off the bottom of it. A gap of one slot reads as a break
-- just as clearly and costs one cell.
local function tabOptions(game)
    local options = { { value = NONE_VALUE, label = STANDARD_LABEL, icon = tabIconFor(game, NONE_VALUE) } }

    local added = {}
    for _, lootName in ipairs(catalog.names) do
        local option = {
            value = lootName,
            label = catalog.labels[lootName] or lootName,
            icon = tabIconFor(game, lootName),
        }
        -- Split by what they ARE, not by name: an added god is one this plugin
        -- registered, which EXTRA_GOD_BY_LOOT is the record of.
        if EXTRA_GOD_BY_LOOT[lootName] ~= nil then
            added[#added + 1] = option
        else
            options[#options + 1] = option
        end
    end

    for index, special in ipairs(SPECIALS) do
        options[#options + 1] = {
            value = special.value,
            label = special.label,
            icon = tabIconFor(game, special.value),
            special = special,
        }
    end

    -- Emblem gods first, then the portrait ones, alphabetical within each. The
    -- two halves LOOK different -- a god's emblem beside a character's face --
    -- so interleaving them by name reads as a mistake even when it is not.
    table.sort(added, function(left, right)
        local leftGod = EXTRA_GOD_BY_LOOT[left.value]
        local rightGod = EXTRA_GOD_BY_LOOT[right.value]
        local leftPortrait = leftGod ~= nil and leftGod.portraitOnly == true
        local rightPortrait = rightGod ~= nil and rightGod.portraitOnly == true
        if leftPortrait ~= rightPortrait then return rightPortrait end
        return tostring(left.label) < tostring(right.label)
    end)

    -- The portrait half starts a ROW of its own rather than flowing on from the
    -- emblem half. Same reason the two are sorted apart in the first place: a
    -- character's face beside a god's emblem reads as a mistake, and a row that
    -- is half emblems and half faces reads as the worst version of it. Given
    -- their own row they read as a set.
    local firstPortrait = nil
    for index, option in ipairs(added) do
        local god = EXTRA_GOD_BY_LOOT[option.value]
        if firstPortrait == nil and god ~= nil and god.portraitOnly == true then
            firstPortrait = index
        end
    end

    for index, option in ipairs(added) do
        -- A ROW break, not a blank slot. The specials lost their separator in
        -- 4.28.0 -- a single empty cell mid-row read as a missing icon rather
        -- than as a boundary, which is the opposite of what it was for -- so the
        -- one break that survives is the one that reads unambiguously: vanilla's
        -- rewards on their own rows, everything this plugin adds below them.
        option.rowBreak = (index == 1) or (index == firstPortrait and index > 1)
        options[#options + 1] = option
    end

    return options
end

-- =============================================================================
-- INFO PANEL
-- =============================================================================
--
-- Up to 2.7.0 this tab drew its own text box across the lower half of the grid.
-- That is not where this screen puts item text: every vanilla category writes
-- into the scroll on the right, through four boxes laid out at
-- ResourceData.lua:4428-4500 and filled by MouseOverResourceItem
-- (ResourcePresentation.lua:39-79):
--
--     InfoBoxName         the item's name, 32pt small-caps
--     InfoBoxDescription  what it is
--     InfoBoxDetails      where it comes from, in Hecate purple
--     InfoBoxFlavor       italic flavour text, near the bottom
--
-- Those components already exist on the screen -- they belong to the screen, not
-- to any category -- so this tab just writes to them. Two details make that
-- safe. InventoryScreenDisplayCategory fades all four to zero at
-- ResourceLogic.lua:396-399, and that runs BEFORE our OpenFunctionName is called
-- at :437, so anything written here survives the switch. And vanilla passes
-- localisation keys, which we have none of -- but the same ModifyTextBox takes
-- RawText, which is what the old bottom-of-screen block already used.
local function infoComponent(screen, key)
    local components = screen ~= nil and screen.Components or nil
    return components ~= nil and components[key] or nil
end

local function writeInfo(game, screen, key, lines)
    local component = infoComponent(screen, key)
    if component == nil then return false end
    if lines == nil or #lines == 0 then
        game.ModifyTextBox({ Id = component.Id, FadeTarget = 0.0 })
        return true
    end
    game.ModifyTextBox({ Id = component.Id, RawText = lines[1], FadeTarget = 1.0, FadeDuration = 0.2 })
    for i = 2, #lines do
        game.ModifyTextBox({ Id = component.Id, RawText = lines[i], Append = true, NumLineBreaks = 1 })
    end
    return true
end

local function clearInfo(game, screen)
    for _, key in ipairs(INFO_KEYS) do
        local component = infoComponent(screen, key)
        if component ~= nil then
            game.ModifyTextBox({ Id = component.Id, FadeTarget = 0.0 })
        end
    end
end

local function godLabelFor(god)
    if god == nil or god == NONE_VALUE then return STANDARD_LABEL end
    local special = specialFor(god)
    if special ~= nil then return special.label end
    return catalog.labels[god] or god
end

-- One sentence per option, all the same shape: what the run does, asserted.
local function blurbFor(god)
    if god == nil or god == NONE_VALUE then
        return "The game's own reward order, unchanged."
    end
    local special = specialFor(god)
    if special ~= nil then return special.blurb end
    -- Neutral on purpose. This box says what the option DOES; whether it is the
    -- one in force is the flavour box's job. Before 4.9.0 this read "The run's
    -- first boon is Zeus", which asserted the state of the run from a mouse
    -- hover -- so every god the cursor crossed claimed to be the pick.
    return "Offer " .. godLabelFor(god) .. " as the run's first reward."
end

-- The two delay gates, as a table so the buttons, the panel lines and the
-- tooltips all read from one place and cannot drift apart.
local GATES = {
    { key = "BlockHermesBeforeBoon", reward = "HermesUpgrade", label = "Hermes Delay",
      who = "Hermes", option = "@Hermes" },
    { key = "BlockSeleneBeforeBoon", reward = "SpellDrop", label = "Selene Delay",
      who = "Selene", option = "@Selene" },
}

-- Reports the SETTING first and the override second.
--
-- Up to 4.1.0 an overridden gate reported only "Overridden", which hid whether
-- it was on or off -- so pressing the button appeared to do nothing at all, even
-- though the setting really was flipping underneath. Now the press is always
-- visible and the override is extra information rather than a replacement.
-- The game's own bold markup, as used throughout its UI text. If the info boxes
-- turn out not to parse tokens in RawText, this is the one place to switch off.
function CONFIG.bold(text)
    if settings.values.BoldGateWords == false then return text end
    return "{#BoldFormat}" .. text .. "{#Prev}"
end

local function gateOverridden(gate)
    local special = specialFor(settings.values.God)
    return special ~= nil and special.reward == gate.reward
end

-- Says what happens, not which way a switch is thrown.
--
-- "Hermes Delay: On" is two guesses away from the answer: whether On means the
-- delay is applied or the god is allowed, and then what a delay does. The
-- setting is BlockHermesBeforeBoon, so on means held back -- CANNOT. CAN and
-- CANNOT carry it, so they are capitalised and the rest is not.
-- What actually happens, then why.
--
-- The old line said which way a switch was thrown, which is two guesses from
-- the answer. Worse, when the pick overrode the gate it read "Hermes cannot be
-- first boon (overridden)" -- a sentence that contradicts itself. Picking a god
-- beats the delay, so in that case they CAN be first and the line has to say so
-- first, with the switch as the parenthetical.
--
-- Simpler than an earlier version, which also named the delay's own on/off
-- state in the parenthetical. Dropped on purpose: while the pick overrides a
-- gate, toggling it genuinely changes nothing for THAT pick -- Hermes spawns
-- first either way -- so there is nothing being hidden by leaving it out. It
-- only matters again if the pick changes away from Hermes, and this line is not
-- shown then.
--
-- "cannot", not "can't": Hades II's own UI text runs 27 to 4 that way in
-- HelpText and 6 to 0 in ScreenText. Contractions live in its dialogue.
local function gateState(gate)
    local blocked = settings.values[gate.key] == true
    local overridden = gateOverridden(gate)
    -- The pick wins, so the god can be first however the delay is set.
    local can = overridden or not blocked
    local word = can and "can" or "cannot"
    -- The trailing space has to sit INSIDE the bold span, before {#Prev}, not
    -- after it. Confirmed against the game's own text: every {#BoldFormat} use
    -- in HelpText.en.sjson puts its trailing space the same way --
    -- "{#BoldFormat}Erebus {#Prev}and beyond", never a space after {#Prev}. The
    -- renderer swallows whitespace right after the closing tag, which is why
    -- this read as "canbe" instead of "can be".
    local line = gate.who .. " " .. CONFIG.bold(word .. " ") .. "be first boon"
    if overridden then
        return line .. " (you picked " .. gate.who .. ")"
    end
    return line
end

local function gateLines()
    local lines = {}
    for _, gate in ipairs(GATES) do
        -- No label prefix: the sentence names the god itself now.
        lines[#lines + 1] = gateState(gate)
    end
    return lines
end

-- The resting state of the panel: what is set, and what the gates are doing.
-- Shown on open and restored whenever the cursor leaves a button, which is the
-- same rhythm as the vanilla tabs except that they fade to nothing instead.
-- Each box means one thing and keeps meaning it, at rest and on hover alike:
--
--     Name         what is under the cursor, or the page itself
--     Description  what that does
--     Details      the two delay gates, ALWAYS -- they never move somewhere else
--     Flavor       what pressing would do
local function drawTabText(game, screen)
    if not writeInfo(game, screen, "InfoBoxName", { "First Boon" }) then
        verbose("info panel components unavailable; no text drawn")
        return
    end

    -- A keepsake outranks the pick, so the page should not pretend otherwise
    -- while one is equipped.
    local keepsakeGod = equippedForcedGod(game)
    if keepsakeGod ~= nil then
        -- Same word the gates use for the same situation, so "overridden" means
        -- one thing on this page wherever it appears.
        writeInfo(game, screen, "InfoBoxDescription",
            { "Set to:  " .. godLabelFor(settings.values.God) })
        writeInfo(game, screen, "InfoBoxDetails", gateLines())
        writeInfo(game, screen, "InfoBoxFlavor",
            { "Idle this run -- your " .. godLabelFor(keepsakeGod)
              .. " keepsake takes the first boon." })
        return
    end

    writeInfo(game, screen, "InfoBoxDescription", { "Set to:  " .. godLabelFor(settings.values.God) })
    writeInfo(game, screen, "InfoBoxDetails", gateLines())
    writeInfo(game, screen, "InfoBoxFlavor", { "Pick the run's first reward." })
end

-- A gate button is lit when its gate is On, and dim when it is Off or
-- overridden -- overridden means the gate is not doing anything, so it should
-- not look like it is.
-- The two override squares are not picks, but they sit among picks, and until
-- 4.10.0 they were sized by their OWN on/off state through the same "the pick is
-- drawn bigger" rule -- so an off or overridden gate shrank, and the same Selene
-- art appeared at two sizes on one page. 4.9.0 pinned them to one size, which
-- fixed that and introduced a different inconsistency: picks change size, gates
-- only change brightness.
--
-- Both readings are defensible, so this is a setting rather than a verdict.
-- Four readings, because there is no single right one:
--
--   brightness  one size, brightness carries on/off        (4.9.0's behaviour)
--   size        both move, exactly like a picked boon      (4.10.0 addition)
--   size-only   size moves, brightness rests DIM           (4.11.0 addition)
--   none        nothing moves; the panel text is the signal
--
-- "size-only" rests an OFF gate at the same size an unpicked boon sits at in the
-- grid, so the two halves of the page agree about what small means.
local function gateStateStyle()
    local value = settings.values.GateStateStyle
    if value == "size" or value == "size-only" or value == "none" then return value end
    return "brightness"
end

-- The two signals are independent, and every style is a choice of which one
-- carries the state. Splitting them here is what keeps applySelection honest:
-- before 4.11.0 it forced one flag for both and "size-only" was unexpressible.
-- Frozen at WHICH level is the second half of the question. "none" means the
-- square never reacts, so it rests bright; "size-only" rests at the same dim
-- level an unpicked boon sits at in the grid, so the two halves of the page
-- agree about what dim means and the size is left to carry the state alone.
local function gateFreezesBrightness()
    local style = gateStateStyle()
    return style == "none" or style == "size-only"
end

local function gateFrozenBrightnessIsLit()
    return gateStateStyle() ~= "size-only"
end

local function gateFreezesSize()
    local style = gateStateStyle()
    return style == "none" or style == "brightness"
end

local function buttonIsLit(game, button)
    local gate = button.SelectFirstBoonGate
    -- The gates keep working while a keepsake is equipped -- they decide when
    -- Hermes and Selene may appear, which is nothing to do with the pick.
    if gate ~= nil then
        return settings.values[gate.key] == true and not gateOverridden(gate)
    end
    -- A keepsake pauses the pick; it does not erase it. Dimming everything hid
    -- which option was chosen, so the pick stays lit and the panel carries the
    -- news that it is idle this run.
    return button.SelectFirstBoonGod == settings.values.God
end

local function applySelection(game, screen)
    local buttons = screen[BUTTON_LIST_FIELD]
    if buttons == nil then return end
    for _, button in ipairs(buttons) do
        local lit = buttonIsLit(game, button)
        local isGate = button.SelectFirstBoonGate ~= nil
        local litForAlpha = lit
        if isGate and gateFreezesBrightness() then
            litForAlpha = gateFrozenBrightnessIsLit()
        end
        game.SetAlpha({
            Id = button.Id,
            Fraction = litForAlpha and SELECTED_ALPHA or unselectedAlpha(),
            Duration = 0.1,
        })
        -- Size carries the choice as much as brightness does, so it has to move
        -- when the choice does.
        local rest = restScaleFor(tonumber(button.SelectFirstBoonIconScale) or 1.0,
                                  lit or button.SelectFirstBoonAlwaysBig == true)
        -- Nothing else to do: SelectFirstBoonAlwaysBig already encodes whether
        -- this button's SIZE is frozen, and `lit` is the gate's real state.
        button.SelectFirstBoonRestScale = rest
        game.SetScale({ Id = button.Id, Fraction = rest, Duration = 0.1,
                        SkipGeometryUpdate = true })

        -- The light has to follow the pick the way brightness and size do.
        -- It is components rather than a property, so it is torn down and
        -- rebuilt rather than set -- but only for the buttons whose state
        -- actually changed, so clicking around does not churn the whole grid.
        local wantsGlow = lit and settings.values.SelectionHalo == true
        -- Only a light this code put there. A per-god halo belongs to the art,
        -- not to the pick, and destroying it here would make Selene's vanish the
        -- moment anything else was selected.
        local hasGlow = button.SelectFirstBoonGlow ~= nil
            and button.SelectFirstBoonGlow.SelectFirstBoonIsSelectionLight == true
        if wantsGlow ~= hasGlow then
            local index = button.SelectFirstBoonSlot
            if hasGlow then
                game.Destroy({ Id = button.SelectFirstBoonGlow.Id })
                for _, extra in ipairs(button.SelectFirstBoonGlow.SelectFirstBoonGlowExtras or {}) do
                    game.Destroy({ Id = extra.Id })
                end
                if screen.Components ~= nil and index ~= nil then
                    screen.Components[BUTTON_KEY_PREFIX .. index .. "Glow"] = nil
                    for layer = 2, SELENE_HALO_MAX_LAYERS do
                        screen.Components[BUTTON_KEY_PREFIX .. index .. "Glow" .. layer] = nil
                    end
                end
                button.SelectFirstBoonGlow = nil
            elseif index ~= nil then
                local glow = makeIconHalo(game, screen, index, {
                    icon = button.SelectFirstBoonIcon,
                    god = button.SelectFirstBoonGodForLight,
                    x = button.SelectFirstBoonX,
                    y = button.SelectFirstBoonY,
                    glowY = button.SelectFirstBoonGlowY or button.SelectFirstBoonY,
                    lit = true,
                    isGate = button.SelectFirstBoonGate ~= nil,
                }, (tonumber(button.SelectFirstBoonRestScale) or 1.0)
                   / ((tonumber(button.SelectFirstBoonIconScale) or 1.0) ~= 0
                      and (tonumber(button.SelectFirstBoonIconScale) or 1.0) or 1.0))
                if glow ~= nil then button.SelectFirstBoonGlow = glow end
            end
        end
    end
end

-- Forward declaration: pickGod calls onButtonOver so that pressing a button
-- leaves the panel describing the button still under the cursor. Without this
-- the call would read a nil global and the press would throw.
local onButtonOver

local function pickGod(game, screen, button)
    -- Two kinds of button share this handler. A gate button toggles a delay
    -- setting and never touches the pick; everything else sets the pick.
    local gate = button.SelectFirstBoonGate
    if gate ~= nil then
        local nowOn = not settings.values[gate.key]
        saveSetting(gate.key, nowOn)
        logAlways(gate.label .. " turned " .. (nowOn and "on" or "off"))
        applySelection(game, screen)
        -- The cursor has not moved, so the panel must keep describing what is
        -- under it. Redrawing the RESTING text here was the bug: pressing a gate
        -- snapped the panel back to "First Boon" while still hovering the gate.
        onButtonOver(game, button)
        return
    end

    local god = button.SelectFirstBoonGod
    if god == nil then
        verbose("click arrived on a button with no god attached; ignored")
        return
    end

    verbose(("click resolved to slot %s (%s) at X=%.1f Y=%.1f")
        :format(tostring(button.SelectFirstBoonSlot), god == NONE_VALUE and STANDARD_LABEL or god,
                button.SelectFirstBoonX or -1, button.SelectFirstBoonY or -1))

    saveSetting("God", god)
    logAlways("first reward set to " .. godLabelFor(god))

    applySelection(game, screen)
    -- Same reasoning as the gate branch: still hovering, so still describing it.
    -- Picking also changes what the gate lines say, and onButtonOver rewrites
    -- those too, so they stay correct without a second pass.
    onButtonOver(game, button)

    local iconComponent = screen.Components and screen.Components["CategoryIcon" .. TAB_CATEGORY_NAME]
    if iconComponent ~= nil then
        game.SetAnimation({ DestinationId = iconComponent.Id, Name = tabIconFor(game, god) })
        pcall(scaleTabStripIcon, game, screen, god)
    else
        verbose("no live CategoryIcon component; tab icon will update on next open")
    end

    refreshTabIcon(game)
end

-- Hover, matched to MouseOverResourceItem / MouseOffResourceItem
-- (ResourcePresentation.lua:36, 88, 99, 106):
--
--   * the slot frame is an ANIMATION on the highlight component, not an alpha
--     fade -- InventoryScreenSlotIn / InventoryScreenSlotOut. Up to 2.7.0 this
--     tab faded a highlight that had no animation on it, so nothing was ever
--     drawn and there was no visible selection frame at all. That matters for
--     the controller specifically: without a frame there is no way to see which
--     button the stick is on.
--   * the icon grows by screen.IconMouseOverScale (1.33, ResourceData.lua:3975)
--     with SkipGeometryUpdate = true, so the art scales and the hitbox does not.
--     Without that flag the box would grow into its neighbours on hover and
--     reintroduce the overlap this version just removed.
-- "frame" is what every vanilla tab does: a slot outline appears behind the
-- icon. "grow" is PonyMenu's approach -- no outline at all, and the icon getting
-- bigger is the whole signal. The scale change below happens either way, so
-- "grow" is simply the frame left undrawn.
local function usingFrameHighlight()
    return settings.values.HighlightStyle ~= "grow"
end

function onButtonOver(game, button)
    local screen = button.Screen
    if button.Highlight ~= nil and usingFrameHighlight() then
        game.SetAnimation({ DestinationId = button.Highlight.Id, Name = "InventoryScreenSlotIn" })
    end
    -- Multiplied by the button's own scale, not replacing it -- vanilla does the
    -- same (IconScale * IconMouseOverScale, ResourcePresentation.lua:88).
    -- Replacing it would shrink Selene on hover instead of growing her.
    local base = tonumber(button.SelectFirstBoonRestScale)
        or tonumber(button.SelectFirstBoonIconScale) or 1.0
    local overScale = (screen ~= nil and tonumber(screen.IconMouseOverScale)) or 1.33
    game.SetScale({
        Id = button.Id,
        Fraction = base * overScale,
        Duration = 0.1, EaseIn = 0.9, EaseOut = 1.0, SkipGeometryUpdate = true,
    })

    local gate = button.SelectFirstBoonGate
    if gate ~= nil then
        local on = settings.values[gate.key] == true
        writeInfo(game, screen, "InfoBoxName", { gate.label })
        if on then
            writeInfo(game, screen, "InfoBoxDescription",
                { gate.who .. " is held back until you hold a boon." })
        else
            writeInfo(game, screen, "InfoBoxDescription",
                { gate.who .. " can turn up from the first room." })
        end
        -- Same box as always. The gate lines never move.
        writeInfo(game, screen, "InfoBoxDetails", gateLines())
        if gateOverridden(gate) then
            -- The press still works and still flips the setting; it just cannot
            -- take effect while that is the pick.
            writeInfo(game, screen, "InfoBoxFlavor",
                { (on and "Press to turn off." or "Press to turn on.")
                  .. "  Idle while " .. gate.who .. " is your pick." })
        else
            writeInfo(game, screen, "InfoBoxFlavor",
                { on and "Press to turn off." or "Press to turn on." })
        end
        verbose("hover on gate " .. gate.label)
        return
    end

    local god = button.SelectFirstBoonGod
    writeInfo(game, screen, "InfoBoxName", { godLabelFor(god) })
    writeInfo(game, screen, "InfoBoxDescription", { blurbFor(god) })
    writeInfo(game, screen, "InfoBoxDetails", gateLines())

    -- The press is real and still saves; it just cannot apply this run. Saying
    -- "overridden" per god read as though THAT god were overridden, when what is
    -- paused is the whole pick.
    local keepsakeGod = equippedForcedGod(game)
    -- State lives here and only here, which is what lets the description above
    -- stay neutral.
    local base = (god == settings.values.God)
        and "Your current pick."
        or "Press to make this your pick."
    if keepsakeGod ~= nil then
        writeInfo(game, screen, "InfoBoxFlavor",
            { base .. "  Idle while your " .. godLabelFor(keepsakeGod)
              .. " keepsake is equipped." })
    else
        writeInfo(game, screen, "InfoBoxFlavor", { base })
    end

    verbose("hover on slot " .. tostring(button.SelectFirstBoonSlot))
end

local function onButtonOff(game, button)
    if button.Highlight ~= nil and usingFrameHighlight() then
        game.SetAnimation({ DestinationId = button.Highlight.Id, Name = "InventoryScreenSlotOut" })
    end
    game.SetScale({
        Id = button.Id,
        Fraction = tonumber(button.SelectFirstBoonRestScale)
            or tonumber(button.SelectFirstBoonIconScale) or 1.0,
        Duration = 0.1, SkipGeometryUpdate = true,
    })
    drawTabText(game, button.Screen)
end

local function destroyTabButtons(game, screen)
    local buttons = screen[BUTTON_LIST_FIELD]
    if buttons == nil then return end
    local destroyed = 0
    for index, button in ipairs(buttons) do
        game.Destroy({ Id = button.Id })
        destroyed = destroyed + 1
        if button.Highlight ~= nil then
            game.Destroy({ Id = button.Highlight.Id })
            destroyed = destroyed + 1
        end
        if button.SelectFirstBoonGlow ~= nil then
            game.Destroy({ Id = button.SelectFirstBoonGlow.Id })
            destroyed = destroyed + 1
            -- Extra halo layers are components too, and leaking three of them
            -- per open would be invisible right up until it was not.
            for _, extra in ipairs(button.SelectFirstBoonGlow.SelectFirstBoonGlowExtras or {}) do
                game.Destroy({ Id = extra.Id })
                destroyed = destroyed + 1
            end
        end
        if screen.Components ~= nil then
            screen.Components[BUTTON_KEY_PREFIX .. index] = nil
            screen.Components[BUTTON_KEY_PREFIX .. index .. "Highlight"] = nil
            screen.Components[BUTTON_KEY_PREFIX .. index .. "Glow"] = nil
            for layer = 2, SELENE_HALO_MAX_LAYERS do
                screen.Components[BUTTON_KEY_PREFIX .. index .. "Glow" .. layer] = nil
            end
        end
    end
    screen[BUTTON_LIST_FIELD] = nil
    verbose("destroyed " .. destroyed .. " components on close")
end

local function tabOpen(game, screen)
    screen.NumItems = 0
    -- Held so a setting change can rebuild what is on screen instead of
    -- waiting for the player to leave the tab and come back. On CONFIG rather
    -- than ui: ui is declared hundreds of lines below this and would resolve as
    -- a nil global from in here.
    CONFIG.openScreen = screen
    CONFIG.openGame = game
    refreshCatalog(game)

    -- A category with a CloseFunctionName owns its own cleanup: vanilla's
    -- component-destroying loop only runs for categories without one
    -- (ResourceLogic.lua:381). Clear first in case of a re-open.
    destroyTabButtons(game, screen)

    local options = tabOptions(game)
    local buttons = {}
    local pitchX = screen.GridSpacingX or 133.6
    local rowStride = (screen.GridSpacingY or 143) * ROW_STRIDE
    local x, y = screen.GridStartX, screen.GridStartY
    local column = 1
    local cursorX, cursorY = nil, nil

    local rowWidth = rowWidthFor(screen)
    -- Every slot in the vanilla grid reserves room under the icon for a quantity
    -- number (CreateTextBoxWithScreenFormat with ResourceCountFormat.OffsetY 58,
    -- ResourceLogic.lua:583). This tab has no quantity to show, so without a nudge
    -- every icon reads as sitting high in an otherwise empty slot. PonyMenu solves
    -- it the same way, with a flat +10 on the button Y (its ready.lua:383).
    local iconOffsetY = tonumber(settings.values.IconOffsetY) or 0
    local highlightOffsetY = tonumber(settings.values.HighlightOffsetY) or 0

    verbose(("opening: %d options, %d per row (screen GridWidth), start=(%.1f, %.1f), pitchX=%.1f, rowStride=%.1f, offsetY=%.1f, style=%s, obstacle=%s")
        :format(#options, rowWidth, screen.GridStartX, screen.GridStartY,
                pitchX, rowStride, iconOffsetY, tostring(settings.values.IconStyle),
                buttonObstacleName))

    -- spec.y is the SLOT line. The icon is nudged down from it; the hover frame
    -- is not. Before 4.1.0 both moved together, which quietly put the frame
    -- IconOffsetY units below the slot it is meant to outline -- the icon nudge
    -- exists precisely because the icon and the slot are NOT the same place, so
    -- anything that outlines the slot has to stay behind.
    local function makeButton(index, spec)
        local iconScale = spec.iconScale or 1.0
        -- Brightness and size are separate signals here. spec.lit drives the
        -- brightness; spec.litSize drives the size and defaults to it, because
        -- for a pick they are the same thing. Only the override squares split
        -- them, and only because their style setting says which one carries the
        -- state (see gateFreezesBrightness / gateFreezesSize).
        local litSize = spec.litSize
        if litSize == nil then litSize = spec.lit end
        local restLit = litSize or spec.alwaysBig == true
        local button = game.CreateScreenComponent({
            -- The rung of the ladder matching this icon's drawn size, so the
            -- box is the icon rather than the whole cell. Falls back to the
            -- vanilla obstacle unchanged when registration did not take.
            Name = (buttonObstacleName == BUTTON_OBSTACLE)
                and CONFIG.boxNameFor(drawsPortraitIcon(spec.icon))
                or buttonObstacleName,
            -- Created at 1.0, NOT at the icon's scale.
            --
            -- CreateScreenComponent has no SkipGeometryUpdate, so a Scale here
            -- shrinks the obstacle's bounds along with the art. Portraits carry
            -- the smallest scale on the page -- their source art is large, so
            -- PortraitIconBoost pulls them right down -- and their hitbox was
            -- coming out around half the rung it had been given, while symbols
            -- at 1.7 came out bigger than theirs. The real size is applied just
            -- below, where SkipGeometryUpdate keeps the bounds alone.
            Scale = 1.0,
            Sound = "/SFX/Menu Sounds/IrisMenuBack",
            Group = "Combat_Menu_Overlay",
            X = spec.x,
            Y = spec.y + iconOffsetY + (spec.extraOffsetY or 0),
            Alpha = 0.0,
            AlphaTarget = spec.lit and SELECTED_ALPHA or unselectedAlpha(),
            AlphaTargetDuration = 0.2,
        })
        button.Screen = screen
        -- The visual size, with the bounds left at the rung's own geometry.
        game.SetScale({ Id = button.Id, Fraction = restScaleFor(iconScale, restLit),
                        Duration = 0.0, SkipGeometryUpdate = true })

        button.SelectFirstBoonIconScale = iconScale
        button.SelectFirstBoonAlwaysBig = spec.alwaysBig == true
        button.SelectFirstBoonRestScale = restScaleFor(iconScale, restLit)
        button.SelectFirstBoonSlot = index
        button.SelectFirstBoonX = spec.x
        button.SelectFirstBoonY = spec.y + iconOffsetY + (spec.extraOffsetY or 0)
        -- Kept so the selection light can be built and torn down as the pick
        -- moves, without rebuilding the whole tab. See applySelection.
        button.SelectFirstBoonIcon = spec.icon
        button.SelectFirstBoonGodForLight = spec.god
        button.SelectFirstBoonGlowY = spec.glowY
        button.OnPressedFunctionName = TAB_PICK_FN
        button.OnMouseOverFunctionName = TAB_OVER_FN
        button.OnMouseOffFunctionName = TAB_OFF_FN
        button.MouseOverSound = "/SFX/Menu Sounds/DialoguePanelOutMenu"
        game.SetAnimation({ DestinationId = button.Id, Name = spec.icon })

        -- SetRGB multiplies the texture, which is how vanilla greys out an item
        -- it cannot offer (SetRGB with Color.Black, ResourceLogic.lua:561). A
        -- value below 1 darkens everything, and the halo -- which reads by
        -- brightness where the symbol reads by shape -- loses more than the
        -- symbol does. A raw table rather than a named colour, so this does not
        -- depend on any particular entry existing in ColorData.
        local brightness = tonumber(settings.values.IconBrightness) or 1.0
        if brightness < 1.0 and type(game.SetRGB) == "function" then
            local level = math.floor(255 * math.max(brightness, 0))
            game.SetRGB({ Id = button.Id, Color = { level, level, level, 255 } })
        end

        screen.Components[BUTTON_KEY_PREFIX .. index] = button

        local highlight = game.CreateScreenComponent({
            Name = "BlankObstacle",
            Group = "Combat_Menu_Overlay_Additive",
            X = spec.x,
            Y = spec.y + highlightOffsetY,
            Alpha = 0.0,
            AlphaTarget = 1.0,
            AlphaTargetDuration = 0.2,
        })
        screen.Components[BUTTON_KEY_PREFIX .. index .. "Highlight"] = highlight
        button.Highlight = highlight

        -- Selene's halo. See SELENE ART above: a second, additive sprite is what
        -- vanilla itself draws when it wants a glow, and it is the only lever
        -- left after Material = "Emissive" turned out to do nothing.
        spec.glowY = spec.y + iconOffsetY + (spec.extraOffsetY or 0)
        -- The lit multiplier, so the light grows with a pick or an on gate and
        -- ignores the per-art-family size correction. See makeIconHalo.
        local base = iconScale ~= 0 and iconScale or 1.0
        local glow = makeIconHalo(game, screen, index, spec,
                                  restScaleFor(iconScale, restLit) / base)
        if glow ~= nil then button.SelectFirstBoonGlow = glow end
        return button
    end

    -- Read once for the whole draw, so every button agrees with the panel.
    local keepsakeGod = equippedForcedGod(game)

    for index, option in ipairs(options) do
        local selected = (option.value == settings.values.God)
        -- First button is the fallback; the chosen one wins if there is one.
        -- The cursor still starts on the pick even when a keepsake overrules it:
        -- that is still where the player left off.
        if cursorX == nil or selected then
            cursorX, cursorY = x, y + iconOffsetY
        end

        local isPortrait = drawsPortraitIcon(option.icon)
        local iconScale = iconScaleFor(option, isPortrait)
        -- Portrait art is a different shape from a god symbol and does not sit at
        -- the same height in the slot, so it gets its own nudge on top of the one
        -- every icon gets. Keyed off the art drawn, not off the god: the four
        -- with haloed symbols draw portraits in the door style too.
        local extraOffset = 0
        local asExtra = option.value ~= nil and EXTRA_GOD_BY_LOOT[option.value] or nil
        if isPortrait or (asExtra ~= nil and asExtra.portraitOnly) then
            extraOffset = tonumber(settings.values.PortraitIconOffsetY) or 0
        end
        local button = makeButton(index, {
            x = x, y = y, icon = option.icon,
            -- Carried so the selection light can find this god's own colour.
            god = option.value,
            lit = selected,
            iconScale = iconScale,
            extraOffsetY = extraOffset,
        })
        button.SelectFirstBoonGod = option.value
        buttons[#buttons + 1] = button
        verbose(("  slot %d = %-18s at (%.1f, %.1f)%s")
            :format(index, option.value == NONE_VALUE and "Random" or option.value,
                    x, y, selected and "  <- selected" or ""))

        if column < rowWidth then
            column = column + 1
            x = x + pitchX
        else
            column = 1
            x = screen.GridStartX
            y = y + rowStride
        end

        -- Look ahead rather than back: the gap belongs BEFORE the option that
        -- asks for it. Skipped at the left edge, where a leading blank would read
        -- as a missing icon rather than as a separator.
        local nextOption = options[index + 1]
        if nextOption ~= nil and nextOption.rowBreak then
            -- A row break wins over a gap and subsumes it. Also skipped at the
            -- left edge -- we are already at the start of a row, and breaking
            -- again would leave a whole empty one.
            if column > 1 then
                column = 1
                x = screen.GridStartX
                y = y + rowStride
            end
        elseif nextOption ~= nil and nextOption.gapBefore and column > 1 then
            if column < rowWidth then
                column = column + 1
                x = x + pitchX
            else
                column = 1
                x = screen.GridStartX
                y = y + rowStride
            end
        end
    end

    local lastIconRow = math.floor(((y - screen.GridStartY) / rowStride) + 0.5)

    -- The two delay gates. Deliberately NOT in the flow: they are a different
    -- kind of control -- they change when Hermes and Selene may appear at all,
    -- not what goes first -- and putting them in the run of icons would read as
    -- two more things to pick. A clear empty row separates them, and the panel
    -- says which is which whenever the cursor is on one.
    -- BOTTOM ROW, fixed. 4.23.0 computed this as "one clear row below the last
    -- icon", which is right in spirit and wrong in practice: with enough gods
    -- enabled it resolved past the bottom of the grid and the override squares
    -- were simply not on screen. There is no row below the last one to move to.
    --
    -- So they go back to the row they have always used, and if the icons ever
    -- reach it that is worth a warning rather than a silent overlap -- the fix
    -- then is fewer gods or a wider grid, not a row that does not exist.
    local gateRow = GATE_ROW
    if lastIconRow >= gateRow then
        logWarn(("the icons reached row %d and the override squares live on row %d; "
            .. "they may overlap"):format(lastIconRow, gateRow))
    end
    local gateY = screen.GridStartY + (gateRow * rowStride)
    for gateIndex, gate in ipairs(GATES) do
        local index = #options + gateIndex
        -- Right-aligned: the last gate lands in the final column, the one before
        -- it immediately to its left.
        local column = rowWidth - #GATES + gateIndex
        local gx = screen.GridStartX + ((column - 1) * pitchX)
        local gateIsOn = settings.values[gate.key] == true and not gateOverridden(gate)
        local button = makeButton(index, {
            x = gx, y = gateY,
            icon = tabIconFor(game, gate.option),
            lit = (gateFreezesBrightness() and gateFrozenBrightnessIsLit()) or
                  (not gateFreezesBrightness() and gateIsOn),
            litSize = gateIsOn,
            -- icon passed as well as special: without it the per-icon size
            -- lookup has no name to key on and every gate stays at 1.0.
            iconScale = iconScaleFor({ special = specialFor(gate.option),
                                       icon = tabIconFor(game, gate.option) }),
            alwaysBig = gateFreezesSize(),
            -- Marked so the selection light can skip it: see makeIconHalo.
            isGate = true,
        })
        button.SelectFirstBoonGate = gate
        buttons[#buttons + 1] = button
        verbose(("  gate %s at (%.1f, %.1f) row %d = %s")
            :format(gate.label, gx, gateY, gateRow, gateState(gate)))
    end

    screen[BUTTON_LIST_FIELD] = buttons
    screen.NumItems = #buttons

    -- See CONTROLLER CURSOR below. OpenInventoryScreen consults these at
    -- ResourceLogic.lua:355, after this function has run, and prefers them over
    -- its own defaults -- so this is the sanctioned way to say where the gamepad
    -- cursor starts. The vanilla resource grid sets the same two fields
    -- (ResourceLogic.lua:590-597).
    if cursorX ~= nil then
        screen.CursorStartX = cursorX
        screen.CursorStartY = cursorY
        verbose(("cursor start set to (%.1f, %.1f)"):format(cursorX, cursorY))
    end

    drawTabText(game, screen)
    pcall(scaleTabStripIcon, game, screen, settings.values.God)
    pcall(game.InventoryScreenUpdateVisibility, screen)
end

-- =============================================================================
-- CONTROLLER CURSOR
-- =============================================================================
--
-- Three attempts at the controller problem tuned FreeFormSelect* settings. That
-- was the wrong layer twice over: those are only config options pushed by
-- SetGamepadNavigation (UILogic.lua:1091), and the actual defect is that the
-- cursor never arrives on this page at all.
--
-- Vanilla moves the gamepad cursor in three places, and two of them branch on
-- whether the category has an OpenFunctionName:
--
--   OpenInventoryScreen           ResourceLogic.lua:355-364
--       CursorStartX/Y if set, else GridStart for a plain category,
--       else PinStart.
--   InventoryScreenNextCategory   ResourceLogic.lua:645-650
--   InventoryScreenPrevCategory   ResourceLogic.lua:670-675
--       GridStart for a plain category, else PinStart. CursorStartX/Y is
--       NOT consulted on either of these.
--
-- "Else PinStart" is the problem. PinStartX/PinStartY is (614, 267) -- the
-- forget-me-not column, a vertical list at the right of the panel. Vanilla
-- assumes any category with an OpenFunctionName looks like that, because the two
-- that ship do. This one is a grid at GridStart (149, 252).
--
-- So tabbing in with a controller parks the cursor at (614, 267): between the
-- fourth button (549.8) and the fifth (683.4), on nothing. With the old 340-wide
-- ButtonInventoryItem box that point sat inside two boxes at once, which is
-- exactly the reported "you switch between two boons but can't move around the
-- rest". With the slot-sized box added in 2.6.0 it sits inside none, so there is
-- nothing selected to step away from.
--
-- Two fixes, one per path:
--
--   * tabOpen sets screen.CursorStartX/Y. That is enough for the open path,
--     which prefers those fields over both defaults, and needs no wrap.
--   * The tab-switch paths ignore those fields, so they get wrapped: run
--     vanilla, then move the cursor again if the category we landed on is ours.
--     Wrapping after the fact rather than overriding means vanilla's own
--     wait(0.02) and presentation still happen exactly as before.
--
-- Mouse clicks on a tab go through InventoryScreenSelectCategory, which does not
-- move the cursor at all. Left alone deliberately: TeleportCursor moves the real
-- pointer, and yanking a mouse user's cursor across the screen is worse than the
-- problem.
local function teleportToTab(game, screen)
    if screen == nil then return end
    local categories = screen.ItemCategories
    local index = screen.ActiveCategoryIndex
    if categories == nil or index == nil then return end
    local active = categories[index]
    if active == nil or active.Name ~= TAB_CATEGORY_NAME then return end

    local x, y = screen.CursorStartX, screen.CursorStartY
    if x == nil or y == nil then return end
    game.TeleportCursor({ OffsetX = x, OffsetY = y, ForceUseCheck = true })
    verbose(("cursor moved to (%.1f, %.1f) on tab switch"):format(x, y))
end

local function installCategoryCursorFix(game)
    local ModUtil = game.ModUtil
    if ModUtil == nil or ModUtil.Path == nil or ModUtil.Path.Wrap == nil then
        logWarn("ModUtil.Path.Wrap unavailable; the controller cursor will land "
            .. "on the pin column when tabbing into this page")
        return
    end
    for _, name in ipairs({ "InventoryScreenNextCategory", "InventoryScreenPrevCategory" }) do
        ModUtil.Path.Wrap(name, function(base, screen, button)
            base(screen, button)
            local ok, err = pcall(teleportToTab, game, screen)
            if not ok then logWarn("cursor move failed: " .. tostring(err)) end
        end)
    end
    logAlways("category cursor fix installed")
end

-- Rebuild the open tab in place.
--
-- Size looked live and the light did not, but neither actually was: a hover
-- re-applies a scale baked at build time, so moving the mouse made a size change
-- appear, while the light -- built once in makeButton -- could only change on a
-- full re-open. Both are build-time facts, so both need a rebuild.
--
-- Silent when the tab is not open: the panel can be used from anywhere.
function CONFIG.refreshOpenTab()
    if CONFIG.openGame == nil or CONFIG.openScreen == nil then return end
    local ok, err = pcall(tabOpen, CONFIG.openGame, CONFIG.openScreen)
    if not ok then
        logWarn("could not refresh the open tab: " .. tostring(err))
        CONFIG.openScreen = nil
    end
end

local function tabClose(game, screen)
    CONFIG.openScreen = nil
    destroyTabButtons(game, screen)
    -- The info boxes belong to the screen, not to us, so hand them back empty
    -- rather than leaving our text under the next category.
    clearInfo(game, screen)
    screen.NumItems = 0
    pcall(game.InventoryScreenUpdateVisibility, screen)
end

local function installInventoryTab(game)
    if not settings.values.ShowInventoryTab then
        logAlways("inventory tab disabled by config")
        return
    end

    -- CallFunctionName looks these up in _G (EventLogic.lua:66), so they have to
    -- live on rom.game. Each is wrapped: an error thrown out of a category
    -- handler would surface inside the inventory screen's own render path.
    game[TAB_OPEN_FN] = function(screen)
        local ok, err = pcall(tabOpen, game, screen)
        if not ok then logWarn("inventory tab open failed: " .. tostring(err)) end
    end
    game[TAB_CLOSE_FN] = function(screen)
        local ok, err = pcall(tabClose, game, screen)
        if not ok then logWarn("inventory tab close failed: " .. tostring(err)) end
    end
    game[TAB_PICK_FN] = function(screen, button)
        local ok, err = pcall(pickGod, game, screen, button)
        if not ok then logWarn("inventory tab selection failed: " .. tostring(err)) end
    end
    game[TAB_OVER_FN] = function(button)
        pcall(onButtonOver, game, button)
    end
    game[TAB_OFF_FN] = function(button)
        pcall(onButtonOff, game, button)
    end

    local screenData = game.ScreenData and game.ScreenData.InventoryScreen
    if screenData == nil or type(screenData.ItemCategories) ~= "table" then
        logWarn("ScreenData.InventoryScreen.ItemCategories unavailable; no native tab")
        return
    end

    -- ipairs, not pairs: proxied game data has been seen to fail under pairs().
    for _, category in ipairs(screenData.ItemCategories) do
        if category.Name == TAB_CATEGORY_NAME then
            logAlways("inventory tab already present")
            return
        end
    end

    table.insert(screenData.ItemCategories, {
        Name = TAB_CATEGORY_NAME,
        Icon = tabIconFor(game, settings.values.God),
        -- Grid, not Blank: this is what draws the slot frames behind the icons,
        -- and it matches the background the working vanilla grid uses.
        OpenAnimation = "InventoryScreenInGrid",
        CloseAnimation = "InventoryScreenOutGrid",
        GameStateRequirements = {},
        OpenFunctionName = TAB_OPEN_FN,
        CloseFunctionName = TAB_CLOSE_FN,
    })

    installCategoryCursorFix(game)

    logAlways("inventory tab installed as \"" .. TAB_CATEGORY_NAME
        .. "\", icon " .. tabIconFor(game, settings.values.God))
end

-- =============================================================================
-- UI
-- =============================================================================

local ui = {
    showWindow = false,
    seededSize = false,
    game = nil,
}

local WINDOW_WIDTH = 460
local WINDOW_HEIGHT = 340
local COMBO_WIDTH = 300
local COMBO_FLAG_NONE = 0



-- Grouped rather than one local each: the main chunk is at Lua's 200-local
-- ceiling for a function, and every new top-level name now costs a slot that a
-- table field does not.
local MORE_TOOLTIPS = {
    Tuning =
        "Presentation only -- none of this changes what the run does.\n\n" ..
        "All three are read when the inventory tab opens, so change one and reopen " ..
        "the inventory to see it. No restart needed.",
    Keepsake =
        "ON  -- an equipped boon keepsake wins and this plugin does nothing at all " ..
        "for that run.\n" ..
        "OFF -- you get both, which means two guaranteed gods: the keepsake takes " ..
        "the first boon and your pick takes the second.\n\n" ..
        "On is the point of the mod -- one chosen boon, not two.",
    NeverFirst =
        "ON  -- they cannot appear until you hold a boon or a hammer.\n" ..
        "OFF -- they can appear from the first room, as vanilla allows.\n\n" ..
        "Nothing to do with the pick above, except that picking one of them " ..
        "overrides its own gate.\n\n" ..
        "Replaces the standalone NoHermesFirstBoon plugin and the speedrun pack's " ..
        "\"Disable Selene Before First Boon\" -- turn those off if these are on.",
    God =
        "Which boon, or which reward, the run opens with.\n\n" ..
        "Standard leaves the game entirely alone.\n\n" ..
        "Takes effect from the next run -- no restart needed. Changing it partway " ..
        "through a run does nothing once that run's first reward has already come up.",
    Eligibility =
        "ON  -- a god you have not met cannot be your first boon: the pick is " ..
        "ignored and the game decides.\n" ..
        "OFF -- pick Ares, get Ares, met or not.\n\n" ..
        "A safeguard, off by default.",
    Priority =
        "OFF -- your pick waits its turn. The game picks the first reward, and " ..
        "anything it has scripted, a Chaos Trial's opening boon or a story beat, " ..
        "happens as designed. Yours lands on the next boon after that.\n" ..
        "ON  -- your pick goes first no matter what, overriding both.\n\n" ..
        "WARNING: that override breaks encounters built around a specific " ..
        "opening boon, and it breaks them QUIETLY. A Chaos Trial designed to " ..
        "start you on Hera still plays. It just is not the trial that was " ..
        "designed.\n\n" ..
        "Off is the honest default. On exists because the alternative reads as " ..
        "the mod being broken: you named a first boon, the game handed you " ..
        "something else, and nothing said why.",
    KeepPick =
        "ON  -- the pick you leave set is still set the next time you launch.\n" ..
        "OFF -- every launch starts at Standard.\n\n" ..
        "Off by default: a pick is about one run, not a permanent setting.",
    ExtraGods =
        "Gods the base game never offers as a boon on the ground. Each one is a "
        .. "first-boon option only: they are never sold in shops, never appear "
        .. "after the first reward, and never count against the run's god "
        .. "limit.\n\n"
        .. "Takes effect on the next launch -- the drop's art is built when the "
        .. "game loads.",
    OnlyPicked =
        "ON  -- Artemis, Athena and the rest can only be the first boon when you "
        .. "picked them. Otherwise you meet them by talking to them, as normal.\n"
        .. "OFF -- they also join the pool the game's own first-boon roll draws "
        .. "from.\n\n"
        .. "Adding a god puts them in that pool as a side effect. On keeps them a "
        .. "choice rather than a change to the rest of the game.",
}





-- Availability markers for the dropdown.
--
-- Returns (set, suppressed). A nil set means "do not mark anything".
--
-- Two traps here, both learned the hard way:
--
--   * GetEligibleLootNames reaches ReachedMaxGods, which dereferences CurrentRun
--     with no nil check, so it must not be called from the main menu.
--
--   * Once the max-gods cap is hit, GetEligibleLootNames stops answering "which
--     gods are available" and starts answering something much narrower:
--     RewardLogic.lua:189-193 replaces the candidate list with
--     OrderedKeysToList( CurrentRun.LootTypeHistory ), i.e. only gods already met
--     THIS RUN. Every other god then reads as unavailable -- including ones the
--     player has fully unlocked. v2.1.0 rendered that as "(locked)", which was
--     simply false. Mid-run past the cap, no marker is honest, so none is shown
--     and the UI says why instead.
--
-- Even below the cap this is "can it be offered right now", not "is it
-- unlocked": some gods carry per-run clauses (Hephaestus requires
-- CurrentRun.TextLinesRecord HasNone ZeusFirstPickUp). Hence "(unavailable)"
-- rather than "(locked)" -- the marker claims only what the check tests.
local function eligibleSet(game)
    if game == nil or game.CurrentRun == nil then return nil, false end

    local okMax, maxed = pcall(game.ReachedMaxGods)
    if okMax and maxed then return nil, true end

    local ok, names = pcall(game.GetEligibleLootNames)
    if not ok or type(names) ~= "table" then return nil, false end
    local set = {}
    for _, n in ipairs(names) do set[n] = true end
    return set, false
end

local function tooltipOnHover(imgui, text)
    if imgui.IsItemHovered() then
        imgui.SetTooltip(text)
    end
end

local function drawGodCombo(imgui)
    local current = settings.values.God
    local preview
    if current == NONE_VALUE then
        preview = NONE_LABEL
    else
        local special = specialFor(current)
        preview = special ~= nil and special.label or (catalog.labels[current] or current)
    end

    imgui.AlignTextToFramePadding()
    imgui.Text("First reward")
    tooltipOnHover(imgui, MORE_TOOLTIPS.God)
    imgui.SameLine()

    imgui.PushItemWidth(COMBO_WIDTH)
    local opened = imgui.BeginCombo("##SelectFirstBoonGod", preview, COMBO_FLAG_NONE)
    if opened then
        local eligible = nil
        if settings.values.RespectEligibility then
            eligible = eligibleSet(ui.game)
        end

        if imgui.Selectable(NONE_LABEL .. "##none", current == NONE_VALUE) and current ~= NONE_VALUE then
            saveSetting("God", NONE_VALUE)
            refreshTabIcon(ui.game)
            logAlways("god set to None (vanilla)")
        end

        for index, lootName in ipairs(catalog.names) do
            local label = catalog.labels[lootName] or lootName
            if eligible ~= nil and not eligible[lootName] then
                label = label .. "  (unavailable)"
            end
            if imgui.Selectable(label .. "##" .. index, lootName == current) and lootName ~= current then
                saveSetting("God", lootName)
                refreshTabIcon(ui.game)
                logAlways("god set to " .. lootName)
            end
        end

        -- Not gods, so no eligibility marks: their availability is decided by
        -- the reward store's own GameStateRequirements at the moment a room
        -- rolls, not by GetEligibleLootNames.
        for index, special in ipairs(SPECIALS) do
            local label = special.label
            if imgui.Selectable(label .. "##special" .. index, special.value == current)
                and special.value ~= current then
                saveSetting("God", special.value)
                refreshTabIcon(ui.game)
                logAlways("first reward set to " .. special.label .. " (" .. special.reward .. ")")
            end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
    tooltipOnHover(imgui, MORE_TOOLTIPS.God)
end

local function drawStatus(imgui)
    local game = ui.game
    local currentRun = game and game.CurrentRun or nil

    if settings.values.God == NONE_VALUE then
        imgui.TextDisabled("Inactive -- vanilla boon rolls.")
        return
    end
    if currentRun == nil then
        imgui.TextDisabled("No run in progress. Will apply on the next run.")
        return
    end
    if currentRun[USED_FIELD] then
        imgui.TextDisabled("Already spent this run -- the forced boon has spawned.")
        return
    end

    local keepsakeGod = equippedForcedGod(game)
    if keepsakeGod ~= nil then
        imgui.TextDisabled("Overridden this run by your " .. godLabelFor(keepsakeGod)
            .. " keepsake, which takes the first boon.")
        return
    end

    local special = specialFor(settings.values.God)
    if special ~= nil then
        if currentRun[PRIORITY_FIELD] then
            imgui.TextDisabled(special.label .. " is queued for this run's first reward"
                .. " (or the first room where it is offered at all).")
        else
            imgui.TextDisabled("Armed. " .. special.label
                .. " will be queued when this run's next reward is rolled.")
        end
        return
    end

    local eligible, maxedOut = eligibleSet(game)
    if maxedOut then
        imgui.TextDisabled("Armed. Past the max-gods cap this run, so availability is not shown"
            .. " -- it is re-checked at each run's first boon.")
        return
    end
    if settings.values.RespectEligibility and eligible ~= nil and not eligible[settings.values.God] then
        imgui.TextDisabled("Armed, but " .. (catalog.labels[settings.values.God] or settings.values.God)
            .. " is not available right now.")
        return
    end
    imgui.TextDisabled("Armed -- next unforced boon will be "
        .. (catalog.labels[settings.values.God] or settings.values.God) .. ".")
end

local function drawGateStatus(imgui)
    local game = ui.game
    local currentRun = game and game.CurrentRun or nil
    if not (settings.values.BlockHermesBeforeBoon or settings.values.BlockSeleneBeforeBoon) then
        return
    end
    if currentRun == nil then
        imgui.TextDisabled("Gates arm when a run starts.")
        return
    end
    local held = false
    local ok, result = pcall(hasBoonThisRun, currentRun)
    if ok then held = result end
    if held then
        imgui.TextDisabled("Gates released -- you hold a boon this run.")
    else
        imgui.TextDisabled("Gates active -- no boon held yet this run.")
    end
end

-- Presentation choices worth comparing side by side. Every one of these is read
-- when the tab opens, so the loop is: change it here, reopen the inventory,
-- look. No restart and no redeploy between attempts.
-- Portraits are still a working IconStyle value in the .cfg, but they are not
-- offered here: they are the character faces, and those were not wanted.
local ICON_STYLE_PRESETS = {
    { value = "symbol",   label = "God symbols (the glowing ones)" },
    { value = "boondrop", label = "Door icons (what a door shows)" },
}
local OFFSET_PRESETS = { 0, 5, 10, 15, 20, 29, 40 }
local SELENE_PRESETS = { 1.0, 1.5, 2.0, 2.5, 3.0 }
-- Its own list, running well BELOW 1.0. Reusing Selene's was a thoughtless
-- choice: hers corrects art that draws too small, so every value in it is 1.0 or
-- more. The portrait art is the opposite problem -- it is the big keepsake
-- picture and comes out too large -- so the only useful half of the range was
-- the half that list does not have.
local PORTRAIT_BOOST_PRESETS = {
    0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.15, 1.3, 1.5,
}
local BRIGHTNESS_PRESETS = { 1.0, 0.9, 0.8, 0.7, 0.6, 0.5 }
local HIGHLIGHT_STYLE_PRESETS = {
    { value = "frame", label = "Slot frame (what vanilla tabs do)" },
    { value = "grow",  label = "No frame, icon grows only" },
}
local HIGHLIGHT_OFFSET_PRESETS = { -10, -5, 0, 5, 10 }
local ICON_SIZE_PRESETS = { 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.5, 3.0 }
local DIM_PRESETS = { 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0 }
local SELECTED_SCALE_PRESETS = { 1.0, 1.1, 1.25, 1.4, 1.6 }
-- Ordered most-likely-first: the top two are the ones with a reason behind
-- them, the rest are there so a whole round of testing costs one sitting instead
-- of one rebuild each.
local SELENE_GLOW_SOURCE_PRESETS = {
    { value = "particle",  label = "1 - Particle glow (vanilla's own halo)" },
    { value = "backing-a", label = "2 - Boon backing A" },
    { value = "backing-b", label = "3 - Boon backing B" },
    { value = "backing-c", label = "4 - Boon backing C" },
}
local SELENE_GLOW_STRENGTH_PRESETS = { 0.0, 0.25, 0.45, 0.6, 0.8, 1.0 }
-- A plain component scale now, not a multiplier -- see SIZE in makeSeleneGlow.
-- Open at the top end on purpose. 0.2 fills a slot, but the right value depends
-- on how big the icons themselves are set, so the range runs well past "one
-- slot" rather than making a rebuild the price of trying a larger halo.
local SELENE_HALO_SPREAD_PRESETS = {
    0.08, 0.12, 0.16, 0.2, 0.25, 0.3, 0.4, 0.5, 0.6, 0.75, 0.9, 1.1, 1.4, 1.8,
}
local SELENE_HALO_LAYER_PRESETS = { 1, 2, 3, 4 }
local TAB_ICON_BOOST_PRESETS = { 1.0, 1.1, 1.15, 1.25, 1.4, 1.6 }
local DROP_ICON_SCALE_PRESETS = { 0.2, 0.25, 0.3, 0.35, 0.4, 0.5, 0.6, 0.7 }
local DROP_PORTRAIT_SCALE_PRESETS = { 0.12, 0.16, 0.2, 0.22, 0.26, 0.3, 0.4, 0.5 }
-- Above 1.0 as well as below. Whether channels past 1.0 actually brighten or
-- simply clamp is not something that can be read out of the data files, so the
-- range is offered and the answer comes from looking at it.
local DROP_GLOW_PRESETS = { 0.4, 0.5, 0.6, 0.7, 0.85, 1.0, 1.25, 1.5, 1.75, 2.0 }
-- Above 1.0 as well, for the same reason the glow list has it: a portrait gets
-- painted over by BoonDropFrontFlare, and pushing the picture brighter is the
-- only counter that does not also dim the orb.
local DROP_EMBLEM_PRESETS = {
    0.15, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.25, 1.5, 2.0,
}
local EMBLEM_ART_PRESETS = {
    { value = "symbol",         label = "Emblem" },
    { value = "portrait",       label = "Keepsake portrait" },
    { value = "portrait-small", label = "Keepsake portrait, small art" },
}
local GATE_STATE_PRESETS = {
    { value = "brightness", label = "Brightness only, one fixed size" },
    { value = "size-only",  label = "Size only, always dimmed like an unpicked boon" },
    { value = "size",       label = "Brightness and size, like a picked boon" },
    { value = "none",       label = "No change at all" },
}


-- If the value in force is not one of the presets, it is added to the list.
--
-- Without this a setting can become a ONE-WAY DOOR, which is what happened in
-- 4.14.0: Athena's emblem default was set to 0.7, 0.7 was not in the preset
-- list, and picking anything else meant never getting back to it without hand-
-- editing the cfg. A default the menu cannot re-select is a bug in the menu, not
-- a reason to move the default.
local function presetValuesFor(presets, current)
    local values = {}
    local seen = false
    for _, preset in ipairs(presets) do
        local value = type(preset) == "table" and preset.value or preset
        values[#values + 1] = value
        if value == current then seen = true end
    end
    if seen or current == nil then return values end

    -- Numbers slot into their sorted place; anything else goes on the end, since
    -- there is no meaningful order to insert a string into.
    if type(current) == "number" then
        for index, value in ipairs(values) do
            if type(value) == "number" and value > current then
                table.insert(values, index, current)
                return values
            end
        end
    end
    values[#values + 1] = current
    return values
end

local function drawPresetCombo(imgui, id, title, current, presets, labelFor, apply)
    imgui.AlignTextToFramePadding()
    imgui.Text(title)
    imgui.SameLine()
    imgui.PushItemWidth(COMBO_WIDTH)
    if imgui.BeginCombo("##" .. id, labelFor(current), COMBO_FLAG_NONE) then
        for index, value in ipairs(presetValuesFor(presets, current)) do
            if imgui.Selectable(labelFor(value) .. "##" .. id .. index, value == current)
                and value ~= current then
                apply(value)
            end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
    tooltipOnHover(imgui, MORE_TOOLTIPS.Tuning)
end

local function iconStyleLabel(value)
    for _, preset in ipairs(ICON_STYLE_PRESETS) do
        if preset.value == value then return preset.label end
    end
    return tostring(value)
end

-- TEMPORARY tuning surface. One correction per icon so each can be matched to
-- the others by eye, which is the only way to judge it. Deliberately at the
-- bottom of the panel and behind its own header so it is out of the way. When
-- the numbers are settled they become the defaults and this whole section, the
-- Size* settings and CONFIG.tune go away together.
-- Fallback only, used when the ImGui binding has no SliderFloat. 0.05 steps, so
-- it is granular enough to tune with even though it is a long list.
CONFIG.tuneSizePresets = {}
for step = 4, 60 do CONFIG.tuneSizePresets[#CONFIG.tuneSizePresets + 1] = step * 0.05 end

-- Set once, the first time the slider is tried. A binding without SliderFloat,
-- or with a different argument order, must not take the whole panel down.
CONFIG.sliderBroken = false

-- One slider, or a dropdown where the binding has none. Shared so the selection
-- light and the per-icon sizes behave identically and both rebuild the tab.
function CONFIG.tuneSlider(imgui, key, label, lo, hi, fallback, isInt)
    local current = tonumber(settings.values[key]) or fallback
    if not CONFIG.sliderBroken and type(imgui.SliderFloat) == "function" then
        local ok, value, changed = pcall(imgui.SliderFloat, label, current, lo, hi, "%.2f")
        if ok then
            if changed and type(value) == "number" then
                -- ImGui hands back a C float and Lua widens it to a double, so
                -- 0.55 arrives as 0.550000011920929 and lands in the .cfg that
                -- way. The slider shows two decimals; store two decimals.
                if isInt then value = math.floor(value + 0.5)
                else value = math.floor(value * 100 + 0.5) / 100 end
                saveSetting(key, value)
                logAlways(label .. " set to " .. tostring(value))
                CONFIG.refreshOpenTab()
            end
            return
        end
        CONFIG.sliderBroken = true
        logWarn("ImGui SliderFloat unavailable (" .. tostring(value) .. "); using dropdowns")
    end
    drawPresetCombo(imgui, key, label, current, CONFIG.tuneSizePresets,
        function(value) return string.format("%.2f", value) end,
        function(value)
            saveSetting(key, value)
            logAlways(label .. " set to " .. tostring(value))
            CONFIG.refreshOpenTab()
        end)
end

function CONFIG.drawSizeTuning(imgui)
    imgui.Text("Icon size tuning (temporary)")

    local useSlider = not CONFIG.sliderBroken and type(imgui.SliderFloat) == "function"

    for _, name in ipairs(CONFIG.tuneNames) do
        local key = "Size" .. name
        local current = tonumber(settings.values[key]) or 1.0

        local drew = false
        if useSlider then
            -- "##size" is ImGui's ID separator: shown text before it, hidden id
            -- after. Without it this row and the light row below share a label,
            -- and a label IS the widget's identity -- dragging one moved the
            -- other, which is exactly what it looked like.
            local ok, value, changed = pcall(imgui.SliderFloat, name .. "##size",
                                             current, 0.2, 3.0, "%.2f")
            if ok then
                drew = true
                -- Same value, changed convention the Checkbox calls above use.
                if changed and type(value) == "number" then
                    value = math.floor(value * 100 + 0.5) / 100
                    saveSetting(key, value)
                    logAlways(name .. " icon size set to " .. string.format("%.2f", value))
                    CONFIG.refreshOpenTab()
                end
            else
                -- Stop trying for the rest of this session and fall back.
                CONFIG.sliderBroken = true
                useSlider = false
                logWarn("ImGui SliderFloat unavailable (" .. tostring(value)
                    .. "); icon size tuning falls back to dropdowns")
            end
        end

        if not drew then
            drawPresetCombo(imgui, key, name, current, CONFIG.tuneSizePresets,
                function(value) return string.format("%.2f", value) end,
                function(value)
                    saveSetting(key, value)
                    logAlways(name .. " icon size set to " .. string.format("%.2f", value))
                    CONFIG.refreshOpenTab()
                end)
        end
    end    imgui.Spacing()
    imgui.Text("Hitbox (needs a game restart)")
    -- In the panel like everything else. It cannot apply live -- the box
    -- geometry is written into GUI.sjson at load -- but that is a reason to say
    -- so on the label, not a reason to make people edit a file by hand.
    CONFIG.tuneSlider(imgui, "HitboxScale", "Hitbox size", 0.3, 3.0, 1.0)
    CONFIG.tuneSlider(imgui, "HitboxScalePortrait", "Hitbox size (portraits)", 0.3, 3.0, 1.0)

    imgui.Spacing()
    imgui.Text("Per-icon light strength (temporary)")
    for _, name in ipairs(CONFIG.tuneNames) do
        CONFIG.tuneSlider(imgui, "Light" .. name, name .. "##light", 0.0, 2.0, 1.0)
    end

    imgui.Spacing()
    imgui.Text("Per-icon light centre (temporary)")
    for _, name in ipairs(CONFIG.tuneNames) do
        CONFIG.tuneSlider(imgui, "Core" .. name, name .. "##core", 0.0, 1.0, 1.0)
    end

    imgui.Spacing()
    imgui.Text("Selection light")

    local haloOn, haloChanged = imgui.Checkbox("Light behind the picked icon",
                                               settings.values.SelectionHalo == true)
    if haloChanged then
        saveSetting("SelectionHalo", haloOn)
        logAlways(haloOn and "selection light on" or "selection light off")
        CONFIG.refreshOpenTab()
    end

    CONFIG.tuneSlider(imgui, "SelectionHaloStrength", "Light strength", 0.0, 1.0, 0.22)
    CONFIG.tuneSlider(imgui, "SelectionHaloSize", "Light radius", 0.1, 2.0, 0.62)
    CONFIG.tuneSlider(imgui, "SelectionHaloLayers", "Light layers", 1, 4, 2, true)
    CONFIG.tuneSlider(imgui, "SelectionHaloSpreadStep", "Light ring spread", 0.0, 1.0, 0.35)
    CONFIG.tuneSlider(imgui, "SelectionHaloCore", "Light centre", 0.0, 1.0, 1.0)
    CONFIG.tuneSlider(imgui, "SelectionHaloWhiten", "Light whiten inward", 0.0, 1.0, 0.0)
    CONFIG.tuneSlider(imgui, "SelectionHaloFollowsIcon", "Light follows icon size", 0.0, 1.0, 1.0)

    drawPresetCombo(imgui, "SelectionHaloTint", "Light colour",
        settings.values.SelectionHaloTint or "neutral",
        { "neutral", "god" },
        function(value)
            if value == "god" then return "The god's own colour" end
            return "Neutral white"
        end,
        function(value)
            saveSetting("SelectionHaloTint", value)
            logAlways("selection light colour set to " .. tostring(value))
            CONFIG.refreshOpenTab()
        end)
    CONFIG.tuneSlider(imgui, "SelectionHaloTintMix", "Light colour strength", 0.0, 1.0, 0.5)



end

local function drawTuning(imgui)
    imgui.Text("Appearance")
    tooltipOnHover(imgui, MORE_TOOLTIPS.Tuning)

    drawPresetCombo(imgui, "IconStyle", "Icon set", settings.values.IconStyle,
        ICON_STYLE_PRESETS, iconStyleLabel,
        function(value)
            saveSetting("IconStyle", value)
            refreshTabIcon(ui.game)
            logAlways("icon set switched to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "IconOffsetY", "Icon nudge", tonumber(settings.values.IconOffsetY) or 0,
        OFFSET_PRESETS,
        function(value) return (value == 0) and "0 (on the grid line)" or ("+" .. tostring(value)) end,
        function(value)
            saveSetting("IconOffsetY", value)
            logAlways("icon nudge set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "SeleneIconBoost", "Selene size",
        tonumber(settings.values.SeleneIconBoost) or 1.0, SELENE_PRESETS,
        function(value) return string.format("%.1fx", value) end,
        function(value)
            saveSetting("SeleneIconBoost", value)
            logAlways("Selene icon size set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "StandardIcon", "Standard icon",
        settings.values.StandardIcon or "pom", STANDARD_ICON_PRESETS,
        function(value)
            for _, preset in ipairs(STANDARD_ICON_PRESETS) do
                if preset.value == value then return preset.label end
            end
            return tostring(value)
        end,
        function(value)
            saveSetting("StandardIcon", value)
            refreshTabIcon(ui.game)
            logAlways("Standard icon set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "PortraitIconOffsetY", "Portrait god nudge",
        tonumber(settings.values.PortraitIconOffsetY) or 6, OFFSET_PRESETS,
        function(value) return string.format("+%d", value) end,
        function(value)
            saveSetting("PortraitIconOffsetY", value)
            logAlways("portrait god icon nudge set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "PortraitIconBoost", "Portrait god size",
        tonumber(settings.values.PortraitIconBoost) or 0.7, PORTRAIT_BOOST_PRESETS,
        function(value) return string.format("%.1fx", value) end,
        function(value)
            saveSetting("PortraitIconBoost", value)
            logAlways("portrait god icon size set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "IconSize", "Icon size", tonumber(settings.values.IconSize) or 1.0,
        ICON_SIZE_PRESETS,
        function(value) return string.format("%.1fx", value) end,
        function(value)
            saveSetting("IconSize", value)
            logAlways("icon size set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "UnselectedBrightness", "Unpicked",
        tonumber(settings.values.UnselectedBrightness) or 0.7, DIM_PRESETS,
        function(value)
            if value >= 1.0 then return "Same as the pick" end
            return string.format("%d%%", math.floor(value * 100 + 0.5))
        end,
        function(value)
            saveSetting("UnselectedBrightness", value)
            logAlways("unpicked brightness set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "SelectedIconScale", "Picked size",
        tonumber(settings.values.SelectedIconScale) or 1.25, SELECTED_SCALE_PRESETS,
        function(value)
            if value <= 1.0 then return "Same as the rest" end
            return string.format("%.2fx", value)
        end,
        function(value)
            saveSetting("SelectedIconScale", value)
            logAlways("picked icon size set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "SeleneGlowSource", "Selene halo art",
        settings.values.SeleneGlowSource, SELENE_GLOW_SOURCE_PRESETS,
        function(value)
            for _, preset in ipairs(SELENE_GLOW_SOURCE_PRESETS) do
                if preset.value == value then return preset.label end
            end
            return tostring(value)
        end,
        function(value)
            saveSetting("SeleneGlowSource", value)
            logAlways("Selene halo art set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "SeleneGlowStrength", "Selene halo",
        tonumber(settings.values.SeleneGlowStrength) or 0.45,
        SELENE_GLOW_STRENGTH_PRESETS,
        function(value)
            if value <= 0 then return "Off" end
            return string.format("%d%%", math.floor(value * 100 + 0.5))
        end,
        function(value)
            saveSetting("SeleneGlowStrength", value)
            logAlways("Selene halo strength set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "SeleneHaloSpread", "Selene halo size",
        tonumber(settings.values.SeleneHaloSpread) or 0.2, SELENE_HALO_SPREAD_PRESETS,
        function(value) return string.format("%.2f", value) end,
        function(value)
            saveSetting("SeleneHaloSpread", value)
            logAlways("Selene halo size set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "SeleneHaloLayers", "Selene halo layers",
        math.floor(tonumber(settings.values.SeleneHaloLayers) or 1),
        SELENE_HALO_LAYER_PRESETS,
        function(value)
            if value == 1 then return "1 (no stacking)" end
            return string.format("%d", value)
        end,
        function(value)
            saveSetting("SeleneHaloLayers", value)
            logAlways("Selene halo layers set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "DropIconScale", "Drop size (emblem)",
        tonumber(settings.values.DropIconScale) or 0.4, DROP_ICON_SCALE_PRESETS,
        function(value) return string.format("%.2f", value) end,
        function(value)
            saveSetting("DropIconScale", value)
            logAlways("added gods' drop emblem scale set to " .. tostring(value)
                .. " (restart to see it)")
        end)

    drawPresetCombo(imgui, "DropPortraitScale", "Drop size (portrait)",
        tonumber(settings.values.DropPortraitScale) or 0.22,
        DROP_PORTRAIT_SCALE_PRESETS,
        function(value) return string.format("%.2f", value) end,
        function(value)
            saveSetting("DropPortraitScale", value)
            logAlways("added gods' drop portrait scale set to " .. tostring(value)
                .. " (restart to see it)")
        end)

    -- "Full" is 1.0 and nothing else. 4.14.0 labelled everything at or above 1.0
    -- as "Full", so the whole upper half of the glow list read identically and
    -- there was no way to tell 1.25 from 2.0 -- or to know a pick had done
    -- anything at all.
    local function brightnessLabel(value)
        if value == 1.0 then return "Full" end
        return string.format("%d%%", math.floor(value * 100 + 0.5))
    end

    for _, god in ipairs(EXTRA_GODS) do
        -- Only offered where there is a real choice to make. Hades gets no combo
        -- at all rather than one whose second option quietly falls back, and a
        -- portrait-only god gets none either -- a portrait is not his preference,
        -- it is the only art he has.
        if god.hasPortrait and god.emblemArtSetting ~= nil and not god.portraitOnly then
            drawPresetCombo(imgui, god.emblemArtSetting, god.name .. " drop art",
                settings.values[god.emblemArtSetting] or "symbol",
                EMBLEM_ART_PRESETS,
                function(value)
                    for _, preset in ipairs(EMBLEM_ART_PRESETS) do
                        if preset.value == value then return preset.label end
                    end
                    return tostring(value)
                end,
                function(value)
                    saveSetting(god.emblemArtSetting, value)
                    logAlways(god.name .. " drop art set to " .. tostring(value)
                        .. " (restart to see it)")
                end)
        end

        drawPresetCombo(imgui, god.emblemSetting, god.name .. " drop emblem",
            tonumber(settings.values[god.emblemSetting]) or 1.0, DROP_EMBLEM_PRESETS,
            brightnessLabel,
            function(value)
                saveSetting(god.emblemSetting, value)
                logAlways(god.name .. " drop emblem brightness set to " .. tostring(value)
                    .. " (restart to see it)")
            end)

        if god.haloSetting ~= nil then
            drawPresetCombo(imgui, god.haloSetting, god.name .. " menu halo",
                tonumber(settings.values[god.haloSetting]) or 1.0,
                SELENE_GLOW_STRENGTH_PRESETS,
                function(value)
                    if value <= 0 then return "Off" end
                    return string.format("%d%%", math.floor(value * 100 + 0.5))
                end,
                function(value)
                    saveSetting(god.haloSetting, value)
                    logAlways(god.name .. " menu halo set to " .. tostring(value))
                end)
        end

        drawPresetCombo(imgui, god.glowSetting, god.name .. " drop glow",
            tonumber(settings.values[god.glowSetting]) or 1.0, DROP_GLOW_PRESETS,
            brightnessLabel,
            function(value)
                saveSetting(god.glowSetting, value)
                logAlways(god.name .. " drop glow set to " .. tostring(value)
                    .. " (restart to see it)")
            end)
    end

    drawPresetCombo(imgui, "TabIconBoost", "Tab icon size",
        tonumber(settings.values.TabIconBoost) or 1.15, TAB_ICON_BOOST_PRESETS,
        function(value)
            if value == 1.0 then return "Vanilla" end
            return string.format("%.2fx vanilla", value)
        end,
        function(value)
            saveSetting("TabIconBoost", value)
            logAlways("tab strip icon size set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "GateStateStyle", "Override squares",
        settings.values.GateStateStyle, GATE_STATE_PRESETS,
        function(value)
            for _, preset in ipairs(GATE_STATE_PRESETS) do
                if preset.value == value then return preset.label end
            end
            return tostring(value)
        end,
        function(value)
            saveSetting("GateStateStyle", value)
            logAlways("override square style set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "HighlightStyle", "Hover", settings.values.HighlightStyle,
        HIGHLIGHT_STYLE_PRESETS,
        function(value)
            for _, preset in ipairs(HIGHLIGHT_STYLE_PRESETS) do
                if preset.value == value then return preset.label end
            end
            return tostring(value)
        end,
        function(value)
            saveSetting("HighlightStyle", value)
            logAlways("hover style set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "HighlightOffsetY", "Frame nudge",
        tonumber(settings.values.HighlightOffsetY) or 0, HIGHLIGHT_OFFSET_PRESETS,
        function(value)
            if value == 0 then return "0 (on the slot)" end
            return (value > 0 and "+" or "") .. tostring(value)
        end,
        function(value)
            saveSetting("HighlightOffsetY", value)
            logAlways("hover frame nudge set to " .. tostring(value))
        end)

    drawPresetCombo(imgui, "IconBrightness", "Brightness",
        tonumber(settings.values.IconBrightness) or 1.0, BRIGHTNESS_PRESETS,
        function(value)
            if value >= 1.0 then return "Full (untouched)" end
            return string.format("%d%%", math.floor(value * 100 + 0.5))
        end,
        function(value)
            saveSetting("IconBrightness", value)
            logAlways("icon brightness set to " .. tostring(value))
        end)

    CONFIG.drawSizeTuning(imgui)
end

local function drawWindowBody(imgui)
    if ui.game == nil or #catalog.names == 0 then
        imgui.TextDisabled("Waiting for the game scripts to finish loading...")
        return
    end

    drawGodCombo(imgui)

    imgui.Spacing()

    local keepsakeWins, keepsakeChanged =
        imgui.Checkbox("Equipped keepsake overrides first boon pick",
                       settings.values.KeepsakeWins)
    if keepsakeChanged then
        saveSetting("KeepsakeWins", keepsakeWins)
        logAlways(keepsakeWins and "keepsakes win" or "keepsakes no longer win -- two gods possible")
    end
    tooltipOnHover(imgui, MORE_TOOLTIPS.Keepsake)

    local priority, priorityChanged =
        imgui.Checkbox("Always first (overrides Chaos Trials)", settings.values.AlwaysFirst)
    if priorityChanged then
        saveSetting("AlwaysFirst", priority)
        logAlways(priority
            and "ALWAYS FIRST on -- scripted encounters will be overridden"
            or "always first off -- the game's own forced boons are respected")
    end
    tooltipOnHover(imgui, MORE_TOOLTIPS.Priority)

    local respect, respectChanged =
        imgui.Checkbox("First boon disabled for unmet gods", settings.values.RespectEligibility)
    if respectChanged then
        saveSetting("RespectEligibility", respect)
    end
    tooltipOnHover(imgui, MORE_TOOLTIPS.Eligibility)

    local onlyPicked, onlyPickedChanged =
        imgui.Checkbox("Added gods only when I pick them",
                       settings.values.AddedGodsOnlyWhenPicked)
    if onlyPickedChanged then
        saveSetting("AddedGodsOnlyWhenPicked", onlyPicked)
        logAlways(onlyPicked and "added gods restricted to the pick"
            or "added gods may appear on the game's own roll")
    end
    tooltipOnHover(imgui, MORE_TOOLTIPS.OnlyPicked)

    local keepPick, keepPickChanged =
        imgui.Checkbox("Keep my pick after a restart", settings.values.KeepPickAfterRestart)
    if keepPickChanged then
        saveSetting("KeepPickAfterRestart", keepPick)
        logAlways(keepPick and "pick kept across restarts"
            or "pick resets to Standard on each launch")
    end
    tooltipOnHover(imgui, MORE_TOOLTIPS.KeepPick)

    local logDecisions, logChanged = imgui.Checkbox("Verbose logging", settings.values.LogDecisions)
    if logChanged then
        -- Write the value before saving so a "logging turned off" line is not the
        -- thing that gets suppressed.
        settings.values.LogDecisions = true
        logAlways(logDecisions and "decision logging enabled" or "decision logging disabled")
        saveSetting("LogDecisions", logDecisions)
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    -- These were config-file-only from the day the first one was added, which
    -- nobody noticed while all four shipped ON: there was never a reason to go
    -- looking for the switch. Two shipping OFF made the gap visible immediately.
    -- Driven from EXTRA_GODS so the next god added gets its switch for free
    -- rather than needing someone to remember this list exists.
    imgui.Text("Extra gods")
    tooltipOnHover(imgui, MORE_TOOLTIPS.ExtraGods)

    for _, god in ipairs(EXTRA_GODS) do
        local enabled, enabledChanged =
            imgui.Checkbox("Offer " .. god.name, settings.values[god.setting] == true)
        if enabledChanged then
            saveSetting(god.setting, enabled)
            logAlways(god.name .. (enabled and " enabled" or " disabled")
                .. " (restart to take effect)")
        end
        tooltipOnHover(imgui, MORE_TOOLTIPS.ExtraGods)
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    imgui.Text("Boon delay")
    tooltipOnHover(imgui, MORE_TOOLTIPS.NeverFirst)

    local hermes, hermesChanged =
        imgui.Checkbox("Hermes waits until I hold a boon", settings.values.BlockHermesBeforeBoon)
    if hermesChanged then
        saveSetting("BlockHermesBeforeBoon", hermes)
        logAlways(hermes and "Hermes gate on" or "Hermes gate off")
    end
    tooltipOnHover(imgui, MORE_TOOLTIPS.NeverFirst)

    local selene, seleneChanged =
        imgui.Checkbox("Selene waits until I hold a boon", settings.values.BlockSeleneBeforeBoon)
    if seleneChanged then
        saveSetting("BlockSeleneBeforeBoon", selene)
        logAlways(selene and "Selene gate on" or "Selene gate off")
    end
    tooltipOnHover(imgui, MORE_TOOLTIPS.NeverFirst)

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    imgui.Spacing()
    drawTuning(imgui)

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    drawStatus(imgui)
    drawGateStatus(imgui)

    if not settings.persistent then
        imgui.Spacing()
        imgui.TextDisabled("Config unavailable -- these settings reset when the game closes.")
    end
end

local function renderWindow()
    if not ui.showWindow then return end

    local imgui = rom.ImGui
    if imgui == nil then return end

    if not ui.seededSize then
        local cond = rom.ImGuiCond and rom.ImGuiCond.FirstUseEver or nil
        if cond ~= nil then
            pcall(imgui.SetNextWindowSize, WINDOW_WIDTH, WINDOW_HEIGHT, cond)
        else
            pcall(imgui.SetNextWindowSize, WINDOW_WIDTH, WINDOW_HEIGHT)
        end
        ui.seededSize = true
    end

    -- ImGui requires End() for every Begin(), including one that returns false,
    -- so the End call sits outside the protected body.
    local began = false
    local openState = true

    local ok, err = pcall(function()
        -- Begin returns (open, shouldDraw). shouldDraw is false when the window
        -- is collapsed or clipped; drawing anyway is wasted work at best.
        local shouldDraw
        openState, shouldDraw = imgui.Begin("Select First Boon###SelectFirstBoon", ui.showWindow)
        began = true
        if shouldDraw then
            drawWindowBody(imgui)
        end
    end)

    if began then
        pcall(imgui.End)
    end

    if not ok then
        logWarn("window render failed, closing it to avoid repeating: " .. tostring(err))
        ui.showWindow = false
        return
    end

    if openState == false then
        ui.showWindow = false
    end
end

local function renderMenuBar()
    local imgui = rom.ImGui
    if imgui == nil then return end

    local ok, err = pcall(function()
        -- EndMenu is called only when BeginMenu returned true, per ImGui's rules.
        if imgui.BeginMenu("SelectFirstBoon") then
            if imgui.MenuItem("Settings") then
                ui.showWindow = not ui.showWindow
                -- On the way open only: once per click, never per frame.
                if ui.showWindow then refreshCatalog(ui.game) end
            end
            imgui.EndMenu()
        end
    end)
    if not ok then
        logWarn("menu bar render failed: " .. tostring(err))
    end
end

-- =============================================================================
-- Install
-- =============================================================================

local function installHooks(game)
    local ModUtil = game.ModUtil
    if ModUtil == nil or ModUtil.Path == nil or ModUtil.Path.Wrap == nil then
        logWarn("ModUtil.Path.Wrap unavailable; hooks not installed")
        return false
    end

    -- SetupRoomReward returns nothing in vanilla (RewardLogic.lua:210-275), and
    -- no caller uses a return value, so we return nothing either.
    ModUtil.Path.Wrap("SetupRoomReward", function(base, currentRun, room, previouslyChosenRewards, args)
        local forceLootNameBeforeBase = room ~= nil and room.ForceLootName or nil

        base(currentRun, room, previouslyChosenRewards, args)

        -- Any failure inside our own logic must not take the reward pipeline
        -- down with it. Vanilla has already produced a valid, playable reward by
        -- this point; falling through leaves it intact.
        local applied, applyErr = pcall(
            applyForcedGod, game, currentRun, room, previouslyChosenRewards, args, forceLootNameBeforeBase
        )
        if not applied then
            logWarn("SetupRoomReward override failed, leaving vanilla reward in place: " .. tostring(applyErr))
        end
    end)

    -- Only ever turns eligible into ineligible; a reward vanilla already
    -- rejected stays rejected, and the base result is returned untouched if our
    -- own check throws.
    ModUtil.Path.Wrap("IsRoomRewardEligible", function(base, run, room, reward, previouslyChosenRewards, args)
        local eligible = base(run, room, reward, previouslyChosenRewards, args)
        if not eligible then return eligible end

        local ok, blocked = pcall(shouldBlockReward, game, reward)
        if not ok then
            logWarn("reward gate failed, leaving vanilla eligibility in place: " .. tostring(blocked))
            return eligible
        end
        if blocked then return false end
        return eligible
    end)

    -- Before base, not after: the priority list is consumed inside
    -- ChooseRoomReward itself (RewardLogic.lua:163-171), so a priority pushed
    -- afterwards would miss this room entirely.
    ModUtil.Path.Wrap("ChooseRoomReward", function(base, run, room, rewardStoreName, previouslyChosenRewards, args)
        -- game.CurrentRun, not the run argument: RewardStoreAddPriority writes
        -- to CurrentRun.RewardPriorities and CurrentRun.RewardStores directly
        -- (RewardLogic.lua:514, 518), so the once-per-run guard has to live on
        -- the same table or the two could disagree.
        local ok, err = pcall(addRewardPriority, game, game.CurrentRun, rewardStoreName)
        if not ok then
            logWarn("could not queue the first reward, leaving vanilla to roll: " .. tostring(err))
        end
        return base(run, room, rewardStoreName, previouslyChosenRewards, args)
    end)

    -- A run has a cap on how many gods it will use. Past it, the game stops
    -- offering new gods and only offers more boons from the ones you already
    -- have (GetEligibleLootNames collapses to LootTypeHistory,
    -- RewardLogic.lua:189-193). The count comes from GetInteractedGodsThisRun,
    -- which counts ANY LootTypeHistory entry whose LootData has GodLoot
    -- (RunLogic.lua:1819-1829).
    --
    -- So without this, taking the Artemis first boon would burn one of those
    -- slots -- you would get one fewer Olympian for the whole run, AND never
    -- another Artemis boon, since she is leashed to the first reward. Strictly
    -- worse than vanilla, and the opposite of the point.
    --
    -- These four are a one-off opening choice, not a patron for the run, so they
    -- are filtered out of that count. This is the single chokepoint: the max-gods
    -- check reads it, and so do the two encounter-loot picks at
    -- RewardLogic.lua:267-273, where an added god would be just as wrong.
    -- THE TAB STRIP ICON, WHICHEVER TAB YOU OPEN ON
    --
    -- scaleTabStripIcon used to run only from tabOpen and pickGod, so it fired
    -- only when OUR category was displayed. Open the inventory on Keepsakes and
    -- our strip icon was never touched -- it drew at whatever the game gives an
    -- unscaled category icon, which is visibly small next to the others, and it
    -- only corrected itself once you clicked onto our tab.
    --
    -- InventoryScreenDisplayCategory runs for every category including the one
    -- the screen opens on, and it is handed the screen, so it is the right
    -- place: our icon gets its size on open and keeps it while you move around.
    ModUtil.Path.Wrap("InventoryScreenDisplayCategory", function(base, screen, categoryIndex, args)
        local result = base(screen, categoryIndex, args)
        if settings.values.ShowInventoryTab then
            local ok, err = pcall(scaleTabStripIcon, game, screen, settings.values.God)
            if not ok then
                verbose("could not size the tab strip icon on category display: " .. tostring(err))
            end
        end
        return result
    end)

    ModUtil.Path.Wrap("GetInteractedGodsThisRun", function(base, ignoredGod)
        local gods = base(ignoredGod)
        local ok, filtered = pcall(function()
            local out = {}
            for _, name in ipairs(gods) do
                if not EXTRA_GOD_LOOT[name] then out[#out + 1] = name end
            end
            return out
        end)
        if not ok then
            logWarn("could not filter the god count, leaving it alone: " .. tostring(filtered))
            return gods
        end
        return filtered
    end)

    -- WHOSE TRAIT IS IT
    --
    -- Adding a LootData entry does more than make a drop possible. Four vanilla
    -- functions answer "which god owns this trait?" by scanning LootData, and
    -- every one of them starts answering "one of ours" the moment we register:
    --
    --   IsGodTrait            TraitLogic.lua:1547
    --   GetGodSourceName      TraitLogic.lua:1562
    --   GetLootSourceName     TraitLogic.lua:1576
    --   GetAllLootSourceNames TraitLogic.lua:1599
    --
    -- In vanilla these four say NO for Artemis, Athena, Dionysus and Hades
    -- traits, and the reason is precise: their data lives in FieldLootData with
    -- TreatAsGodLootByShops = true and GodLoot UNSET (RunData.lua:556-570), and
    -- the FieldLootData branch of IsGodTrait requires GodLoot unless the caller
    -- passed ForShop. That "no" is what makes their boons rarity-only.
    --
    -- Our entry sets GodLoot = true, because the reward pipeline needs it to
    -- treat the drop as boon loot at all. The side effect is that IsGodTrait
    -- flips to yes, and with it:
    --
    --   * GetAllUpgradeableGodTraits (TraitLogic.lua:1673) -- the list a Pom of
    --     Power offers. These boons would become pommable.
    --   * UpgradableGodTraitCountAtLeast (:1610) and HasSuperchargeableBoon
    --     (:1624) -- requirement checks some Arcana and shrines read.
    --   * The stack-boost block at UpgradeChoiceLogic.lua:295.
    --
    -- And it applies to boons taken from the NPC in an ordinary room, not just
    -- ours -- the trait names are the same objects. That is a change to the rest
    -- of the run, which is exactly what this plugin promises not to do.
    --
    -- The fix is to make our shadow entries invisible to those four scans, so
    -- they return the answer they would have returned with this plugin absent.
    -- Hiding the entries for the duration of the call rather than filtering the
    -- result is deliberate: IsGodTrait returns a bare boolean, so there is
    -- nothing in the result to filter. All four are synchronous, read-only
    -- scans over LootData and FieldLootData -- no waits, no callbacks -- so
    -- nothing can observe the gap.
    local TRAIT_SOURCE_FUNCTIONS = {
        "IsGodTrait", "GetGodSourceName", "GetLootSourceName", "GetAllLootSourceNames",
    }
    for _, fnName in ipairs(TRAIT_SOURCE_FUNCTIONS) do
        if type(game[fnName]) == "function" then
            ModUtil.Path.Wrap(fnName, function(base, a, b, c)
                local lootData = game.LootData
                if type(lootData) ~= "table" then return base(a, b, c) end

                local stash = nil
                for name in pairs(EXTRA_GOD_LOOT) do
                    if lootData[name] ~= nil then
                        stash = stash or {}
                        stash[name] = lootData[name]
                        lootData[name] = nil
                    end
                end
                if stash == nil then return base(a, b, c) end

                local ok, result = pcall(base, a, b, c)
                -- Restored before anything else, including before the error
                -- path: leaving four LootData entries missing would be a far
                -- worse failure than whatever raised.
                for name, data in pairs(stash) do lootData[name] = data end
                if not ok then
                    logWarn(fnName .. " raised while our gods were hidden: " .. tostring(result))
                    -- Re-raised rather than retried. These are pure scans over
                    -- LootData and FieldLootData, so hiding four entries cannot
                    -- be what made one throw -- a retry would fail identically
                    -- and only bury the real error one frame deeper.
                    error(result, 0)
                end
                return result
            end)
        else
            logWarn("no " .. fnName .. " to wrap; added gods' boons may become pommable")
        end
    end

    -- ADDED GODS ARE A PICK, NOT A NEW RESIDENT OF THE POOL
    --
    -- Registering a god means adding a LootData entry with GodLoot = true, and
    -- GetEligibleLootNames (RewardLogic.lua:186-200) walks all of LootData and
    -- keeps everything with that flag whose GameStateRequirements pass. Ours pass
    -- while no boon has been taken yet -- so on the run's first boon they sat in
    -- vanilla's candidate list beside Zeus and Hera, and its own roll could land
    -- on one. That happened regardless of the pick, including on Standard.
    --
    -- Which is a contradiction in a plugin whose whole claim is that you choose
    -- what comes first: you could ask for Hermes, take him, and have the run's
    -- actual first boon come back Narcissus unasked.
    --
    -- So an added god is eligible only while it IS the pick. Everywhere else
    -- these gods are met the way the base game means them to be met: by talking
    -- to them. Note the four cases this closes that a narrower fix would not --
    -- Standard, an overriding keepsake, an unmet-god skip, and a Hammer, Hermes
    -- or Selene pick, none of which count as a boon and so leave the first boon
    -- still ahead.
    ModUtil.Path.Wrap("GetEligibleLootNames", function(base, excludeLootNames)
        local names = base(excludeLootNames)
        if not settings.values.AddedGodsOnlyWhenPicked then return names end
        if type(names) ~= "table" then return names end

        local ok, filtered = pcall(function()
            local chosen = settings.values.God
            local out = {}
            for _, name in ipairs(names) do
                if not EXTRA_GOD_LOOT[name] or name == chosen then
                    out[#out + 1] = name
                end
            end
            return out
        end)
        if not ok then
            logWarn("could not filter the eligible gods, leaving them alone: "
                .. tostring(filtered))
            return names
        end
        -- Never hand back an empty list where the game had one: emptying the god
        -- pool is a far worse failure than an added god being offered once.
        if #filtered == 0 and #names > 0 then
            logWarn("filtering the added gods would have emptied the pool; left alone")
            return names
        end
        return filtered
    end)

    -- The one place vanilla turns a loot's trait pool into the list it will
    -- actually offer (UpgradeChoiceLogic.lua:899; sole caller TraitLogic.lua:1861).
    -- It filters on TraitRequirements and IsTraitEligible but knows nothing of the
    -- per-offer GameStateRequirements sitting on the encounter tables -- in vanilla
    -- the encounter had already applied those long before this ran. Our drop has no
    -- encounter, so we apply them here, on the finished list, after vanilla's own.
    ModUtil.Path.Wrap("GetEligibleUpgrades", function(base, upgradeOptions, lootData, upgradeChoiceData)
        local upgrades = base(upgradeOptions, lootData, upgradeChoiceData)
        local ok, result = pcall(CONFIG.filterOffers, game, lootData, upgrades)
        if not ok then
            logWarn("offer gating failed, leaving the vanilla list intact: " .. tostring(result))
            return upgrades
        end
        return result
    end)

    ModUtil.Path.Wrap("GiveLoot", function(base, args)
        local loot = base(args)

        local marked, markErr = pcall(markSpawned, game, args, loot)
        if not marked then
            logWarn("GiveLoot bookkeeping failed: " .. tostring(markErr))
        end

        return loot
    end)

    return true
end

local function installUi()
    if rom.gui == nil then
        logWarn("rom.gui unavailable; no settings UI")
        return
    end
    if type(rom.gui.add_to_menu_bar) == "function" then
        rom.gui.add_to_menu_bar(renderMenuBar)
    end
    if type(rom.gui.add_imgui) == "function" then
        rom.gui.add_imgui(renderWindow)
    end
end

-- Both run in the main chunk, where an uncaught error means ReturnOfModding
-- refuses to load the module at all. Neither is worth losing the plugin over.
local bootOk, bootErr = pcall(function()
    loadSettings()
    resetPickOnLaunch()
    installUi()
end)
if not bootOk then
    logWarn("startup failed, continuing with defaults and no UI: " .. tostring(bootErr))
end

modutil.once_loaded.game(function()
    local ok, err = pcall(function()
        local game = rom.game
        if game == nil then
            logWarn("rom.game is nil; not installing")
            return
        end
        ui.game = game

        -- Before buildCatalog, so she is in the list on the very first open
        -- rather than only after a refresh.
        registerExtraGods(game)

        local candidatesOk, candidatesErr = pcall(logGodCandidates, game)
        if not candidatesOk then
            logWarn("could not list god candidates: " .. tostring(candidatesErr))
        end

        buildCatalog(game)

        local obstacleOk, obstacleErr = pcall(registerButtonObstacle, game)
        if not obstacleOk then
            logWarn("button obstacle setup failed, using the vanilla button: " .. tostring(obstacleErr))
        end

        local iconOk, iconErr = pcall(registerCustomIcons)
        if not iconOk then
            logWarn("custom icon registration failed, using the vanilla set: " .. tostring(iconErr))
        end

        local tabOk, tabErr = pcall(installInventoryTab, game)
        if not tabOk then
            logWarn("inventory tab install failed, continuing without it: " .. tostring(tabErr))
        end

        if installHooks(game) then
            local chosen = settings.values.God
            logAlways("installed; first boon god is "
                .. (chosen == NONE_VALUE and "None (vanilla)" or chosen)
                .. (settings.persistent and "" or " (settings not persisted)"))
        end
    end)

    if not ok then
        logWarn("install failed, plugin inactive: " .. tostring(err))
    end
end)
