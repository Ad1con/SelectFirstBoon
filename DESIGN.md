# SelectFirstBoon -- design notes

Development narrative: what the game does, what this mod mirrors, what it
deliberately does not, and why. Moved out of `src/main.lua`'s header, which had
grown to 164 lines before a line of code.

**Every `file:line` citation from that header is preserved below.** They point
into the game's own scripts under
`Content\Scripts\`, and they are the most valuable thing here -- each one is a
claim someone verified rather than assumed.

This file is in the repo and is NOT in `thunderstore.toml`'s copy list, so it
does not ship.

Two things in the original header were already wrong when it was moved, and are
corrected rather than preserved:

- It stamped the version as `v4.31.0`. Version lives in `src/manifest.json` and
  `thunderstore.toml`, which a test keeps in agreement; a third copy in a comment
  could only ever drift.
- It said the plugin lives in `plugins\Adamant\...`. It has not since the
  namespace became `Adicon-SelectFirstBoon`.

---

SelectFirstBoon (v4.31.0) -- logs the run seed and the offered traits at spawn,
to settle a report of identical boon options across re-rolled seeds.

Forces the first boon reward of a run to come from one chosen god.

This is NOT a boon spawner. The run plays normally: you still walk into the
boon room, still get three options, still at the normal time. The only thing
that changes is WHICH god that first boon reward belongs to.

Phase 1 hardcoded the god in a constant. Phase 2 keeps that logic byte-for-
byte and puts a dropdown in front of it. The decision function reads the
setting at the moment a reward is set up, so changing the dropdown mid-run
takes effect at the very next door unlock -- no restart, no new run.

The default is None: vanilla randomness, with Hermes and Selene held back
until you hold a boon. Pick a god -- or switch the gates off -- in the
ReturnOfModding menu bar under "SelectFirstBoon", or edit
Adicon-SelectFirstBoon.cfg in the config folder.

THE NEVER-FIRST GATES (v2.1.0)

Hermes and Selene are not boons. HermesUpgrade is GodLoot = false
(LootData_Hermes.lua:10) and Selene's reward is SpellDrop; both sit in
RewardStoreData.RunProgress as their own reward TYPES, siblings of "Boon".
So the god dropdown above can never affect them -- it only runs when
chosenRewardType == "Boon". Holding them back is a separate mechanism.

This replaces two things: the standalone NoHermesFirstBoon plugin, and
adamantSpeedrun-Gameplay_QoL's DisableSeleneBeforeBoon. Both of those work by
appending a requirement to game data -- the Selene module to the shared
NamedRequirementsData.SpellDropRequirements, the Hermes plugin to the
RunProgress HermesUpgrade entry's own GameStateRequirements.

This one wraps IsRoomRewardEligible (RewardLogic.lua:34) instead, and that is
a deliberate upgrade on both counts:

  * No shared data is mutated at all, so there is no blast radius to reason
    about. NamedRequirementsData.SpellDropRequirements has two consumers
    (LootData.lua:864 and :1685); HermesUpgradeRequirements has seventeen
    (RunProgress, HubRewards, and fifteen entries in BountyData.lua).
  * RewardLogic.lua:20 InitializeRewardStores deep-copies RewardStoreData into
    run.RewardStores at run start, so a data patch only affects runs started
    afterwards. A wrap is consulted live, so toggling these takes effect at
    the next door unlock like every other setting here.
  * A wrap filters at eligibility time rather than in one store's data, so it
    holds for every reward store, not just RunProgress.

IsRoomRewardEligible has exactly one caller, ChooseRoomReward at
RewardLogic.lua:142 -- verified by grep across all game scripts -- so the wrap
cannot reach anything else.

The gate releases once CurrentRun.LootTypeHistory holds any of the nine boon
gods or WeaponUpgrade, which is the list both replaced modules use.
LootTypeHistory is incremented in HandleLootPickup (InteractLogic.lua:717), so
it counts boons actually PICKED UP, not merely offered. That is what makes
"until you hold a boon" work rather than "until one is on a door".

Starvation was checked: no room restricts EligibleRewards to HermesUpgrade or
SpellDrop, so filtering them can never empty the eligible pool. Rooms that
force a reward outright (room.ForcedReward, roomData.ForcedRewards) bypass
IsRoomRewardEligible entirely and are unaffected -- the same blind spot the
two replaced modules have, since GameStateRequirements is skipped there too.

## THE VANILLA MECHANISM BEING MIRRORED

RewardLogic.lua:228-258, inside SetupRoomReward:

    if chosenRewardType == "Boon" and ( args.AlwaysSetupForceLootName or not room.ForceLootName ) then
        local excludeLootNames = {}
        if previouslyChosenRewards ~= nil then
            for i, data in pairs( previouslyChosenRewards ) do
                if data.RewardType == "Boon" then
                    table.insert( excludeLootNames, data.ForceLootName )
                end
            end
        end
        local lootData = ChooseLoot( excludeLootNames )
        if not args.IgnoreForceLootName then
            for k, trait in ipairs( CurrentRun.Hero.Traits ) do
                if trait ~= nil and trait.ForceBoonName ~= nil and trait.Uses > 0
                   and not Contains(excludeLootNames, trait.ForceBoonName) then
                    lootData = { Name = trait.ForceBoonName }
                    room.ForcedBoonNames[trait.ForceBoonName] = true
                    room.ForceBoonChosenTrait = trait
                    break
                end
            end
        end
        ...
        room.ForceLootName = lootData.Name
    end

Consumption is NOT here. It happens at spawn time, in RoomLogic.lua:2058-2069
inside GiveLoot, where a matching keepsake gets ReduceTraitUses. So a keepsake
keeps forcing until a boon of that god actually SPAWNS -- not until you pick it
up, and not merely because a door previewed it. This plugin copies that exact
consumption point.

## WHAT IS DELIBERATELY NOT REPRODUCED, AND WHY

room.ForceBoonChosenTrait -- vanilla sets it so the door preview can play the
  keepsake flash. Verified reader: RewardPresentation.lua:18-21, which threads
  ForceBoonChosenPresentation( room.ForceBoonChosenTrait ). That is the only
  read of the field anywhere in the 52 game scripts checked. We have no trait
  to flash, so it stays nil and no flash plays. Correct: there is no keepsake.

room.ForcedBoonNames[name] -- set anyway, purely to match vanilla state. It is
  initialised in RunLogic.lua:589 (RoomInit) and, in the scripts checked, is
  never read by anything.

The Devotion branch (RewardLogic.lua:259-274) also consults ForceBoonName
  traits. Not mirrored -- a Devotion encounter is not "the first boon".

Rooms with DeferReward or PersistentExitDoorRewards are skipped entirely.
  Vanilla evaluates its `not room.ForceLootName` guard AFTER CheckPreviousReward
  (RunLogic.lua:752) may have assigned that field, and a post-wrap cannot see
  that intermediate state. Rather than guess, the plugin stands down. Both flags
  mean "re-offer what was already promised", so this can only cost a force,
  never corrupt one.

PHASE 2 NOTES

Settings persist through ReturnOfModding's own config API -- the same
rom.config.config_file / bind / get / set / save primitives SGG_Modding-Chalk
is built on, used directly. v2.0.0 went through Chalk and failed to load:
chalk.auto calls envy.import to read a config.lua from the plugin folder, and
that import could not find the file even though it was sitting right there.
The plugin lives in a nested folder (plugins\Adamant\...) whose leaf name is
what ReturnOfModding uses as the plugin guid, so guid-based path resolution
and the real path disagree. Rather than pin down exactly where that resolution
goes wrong, the import step is gone: defaults are declared inline below and
there is no second file to find. If the config API is unavailable the plugin
still runs, using in-memory settings that reset when the game closes.

Logging goes exclusively through rom.log.info, with severity as text. This is
not stylistic: rom.log.error RAISES a Lua error rather than logging one. In
v2.0.0 the Chalk failure above was reported with rom.log.error inside the main
chunk, which turned a handled, recoverable condition into a module that failed
to load outright. The stack traceback read "[C]: in function 'error'".

The god list is built from the game's own LootData rather than hardcoded, so
a patch that adds an Olympian picks it up for free. LootData entries inherit
from a BaseLoot template that carries DebugOnly = true, and InheritFrom is
resolved engine-side -- not in any Lua script -- so whether DebugOnly reaches
the individual gods cannot be settled by reading the source. The catalog
builder therefore filters on DebugOnly, and if that filter empties the list it
retries without it, then falls back to a static list read out of the
LootData_*.lua files. Whichever path is taken is logged at startup.

All ImGui work is wrapped so that a UI failure cannot take the game down, and
Begin/End, BeginCombo/EndCombo and BeginMenu/EndMenu are paired to ImGui's
rules (End is unconditional after Begin; EndCombo and EndMenu only when their
Begin returned true).
