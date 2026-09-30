-- =============================================================================
-- SelectFirstBoon
-- =============================================================================
-- Forces the first boon reward of a run to come from one chosen god.
--
-- NOT a boon spawner. The run plays normally -- you walk into the boon room,
-- get three options, at the normal time. Only WHICH god it belongs to changes.
--
-- Hermes and Selene are held back separately: neither is a "Boon" reward type,
-- so the pick can never affect them. That is a different mechanism, in
-- shouldBlockReward below.
--
-- DESIGN.md explains every mechanism, with citations into the game's scripts.
-- Read it before changing behavior; CONTRIBUTING.md has the test rules.
-- =============================================================================
local mods = rom.mods
-- LuaENVY-ENVY, not the SGG_Modding-ENVY shim, which the manifest doesn't list.
mods["LuaENVY-ENVY"].auto()

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
-- is the game's own behavior with nothing touched, and how random that is
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

-- Hammer, Hermes, Selene and Chaos are reward TYPES, not boons, so the god
-- mechanism (room.ForceLootName) can't reach them. They go the way a keepsake
-- does instead: RewardStoreAddPriority pushes the reward name onto
-- CurrentRun.RewardPriorities, and ChooseRoomReward consumes it once
-- (RewardLogic.lua:163-171, 513-533). Values are @-prefixed so they can never
-- collide with a LootData key.
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
        -- No moon in BoonSelectSymbols, so her door-preview art instead.
        file   = "Items\\Loot\\SpellDrop_Preview",
        portrait = "Selene",
        gate   = "BlockSeleneBeforeBoon",
        blurb  = "Offer Selene's path as the run's first reward.",
    },
    {
        -- TrialUpgrade already has a full LootData entry and art; it only needs
        -- queuing as the first reward, like Hermes.
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
        AlwaysFirst = false,
        DisableEverything = false,
        KeepsakeWins = false,
        KeepPickAfterRestart = false,
        EnableArtemis = true,
        EnableAthena = true,
        EnableDionysus = true,
        EnableHades = true,
        EnableNarcissus = true,
        EnableArachne = true,
        EnableCirce = true,
        EnableEcho = true,
        EnableIcarus = true,
        EnableMedea = true,
    },
    entries = {},
    file = nil,
    persistent = false,
}

-- How everything looks: sizes, brightness, the selection light, which art is
-- used. Constants set by eye in game (DESIGN.md, "Tuning"). Not in the .cfg
-- and not on the panel.
local TUNING = {
        TabIconScale = 0.45,
        TabButtonBoxWidth = 0,
        TabButtonBoxHeight = 0,
        IconStyle = "boondrop",
        PortraitIconOffsetY = 6,
        IconOffsetY = 10,
        SeleneIconBoost = 2.0,
        PortraitIconBoost = 0.4,
        DropIconScale = 0.4,
        DropPortraitScale = 0.22,
        DoorEmblemScale = 0.6,
        DoorPortraitScale = 0.25,
        GlowBrightnessArtemis = 0.6,
        GlowBrightnessAthena = 0.7,
        GlowBrightnessDionysus = 0.6,
        GlowBrightnessHades = 0.6,
        EmblemBrightnessArtemis = 1.0,
        EmblemBrightnessAthena = 0.7,
        EmblemBrightnessDionysus = 1.0,
        EmblemBrightnessHades = 1.0,
        HitboxScale = 1.0,
        HitboxScalePortrait = 1.0,
        SelectionHaloStrength = 0.35,
        SelectionHaloSize = 0.5,
        -- A hollow core and outward-stepped layers make the light a ring the
        -- art sits inside, rather than a wash behind it.
        SelectionHaloSpreadStep = 0.15,
        SelectionHaloCore = 0,
        SelectionHaloWhiten = 0.05,
        SelectionHaloFollowsIcon = 0.25,
        SelectionHaloTint = "god",
        SelectionHaloTintMix = 1.0,
        SelectionHaloLayers = 4,
        TabIconBoost = 1.15,
        IconSize = 1.0,
        UnselectedBrightness = 0.7,
        SelectedIconScale = 1.25,
        IconBrightness = 1.0,
        EmblemBrightnessNarcissus = 1.0,
        GlowBrightnessNarcissus = 0.6,
        EmblemBrightnessCirce = 1.0,
        GlowBrightnessCirce = 0.6,
        EmblemBrightnessEcho = 1.0,
        GlowBrightnessEcho = 0.6,
        EmblemBrightnessIcarus = 1.0,
        GlowBrightnessIcarus = 0.6,
        EmblemBrightnessMedea = 1.0,
        GlowBrightnessMedea = 0.6,
        EmblemBrightnessArachne = 1.0,
        GlowBrightnessArachne = 0.6,
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

-- .cfg sections, numbered so Chalk writes Main first. CONFIG is one table
-- rather than several locals because this file is near Lua's 200-local limit.
local CONFIG = {
    MAIN       = "1 - Main",
    GODS       = "2 - Extra gods",
}

function CONFIG.sectionFor(key)
    if key:sub(1, 6) == "Enable" then return CONFIG.GODS end
    return CONFIG.MAIN
end

-- Each ends with when a change applies: at once, "Next run.", "Next reward
-- rolled.", or "Restart the game." (baked into game data at load).
local CONFIG_DESCRIPTIONS = {
    God = "What the run's first reward is. Empty means the game's own order, "
        .. "untouched. Otherwise a god's loot name -- ZeusUpgrade, HeraUpgrade, "
        .. "HestiaUpgrade and so on -- or one of @Hammer, @Hermes, @Selene. "
        .. "Anything else is ignored and logged. Next reward rolled.",

    DisableEverything = "The master switch. On, this plugin does nothing at all: "
        .. "no pick is forced, no boon is scheduled, and Hermes and Selene are "
        .. "left alone. Everything you have set is remembered and comes back "
        .. "exactly as it was when you turn it off again -- it is a way to be "
        .. "certain the mod is out of the way for a run, not a reset. Next reward "
        .. "rolled.",

    AlwaysFirst = "Off: your pick waits its turn. The game chooses the first "
        .. "reward, and anything it has scripted -- a Chaos Trial's opening boon, "
        .. "a story beat -- happens as designed; yours lands on the next boon "
        .. "after that. On: your pick goes first no matter what, and the "
        .. "scripted boon is replaced rather than delayed. Next run.",

    KeepsakeWins = "Whether an equipped boon keepsake beats the pick. On, the "
        .. "keepsake wins and this plugin sits out the whole run. Off, you get "
        .. "both: the keepsake forces the first boon and the pick takes the "
        .. "next one, so two guaranteed gods. Next run.",

    RespectEligibility = "On, a god you have not met cannot be your first boon and "
        .. "the pick is ignored. Off, you get them regardless, which is what an "
        .. "equipped keepsake does. A safeguard, off by default. Next reward "
        .. "rolled.",

    KeepPickAfterRestart = "On, your pick is still there next time you launch the "
        .. "game. Off, every launch starts at Standard and picking a god is "
        .. "something you do on purpose that session. Off by default. Takes "
        .. "effect at the next launch.",

    BlockHermesBeforeBoon = "Hold Hermes out of the reward pool until you hold a "
        .. "boon or a hammer. Ignored while Hermes is your pick. Next reward rolled.",

    BlockSeleneBeforeBoon = "Hold Selene out of the reward pool until you hold a "
        .. "boon or a hammer. Ignored while Selene is your pick. Next reward rolled.",

    EnableNarcissus = "Whether Narcissus can be picked as the run's first boon. "
        .. "His drop uses a keepsake portrait with a glow added at runtime rather "
        .. "than a painted boon symbol. Restart the game.",

    EnableCirce = "Whether Circe can be picked as the run's first boon. Her drop "
        .. "uses a keepsake portrait with a glow added at runtime rather than a "
        .. "painted boon symbol. Restart the game.",
    EnableEcho = "Whether Echo can be picked as the run's first boon. Her drop "
        .. "uses a keepsake portrait with a glow added at runtime rather than a "
        .. "painted boon symbol. Restart the game.",
    EnableIcarus = "Whether Icarus can be picked as the run's first boon. His drop "
        .. "uses a keepsake portrait with a glow added at runtime rather than a "
        .. "painted boon symbol. Restart the game.",

    EnableMedea = "Whether Medea can be picked as the run's first boon. She was "
        .. "briefly blamed for a crash during development; it was traced to a "
        .. "Lua memory fault unconnected to her, and four deliberate tests since "
        .. "have been clean. Restart the game.",
    EnableArachne = "Whether Arachne can be picked as the run's first boon. Her "
        .. "drop uses a keepsake portrait with a glow added at runtime. Note "
        .. "that her boons come with a costume, so picking her first changes "
        .. "Melinoe's outfit for the run -- that is how her boons work in the "
        .. "base game, not something this adds. Restart the game.",

    EnableHades = "Offer Hades as a first-boon option, on the same terms as Artemis. Restart the game.",

    LogDecisions = "Write one line to the ReturnOfModding log for each decision "
        .. "this plugin makes, and each one it declines to make, plus the tab's "
        .. "layout, hovers and clicks. Leave it on if you might report a bug.",
}


-- =============================================================================
-- NATIVE INVENTORY TAB
-- =============================================================================
--
-- The game supports custom inventory tabs: InventoryScreenDisplayCategory
-- calls category.OpenFunctionName / CloseFunctionName (ResourceLogic.lua:381,
-- 438), as the Pin and Line History tabs do. Adding a category costs one
-- table.insert and overrides nothing, unlike PonyMenu's override of the whole
-- render function; PonyMenu's copy keeps that branch, so both work together.
--
-- CallFunctionName resolves through _G (EventLogic.lua:66), so the handlers
-- are assigned onto rom.game. OpenInventoryScreen deep-copies the screen data
-- (ResourceLogic.lua:228), so inserting the category once at load is enough.

local TAB_CATEGORY_NAME = "Select First Boon"
local TAB_OPEN_FN = "SelectFirstBoon_InventoryTabOpen"
local TAB_CLOSE_FN = "SelectFirstBoon_InventoryTabClose"
local TAB_PICK_FN = "SelectFirstBoon_InventoryTabPick"
local TAB_OVER_FN = "SelectFirstBoon_InventoryTabOver"
local TAB_OFF_FN = "SelectFirstBoon_InventoryTabOff"

-- The tab icon is an animation name (ResourceLogic.lua:290). The tab shows the
-- current pick's icon; see tabIconFor.
local DEFAULT_TAB_ICON = "BoonInfoSymbolChaosIcon"
-- Standard's picture: the flat pomegranate. It isn't a god, and nothing else
-- in the menu uses it.
local function standardSymbol()
    return "PomFlat"
end

-- Reward-store entry name -> the setting that gates it. These are reward TYPES,
-- not gods: LootData_Hermes.lua has GodLoot = false, and Selene's reward is
-- SpellDrop, so neither can ever come out of ChooseLoot for a "Boon".
local GATED_REWARDS = {
    HermesUpgrade = "BlockHermesBeforeBoon",
    SpellDrop     = "BlockSeleneBeforeBoon",
}

-- What counts as "you hold a boon". The list is adamantSpeedrun's, from the
-- Gameplay QoL pack's DisableSeleneBeforeBoon, WeaponUpgrade (a Daedalus
-- hammer) included.
local COUNTS_AS_A_BOON = {
    "AphroditeUpgrade", "ApolloUpgrade", "AresUpgrade", "DemeterUpgrade",
    "HephaestusUpgrade", "HeraUpgrade", "HestiaUpgrade", "PoseidonUpgrade",
    "ZeusUpgrade", "WeaponUpgrade",
}

local BLOCK_LOG_FIELD = "SelectFirstBoon_BlockLogged"

-- Tests vary the tuning to check the arithmetic built on it, through this one
-- global set by the harness. In the game it is nil. Size<Icon>, Core<Icon> and
-- Light<Icon> reach the per-icon tables.
local function applyTuningOverrides()
    local overrides = type(_G) == "table" and rawget(_G, "SelectFirstBoon_TuningOverrides") or nil
    if type(overrides) ~= "table" then return end
    for key, value in pairs(overrides) do
        local kind, name = tostring(key):match("^(%u%l+)(%u%a*)$")
        local perIcon = kind and CONFIG["tune" .. kind .. "Defaults"]
        if TUNING[key] ~= nil and type(value) == type(TUNING[key]) then
            TUNING[key] = value
        elseif perIcon ~= nil and type(value) == "number" then
            perIcon[name] = value
        end
    end
end

-- Chalk's own primitives (bind, get, set, save), used directly.
local function loadSettings()
    applyTuningOverrides()
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

-- The pick is a choice about one run, so each launch starts at Standard
-- unless KeepPickAfterRestart is on. Runs before the UI is built.
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

-- Another plugin may add gods after this one loads, so the catalog is also
-- rebuilt when the tab or window opens, if the god count has changed.
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

    -- A pick that no longer exists would sit in the .cfg forever, declined
    -- silently. Clear it, but only against a real LootData read.
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

-- Only rebuilds when the god count changed; a stale list beats a failed screen.
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
-- Logic
-- =============================================================================

-- The exclusion list, built as RewardLogic.lua:230-237 does (skipping nils).
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

-- With KeepsakeWins on, an armed keepsake makes the plugin sit out the whole
-- run. Latched per run: checked live, it would unlatch once the keepsake is
-- spent and force a second god.
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

-- What an equipped keepsake will force, without latching anything: reading the
-- panel must never decide the run. Only Olympian keepsakes carry ForceBoonName.
function CONFIG.keepsakeGod(game)
    local currentRun = game ~= nil and game.CurrentRun or nil
    if currentRun == nil then return nil end
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

local function equippedForcedGod(game)
    if not settings.values.KeepsakeWins then return nil end
    return CONFIG.keepsakeGod(game)
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
    if CONFIG.pluginOff() then
        log("declined: the master switch is off")
        return
    end
    if standDownForKeepsake(game, currentRun) then return end

    args = args or {}

    local chosenRewardType = args.ChosenRewardType or room.ChosenRewardType
    if chosenRewardType ~= "Boon" then return end

    -- Vanilla's entry guard (RewardLogic.lua:228): a ForceLootName set on the
    -- way in means something scripted (a Chaos Trial, a story beat) already
    -- chose the god. AlwaysFirst ("Override Special") walks through it.
    local excludeLootNames = buildExcludeLootNames(previouslyChosenRewards)

    -- An armed keepsake outranks the pick, AlwaysFirst or not; the pick takes
    -- the next boon. Checked before the override so the keepsake keeps its credit.
    local keepsakeGod = keepsakeWouldClaim(game, currentRun, excludeLootNames)
    if keepsakeGod ~= nil then
        log("declined: equipped keepsake is forcing " .. tostring(keepsakeGod) .. " and takes priority")
        return
    end

    if not (args.AlwaysSetupForceLootName or not forceLootNameBeforeBase) then
        if settings.values.AlwaysFirst then
            logAlways("overriding a pre-forced reward ("
                .. tostring(forceLootNameBeforeBase) .. ") because AlwaysFirst is on"
                .. " -- scripted encounters like Chaos Trials will not play as designed")
            -- Clear the keepsake credit vanilla recorded (RewardLogic.lua:245), or
            -- its flourish would play for a boon it didn't give.
            if room.ForceBoonChosenTrait ~= nil then
                log("clearing the keepsake credit: its boon was overridden, so the"
                    .. " flourish would name a keepsake that did not give this")
                room.ForceBoonChosenTrait = nil
            end
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

    -- Another door in this same unlock already took our god. Vanilla's keepsake
    -- stands down here too, which is what stops two doors showing the same god.
    if game.Contains(excludeLootNames, desiredGod) then
        log("declined: " .. desiredGod .. " already offered by another door in this unlock")
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
local function markSpawned(game, args, loot, keepsakeArmedFor)
    local desiredGod = settings.values.God
    if desiredGod == nil or desiredGod == NONE_VALUE then return end

    local currentRun = game.CurrentRun
    if currentRun == nil or currentRun[USED_FIELD] then return end
    if loot == nil or loot.Name ~= desiredGod then return end
    if args ~= nil and args.BoughtFromShop then return end

    -- Same god on keepsake and pick: this spawn is the keepsake's, and the pick
    -- still takes the next boon.
    if keepsakeArmedFor ~= nil and keepsakeArmedFor == loot.Name
        and not settings.values.KeepsakeWins then
        log(desiredGod .. " boon spawned for the keepsake; the pick of the same god still stands for the next boon")
        return
    end

    currentRun[USED_FIELD] = true
    log(desiredGod .. " boon spawned; plugin is done for this run")

    -- Seed diagnostic, three lines per run: if a pick ever seems to repeat the
    -- same three boons, this shows whether NextSeeds[1] or DebugRNGSeed is why
    -- (RandomLogic.lua:11, 66).
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

    -- Not gated on AlwaysFirst: pushing "Boon" only schedules a boon, as a
    -- keepsake does, and overrides nothing.
    if not catalog.index[chosen] then return nil end
    return "Boon", nil
end

-- The game's own RewardStoreAddPriority, which also tops up the store
-- (RewardLogic.lua:518-532), into the store ChooseRoomReward is reading. Once
-- per run, recorded on CurrentRun so a save-and-quit can't push a second.
local function addRewardPriority(game, currentRun, rewardStoreName)
    if currentRun == nil then return end
    if currentRun[PRIORITY_FIELD] then return end
    if currentRun[USED_FIELD] then return end
    if CONFIG.pluginOff() then return end
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

-- "Holds a boon": any god boon or a Daedalus hammer in LootTypeHistory.
local function hasBoonThisRun(currentRun)
    local history = currentRun and currentRun.LootTypeHistory
    if type(history) ~= "table" then return false end
    for _, name in ipairs(COUNTS_AS_A_BOON) do
        if history[name] then return true end
    end
    return false
end

-- The eligibility check runs dozens of times per door; log once per reward per run.
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

-- The master switch. Every action routes through this, the forced pick or the
-- reward priority.
function CONFIG.pluginOff()
    return settings.values.DisableEverything == true
end

-- Picking Hermes or Selene first switches off its own gate while it's picked;
-- otherwise the gate would block the reward the priority asked for.
local function gateSuppressedBy(rewardName)
    local special = specialFor(settings.values.God)
    if special == nil then return false end
    return special.reward == rewardName
end

local function shouldBlockReward(game, reward)
    if type(reward) ~= "table" then return false end
    -- Master switch: Hermes and Selene are left exactly as vanilla has them.
    if CONFIG.pluginOff() then return false end

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
-- Added boon gods: first-reward-only
-- =============================================================================
-- NPC gods who already offer a one-of-three boon choice in vanilla, given a
-- LootData entry so a door can promise one. Everything in it points at art and
-- data the game ships (trait pool, emblem or portrait, colors). Three promises,
-- each enforced below: never a shop item; eligible only as the run's first
-- reward (FIRST_REWARD_ONLY); meeting them in the world is untouched.
--
-- dropA/B/C are the orb's glow layers in the game's 0-1 channel form. Athena
-- follows Hephaestus's shape (dark outside, saturated color at the core); the
-- portrait gods derive theirs from LootColor. DESIGN.md, "The glow layers".
local EXTRA_GODS = {
    {
        name = "Artemis", setting = "EnableArtemis",
        emblemSetting = "EmblemBrightnessArtemis",
        glowSetting = "GlowBrightnessArtemis",
        npc = "NPC_Artemis_Field_01",
        dropA = { Red = 0.28, Green = 0.46, Blue = 0.12, Opacity = 0.91 },
        dropB = { Red = 0.39, Green = 0.52, Blue = 0.21, Opacity = 0.93 },
        dropC = { Red = 0.23, Green = 0.57, Blue = 0.31, Opacity = 1.0 },
        lootColor = { 20, 120, 7, 255 },
    },
    {
        name = "Athena", setting = "EnableAthena",
        emblemSetting = "EmblemBrightnessAthena",
        glowSetting = "GlowBrightnessAthena",
        npc = "NPC_Athena_01",
        dropA = { Red = 0.36, Green = 0.28, Blue = 0.06 },
        dropB = { Red = 0.96, Green = 0.72, Blue = 0.14 },
        dropC = { Red = 1.0, Green = 0.76, Blue = 0.0 },
        lootColor = { 194, 163, 41, 255 },
    },
    {
        name = "Dionysus", setting = "EnableDionysus",
        emblemSetting = "EmblemBrightnessDionysus",
        glowSetting = "GlowBrightnessDionysus",
        npc = "NPC_Dionysus_01",
        -- Wine out, vine in.
        dropA = { Red = 0.62, Green = 0.16, Blue = 0.85 },
        dropB = { Red = 0.72, Green = 0.20, Blue = 1.0 },
        dropC = { Red = 0.35, Green = 1.0, Blue = 0.45 },
        lootColor = { 166, 41, 194, 255 },
    },
    {
        -- A full boon god here; GodsAPI clears his GodLoot, but the game doesn't require it.
        name = "Hades", setting = "EnableHades",
        emblemSetting = "EmblemBrightnessHades",
        glowSetting = "GlowBrightnessHades",
        npc = "NPC_Hades_Field_01",
        dropA = { Red = 0.10, Green = 0.10, Blue = 0.12 },
        dropB = { Red = 0.859, Green = 0.859, Blue = 0.776, Opacity = 0.8 },
        dropC = { Red = 0.16, Green = 0.16, Blue = 0.18 },
        lootColor = { 219, 219, 198, 255 },
    },
    {
        -- Portrait-only gods: a keepsake portrait, no emblem. Their traits carry
        -- RarityLevels and are offered one-of-three, which is what makes them boons.
        name = "Narcissus", setting = "EnableNarcissus",
        npc = "NPC_Narcissus_Field_01",
        offers = "NarcissusBenefitChoices",
        emblemSetting = "EmblemBrightnessNarcissus",
        glowSetting = "GlowBrightnessNarcissus",
        portraitOnly = true,
    },
    {
        -- Her traits change Melinoe's outfit, as they do when taken from her.
        name = "Arachne", setting = "EnableArachne",
        npc = "NPC_Arachne_01",
        offers = "ArachneCostumeChoices",
        emblemSetting = "EmblemBrightnessArachne",
        glowSetting = "GlowBrightnessArachne",
        portraitOnly = true,
    },
    {
        -- Run modifiers: shrink, enlarge, Arcana.
        name = "Circe", setting = "EnableCirce",
        npc = "NPC_Circe_01",
        offers = "CirceBlessingChoices",
        emblemSetting = "EmblemBrightnessCirce",
        glowSetting = "GlowBrightnessCirce",
        portraitOnly = true,
    },
    {
        -- Repeats last run's boon or reward.
        name = "Echo", setting = "EnableEcho",
        npc = "NPC_Echo_01",
        offers = "EchoBenefitChoices",
        emblemSetting = "EmblemBrightnessEcho",
        glowSetting = "GlowBrightnessEcho",
        portraitOnly = true,
    },
    {
        name = "Icarus", setting = "EnableIcarus",
        npc = "NPC_Icarus_01",
        offers = "IcarusBenefitChoices",
        emblemSetting = "EmblemBrightnessIcarus",
        glowSetting = "GlowBrightnessIcarus",
        portraitOnly = true,
    },
    {
        -- A crash was once blamed on her; it wasn't hers (DESIGN.md, "Medea").
        name = "Medea", setting = "EnableMedea",
        npc = "NPC_Medea_01",
        emblemSetting = "EmblemBrightnessMedea",
        glowSetting = "GlowBrightnessMedea",
        portraitOnly = true,
    },
}

-- Named after the mod: these strings reach the .cfg and save data, so they must not churn.
local LOOT_PREFIX = "SelectFirstBoon-"
local function lootNameFor(godName) return LOOT_PREFIX .. godName .. "Upgrade" end


-- The picture inside the orb: an emblem god's BoonSelectSymbols art, or a
-- portrait-only god's keepsake portrait (which renders in a world orb; DESIGN.md,
-- "Portrait-in-orb").
local EMBLEM_ART_PATHS = {
    symbol = "GUI\\Screens\\BoonSelectSymbols\\",
    portrait = "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_big\\",
}

local function emblemArtStyleFor(god)
    if god ~= nil and god.portraitOnly then return "portrait" end
    return "symbol"
end

local function emblemArtPathFor(god)
    local style = emblemArtStyleFor(god)
    return EMBLEM_ART_PATHS[style] .. god.name
end

-- The orb picture's size, per art family: emblems and portraits differ in source size.
local function dropIconScale(god)
    local portrait = emblemArtStyleFor(god) ~= "symbol"
    local key = portrait and "DropPortraitScale" or "DropIconScale"
    local fallback = portrait and 0.22 or 0.4
    local value = tonumber(TUNING[key])
    if value == nil or value <= 0 then return fallback end
    return value
end

-- The door picture's size, per art family.
function CONFIG.doorPreviewScale(god)
    local portrait = emblemArtStyleFor(god) ~= "symbol"
    local key = portrait and "DoorPortraitScale" or "DoorEmblemScale"
    local fallback = portrait and 0.22 or 1.0
    local value = tonumber(TUNING[key])
    if value == nil or value <= 0 then return fallback end
    return value
end

-- A gray multiplier on one god's emblem (it dims the painted halo too), or nil
-- at 1.0 so the entry is left as vanilla-shaped as possible.
local function emblemColor(god)
    local key = god ~= nil and god.emblemSetting or nil
    if key == nil then return nil end
    local value = tonumber(TUNING[key])
    if value == nil or value <= 0 or value == 1.0 then return nil end
    return { Red = value, Green = value, Blue = value }
end

-- Emblem art on a door is dimmed: its painted halo reads as glow around a
-- small medallion.
local DOOR_EMBLEM_DIM = 0.5
local function doorPreviewColor(god)
    if emblemArtStyleFor(god) ~= "symbol" then return nil end
    local base = emblemColor(god)
    local value = (base and base.Red or 1.0) * DOOR_EMBLEM_DIM
    return { Red = value, Green = value, Blue = value }
end

local EXTRA_GOD_LOOT = {}
local EXTRA_GOD_BY_LOOT = {}
for _, god in ipairs(EXTRA_GODS) do
    EXTRA_GOD_LOOT[lootNameFor(god.name)] = true
    EXTRA_GOD_BY_LOOT[lootNameFor(god.name)] = god
end

-- "No boon taken yet this run", as data, so the game's own eligibility pass
-- enforces it.
local function firstRewardOnlyRequirement(game, selfLoot)
    local taken = {}
    for _, name in ipairs(COUNTS_AS_A_BOON) do taken[#taken + 1] = name end
    -- Every added god counts, this one included, and any god another plugin
    -- added, or "first boon" would mean "first vanilla boon".
    for _, god in ipairs(EXTRA_GODS) do taken[#taken + 1] = lootNameFor(god.name) end
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

-- A boon drop is a chain of shared vanilla layers with one god-specific
-- picture at the center (Items_General_VFX.sjson:4905):
--
--     BoonDrop<God>       <- BoonDropGold      the orb
--       BoonDropA-<God>   <- BoonDropA         outer glow, tinted
--       BoonDropB-<God>   <- BoonDropB         mid glow, tinted
--       BoonDropC-<God>   <- BoonDropC         inner glow, tinted
--       BoonDrop<God>Icon <- BoonDropIcon      the god's picture
--
-- Animation colors are named 0-1 channels, not LootData's 0-255 tables; the
-- wrong shape fails silently (the drop renders untinted).
local COLOR_ORDER = { "Red", "Green", "Blue", "Opacity" }

-- The glow and flare each layer spawns, as vanilla does (:5854-5884). The flare
-- is our own copy of BoonDropFrontFlare with its pulse capped: vanilla's three
-- stacked white pulses wash a painted portrait out.
local DROP_FLARE_NAME = "SelectFirstBoon_DropFrontFlare"
local DROP_FLARE_PEAK = 0.4
local DROP_SUB_ANIMATIONS = { "BoonDropBackGlow", DROP_FLARE_NAME }

-- Layer colors for a god with no hand-picked palette, from the game's own color
-- for them (LootColor, else LightingColor, else SubtitleColor), normalized so
-- the brightest channel is 1.0, in Hephaestus's dark-to-saturated shape.
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
                        "Loop", "Scale", "EndOffsetZ",
                        "StartScaleX", "EndScaleX", "PingPongScale", "Duration",
                        "StartAngle", "EndAngle", "PingPongAngle",
                        "Alpha", "StartAlpha", "EndAlpha" }
        -- One brightness for the whole orb: the channels are scaled, since vanilla
        -- drops carry no Opacity.
        local glow = tonumber(TUNING[god.glowSetting or ""])
        if glow == nil or glow <= 0 then glow = 1.0 end
        logAlways(("%s drop registering at glow %s (orb and all three layers)")
            :format(god.name, tostring(glow)))
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
                    -- Opacity is alpha; scaling it would fade, not dim.
                    if channel == "Opacity" then
                        scaled[channel] = value
                    else
                        scaled[channel] = value * glow
                    end
                end
            end
            return sjson.to_object(scaled, COLOR_ORDER)
        end
        -- The picture isn't a glow layer, so it skips the glow dial.
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
            -- BoonDropGold's Color multiplies (:4958-4971), so this dims the orb
            -- with its glow; white is vanilla.
            { Name = "BoonDrop" .. loot, InheritFrom = "BoonDropGold",
              ChildAnimation = "BoonDropA-" .. loot,
              Color = colorOf({ Red = 1.0, Green = 1.0, Blue = 1.0 }) },
            { Name = "BoonDropA-" .. loot, InheritFrom = "BoonDropA",
              ChildAnimation = "BoonDropB-" .. loot,
              CreateAnimations = subAnimations(), Color = colorOf(dropA) },
            { Name = "BoonDropB-" .. loot, InheritFrom = "BoonDropB",
              ChildAnimation = "BoonDropC-" .. loot,
              CreateAnimations = subAnimations(), Color = colorOf(dropB) },
            { Name = "BoonDropC-" .. loot, InheritFrom = "BoonDropC",
              ChildAnimation = "BoonDrop" .. loot .. "Icon",
              CreateAnimations = subAnimations(), Color = colorOf(dropC) },
            -- The god's picture. Vanilla spins fifty frames of a tilted medallion
            -- rocking a few degrees; one picture fakes it with an angle and ScaleX
            -- ping-pong. Loop = true with one frame is how vanilla's own door
            -- preview works. Color multiplies (:4905-4920).
            { Name = "BoonDrop" .. loot .. "Icon", InheritFrom = "BoonDropIcon",
              FilePath = emblem, EndFrame = 1, NumFrames = 1, StartFrame = 1,
              Loop = true, Scale = dropIconScale(god),
              Color = rawColorOf(emblemColor(god)),
              StartScaleX = 1.0, EndScaleX = 0.88, PingPongScale = true,
              StartAngle = -8, EndAngle = 8, PingPongAngle = true,
              Duration = 2.2 },
            -- The door picture, shaped like vanilla's own previews: no Loop
            -- override (the base loops), an explicit Scale, and the base's bob
            -- written out. ColorFromOwner/AngleFromOwner aren't in the order
            -- list, so they would be dropped if set.
            { Name = "BoonDrop" .. loot .. "Preview",
              InheritFrom = "BoonDropRoomRewardIconPreviewBase",
              FilePath = emblem, NumFrames = 1,
              Scale = CONFIG.doorPreviewScale(god),
              Color = rawColorOf(doorPreviewColor(god)),
              EndOffsetZ = 5 },
        }

        -- One flare entry for all gods, ahead of the first chain that names it.
        if not CONFIG.dropFlareRegistered then
            CONFIG.dropFlareRegistered = true
            table.insert(entries, 1, { Name = DROP_FLARE_NAME, InheritFrom = "BoonDropFrontFlare",
                                       Alpha = 0.1, StartAlpha = 0.1, EndAlpha = DROP_FLARE_PEAK })
        end

        local objects = {}
        for _, entry in ipairs(entries) do
            objects[#objects + 1] = sjson.to_object(entry, order)
        end
        logAlways(("%s door preview registered at scale %.2f (%s art)")
            :format(god.name, CONFIG.doorPreviewScale(god),
                    god.portraitOnly and "portrait" or "emblem"))

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

-- Traits whose tooltip reads session state only their own encounter sets up
-- (MergeTooltipDataFromSession) crash when offered anywhere else: Circe's
-- DoubleFamiliarTrait read a nil SessionMapState entry (UpgradeChoiceLogic.lua
-- :399, set up at EventLogic.lua:1150). They aren't offered. Filtered by the
-- field, not the name, so a future one is caught too.
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

-- Each god's own encounter checks every option's GameStateRequirements before
-- offering it (Circe withholds DoubleFamiliarTrait without a familiar out, and
-- so on); npc.Traits is the same pool with none of that attached. So the gates
-- are collected at registration and evaluated at offer time, when there's a
-- run to evaluate them against. None use ChanceToPlay, so the seed can't move.
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

    -- A requirement can call a game function; if it throws, withhold the option.
    local called, result = pcall(eligible, { Name = loot }, requirements)
    if not called then
        logWarn(("%s: eligibility check for %s errored (%s); withholding it")
            :format(loot, traitName, tostring(result)))
        return false
    end
    return result and true or false
end

-- Applied to the finished upgrade list, after vanilla's own filtering, so
-- lootData.Traits stays a live reference.
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
    CONFIG.offerGates[loot] = CONFIG.collectOfferGates(game, god)
    if type(game.LootData) ~= "table" then
        logWarn("LootData unavailable; " .. god.name .. " not registered")
        return
    end
    if game.LootData[loot] ~= nil then
        logAlways(god.name .. " already registered")
        return
    end

    -- If another plugin (Droppable Gods, GodsAPI) already registers this god,
    -- stand down: two entries with one name would mean different things. Picking
    -- that god still works through theirs. Matched on display name, which is
    -- what collides for the player.
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

    -- The tab's halo tint for this god, from the same color chain as the drop.
    god.haloColor = npc.LootColor or npc.LightingColor or npc.SubtitleColor

    if not registerGodArt(god, npc) then return end

    local ok, err = pcall(function()
        game.LootData[loot] = {
            InheritFrom = { "BaseLoot", "BaseSoundPackage" },
            Name = loot,
            GodLoot = true,
            -- Unset on purpose: this flag puts a god in shops.
            TreatAsGodLootByShops = nil,

            -- Their boons are rarity-only. This vanilla flag skips the stack-boost
            -- block (UpgradeChoiceLogic.lua:295), which a keepsake could push to level 4.
            IgnoreStackBoost = true,

            GameStateRequirements = firstRewardOnlyRequirement(game, loot),

            -- By reference where possible, so the pool follows the game's.
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
-- Three matched art sets, each registered as our own static, single-frame
-- entries: vanilla's symbol entries inherit a bobbing, looping base.
--
--   symbol    GUI\Screens\BoonSelectSymbols\<Name>  (Olympians have a painted halo)
--   portrait  KeepsakeMaxGift_big\<Name>
--   boondrop  the door-preview art, Items\Loot\Boon\<Name>IconSpin0015
--
-- boondrop ships. A name missing from a set falls through to the next.
local SYMBOL_NAMES = {
    "Aphrodite", "Apollo", "Ares", "Artemis", "Athena", "BoonBackingA",
    "BoonBackingB", "BoonBackingC", "Chaos", "Demeter", "Dionysus", "Hades",
    "Hammer", "Hephaestus", "Hera", "Hermes", "Hestia", "Pom", "Poseidon",
    "Zeus",
}

local SYMBOL_SET = {}
for _, symbol in ipairs(SYMBOL_NAMES) do SYMBOL_SET[symbol] = true end

-- Every portrait-only god must be here: for them it's the only picture there is.
local PORTRAIT_NAMES = {
    "Aphrodite", "Apollo", "Arachne", "Ares", "Artemis", "Athena", "Chaos",
    "Circe", "Demeter", "Dionysus", "Echo", "Hades", "Hephaestus", "Hera",
    "Hermes", "Hestia", "Icarus", "Medea", "Narcissus", "Poseidon", "Selene",
    "Zeus",
}

-- Hades's portrait is the joint Hades-and-Persephone file.
local PORTRAIT_FILE_OVERRIDE = { Hades = "HadesPersephone" }
local PORTRAIT_SET = {}
for _, name in ipairs(PORTRAIT_NAMES) do PORTRAIT_SET[name] = true end
-- _big, because small art drawn at tab size looks jagged.
local PORTRAIT_PATH = "GUI\\Screens\\AwardMenu\\KeepsakeMaxGift\\KeepsakeMaxGift_big\\"

local BOONDROP_SPIN = {
    "Aphrodite", "Apollo", "Ares", "Chaos", "Demeter", "Hephaestus",
    "Hera", "Hermes", "Hestia", "Poseidon", "Selene", "Zeus",
}
local BOONDROP_SET = {}
for _, name in ipairs(BOONDROP_SPIN) do BOONDROP_SET[name] = true end

-- The hammer's preview is declared at Scale 0.55 (:1144-1148), so that's baked in.
local BOONDROP_EXTRA = {
    { name = "Hammer", file = "Items\\Loot\\WeaponUpgrade_Preview", factor = 0.55 },
    -- Standard's flat pomegranate, from the game's unglowing UI art.
    { name = "PomFlat", file = "GUI\\Icons\\Pom", factor = 1.0 },
}

for _, e in ipairs(BOONDROP_EXTRA) do BOONDROP_SET[e.name] = true end

-- Per-icon corrections, set by eye in game until the grid read as one set;
-- each art family has its own native size, so no formula produces these.
-- Anything not listed is 1.0. Portrait gods are governed by PortraitIconBoost.
CONFIG.tuneSizeDefaults = {
    Aphrodite = 1.6, Apollo = 1.95, Arachne = 0.97, Ares = 2.1,
    Artemis = 1.1, Chaos = 2.0, Circe = 1.1, Demeter = 2.2,
    Echo = 1.17, Hades = 1.15, Hammer = 1.6, Hephaestus = 1.85,
    Hera = 1.9, Hermes = 2.1, Hestia = 1.92, PomFlat = 2.4,
    Poseidon = 2.3, Selene = 0.87, Zeus = 2.05,
}

-- Hermes' wing and Selene's moon are thin and pale; the light's center is
-- hollowed behind them so it doesn't wash them out.
CONFIG.tuneCoreDefaults = { Hermes = 0.1, Selene = 0.1 }

-- A perceived-brightness correction for the light: additive light is only as
-- bright as its channels, so deep red reads dim and lime green reads strong.
CONFIG.tuneLightDefaults = {
    Hades = 1.6, Artemis = 0.7,
    Arachne = 1.15, Chaos = 1.25, Circe = 1.15, Dionysus = 0.9, Icarus = 1.15,
    PomFlat = 0.95,
}


local CUSTOM_ICON_PREFIX = "SelectFirstBoon_Symbol_"
local customIconsRegistered = false

local PORTRAIT_ICON_PREFIX = "SelectFirstBoon_Portrait_"
local BOONDROP_ICON_PREFIX = "SelectFirstBoon_BoonDrop_"
local SELENE_ICON_PREFIX = "SelectFirstBoon_Selene_"

-- Selene has no BoonSelectSymbols emblem, so she draws her door-preview art.
-- The selection light's texture is vanilla's own halo sprite, particle_glow.
local SELENE_GLOW_ANIM = "SelectFirstBoon_SeleneGlow"

-- The two switches' art: the Vow of Hubris for Override Special and the pause
-- icon for the master switch. The pause source is 72px against Hubris's 150
-- (measured with deppth2), so factor evens them out.
CONFIG.toggleArt = {
    { symbol = "AlwaysFirst", file = [[GUI\Screens\ShrineIcons\VowHubris]], factor = 1.0 },
    { symbol = "PluginOff",   file = [[GUI\Icons\Pause]],                    factor = 150 / 72 },
}

local SELENE_GLOW_FILE = "Particles\\particle_glow"
local SELENE_GLOW_ANIM_NAME = SELENE_GLOW_ANIM .. "_particle"

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
    return TUNING.IconStyle == "portrait"
end

local function usingBoonDrops()
    return TUNING.IconStyle == "boondrop"
end

-- The art name for a god: from LootData.Icon ("BoonSymbol<Name>") or
-- SpeakerName, each also tried without a namespace prefix (GodsAPI builds Icon
-- as "BoonSymbol<guid>-<Name>"). The first that names art we have wins.
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

    local extra = {}
    for _, name in ipairs(candidates) do
        local tail = string.match(name, "^.*%-(.+)$")
        if tail ~= nil then extra[#extra + 1] = tail end
    end
    for _, name in ipairs(extra) do candidates[#candidates + 1] = name end

    for _, name in ipairs(candidates) do
        if haveArtFor(name) then return name end
    end
    -- No match: the caller can still try the god's own BoonInfoIcon.
    return candidates[1]
end

local BUTTON_OBSTACLE = "SelectFirstBoon_Button"

-- Hitbox sizes, as a fraction of one grid cell, each registered as its own
-- obstacle: geometry is baked into GUI.sjson at load and can't scale later.
CONFIG.boxSteps = { 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 1.0, 1.15, 1.3, 1.6, 2.0, 2.5, 3.0 }

function CONFIG.boxObstacleName(step)
    return "SelectFirstBoon_Button_" .. tostring(math.floor(step * 100 + 0.5))
end

-- Which rung a button uses. At 1.0 the boxes tile the grid, which controller
-- navigation needs (it resolves against obstacle bounds). Only rungs actually
-- registered this session can be chosen.
CONFIG.boxRegistered = {}

function CONFIG.boxNameFor(isPortrait)
    -- Portraits render large at a low scale, so they get their own rung.
    local key = isPortrait and "HitboxScalePortrait" or "HitboxScale"
    local want = tonumber(TUNING[key]) or 1.0
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

local FALLBACK_OBSTACLE = "ButtonInventoryItem"
local buttonObstacleName = FALLBACK_OBSTACLE
local obstacleSizeNote = "not registered"

-- One grid cell (ResourceData.lua:3968-3972) minus a hairline: no overlap into
-- the neighbours, which misrouted clicks, and no gaps, which strand a
-- controller. Points wind the way vanilla's do.
local function buttonBoxSize(game)
    local override = {
        tonumber(TUNING.TabButtonBoxWidth) or 0,
        tonumber(TUNING.TabButtonBoxHeight) or 0,
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
    local scale = tonumber(TUNING.TabIconScale) or 0
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

        -- Specials whose art lives outside BoonSelectSymbols.
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

        -- The switches have one art in every style.
        for _, art in ipairs(CONFIG.toggleArt) do
            newEntries[#newEntries + 1] = sjson.to_object({
                Name = customIconName(art.symbol),
                FilePath = art.file,
                EndFrame = 1,
                NumFrames = 1,
                StartFrame = 1,
                Material = "Unlit",
                Scale = scale * (art.factor or 1.0),
            }, order)
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

        -- The light's texture. Scale 1: the component sizes itself at draw time.
        newEntries[#newEntries + 1] = sjson.to_object({
            Name = SELENE_GLOW_ANIM_NAME,
            FilePath = SELENE_GLOW_FILE,
            EndFrame = 1,
            NumFrames = 1,
            StartFrame = 1,
            Material = "Unlit",
            Scale = 1,
        }, order)

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
-- Laid out like the vanilla resource grid: InventoryScreenInGrid background
-- (which draws the slot frames), a Highlight per button, an explicit Scale,
-- MouseOver/MouseOff, and rows filled to the screen's GridWidth. Vanilla's
-- ButtonInventoryItem hitbox is 340x360 against a 133.6x143 grid, so every
-- point sat in several boxes and clicks resolved to neighbours; the buttons use
-- our own one-cell obstacle instead, falling back to ButtonInventoryItem if it
-- can't be registered. DESIGN.md, "The button hitbox".
local BUTTON_KEY_PREFIX = "SelectFirstBoonBtn_"
local BUTTON_LIST_FIELD = "SelectFirstBoonButtons"
local SELECTED_ALPHA = 1.0

local function unselectedAlpha()
    local value = tonumber(TUNING.UnselectedBrightness)
    if value == nil or value < 0 or value > 1 then return 0.7 end
    return value
end

local INFO_KEYS = { "InfoBoxName", "InfoBoxDescription", "InfoBoxDetails", "InfoBoxFlavor" }

-- Size is set at draw time with SkipGeometryUpdate, so art can grow while the
-- hitbox stays one cell. The pick rests larger than the rest, and hover
-- multiplies from its resting size.
local function restScaleFor(baseScale, lit)
    if not lit then return baseScale end
    local grow = tonumber(TUNING.SelectedIconScale) or 1.0
    if grow <= 0 then grow = 1.0 end
    return baseScale * grow
end

-- Per-icon corrections, keyed by the icon's own name recovered from its
-- animation name. On CONFIG because the main chunk is at Lua's 200-local limit.
CONFIG.tune = {
    prefixes = {
        BOONDROP_ICON_PREFIX, PORTRAIT_ICON_PREFIX,
        CUSTOM_ICON_PREFIX, SELENE_ICON_PREFIX,
    },
}

function CONFIG.tune.baseName(resolvedIcon)
    if type(resolvedIcon) ~= "string" then return nil end
    -- Her entry is named after its file, not her.
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
    local value = tonumber(CONFIG.tuneCoreDefaults[base])
    if value == nil or value < 0 then return 1.0 end
    return value
end

function CONFIG.tune.lightFor(resolvedIcon)
    local base = CONFIG.tune.baseName(resolvedIcon)
    if base == nil then return 1.0 end
    local value = tonumber(CONFIG.tuneLightDefaults[base])
    if value == nil or value < 0 then return 1.0 end
    return value
end

function CONFIG.tune.sizeFor(resolvedIcon)
    local base = CONFIG.tune.baseName(resolvedIcon)
    if base == nil then return 1.0 end
    local value = tonumber(CONFIG.tuneSizeDefaults[base])
    if value == nil or value <= 0 then return 1.0 end
    return value
end

-- drawsPortrait comes from the caller: whether this slot draws a portrait
-- depends on the style, not only on the god.
local function iconScaleFor(option, drawsPortrait)
    local size = tonumber(TUNING.IconSize) or 1.0
    if size <= 0 then size = 1.0 end

    local special = option ~= nil and option.special or nil
    local per = CONFIG.tune.sizeFor(option ~= nil and option.icon or nil)

    if special ~= nil and special.file ~= nil and not usingPortraits() then
        local boost = tonumber(TUNING.SeleneIconBoost) or 0
        if boost > 0 then return size * boost * per end
    end

    -- A portrait among non-portraits needs the portrait correction.
    local extra = option ~= nil and option.value ~= nil
        and EXTRA_GOD_BY_LOOT[option.value] or nil
    if (drawsPortrait and not usingPortraits()) or (extra ~= nil and extra.portraitOnly) then
        local boost = tonumber(TUNING.PortraitIconBoost) or 0.7
        if boost > 0 then return size * boost * per end
    end
    return size * per
end


-- Rows fill to the screen's GridWidth and wrap, as the resource grid does
-- (ResourceLogic.lua:614-620).
local FALLBACK_ROW_WIDTH = 8

local function rowWidthFor(screen)
    local width = screen ~= nil and tonumber(screen.GridWidth) or nil
    if width == nil or width < 1 then return FALLBACK_ROW_WIDTH end
    return math.floor(width)
end

local ROW_STRIDE = 1

-- The gates share row 1 with Standard, leaving the other rows for boons.
local GATE_ROW = 0

-- The vanilla inventory grid is five rows.
CONFIG.lastGridRow = 4


-- No GamepadNavigation block on the category, so the screen's own (the one the
-- resource grid uses, ResourceData.lua:3999) applies.

-- The tab's layout, hovers and clicks, behind the one log switch.
local function verbose(message)
    if settings.values.LogDecisions then
        logAlways("[tab] " .. tostring(message))
    end
end

local SELENE_HALO_DEFAULT_SPREAD = 0.2

-- Additive alpha stops at 1.0; stacked layers go brighter, as vanilla's
-- BoonDropA/B/C do.
local SELENE_HALO_MAX_LAYERS = 4

-- Light colors said outright, for gods whose derived color was wrong for a
-- light (Circe's subtitle green, Hades's near-white, nothing at all for Chaos
-- and Selene). 0-255, blended toward white by SelectionHaloTintMix. Additive
-- light gets deep from the gap between channels, not from low values.
CONFIG.lightOverrides = {
    Circe   = { 205,  95,  20 },   -- deep orange; 230,140,50 read washed out
    Athena  = { 235, 195,  70 },   -- gold
    Hades   = { 200,  12,  16 },   -- deep red; green and blue as low as they go
    Chaos   = { 110,  60, 150 },   -- dark purple
    Selene  = { 150, 185, 220 },   -- blue-silver; 170,110,220 read purple
    Hermes  = { 245, 200,  90 },   -- gold
    Narcissus = { 235, 225, 110 }, -- yellow; his derived 165,255,101 was green
    Echo    = { 195, 175, 235 },   -- pale lavender
    -- Standard, by icon: the rose of the seeds, not the red of the rind.
    Pom     = { 255, 120, 125 },
    PomFlat = { 255, 120, 125 },
    -- The switches: jade for Hubris's sprout, cold steel for the pause.
    AlwaysFirst = {  60, 210, 130 },
    PluginOff   = { 155, 165, 180 },
}

-- Shared so a color looked up by icon blends exactly as one looked up by god.
function CONFIG.blendLight(source, mix)
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

-- For anything that has no god to ask about: Standard, and any icon we decide to
-- color on its own.
function CONFIG.iconLightColor(icon, mix)
    local base = CONFIG.tune.baseName(icon)
    if base == nil then return nil end
    return CONFIG.blendLight(CONFIG.lightOverrides[base], mix)
end

-- "SelectFirstBoon-CirceUpgrade" and "@Selene" and "HadesUpgrade" all name a god
-- this table might have an opinion about.
function CONFIG.lightOverrideFor(god)
    if type(god) ~= "string" then return nil end
    -- Plain string ops: LOOT_PREFIX's "-" is a lazy quantifier in a pattern.
    local name = god
    if name:sub(1, 1) == "@" then name = name:sub(2) end
    if name:sub(1, #LOOT_PREFIX) == LOOT_PREFIX then
        name = name:sub(#LOOT_PREFIX + 1)
    end
    if name:sub(-7) == "Upgrade" then name = name:sub(1, -8) end
    return CONFIG.lightOverrides[name]
end

function CONFIG.godLightColor(game, god, mix)
    if game == nil or god == nil then return nil end

    -- Said outright first, then an added god's own color chain, then LootData.
    local source = CONFIG.lightOverrideFor(god)

    local extra = source == nil and EXTRA_GOD_BY_LOOT[god] or nil
    source = source or (extra ~= nil and extra.haloColor or nil)

    if source == nil then
        local data = game.LootData and game.LootData[god] or nil
        source = data ~= nil
            and (data.LootColor or data.LightingColor or data.SubtitleColor) or nil
    end
    return CONFIG.blendLight(source, mix)
end

-- A near-white light, deliberately not a god color. This one means "picked",
-- and a tint borrowed from a god would read as part of that god's art instead.
CONFIG.selectionHaloColor = { 235, 235, 245, 255 }

-- The selection light: layered additive glow behind whatever is lit (the pick,
-- a lit gate, the hovered icon), tinted from that god's color.
local function makeIconHalo(game, screen, index, spec, iconScale)
    if not spec.lit then return nil end
    local isSelection = true
    local tint = CONFIG.selectionHaloColor
    if TUNING.SelectionHaloTint == "god" then
        local mix = tonumber(TUNING.SelectionHaloTintMix) or 0.5
        tint = CONFIG.godLightColor(game, spec.god, mix)
               or CONFIG.iconLightColor(spec.icon, mix)
               or CONFIG.selectionHaloColor
    end
    local strength = (tonumber(TUNING.SelectionHaloStrength) or 0)
        * CONFIG.tune.lightFor(spec.icon)
    verbose(("  light %-32s %s  strength %.2f"):format(
        tostring(spec.god),
        tint ~= nil and table.concat(tint, ",") or "(none)",
        strength or 0))
    local spread = tonumber(TUNING.SelectionHaloSize) or 0
    local layers = math.floor(tonumber(TUNING.SelectionHaloLayers) or 1)

    if strength <= 0 then
        verbose("icon halo skipped: strength is 0")
        return nil
    end
    if strength > 1 then strength = 1 end

    if spread <= 0 then spread = SELENE_HALO_DEFAULT_SPREAD end

    if layers < 1 then layers = 1 end
    if layers > SELENE_HALO_MAX_LAYERS then layers = SELENE_HALO_MAX_LAYERS end

    if type(game.CreateScreenComponent) ~= "function" then return nil end
    local animName = SELENE_GLOW_ANIM_NAME
    local x = spec.x
    local y = spec.glowY or spec.y

    -- Only the first layer is returned and tracked as button.SelectFirstBoonGlow;
    -- the rest are held in the same list so cleanup destroys all of them.
    local first = nil
    local extras = nil
    for layer = 1, layers do
        -- Each layer grows and fades outward, so the light is a ring around the
        -- art rather than a hot spot on it. It follows the lit multiplier (how
        -- much bigger this is drawn than at rest), not the absolute scale,
        -- which is a per-art correction.
        local followScale = 1.0
        if isSelection then
            local follow = tonumber(TUNING.SelectionHaloFollowsIcon)
            if follow == nil then follow = 1.0 end
            local litMul = tonumber(iconScale) or 1.0
            if litMul <= 0 then litMul = 1.0 end
            followScale = 1 + (litMul - 1) * follow
        end

        local layerScale, layerAlpha = spread * followScale, strength
        if isSelection then
            if layer > 1 then
                local step = tonumber(TUNING.SelectionHaloSpreadStep) or 0.35
                layerScale = spread * followScale * (1 + (layer - 1) * step)
                layerAlpha = strength / layer
            else
                -- The innermost layer sits behind the art; lowering it hollows the ring.
                local core = tonumber(TUNING.SelectionHaloCore)
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
        -- An unknown animation name leaves a blank component, so say so.
        local animOk, animErr = pcall(game.SetAnimation,
            { DestinationId = glow.Id, Name = animName })
        if not animOk then
            logWarn("light animation " .. animName .. " was rejected: " .. tostring(animErr))
        end
        if type(game.SetRGB) == "function" then
            local layerTint = tint
            -- Inner layers are mixed toward white, so where color turns to white
            -- is set here rather than wherever the additive blend clips.
            if isSelection and layers > 1 then
                local whiten = tonumber(TUNING.SelectionHaloWhiten) or 0
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
        first.SelectFirstBoonIsSelectionLight = isSelection
    end
    verbose(("icon halo drawn on %s: source=%s anim=%s strength=%.0f%% spread=%.2f layers=%d at (%.1f, %.1f)")
        :format(tostring(spec.icon), "particle", animName, strength * 100, spread,
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
        -- No flat art: a portrait beats a haloed symbol among flat icons.
        if PORTRAIT_SET[name] then return portraitIconName(name) end
    end
    if usingPortraits() and PORTRAIT_SET[name] then
        return portraitIconName(name)
    end
    if SYMBOL_SET[name] then
        return customIconName(name)
    end
    if PORTRAIT_SET[name] then return portraitIconName(name) end
    if BOONDROP_SET[name] then return boonDropIconName(name) end
    return nil
end

-- Whether a slot draws a portrait, from its RESOLVED icon name.
local function drawsPortraitIcon(resolvedIcon)
    return type(resolvedIcon) == "string"
        and resolvedIcon:sub(1, #PORTRAIT_ICON_PREFIX) == PORTRAIT_ICON_PREFIX
end

local function tabIconFor(game, god)
    local special = specialFor(god)
    if special ~= nil then
        if customIconsRegistered then
            if not usingPortraits() and not usingBoonDrops() then
                if special.symbol ~= nil and SYMBOL_SET[special.symbol] then
                    return customIconName(special.symbol)
                end
                if special.file ~= nil then
                    return seleneIconName()
                end
            end
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
    -- A portrait-only god has one picture in every style.
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

-- The tab-strip icon is vanilla's, created at CategoryIconScale 0.45
-- (ResourceLogic.lua:290, ResourceData.lua:3931). SetScale's Fraction is
-- absolute, so the base is the strip's own scale, with the same corrections the
-- grid applies on top.
local function scaleTabStripIcon(game, screen, god)
    local components = screen ~= nil and screen.Components or nil
    local icon = components ~= nil and components["CategoryIcon" .. TAB_CATEGORY_NAME] or nil
    if icon == nil or type(game.SetScale) ~= "function" then return end

    local base = tonumber(screen.CategoryIconScale)
    if base == nil or base <= 0 then base = tonumber(TUNING.TabIconScale) or 0.45 end
    if base <= 0 then base = 0.45 end

    local tabBoost = tonumber(TUNING.TabIconBoost) or 0
    if tabBoost <= 0 then tabBoost = 1.0 end

    -- Always set, so moving the pick off Selene takes her boost back off.
    local special = specialFor(god)
    local boost = 1.0
    if special ~= nil and special.file ~= nil and not usingPortraits() then
        boost = tonumber(TUNING.SeleneIconBoost) or 0
        if boost <= 0 then boost = 1.0 end
    end

    local resolved = tabIconFor(game, god)

    local extra = EXTRA_GOD_BY_LOOT[god]
    if (drawsPortraitIcon(resolved) and not usingPortraits())
        or (extra ~= nil and extra.portraitOnly) then
        local portrait = tonumber(TUNING.PortraitIconBoost) or 0
        if portrait > 0 then boost = boost * portrait end
    end

    local per = CONFIG.tune.sizeFor(resolved)

    local scale = base * tabBoost * boost * per
    game.SetScale({ Id = icon.Id, Fraction = scale, Duration = 0.0,
                    SkipGeometryUpdate = true })
    verbose(("tab strip icon scaled to %.2f (%.2f base x %.2f tab x %.2f god x %.2f per-icon)")
        :format(scale, base, tabBoost, boost, per))
end

local function refreshTabIcon(game)
    local ok, err = pcall(function()
        setTabIcon(game, tabIconFor(game, settings.values.God))
    end)
    if not ok then logWarn("could not update the tab icon: " .. tostring(err)) end
end

-- Standard, then the nine Olympians, then Hammer, Hermes, Selene and Chaos,
-- then the added gods (emblems before portraits). Standard shares row 1 with
-- the switches, with a blank row under them.
local function tabOptions(game)
    local options = { { value = NONE_VALUE, label = STANDARD_LABEL, icon = tabIconFor(game, NONE_VALUE) } }

    local added = {}
    for _, lootName in ipairs(catalog.names) do
        local option = {
            value = lootName,
            label = catalog.labels[lootName] or lootName,
            icon = tabIconFor(game, lootName),
        }
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

    table.sort(added, function(left, right)
        local leftGod = EXTRA_GOD_BY_LOOT[left.value]
        local rightGod = EXTRA_GOD_BY_LOOT[right.value]
        local leftPortrait = leftGod ~= nil and leftGod.portraitOnly == true
        local rightPortrait = rightGod ~= nil and rightGod.portraitOnly == true
        if leftPortrait ~= rightPortrait then return rightPortrait end
        return tostring(left.label) < tostring(right.label)
    end)

    for _, option in ipairs(added) do
        options[#options + 1] = option
    end

    if options[2] ~= nil then options[2].rowBreak = 1 end

    return options
end

-- =============================================================================
-- INFO PANEL
-- =============================================================================
-- The tab writes into the screen's own four info boxes, as every vanilla
-- category does (ResourceData.lua:4428-4500), with RawText since we have no
-- localization keys. Vanilla fades them before our OpenFunctionName runs
-- (ResourceLogic.lua:396-399), so what we write survives the switch.
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
        -- The delays still apply with no pick, so say so when one is on.
        if not CONFIG.pluginOff() then
            for _, key in pairs(GATED_REWARDS) do
                if settings.values[key] == true then
                    return "No first reward selected. Restrictions active."
                end
            end
        end
        return "No first reward selected."
    end
    local special = specialFor(god)
    if special ~= nil then return special.blurb end
    -- Says what the option does; whether it's the pick is the flavor box's job.
    return "Offer " .. godLabelFor(god) .. " as the run's first reward."
end

-- The two delay gates, as a table so the buttons, the panel lines and the
-- tooltips all read from one place and cannot drift apart.
local GATES = {
    { key = "BlockHermesBeforeBoon", reward = "HermesUpgrade", label = "Hermes Delay",
      who = "Hermes", option = "@Hermes" },
    { key = "BlockSeleneBeforeBoon", reward = "SpellDrop", label = "Selene Delay",
      who = "Selene", option = "@Selene" },
    -- The two switches aren't gods, so they carry their own art and sentences.
    { key = "AlwaysFirst", symbol = "AlwaysFirst", label = "Override Special",
      onDesc = "Special/story first boons overridden.",
      offDesc = "Special/story first boons happen as designed. Your pick offered next.",
      sentence = function(on)
          if on then
              -- With a keepsake equipped the line above says it goes first.
              if CONFIG.keepsakeGod(rom and rom.game) ~= nil then
                  return "Special/story first boons overridden"
              end
              return "Your pick goes " .. CONFIG.bold("first") .. ", special/story first boons overridden"
          end
          return "Your pick " .. CONFIG.bold("waits ") .. "for anything the game has scripted"
      end },
    { key = "DisableEverything", symbol = "PluginOff", label = "Pause Plugin",
      onDesc = "This plugin is paused and doing nothing.",
      offDesc = "This plugin is working normally.",
      sentence = function(on)
          if on then
              return "This mod is " .. CONFIG.bold("off ")
          end
          return "This mod is " .. CONFIG.bold("on ")
      end },
}

-- The game's own bold markup.
function CONFIG.bold(text)
    return "{#BoldFormat}" .. text .. "{#Prev}"
end

-- A delay only matters while the first boon is the game's own roll: any pick
-- queues a Boon, which Hermes and Selene never come out of. So with a pick set,
-- the delays read as not in force.
local function gateOverridden(gate)
    if gate.reward == nil then return false end
    local pick = settings.values.God
    return pick ~= nil and pick ~= NONE_VALUE
end

-- What happens, then why: "Hermes CANNOT be first boon". When the pick
-- overrides the delay, the god CAN be first and the line says so. "cannot", not
-- "can't", as the game's own UI text writes it.
local function gateState(gate)
    if gate.sentence ~= nil then return gate.sentence(settings.values[gate.key] == true) end
    local blocked = settings.values[gate.key] == true
    local overridden = gateOverridden(gate)
    -- The pick wins, so the god can be first however the delay is set.
    local can = overridden or not blocked
    local word = can and "can" or "cannot"
    -- A trailing space goes inside the bold span; the renderer eats one after it.
    local line = gate.who .. " " .. CONFIG.bold(word .. " ") .. "be first boon"
    if overridden then
        return line .. " (you picked " .. godLabelFor(settings.values.God) .. ")"
    end
    return line
end

-- The outcome of every rule together, said first. An equipped Olympian keepsake
-- forces the first boon itself, so it is part of the answer.
function CONFIG.firstBoonLine()
    local game = CONFIG.openGame
    local pick = settings.values.God
    local hasPick = pick ~= nil and pick ~= NONE_VALUE
    local pickName = hasPick and godLabelFor(pick) or nil

    if CONFIG.pluginOff() then
        return "First boon: " .. CONFIG.bold("No change")
    end

    local keepsake = CONFIG.keepsakeGod(game)
    if keepsake ~= nil then
        local keepsakeName = godLabelFor(keepsake)
        if settings.values.KeepsakeWins then
            return "First boon: " .. CONFIG.bold(keepsakeName .. " ") .. "from your keepsake"
        end
        -- The keepsake goes first whatever Override Special says, then the pick
        -- (two boons even when it's the same god).
        if hasPick then
            return "First boon: " .. CONFIG.bold(keepsakeName .. " ")
                .. "from your keepsake, then " .. CONFIG.bold(pickName)
        end
        return "First boon: " .. CONFIG.bold(keepsakeName .. " ") .. "from your keepsake"
    end

    if hasPick then
        return "First boon: " .. CONFIG.bold(pickName)
    end
    return "First boon: " .. CONFIG.bold("No change")
end

-- One line for whatever the delays are actually holding back ("First boon
-- cannot be: Hermes or Selene"), or none. On CONFIG: the 200-local limit.
function CONFIG.blockedLine()
    local names = {}
    for _, gate in ipairs(GATES) do
        if gate.who ~= nil and settings.values[gate.key] == true
                and not gateOverridden(gate) then
            names[#names + 1] = gate.who
        end
    end
    if #names == 0 then return nil end

    local parts = {}
    for i, who in ipairs(names) do
        if i == #names then
            parts[#parts + 1] = CONFIG.bold(who)
        elseif i == #names - 1 then
            parts[#parts + 1] = CONFIG.bold(who .. " ") .. "or "
        else
            parts[#parts + 1] = CONFIG.bold(who) .. ", "
        end
    end
    return "First boon cannot be: " .. table.concat(parts)
end

local function gateLines()
    local lines = { CONFIG.firstBoonLine() }
    -- With the plugin paused, only the answer and the pause line.
    if CONFIG.pluginOff() then
        for _, gate in ipairs(GATES) do
            if gate.key == "DisableEverything" then
                lines[#lines + 1] = gateState(gate)
                return lines
            end
        end
        return lines
    end
    local blocked = CONFIG.blockedLine()
    if blocked ~= nil then
        lines[#lines + 1] = blocked
    end
    for _, gate in ipairs(GATES) do
        -- The two switches earn a line only when on.
        if gate.sentence ~= nil and settings.values[gate.key] == true then
            lines[#lines + 1] = gateState(gate)
        end
    end
    return lines
end

-- The panel at rest, restored whenever the cursor leaves a button. Each box
-- keeps one meaning: Name (what's under the cursor), Description (what it
-- does), Details (the gate lines, always), Flavor (what pressing would do).
local function drawTabText(game, screen)
    if not writeInfo(game, screen, "InfoBoxName", { TAB_CATEGORY_NAME }) then
        verbose("info panel components unavailable; no text drawn")
        return
    end

    local keepsakeGod = equippedForcedGod(game)
    if keepsakeGod ~= nil then
        writeInfo(game, screen, "InfoBoxDescription",
            { "Set to:  " .. godLabelFor(settings.values.God) })
        writeInfo(game, screen, "InfoBoxDetails", gateLines())
        writeInfo(game, screen, "InfoBoxFlavor",
            { "Your " .. godLabelFor(keepsakeGod)
              .. " keepsake forces the first boon, your pick waits." })
        return
    end

    writeInfo(game, screen, "InfoBoxDescription", { "Set to:  " .. godLabelFor(settings.values.God) })
    writeInfo(game, screen, "InfoBoxDetails", gateLines())
    writeInfo(game, screen, "InfoBoxFlavor", { "Pick the run's first reward." })
end

-- A switch is lit when on and not overridden, and grows like a picked boon.
local function buttonIsLit(game, button)
    local gate = button.SelectFirstBoonGate
    -- Paused: only the pause switch is lit; every setting is kept underneath.
    if CONFIG.pluginOff() then
        return gate ~= nil and gate.key == "DisableEverything"
    end
    if gate ~= nil then
        return settings.values[gate.key] == true and not gateOverridden(gate)
    end
    -- The pick stays lit under a keepsake; the panel says it waits.
    return button.SelectFirstBoonGod == settings.values.God
end

-- Adds or removes one button's light (for the pick or the cursor).
function CONFIG.syncButtonGlow(game, screen, button, lit)
    local wantsGlow = lit or button.SelectFirstBoonHovered == true
    local hasGlow = button.SelectFirstBoonGlow ~= nil
        and button.SelectFirstBoonGlow.SelectFirstBoonIsSelectionLight == true
    if wantsGlow == hasGlow then return end

    local index = button.SelectFirstBoonSlot
    if hasGlow then
        game.Destroy({ Id = button.SelectFirstBoonGlow.Id })
        for _, extra in ipairs(button.SelectFirstBoonGlow.SelectFirstBoonGlowExtras or {}) do
            game.Destroy({ Id = extra.Id })
        end
        if screen ~= nil and screen.Components ~= nil and index ~= nil then
            screen.Components[BUTTON_KEY_PREFIX .. index .. "Glow"] = nil
            for layer = 2, SELENE_HALO_MAX_LAYERS do
                screen.Components[BUTTON_KEY_PREFIX .. index .. "Glow" .. layer] = nil
            end
        end
        button.SelectFirstBoonGlow = nil
    elseif index ~= nil then
        local iconScale = tonumber(button.SelectFirstBoonIconScale) or 1.0
        if iconScale == 0 then iconScale = 1.0 end
        local glow = makeIconHalo(game, screen, index, {
            icon = button.SelectFirstBoonIcon,
            god = button.SelectFirstBoonGodForLight,
            x = button.SelectFirstBoonX,
            y = button.SelectFirstBoonY,
            glowY = button.SelectFirstBoonGlowY or button.SelectFirstBoonY,
            lit = true,
            isGate = button.SelectFirstBoonGate ~= nil,
        }, (tonumber(button.SelectFirstBoonRestScale) or 1.0) / iconScale)
        if glow ~= nil then button.SelectFirstBoonGlow = glow end
    end
end

local function applySelection(game, screen)
    local buttons = screen[BUTTON_LIST_FIELD]
    if buttons == nil then return end
    for _, button in ipairs(buttons) do
        local lit = buttonIsLit(game, button)
        game.SetAlpha({
            Id = button.Id,
            Fraction = lit and SELECTED_ALPHA or unselectedAlpha(),
            Duration = 0.1,
        })
        local rest = restScaleFor(tonumber(button.SelectFirstBoonIconScale) or 1.0, lit)
        button.SelectFirstBoonRestScale = rest
        game.SetScale({ Id = button.Id, Fraction = rest, Duration = 0.1,
                        SkipGeometryUpdate = true })

        CONFIG.syncButtonGlow(game, screen, button, lit)
    end
end

-- Forward declaration: pressing a button re-describes it through onButtonOver.
local onButtonOver

local function pickGod(game, screen, button)
    -- A switch toggles its setting; anything else sets the pick.
    local gate = button.SelectFirstBoonGate
    if gate ~= nil then
        local nowOn = not settings.values[gate.key]
        saveSetting(gate.key, nowOn)
        logAlways(gate.label .. " turned " .. (nowOn and "on" or "off"))
        applySelection(game, screen)
        onButtonOver(game, button)
        return
    end

    local god = button.SelectFirstBoonGod
    if god == nil then
        verbose("click arrived on a button with no god attached; ignored")
        return
    end

    -- Picking anything clears the pause, or pausing would be a one-way door.
    if CONFIG.pluginOff() then
        saveSetting("DisableEverything", false)
        logAlways("master switch cleared: picking " .. godLabelFor(god)
            .. " means the plugin is wanted after all")
    end

    verbose(("click resolved to slot %s (%s) at X=%.1f Y=%.1f")
        :format(tostring(button.SelectFirstBoonSlot), god == NONE_VALUE and STANDARD_LABEL or god,
                button.SelectFirstBoonX or -1, button.SelectFirstBoonY or -1))

    saveSetting("God", god)
    logAlways("first reward set to " .. godLabelFor(god))

    applySelection(game, screen)
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

-- Hover, matched to MouseOverResourceItem (ResourcePresentation.lua:88): the
-- icon grows by IconMouseOverScale from its own resting size, with
-- SkipGeometryUpdate so the hitbox doesn't. No slot frame (PonyMenu's style).
function onButtonOver(game, button)
    local screen = button.Screen
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
        if gate.onDesc ~= nil or gate.offDesc ~= nil then
            writeInfo(game, screen, "InfoBoxDescription",
                { on and gate.onDesc or gate.offDesc })
        elseif on then
            writeInfo(game, screen, "InfoBoxDescription",
                { gate.who .. " will not appear until you have a boon." })
        else
            writeInfo(game, screen, "InfoBoxDescription",
                { gate.who .. " can appear in the first room." })
        end
        writeInfo(game, screen, "InfoBoxDetails", gateLines())
        if gateOverridden(gate) then
            writeInfo(game, screen, "InfoBoxFlavor",
                { (on and "Press to turn off." or "Press to turn on.")
                  .. " No effect while " .. godLabelFor(settings.values.God) .. " is your pick." })
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

    local keepsakeGod = equippedForcedGod(game)
    local base = (god == settings.values.God)
        and "Your current pick."
        or "Press to make this your pick."
    if keepsakeGod ~= nil then
        writeInfo(game, screen, "InfoBoxFlavor",
            { base .. " Your " .. godLabelFor(keepsakeGod)
              .. " keepsake forces the first boon this run." })
    else
        writeInfo(game, screen, "InfoBoxFlavor", { base })
    end

    -- Hover lights the button in its god's color.
    button.SelectFirstBoonHovered = true
    CONFIG.syncButtonGlow(game, screen, button, buttonIsLit(game, button))

    verbose("hover on slot " .. tostring(button.SelectFirstBoonSlot))
end

local function onButtonOff(game, button)
    -- Cleared before the sync, so the pick keeps its own light.
    if button.SelectFirstBoonHovered then
        button.SelectFirstBoonHovered = nil
        CONFIG.syncButtonGlow(game, button.Screen, button, buttonIsLit(game, button))
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
    -- Held so a setting change can rebuild the open tab.
    CONFIG.openScreen = screen
    CONFIG.openGame = game
    refreshCatalog(game)

    -- With a CloseFunctionName, cleanup is ours (ResourceLogic.lua:381).
    destroyTabButtons(game, screen)

    local options = tabOptions(game)
    local buttons = {}
    local pitchX = screen.GridSpacingX or 133.6
    local rowStride = (screen.GridSpacingY or 143) * ROW_STRIDE
    local x, y = screen.GridStartX, screen.GridStartY
    local column = 1
    local cursorX, cursorY = nil, nil

    local rowWidth = rowWidthFor(screen)
    -- Vanilla slots leave room for a quantity we don't show, so icons sit lower.
    local iconOffsetY = tonumber(TUNING.IconOffsetY) or 0

    verbose(("opening: %d options, %d per row (screen GridWidth), start=(%.1f, %.1f), pitchX=%.1f, rowStride=%.1f, offsetY=%.1f, style=%s, obstacle=%s")
        :format(#options, rowWidth, screen.GridStartX, screen.GridStartY,
                pitchX, rowStride, iconOffsetY, tostring(TUNING.IconStyle),
                buttonObstacleName))

    -- spec.y is the slot line; the icon is nudged down from it, the highlight isn't.
    local function makeButton(index, spec)
        local iconScale = spec.iconScale or 1.0
        local restLit = spec.lit == true
        local button = game.CreateScreenComponent({
            Name = (buttonObstacleName == BUTTON_OBSTACLE)
                and CONFIG.boxNameFor(drawsPortraitIcon(spec.icon))
                or buttonObstacleName,
            -- 1.0: a Scale here would shrink the bounds too. The size is set below.
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
        button.SelectFirstBoonRestScale = restScaleFor(iconScale, restLit)
        button.SelectFirstBoonSlot = index
        button.SelectFirstBoonX = spec.x
        button.SelectFirstBoonY = spec.y + iconOffsetY + (spec.extraOffsetY or 0)
        button.SelectFirstBoonIcon = spec.icon
        button.SelectFirstBoonGodForLight = spec.god
        button.SelectFirstBoonGlowY = spec.glowY
        button.OnPressedFunctionName = TAB_PICK_FN
        button.OnMouseOverFunctionName = TAB_OVER_FN
        button.OnMouseOffFunctionName = TAB_OFF_FN
        button.MouseOverSound = "/SFX/Menu Sounds/DialoguePanelOutMenu"
        game.SetAnimation({ DestinationId = button.Id, Name = spec.icon })

        -- SetRGB multiplies the texture, as vanilla grays an item (ResourceLogic.lua:561).
        local brightness = tonumber(TUNING.IconBrightness) or 1.0
        if brightness < 1.0 and type(game.SetRGB) == "function" then
            local level = math.floor(255 * math.max(brightness, 0))
            game.SetRGB({ Id = button.Id, Color = { level, level, level, 255 } })
        end

        screen.Components[BUTTON_KEY_PREFIX .. index] = button

        local highlight = game.CreateScreenComponent({
            Name = "BlankObstacle",
            Group = "Combat_Menu_Overlay_Additive",
            X = spec.x,
            Y = spec.y,
            Alpha = 0.0,
            AlphaTarget = 1.0,
            AlphaTargetDuration = 0.2,
        })
        screen.Components[BUTTON_KEY_PREFIX .. index .. "Highlight"] = highlight
        button.Highlight = highlight

        spec.glowY = spec.y + iconOffsetY + (spec.extraOffsetY or 0)
        local base = iconScale ~= 0 and iconScale or 1.0
        local glow = makeIconHalo(game, screen, index, spec,
                                  restScaleFor(iconScale, restLit) / base)
        if glow ~= nil then button.SelectFirstBoonGlow = glow end
        return button
    end

    -- Read once for the whole draw, so every button agrees with the panel.
    local keepsakeGod = equippedForcedGod(game)

    for index, option in ipairs(options) do
        local selected = not CONFIG.pluginOff()
            and (option.value == settings.values.God)
        -- The cursor starts on the pick, else the first button.
        if cursorX == nil or selected then
            cursorX, cursorY = x, y + iconOffsetY
        end

        local isPortrait = drawsPortraitIcon(option.icon)
        local iconScale = iconScaleFor(option, isPortrait)
        -- Portrait art sits differently in the slot, so it gets its own nudge.
        local extraOffset = 0
        local asExtra = option.value ~= nil and EXTRA_GOD_BY_LOOT[option.value] or nil
        if isPortrait or (asExtra ~= nil and asExtra.portraitOnly) then
            extraOffset = tonumber(TUNING.PortraitIconOffsetY) or 0
        end
        local button = makeButton(index, {
            x = x, y = y, icon = option.icon,
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

        -- A row break or gap belongs before the option asking for it.
        local nextOption = options[index + 1]
        if nextOption ~= nil and nextOption.rowBreak then
            -- rowBreak = n leaves n rows behind (true means 1).
            local rows = nextOption.rowBreak
            if rows == true then rows = 1 end
            rows = tonumber(rows) or 1
            if column > 1 then
                column = 1
                x = screen.GridStartX
                y = y + rowStride
                rows = rows - 1
            end
            if rows > 0 then y = y + (rows * rowStride) end
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

    -- The four switches, right of Standard on row 1.
    local gateRow = GATE_ROW
    -- The grid is five rows; warn if the boons run off the bottom.
    if lastIconRow > CONFIG.lastGridRow then
        logWarn(("the icons reached row %d and the grid ends at row %d; the last "
            .. "of them may overlap the edge or fall off it"):format(lastIconRow, CONFIG.lastGridRow))
    end
    local gateY = screen.GridStartY + (gateRow * rowStride)
    for gateIndex, gate in ipairs(GATES) do
        local index = #options + gateIndex
        local column = 1 + gateIndex
        local gx = screen.GridStartX + ((column - 1) * pitchX)
        local gateIsOn = settings.values[gate.key] == true and not gateOverridden(gate)
        if CONFIG.pluginOff() then
            gateIsOn = (gate.key == "DisableEverything")
        end
        -- A delay borrows its god's icon; the two switches have their own art.
        local gateIcon = gate.symbol ~= nil and customIconName(gate.symbol)
            or tabIconFor(game, gate.option)
        local button = makeButton(index, {
            x = gx, y = gateY,
            icon = gateIcon,
            lit = gateIsOn,
            iconScale = iconScaleFor({ special = gate.option ~= nil
                                           and specialFor(gate.option) or nil,
                                       icon = gateIcon }),
            -- A delay's light is its god's color.
            god = gate.option,
            isGate = true,
        })
        button.SelectFirstBoonGate = gate
        buttons[#buttons + 1] = button
        verbose(("  gate %s at (%.1f, %.1f) row %d = %s")
            :format(gate.label, gx, gateY, gateRow, gateState(gate)))
    end

    screen[BUTTON_LIST_FIELD] = buttons
    screen.NumItems = #buttons

    -- Where the controller cursor starts (ResourceLogic.lua:355, 590-597).
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
-- Opening the inventory honors CursorStartX/Y (set in tabOpen), but switching
-- tabs with a controller doesn't: for any category with an OpenFunctionName,
-- vanilla parks the cursor at PinStart (614, 267), the forget-me-not column,
-- which on this grid is between two buttons (ResourceLogic.lua:645-650,
-- 670-675). The tab-switch functions are wrapped to move it after vanilla runs.
-- Mouse tab clicks are left alone: TeleportCursor moves the real pointer.
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

-- Rebuild the open tab in place (sizes and lights are build-time facts).
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
    -- The info boxes are the screen's; hand them back empty.
    clearInfo(game, screen)
    screen.NumItems = 0
    pcall(game.InventoryScreenUpdateVisibility, screen)
end

local function installInventoryTab(game)
    -- One instance owns the tab and the hooks together. A ReLoad re-run is a
    -- second instance with its own settings; guarded like installHooks so the
    -- tab and hooks never split between two (DESIGN.md, "A re-run").
    if game[CONFIG.hooksField] then
        logAlways("inventory tab already installed by an earlier instance; keeping it "
            .. "(restart the game to pick up changed code)")
        return
    end

    -- On rom.game for CallFunctionName; guarded so an error can't reach the
    -- inventory screen's own render path.
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

    for _, category in ipairs(screenData.ItemCategories) do
        if category.Name == TAB_CATEGORY_NAME then
            logAlways("inventory tab already present")
            return
        end
    end

    table.insert(screenData.ItemCategories, {
        Name = TAB_CATEGORY_NAME,
        Icon = tabIconFor(game, settings.values.God),
        -- Grid, not Blank: it draws the slot frames, as the resource grid does.
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

-- One table rather than several locals: the 200-local limit.
local MORE_TOOLTIPS = {
    Keepsake =
        "ON  -- an equipped boon keepsake wins and this plugin does nothing at all " ..
        "for that run.\n" ..
        "OFF -- you get both, which means two guaranteed gods: the keepsake forces " ..
        "the first boon and your pick takes the next one.",
    NeverFirst =
        "ON  -- they cannot appear until you hold a boon or a hammer.\n" ..
        "OFF -- they can appear from the first room, as vanilla allows.\n\n" ..
        "Nothing to do with the pick above, except that picking one of them " ..
        "overrides its own gate.\n\n" ..
        "Covers what the speedrun pack's \"Disable Selene Before First Boon\" " ..
        "does -- turn that off if this is on.",
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
}

-- Availability markers for the dropdown.
--
-- Returns (set, suppressed); a nil set marks nothing. Never called outside a
-- run (ReachedMaxGods dereferences CurrentRun unchecked), and nothing is marked
-- past the max-gods cap, where GetEligibleLootNames collapses to gods already
-- met this run (RewardLogic.lua:189-193). "(unavailable)", not "(locked)":
-- the check is "can it be offered now".
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

        -- Specials aren't gods, so they get no eligibility marks.
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
        imgui.TextDisabled("Your " .. godLabelFor(keepsakeGod)
            .. " keepsake forces the first boon, your pick waits.")
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
    if hasBoonThisRun(currentRun) then
        imgui.TextDisabled("Gates released -- you hold a boon this run.")
    else
        imgui.TextDisabled("Gates active -- no boon held yet this run.")
    end
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
        -- Log before the switch takes effect, so turning it off is still logged.
        settings.values.LogDecisions = true
        logAlways(logDecisions and "decision logging enabled" or "decision logging disabled")
        saveSetting("LogDecisions", logDecisions)
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    -- One switch per added god, driven from EXTRA_GODS.
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

    -- ImGui needs End() for every Begin(), so it sits outside the guarded body.
    local began = false
    local openState = true

    local ok, err = pcall(function()
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

-- On the game table, which survives a plugin re-run; a local would not.
CONFIG.hooksField = "SelectFirstBoon_HooksInstalled"

local function installHooks(game)
    local ModUtil = game.ModUtil
    if ModUtil == nil or ModUtil.Path == nil or ModUtil.Path.Wrap == nil then
        logWarn("ModUtil.Path.Wrap unavailable; hooks not installed")
        return false
    end

    -- The loader re-runs every plugin when any one reloads, and ModUtil wraps
    -- stack, so a second pass would layer a second copy of every hook.
    if game[CONFIG.hooksField] then
        logAlways("hooks already installed; skipping (the loader re-ran this "
            .. "plugin, which happens when any mod reloads)")
        return false
    end
    game[CONFIG.hooksField] = true

    -- SetupRoomReward returns nothing (RewardLogic.lua:210-275).
    ModUtil.Path.Wrap("SetupRoomReward", function(base, currentRun, room, previouslyChosenRewards, args)
        local forceLootNameBeforeBase = room ~= nil and room.ForceLootName or nil

        base(currentRun, room, previouslyChosenRewards, args)

        -- Vanilla's reward is already valid here; a failure of ours leaves it.
        local applied, applyErr = pcall(
            applyForcedGod, game, currentRun, room, previouslyChosenRewards, args, forceLootNameBeforeBase
        )
        if not applied then
            logWarn("SetupRoomReward override failed, leaving vanilla reward in place: " .. tostring(applyErr))
        end
    end)

    -- Only ever turns eligible into ineligible.
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

    -- Before base: ChooseRoomReward consumes the priority list itself
    -- (RewardLogic.lua:163-171).
    ModUtil.Path.Wrap("ChooseRoomReward", function(base, run, room, rewardStoreName, previouslyChosenRewards, args)
        -- game.CurrentRun: RewardStoreAddPriority writes there (RewardLogic.lua:514, 518).
        local ok, err = pcall(addRewardPriority, game, game.CurrentRun, rewardStoreName)
        if not ok then
            logWarn("could not queue the first reward, leaving vanilla to roll: " .. tostring(err))
        end
        return base(run, room, rewardStoreName, previouslyChosenRewards, args)
    end)

    -- Every category display, so our strip icon is sized whichever tab opens first.
    ModUtil.Path.Wrap("InventoryScreenDisplayCategory", function(base, screen, categoryIndex, args)
        local result = base(screen, categoryIndex, args)
        local ok, err = pcall(scaleTabStripIcon, game, screen, settings.values.God)
        if not ok then
            verbose("could not size the tab strip icon on category display: " .. tostring(err))
        end
        return result
    end)

    -- The run's god cap counts GetInteractedGodsThisRun (RunLogic.lua:1819-1829).
    -- An added god is a one-off opening choice, not a patron, so it must not burn
    -- a slot; this also covers the encounter-loot picks (RewardLogic.lua:267-273).
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

    -- Our entries set GodLoot, which would make four trait-owner scans claim the
    -- added gods' traits (IsGodTrait and friends, TraitLogic.lua:1547-1599) and
    -- make those boons pommable everywhere, including from the NPCs in the
    -- world. Vanilla says no for them (FieldLootData, RunData.lua:556-570). So
    -- the entries are hidden for the duration of each scan: synchronous,
    -- read-only, and nothing can observe the gap.
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
                -- Restored first, error or not.
                for name, data in pairs(stash) do lootData[name] = data end
                if not ok then
                    logWarn(fnName .. " raised while our gods were hidden: " .. tostring(result))
                    error(result, 0)
                end
                return result
            end)
        else
            logWarn("no " .. fnName .. " to wrap; added gods' boons may become pommable")
        end
    end

    -- An added god is eligible only while it IS the pick. Otherwise vanilla's
    -- own first-boon roll (RewardLogic.lua:186-200) could land on one unasked,
    -- even on Standard.
    ModUtil.Path.Wrap("GetEligibleLootNames", function(base, excludeLootNames)
        local names = base(excludeLootNames)
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
        -- Never empty a pool the game had filled.
        if #filtered == 0 and #names > 0 then
            logWarn("filtering the added gods would have emptied the pool; left alone")
            return names
        end
        return filtered
    end)

    -- Where the offer list is built (UpgradeChoiceLogic.lua:899): the added gods'
    -- encounter gates are applied here, after vanilla's own filtering.
    ModUtil.Path.Wrap("GetEligibleUpgrades", function(base, upgradeOptions, lootData, upgradeChoiceData)
        local upgrades = base(upgradeOptions, lootData, upgradeChoiceData)
        local ok, result = pcall(CONFIG.filterOffers, game, lootData, upgrades)
        if not ok then
            logWarn("offer gating failed, leaving the vanilla list intact: " .. tostring(result))
            return upgrades
        end
        return result
    end)

    -- The portrait gods' own encounters filter their lists by requirements only,
    -- since in vanilla you can't already hold what they offer. Taken as a first
    -- boon, you can: so their list drops anything the hero holds (on a copy).
    local NPC_CHOICE_FUNCTIONS = {
        "ArachneCostumeChoice", "CirceBlessingChoice", "EchoChoice",
        "IcarusBenefitChoice", "MedeaCurseChoice", "NarcissusBenefitChoice",
    }
    local function heroHolds(name)
        if type(game.HeroHasTrait) == "function" then
            return game.HeroHasTrait(name) == true
        end
        local hero = game.CurrentRun and game.CurrentRun.Hero
        for _, trait in ipairs(hero and hero.Traits or {}) do
            if type(trait) == "table" and trait.Name == name then return true end
        end
        return false
    end
    for _, fnName in ipairs(NPC_CHOICE_FUNCTIONS) do
        if type(game[fnName]) == "function" then
            ModUtil.Path.Wrap(fnName, function(base, source, args, screen)
                local ok, filtered = pcall(function()
                    if type(args) ~= "table" or type(args.UpgradeOptions) ~= "table" then return nil end
                    local kept, dropped = {}, {}
                    for _, option in ipairs(args.UpgradeOptions) do
                        if type(option) == "table" and option.ItemName ~= nil and heroHolds(option.ItemName) then
                            dropped[#dropped + 1] = tostring(option.ItemName)
                        else
                            kept[#kept + 1] = option
                        end
                    end
                    if #dropped == 0 then return nil end
                    local copy = {}
                    for k, v in pairs(args) do copy[k] = v end
                    copy.UpgradeOptions = kept
                    log(fnName .. ": not offering " .. table.concat(dropped, ", ")
                        .. " again -- already held this run")
                    return copy
                end)
                if not ok then
                    logWarn(fnName .. " filter failed, offering the full list: " .. tostring(filtered))
                    filtered = nil
                end
                return base(source, filtered or args, screen)
            end)
        end
    end

    ModUtil.Path.Wrap("GiveLoot", function(base, args)
        -- Read before base spends the keepsake's charge (RoomLogic.lua:2062-2066).
        local armedFor = nil
        local okArmed, armed = pcall(keepsakeWouldClaim, game, game.CurrentRun, {})
        if okArmed then armedFor = armed end

        local loot = base(args)

        local marked, markErr = pcall(markSpawned, game, args, loot, armedFor)
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

-- An uncaught error in the main chunk would stop the module loading at all.
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

        -- Before buildCatalog, so the added gods are listed on the first open.
        registerExtraGods(game)

        buildCatalog(game)

        registerButtonObstacle(game)
        registerCustomIcons()

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
