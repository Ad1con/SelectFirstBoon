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

## Before you change anything

Invariants that look arbitrary and are not. Each of these was arrived at the
expensive way, and each has been "improved" or nearly was.

- **`GATE_ROW = 4` is a constant, not computed.** An earlier version derived it
  from the last icon row and the override squares resolved past the bottom of the
  grid, off screen entirely.
- **The wrapper around `IsGodTrait`, `GetGodSourceName`, `GetLootSourceName` and
  `GetAllLootSourceNames`** hides this mod's LootData entries from those four
  scans. Without it the added gods' boons become pom-upgradeable, which changes
  the rest of the run and breaks the mod's core promise.
- **`IgnoreStackBoost = true`** on every added god's LootData. It is vanilla's own
  field, read in exactly one place, and it is what keeps these boons rarity-based.
- **The `[rng]` diagnostic in `markSpawned`** logs two lines per run,
  unconditionally. It has settled two bug reports that would otherwise have been
  guesswork. Do not put it behind a setting.
- **Loot keys are prefixed `SelectFirstBoon-`**, deliberately tied to the mod and
  not to the author's handle. These strings end up in player configs and save
  data, so churning them costs users a reset.
- **Config sections.** Settings bind to `1 - Main`, `2 - Extra gods` or
  `3 - Appearance`. Test 106 asserts Main stays around a dozen keys. If a
  cosmetic setting needs promoting, argue for it rather than editing the test.

## Style

- The comments carry the reasoning. When changing code, update the comment that
  explains it in the same edit.
- Tests encode things that were expensive to learn. If a change breaks one, read
  what it asserts before changing it.
- Lua has a 200-local ceiling per function and the main chunk is close to it.
  Adding several top-level locals will fail to parse. Fold related values into a
  table instead.

## Compatibility

This mod stands down rather than fighting. If another plugin has already decided
what a door gives, or already offers a god by the same display name, this one
declines and logs why. Preserve that instinct.

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

---

# Part 2 -- how it works, mechanism by mechanism

Was `TECHNICAL.md`. Merged here because both files answered the same question --
how this works and why it was built that way -- and two files answering it meant
two places to keep in step. Every `file:line` citation is preserved.

---

Two independent things:

1. **Pick what the run's first reward is** — one of the nine boon gods, a
   Daedalus Hammer, Hermes, Selene, or leave it random. The run is otherwise
   untouched: same room, same time, same three options, normal rarity rolls.
2. **Hold Hermes and Selene out of the reward pool until you hold a boon.**

Default is random-with-both-gates-on. This replaces the standalone
`Claude-NoHermesFirstBoon` plugin and the speedrun pack's *Disable Selene Before
First Boon* — turn those off if you enable these.

## Using it

Open the ReturnOfModding GUI, then **SelectFirstBoon** → **Settings** in the
menu bar. The GUI key is whatever `gui_toggle` is set to in
`ReturnOfModding\config\Hell2Modding-Hell2Modding-Hotkeys.cfg` — currently `N`.

The god list is a dropdown of display names — Zeus, Poseidon, Hera — not the
internal `...Upgrade` keys. Those only appear if you edit the `.cfg` by hand.

- **First boon god** — the nine Olympians whose loot is `GodLoot = true`, plus
  **None (vanilla)**. Gods the game would not currently offer are marked
  `(unavailable)` — see below, this does **not** mean locked.
- **Only force gods I have unlocked** — on by default. See below.
- **Hold back Hermes / Hold back Selene until I hold a boon** — on by default.
- **Log every decision** — one line per decision to the ReturnOfModding log.
- Status lines say whether the god force is armed or already spent this run, and
  whether the gates are still holding.

Changes apply **at the next door unlock**. No restart, no new run.

Settings live in `ReturnOfModding\config\Claude-SelectFirstBoon.cfg` and can be
edited there instead. The default is Zeus, matching what v1.0.0 hardcoded, so
upgrading changes nothing until you change it.

**The folder must be named `Claude-SelectFirstBoon`.** ReturnOfModding derives
the plugin guid from the leaf folder name and wants `Author-Mod` format; a folder
called just `SelectFirstBoon` logs `Bad folder name` and gets a guid that will
not match the config file this plugin writes.

## What it hooks

Two post-wraps, no data patches:

| Function | File | Why |
|---|---|---|
| `SetupRoomReward` | `RewardLogic.lua:210` | Vanilla picks a god and assigns `room.ForceLootName` at line 258; we replace that one value. |
| `GiveLoot` | `RoomLogic.lua:2058` | Marks the forced boon spent once it actually spawns — the same point vanilla calls `ReduceTraitUses` on a keepsake. |
| `IsRoomRewardEligible` | `RewardLogic.lua:34` | The never-first gates. Only ever narrows the base result. |

Plus three functions registered on `rom.game` for the tab itself — open, close and
button-press — since `CallFunctionName` resolves through `_G`.

## The native inventory tab

There's a **First Boon** tab in the in-game inventory screen with **ten clickable
buttons** — Random plus the nine gods. Click one and it takes effect immediately:
the setting saves, the selected button brightens, and the tab's own icon changes
**while you're looking at it**.

That last part is worth explaining. The tab's stored icon only reaches the screen
on the next open, because `OpenInventoryScreen` deep-copies `ScreenData`
(`ResourceLogic.lua:228`). But the click handler is passed the live `screen`, so
it also animates `screen.Components["CategoryIconFirst Boon"]` directly — the
data change is for next time, the animation is for right now.

The two never-first gates are still display-only here; they're toggles in the
ReturnOfModding window.

The game supports custom tabs outright — `InventoryScreenDisplayCategory`
(`ResourceLogic.lua:438`) calls `category.OpenFunctionName`, and its cleanup path
calls `prevCategory.CloseFunctionName`. Two shipped tabs already rely on it,
`InventoryScreen_PinTab` and `InventoryScreen_LineHistoryTab`. So the tab is one
`table.insert` into `ScreenData.InventoryScreen.ItemCategories` and two functions
on `rom.game`; nothing is overridden.

That's worth contrasting with PonyMenu, the obvious template, which does *not*
use this: it overrides `InventoryScreenDisplayCategory` wholesale — a copy of the
200-line vanilla function with four small edits — and draws its menu inside the
copy. That goes stale on any game patch and collides with anything else touching
the same function. Compatibility was checked in the direction that matters:
PonyMenu's copy preserves the `OpenFunctionName` branch, so this tab works with
or without PonyMenu installed.

Three mechanics worth recording:

- `CallFunctionName` resolves through `_G` (`EventLogic.lua:66`), so the handlers
  are assigned onto `rom.game` rather than left in the plugin's ENVY scope.
- `OpenInventoryScreen` does `DeepCopyTable( screenData )`
  (`ResourceLogic.lua:228`), so inserting the category once at load reaches every
  subsequent open.
- `table.insert` on `rom.game`'s proxied tables is safe *here*: a previous plugin
  hit `Optional has no value` errors reading proxied data with `pairs()` and `#`,
  so it isn't free of doubt generally — but PonyMenu performs this exact insert
  on this exact table.

**The tab icon shows the god you've chosen.** It uses a small set of custom
animation definitions registered through `sjson.hook` — the same mechanism
PonyMenu uses to add its `Box_FullScreen` graphic.

**No artwork is shipped.** The icons point at the game's own
`GUI\Screens\BoonSelectSymbols\<God>` files. Only the *wrapper* is ours.

Getting here took four wrong turns, all finally settled by reading
`Content/Game/Animations/GUI_Screens_VFX.sjson` rather than guessing at art:

| attempt | what it was | why it failed |
|---|---|---|
| `Icon-Log` | the dialogue tab's own icon | indistinguishable from that tab |
| `Keepsake_<God>` | god *portraits*, plus a pink ribbon for Random | not symbol art at all |
| `BoonInfoIcon` | `Items\Loot\Boon\<God>IconSpin\<God>IconSpin0015` | frames of the boon-on-the-ground spinner; per-god art, mismatched sizes |
| `Icon` → `BoonSymbol<God>` | matched `BoonSelectSymbols` art | inherits `BoonSymbolBase`, which has `Loop`, `Duration 2.5`, `PingPongShiftOverDuration`, `EndOffsetZ 5.0` — a big glowing icon that bobs |

The last one is the key: **the animation is on the base, not on the god entries.**
The matched art was always right; only its wrapper was wrong. So v2.3.0 defines
its own leaves — same art, `NumFrames = 1`, no animated base, at a scale we set.
That isn't invented: `BoonInfoSymbolBase` already uses exactly this recipe
(`FilePath GUI\Screens\BoonSelectSymbols\Zeus` with `NumFrames = 1`), it just
isn't exposed per god.

`TabIconScale` in the `.cfg` tunes the size and takes effect on restart, since
the hook runs at load. **Set it to `0`** to skip the hook entirely and fall back
to the game's own static icons. Every failure path — no SJSON, a throwing hook, a
god with no matching symbol — degrades to those same vanilla icons and logs why.

**None of this is covered by the harness.** Screen components, animations and
gamepad navigation are render-side. The tests cover installation, idempotency,
config gating, handler registration and failure containment; whether the tab
actually *draws* is only answerable in game. Step 1 deliberately writes into the
screen's existing `EmptyCategoryHint` component rather than creating its own, to
keep as little untested machinery as possible between "it works" and "it
doesn't".

If it ever breaks the inventory screen, set `ShowInventoryTab = false` in
`Claude-SelectFirstBoon.cfg` and relaunch — the category is inserted at load, so
that setting needs a restart.

## What `(unavailable)` means, and what it doesn't

It means the game's own `GetEligibleLootNames` would not return that god right
now. That is a narrower claim than "you haven't unlocked it", and v2.1.0 got this
wrong by labelling it `(locked)`.

Two things can make an unlocked god read as unavailable:

- **The max-gods cap.** Once `ReachedMaxGods` is true,
  `GetEligibleLootNames` stops listing available gods and starts listing only
  gods already met *this run* (`RewardLogic.lua:189-193`). Every other god then
  looks unavailable, however unlocked it is. Past the cap the dropdown therefore
  shows **no** marks at all and says so, because no mark would be honest.
- **Per-run clauses.** Some gods carry conditions on `CurrentRun`, not just
  `GameState` — Hephaestus requires `CurrentRun.TextLinesRecord HasNone
  ZeusFirstPickUp`, for instance.

Availability is re-checked at each run's first boon, so a mark you see mid-run
says nothing about your next run.

## The never-first gates

Hermes and Selene **are not boons**. `HermesUpgrade` is `GodLoot = false`
(`LootData_Hermes.lua:10`) and Selene's reward is `SpellDrop`; both sit in
`RewardStoreData.RunProgress` as their own reward *types*, siblings of `"Boon"`.
The god dropdown can never touch them — it only runs when
`chosenRewardType == "Boon"`. Holding them back is a separate mechanism.

Both replaced modules do it by appending a requirement to game data. This one
wraps `IsRoomRewardEligible` instead, which is better on three counts:

- **No shared data is mutated**, so there is no blast radius to reason about.
  `NamedRequirementsData.SpellDropRequirements` has two consumers;
  `HermesUpgradeRequirements` has seventeen (`RunProgress`, `HubRewards`, and
  fifteen entries in `BountyData.lua`).
- **It applies live.** `InitializeRewardStores` (`RewardLogic.lua:20`)
  deep-copies `RewardStoreData` at run start, so a data patch only affects runs
  begun afterwards. A wrap is consulted on every roll, so toggling a gate takes
  effect at the next door unlock like everything else here.
- **It covers every reward store**, not just `RunProgress`.

`IsRoomRewardEligible` has exactly one caller — `ChooseRoomReward` at
`RewardLogic.lua:142`, verified by grep across all game scripts — so the wrap
cannot reach anything else. It only ever turns eligible into ineligible.

The gate releases once `CurrentRun.LootTypeHistory` holds any of the nine boon
gods or `WeaponUpgrade`, the same list both replaced modules use.
`LootTypeHistory` is incremented in `HandleLootPickup`
(`InteractLogic.lua:717`), so it counts boons **picked up**, not merely offered.
That is what makes "until you hold a boon" mean what it says. A Selene spell does
not release it; a Daedalus hammer does.

Two limits, stated plainly:

- **Rooms that force a reward outright are unaffected.** `room.ForcedReward` and
  `roomData.ForcedRewards` are resolved before any eligibility filtering
  (`RewardLogic.lua:66-135`). Both replaced modules have the same blind spot,
  since `GameStateRequirements` is skipped there too.
- **This defers Hermes and Selene, it does not reduce them.** The reward store is
  a depleting bag: only the *chosen* reward is removed
  (`RemoveIndexAndCollapse`, `RewardLogic.lua:178`), while ineligible ones stay
  in place for later draws.

## The vanilla behavior it mirrors

An equipped keepsake forces the next boon through `RewardLogic.lua:241-248`:
any trait with `ForceBoonName` and `Uses > 0` wins, unless that god is already
in `excludeLootNames`. This plugin runs the same tests against the same state
and applies the same result — it just doesn't require a keepsake.

Consequences, all inherited rather than invented:

- **A door offering the god is not enough.** Consumption happens when the boon
  *spawns*, not when a door previews it and not when you pick it up. Walk past
  the forced door and the next unlock forces again.
- **Two doors never both show the god.** `previouslyChosenRewards` carries the
  first door's choice into the second door's `excludeLootNames`.
- **A shop purchase does not consume it.** Vanilla excludes
  `args.BoughtFromShop`; so do we.
- **An equipped keepsake outranks the plugin.** If you have one on, it wins.

## Deliberate departures from vanilla, and why

- **`room.ForceBoonChosenTrait` is left nil.** Vanilla sets it so
  `RewardPresentation.lua:18-21` can thread `ForceBoonChosenPresentation` — the
  keepsake flash on the door. That is the only read of the field in the 52 game
  scripts checked. No keepsake, no flash.
- **"Only force gods I have unlocked" (default on).** Checks the chosen god
  against the game's own `GetEligibleLootNames`. Vanilla keepsakes skip this
  check, but you can only equip a keepsake for a god you have already met and
  this plugin has no such gate. Turn it off for exact parity.
- **Rooms with `DeferReward` or `PersistentExitDoorRewards` are skipped
  entirely.** Vanilla evaluates its `not room.ForceLootName` guard *after*
  `CheckPreviousReward` (`RunLogic.lua:752`) may have assigned that field, and a
  post-wrap cannot observe that intermediate state. Rather than guess, the
  plugin stands down. Both flags mean "re-offer what was already promised", so
  this can only cost a force, never corrupt one.

## Three things worth knowing about the implementation

**The god list is not hardcoded.** It is built from the game's own `LootData` at
startup, so a patch that adds an Olympian is picked up for free. There is a
wrinkle: `LootData` entries inherit from a `BaseLoot` template carrying
`DebugOnly = true`, and `InheritFrom` is resolved engine-side — it appears in no
Lua script — so whether `DebugOnly` reaches the individual gods **cannot be
settled by reading the source**. The builder therefore filters on `DebugOnly`,
retries without the filter if that empties the list, and falls back to a static
nine-name list read out of `LootData_*.lua` if `LootData` is unreadable
altogether. Which path was taken is logged at startup.

**Settings use ReturnOfModding's config API directly, not Chalk.** v2.0.0
depended on `chalk.auto("config.lua")`, and it failed to load: `chalk.auto` calls
`envy.import` to read a `config.lua` out of the plugin folder, and that import
could not find the file even though it was sitting right there. The plugin lives
in a nested folder (`plugins\Adamant\...`) whose *leaf* name is what
ReturnOfModding uses as the guid, so guid-based path resolution and the real path
disagree. Rather than chase exactly where that goes wrong, the import step is
gone: v2.0.1 binds its keys straight onto `rom.config.config_file` — the same
`bind` / `get` / `set` / `save` primitives Chalk is built on — with defaults
declared inline. One fewer dependency and no second file to find.

**`rom.log.error` is never called.** In this ReturnOfModding build it *raises* a
Lua error rather than logging one; the v2.0.0 traceback read
`[C]: in function 'error'`. Using it to report the handled, recoverable Chalk
failure above is what actually turned that failure into a module that refused to
load. All logging goes through `rom.log.info` with severity carried in the text.
The two calls in the main chunk are additionally wrapped in `pcall`, since an
uncaught error there costs the whole plugin.

## The button hitbox

Every version up to 2.5.0 used `ButtonInventoryItem`, declared in
`Content/Game/Obstacles/GUI.sjson` as **340 wide by 360 tall**, and asymmetric
about its origin (`Y` from −140 to +220), so the box's center sits 40 units off
the icon it draws. Against a grid pitch of 133.6 × 143, every point on the panel
lies inside two to six boxes at once:

```
row 1 button at y=252  ->  hitbox 112 .. 472
row 2 button at y=395  ->  hitbox 255 .. 615
```

A click on a row-2 icon at y=395 is inside **both**, and row 1 wins — which is
exactly what it felt like in game.

v2.4.1 and v2.5.0 both tried to fix the controller by changing `FreeFormSelect*`
settings. **That was the wrong layer** — free-form selection resolves against
obstacle *bounds*, so no navigation tuning helps while the bounds overlap.

v2.6.0 registered its own obstacle, `SelectFirstBoon_Button`, through the same
`sjson.hook` path already used for the icons (PonyMenu performs this exact insert
into `data.Obstacles`, so the mechanism is proven and only the payload is new).
That fixed clicks. It also introduced the opposite problem: at 120 × 124 in a
133.6 × 143 grid the boxes no longer touched, and a controller step can land in
the gap between them. Vanilla's boxes overlap, so vanilla never has a gap.

v2.8.0 stops guessing the number and derives it: one grid cell minus a 2-unit
hairline, read from `ScreenData.InventoryScreen.GridSpacingX/Y`
(`ResourceData.lua:3968-3972`) at load time. **132 × 141.** No overlap into the
neighbouring cell, and no gap wide enough for the 16-unit free-form step to fall
through. `TabButtonBoxWidth` / `TabButtonBoxHeight` override it if ever needed;
`0` (the default) means derive. If the spacing can't be read, or SJSON is
missing, it falls back to the vanilla button — degraded hit-testing, but working.

## Hammer, Hermes and Selene: a different mechanism

The nine gods are reached through `room.ForceLootName`, which is what a keepsake
sets. Hammer, Hermes and Selene cannot be: they are not boons at all. Each is its
own **reward type** in the reward store — `WeaponUpgrade`, `HermesUpgrade`,
`SpellDrop` (`LootData.lua`, `RunProgress`) — and `ForceLootName` only chooses
*which god* once the store has already decided the reward is a `Boon`.

The right lever turned out to be the *other half* of what a keepsake does. Every
god keepsake carries two fields, not one (`TraitData_Keepsake.lua:2593-2604`):

```lua
ForceBoonName       = "HephaestusUpgrade"    -- WHICH god, once a Boon is chosen
AcquireFunctionName = "RewardStoreAddPriority"
AcquireFunctionArgs = { Name = "Boon" }      -- that the first reward IS a Boon
```

`RewardStoreAddPriority` (`RewardLogic.lua:513-533`) pushes a reward **name** onto
`CurrentRun.RewardPriorities` and tops the store up if that name isn't currently
in the carousel. `ChooseRoomReward` then walks the priority list
(`RewardLogic.lua:163-171`), takes the first entry eligible *at that moment*, and
`RemoveValueAndCollapse`s it — so a priority is one-shot and self-consuming,
which is exactly the shape this needs.

So:

| Pick | Priority pushed | How the god is then chosen |
|---|---|---|
| a god | `"Boon"` | `room.ForceLootName`, as before |
| Daedalus Hammer | `"WeaponUpgrade"` | n/a |
| Hermes | `"HermesUpgrade"` | n/a |
| Selene | `"SpellDrop"` | n/a |

**Every version before 3.0.0 was missing the `"Boon"` half for gods.** It forced
*which* god whenever a boon came up, but did nothing to make the first reward a
boon in the first place — so a first room offering a hammer or Hermes would push
your pick to the second room. `PriorityFirstReward` (default **on**) closes that
gap and makes a god pick behave exactly like an equipped keepsake. Turn it off
for the old behavior: your pick applies whenever a boon next happens.

The plugin calls the game's own `RewardStoreAddPriority` rather than
reimplementing it, and passes the store `ChooseRoomReward` is actually reading
rather than vanilla's `"RunProgress"` default, so the top-up lands in the right
carousel. It is pushed once per run, guarded by a flag on `CurrentRun` — the same
table `RewardStoreAddPriority` mutates — because `ChooseRoomReward` runs once per
door and recurses on an empty store.

If a priority can't fire in room 1 because its `GameStateRequirements` aren't met
(`HammerLootRequirements`, `HermesUpgradeRequirements`, `SpellDropRequirements`),
it stays in the list and fires at the first room where they are. That's vanilla
priority behavior, not a workaround.

### The gates suppress themselves

Picking Hermes or Selene while its never-first gate is on would have the plugin
fight itself: queue the priority, then make the reward ineligible through its own
`IsRoomRewardEligible` wrap, so the priority never fires. Choosing one suppresses
*its own* gate for as long as it's chosen. The gate **setting** is left alone
rather than rewritten, so changing your pick restores it with no user action —
and the tab's info panel reads `OVERRIDDEN BY YOUR PICK` rather than `ON`, so
it's never silent.

### Icons

Hammer and Hermes are both in `GUI\Screens\BoonSelectSymbols`
(`GUI_Screens_VFX.sjson:8253-8368`) — the same matched set the nine gods already
use — so they cost nothing extra and match in size.

**Selene isn't in that set at all**; it has no moon symbol. Her icon comes from
her door-preview art, `Items\Loot\SpellDrop_Preview`, registered separately with
`NumFrames = 1` and `Material = "Unlit"` so it neither loops nor pulses.
Different art from a different folder means its native size is unknown, so
`SeleneIconScale` exists to correct it (`0` = use `TabIconScale`).

## Artemis, Athena, Dionysus and Hades: first-reward-only boon gods

Artemis already gives boons in vanilla: you meet her in the field and she offers
one of three from a trait list, exactly as an Olympian does. What she has no
version of is a boon **lying on the ground** for a door to promise, because
nothing in vanilla ever creates one.

All four are here on identical terms, each switchable on its own. They are these
four and no others because the entry requirement is two facts at once: the god
already gives a 1-of-3 boon choice in vanilla, **and** the base game already has
its emblem in `BoonSelectSymbols`. Narcissus, Arachne, Circe, Echo, Medea and
Icarus have the trait pool but no emblem, so they would need art that does not
exist.

Hades is registered as a **full boon god**. GodsAPI forces him to NPC-style
instead by clearing `GodLoot` (its `main.lua:352`) — that was their choice, not
the game's, and nothing here requires it.

That gap turned out to be a single missing table:

```
CreateLoot({ Name = X })  ->  builds the loot from LootData[X]
                          ->  HandleLootPickup       (InteractLogic.lua:693)
                          ->  OpenUpgradeChoiceMenu  (InteractLogic.lua:733)
```

There is no `LootData.ArtemisUpgrade` for `CreateLoot` to build from. So this
adds one, as `Claude-ArtemisUpgrade`. Everything of substance in it points at
things the base game already ships — her trait pool, her emblem, her menu title,
her portrait, her colors. It is wiring, not authoring.

### They do not burn a max-god slot

A run caps how many gods it will use. Past that cap the game stops offering new
gods and only offers more boons from the ones you already hold —
`GetEligibleLootNames` collapses to `CurrentRun.LootTypeHistory`
(`RewardLogic.lua:189-193`).

The count comes from `GetInteractedGodsThisRun` (`RunLogic.lua:1819-1829`), which
counts **any** `LootTypeHistory` entry whose `LootData` has `GodLoot`. So without
intervention, taking the Artemis first boon would spend one of those slots —
you'd get one fewer Olympian for the whole run, **and** never another Artemis
boon, since she is leashed to the first reward. Strictly worse than vanilla.

These four are a one-off opening choice, not a patron for the run, so they are
filtered out of that count. `GetInteractedGodsThisRun` is the single chokepoint:
the max-gods check reads it, and so do the two encounter-loot picks at
`RewardLogic.lua:267-273`, where an added god would be just as wrong.

### Three promises, each enforced by a specific line

**1. Never a shop item.** `TreatAsGodLootByShops` is left unset and no
`StoreData` entry is added — which is exactly where GodsAPI would have put her.

**2. Only ever the run's first reward.** A `GameStateRequirements` entry checks
`CurrentRun.LootTypeHistory` for `HasNone` of every god, every hammer, and
herself. `IsGameStateEligible` enforces it inside `GetEligibleLootNames`
(`RewardLogic.lua:187-200`), so the game's own eligibility pass does the work.
The moment any boon is taken she stops being eligible for the rest of the run.

**3. Meeting her in the world is untouched.** That path runs off
`EnemyData.NPC_Artemis_Field_01`, a different table this never writes to. She
appears where she always did and behaves as she always did — including still
offering boons after her drop was taken, since the two are separate objects.

### The drop is built entirely from vanilla layers

A boon on the ground is not one picture. It is a chain with exactly **one**
god-specific layer at the center (`Items_General_VFX.sjson:4905`):

| Layer | Inherits | Source |
|---|---|---|
| `BoonDrop<God>` | `BoonDropGold` | vanilla orb |
| `BoonDropA-<God>` | `BoonDropA` | vanilla glow, tinted |
| `BoonDropB-<God>` | `BoonDropB` | vanilla glow, tinted |
| `BoonDropC-<God>` | `BoonDropC` | vanilla glow, tinted |
| `BoonDrop<God>Icon` | `BoonDropIcon` | **the only god-specific art** |

Each of the three tinted layers also spawns `BoonDropBackGlow` and
`BoonDropFrontFlare` through `CreateAnimations`, exactly as vanilla does
(`Items_General_VFX.sjson:5854-5884`). Without them the orb has no bloom.

**Animation colors are not LootData colors.** `LootData` uses `{r, g, b, a}` at
0-255; animation layers use **named channels as 0-1 floats**:

```
Color = { Red = 1.0 Green = 0.59 Blue = 0.22 }     -- BoonDropA-Zeus, :5859
```

v4.0.0 shipped the 0-255 positional form here, which fails **silently** — the
drop simply renders untinted. The harness passed it. There are now assertions
pinning both the channel names and the 0-1 range, since this is exactly the class
of bug a mock cannot see.

The orb, both flares and all three glows are shared vanilla animations. So the
only thing Artemis was missing is the innermost image — and her emblem is
already in the game at `GUI\Screens\BoonSelectSymbols\Artemis`. Pointing the
icon layer at it gives a real glowing boon orb with her bow inside, not a flat
symbol lying on the floor. `BoonDropIcon` defaults to a 50-frame spin, so the
frame count is overridden to a single static frame.

**No shipped art, no packer, no dependency.**

## The added gods' boons stay rarity-only

Artemis, Athena, Dionysus and Hades give boons whose power is their **rarity**.
Vanilla never lets a pom level them, and the reason is precise: their data lives
in `FieldLootData` with `TreatAsGodLootByShops = true` and `GodLoot` **unset**
(`RunData.lua:556-570`), and `IsGodTrait`'s `FieldLootData` branch requires
`GodLoot` unless the caller passed `ForShop`. That "no" is the whole mechanism.

Our `LootData` entry sets `GodLoot = true`, because the reward pipeline needs it
to treat the drop as boon loot at all. Two consequences, both fixed in v4.11.0:

**Reported.** With the Hades-and-Persephone keepsake equipped, boons taken from
our drop came out at **level 4**. `UpgradeChoiceLogic.lua:295` gates the whole
stack-boost block — both `MaxBonusBoonRank` levels and the keepsake's
`FatedBoonLevelBonus` — on `not lootData.IgnoreStackBoost`, and `lootData` there
is a `DeepCopyTable` of our entry (`RoomLogic.lua:2247`). So the entry now sets
`IgnoreStackBoost = true`. That field is vanilla's own and is read in exactly one
place in the entire game script set.

**Found while fixing it, not reported.** `GodLoot = true` also flips four vanilla
"which god owns this trait?" scans to *yes* for these traits:

| Function | Where | What it feeds |
|---|---|---|
| `IsGodTrait` | `TraitLogic.lua:1547` | `GetAllUpgradeableGodTraits` (`:1673`) — the list a **Pom of Power** offers; `UpgradableGodTraitCountAtLeast` and `HasSuperchargeableBoon` — requirement checks some Arcana and shrines read |
| `GetGodSourceName` | `:1562` | boon grouping |
| `GetLootSourceName` | `:1576` | Boon Info screen, package loading |
| `GetAllLootSourceNames` | `:1599` | shared-god checks |

And it applies to boons taken from the **NPC in an ordinary room**, not just from
our drop — the trait names are the same objects. That is a change to the rest of
the run, which is the one thing this plugin promises not to do.

So all four are wrapped to make our shadow entries invisible for the duration of
the call, and they return the answer they would have returned with this plugin
absent. Hiding the entries rather than filtering the result is deliberate:
`IsGodTrait` returns a bare boolean, so there is nothing in a result to filter.
All four are synchronous, read-only scans — no waits, no callbacks — so nothing
can observe the gap, and the entries are restored before the error path too.

## The added gods' drop is scaled to match a vanilla one

`BoonDropIcon` is `Scale = 0.7` (`Items_General_VFX.sjson:4917`) around
`Items\Loot\Boon\<God>IconSpin`. Our emblem layer inherits that but points at
`GUI\Screens\BoonSelectSymbols\<God>` — bigger source art — so the orb came out
visibly larger than a vanilla boon beside it.

`DropIconScale` (default `0.4`) sets it explicitly. The right number is a
measurement that can't be taken from outside the game — the textures live inside
`.pkg` files — so it is a knob rather than a guess baked in. Takes effect on
restart, since it is written into the animation at load.

### The glow layers: two vanilla patterns, not one

An earlier version of this section claimed the innermost layer *always* contrasts
with the emblem. That was overstated — true of five gods, false of three:

| Shape | Gods | A → B → C |
|---|---|---|
| **Contrasting** | Zeus, Hera, Hestia, Apollo, Poseidon | e.g. Zeus orange → orange → **green** |
| **One family, dark outward** | Aphrodite, Hephaestus, Ares | e.g. Hephaestus `0.30` gray → tan → **red** |

The second shape is the useful one here. Hephaestus and Ares start **dark** on the
outer layer — around `0.30` on every channel — and put the saturated hero color
innermost. That is far less total light than three bright layers, and it puts the
god's own color where the emblem sits.

Athena took three attempts, each failing differently:

1. Three near-identical golds — a flat wash, emblem unreadable.
2. Gold → **pale gold** → blue. The pale gold sat on the *additive* B layer, and
   adding near-white light is how you get a white blob.
3. Gold → deep gold → **blue core**. Read cold and blue overall, against a
   reference showing her drop as gold-dominant.

She now follows Hephaestus's structure in gold: `0.30/0.26/0.10` → `0.88/0.66/0.22`
→ `1.0/0.68/0.05`. Dionysus keeps the contrasting shape — nothing has been
reported about his, and churning an untested drop only loses the thread on which
change did what. Artemis and Hades are byte-for-byte unchanged; both were checked
in game and approved.

Two related cleanups. The A and B colors used to be **swapped** on the way into
the animation — a leftover of Droppable Gods' table shape — which made this block
impossible to read against the vanilla entries it copies; they now go straight
through as `dropA`/`dropB`/`dropC`. And `DropGlowBrightness` (default `1.0`)
scales every layer's channels together, so a drop can be taken down without
disturbing the hue relationships that keep the emblem legible. `Opacity` is left
alone by that dial — it is an alpha, and scaling it would fade the layer out
rather than dim it.

### The B layer is the additive one

`BoonDropB` sets `AddColor = true` (`Items_General_VFX.sjson:5002`); `A` and `C`
inherit `BoonDropA`, which does not. So **B's color is added to the scene** while
A and C multiply. Every vanilla B is a *saturated* color — never near-white:

| God | B layer | spread (max−min) |
|---|---|---|
| Zeus | 1.0 / 0.60 / 0.31 | 0.69 |
| Hera | 0.32 / 0.96 / 0.28 | 0.68 |
| Hestia | 1.0 / 0.14 / 0.44 | 0.86 |
| Apollo | 1.0 / 1.0 / 0.30 | 0.70 |
| Poseidon | 0.29 / 1.0 / 0.52 | 0.71 |

v4.12.0 gave Athena a "pale gold" B of `1.0 / 0.90 / 0.42` — adding near-white
light, which is how you get a white blob. Both added-god B layers are now
saturated, and a test pins the spread so a future color tweak can't quietly
re-introduce it.

### Two dials, because there are two hypotheses

The emblem art is the other suspect. `BoonSelectSymbols` textures carry a
**painted halo** — the menu proves it: the nine Olympians glow and Hammer and
Hermes, from that same folder, do not. Vanilla's drop emblems come from
`<God>IconSpin`, which has no painted halo. So this puts a bloom-painted picture
inside a glowing orb.

`BoonDropIcon` sets no `AddColor`, so a `Color` on the emblem entry **multiplies**
— it dims the emblem and its painted halo together without touching the orb.

**Per god, not one shared dial.** How much painted glow the art carries varies by
texture: Athena's is a bright gold Olympian emblem and washes out inside the orb,
while Artemis's and Hades's were checked in game at full and look right. One
value cannot be correct for four different pictures — dimming to rescue Athena
would spoil two drops that are already fine. So there is an
`EmblemBrightness<God>` per added god, and **only Athena starts below full**
(`0.7`), so a fresh install looks right without anyone opening settings.

### Three dials, three different things

| Setting | Changes | Not to be confused with |
|---|---|---|
| `DropIconScale` | how *large* the emblem is drawn | pure geometry, no brightness |
| `EmblemBrightness<God>` | how *bright the emblem picture* is | multiplies that sprite only |
| `DropGlowBrightness` | how bright the *three tinted layers* around it are | scales their channels only |

`GlowBrightness<God>` is **per god too**, for the same reason the emblem dial is,
and goes **above 1.0 as well as below**. Whether channels past
`1.0` actually brighten or simply clamp cannot be read out of the data files, so
the range is offered rather than guessed at — and the plugin imposes no ceiling of
its own, which would hide the answer behind our own clamp.

Two menu bugs shipped alongside it in v4.14.0 and are fixed in v4.15.1. Athena's
emblem default was `0.7` while `0.7` was not in the preset list — the combo showed
`70%` but picking anything else meant never getting back without hand-editing the
cfg. `drawPresetCombo` now folds the value in force into its own list, so a
setting can never again become a one-way door. And every value at or above `1.0`
was labelled "Full", so the whole upper half of the glow list read identically;
"Full" is now `1.0` and nothing else.

It is still a **weak lever, worth saying plainly**: much of an orb's light comes
from `BoonDropFrontFlare` (`:4523`, alpha to 1.0 at Scale 2.5) and
`BoonDropBackGlow` (`:5087`), which are *shared base-game animations* attached to
all three layers. Nothing here can change those without redefining them for every
god in the game, which is not a trade this plugin will make.

Athena's and Dionysus's specific hues are a judgement call following the vanilla
pattern, not a measurement.

## Portrait-in-orb: confirmed, and what it unlocked

Six more NPC gods give a 1-of-3 boon choice and could in principle be added:
Narcissus, Arachne, Circe, Echo, Medea, Icarus. **None has an emblem.**
`GUI\Screens\BoonSelectSymbols\` contains exactly the nine droppable Olympians,
Artemis, Athena, Dionysus, Hades, Chaos, Hermes, Hammer and Pom — that is the
whole folder, checked against every `FilePath` in the animation files.

What the six do have:

| Art | What it is | Usable as an emblem? |
|---|---|---|
| `KeepsakeMaxGift_small\<Name>` | keepsake portrait | maybe — that's the experiment |
| `BoonIcons\<Name>_NN` | **one icon per boon** (Narcissus has 9, one per trait; `TraitData_Arachne.lua:6` sets `Icon = "Boon_Arachne_01"`) | no — picking one would be using a single boon's art for the whole god, the same trap as `BoonIcons\Selene_100` for Selene |

**It renders.** Confirmed in game on Artemis, which settles the question the
toggle existed to ask and is what makes a god with no emblem possible at all.
(Had it come back blank, the next move would have been packages: `CreateLoot`
calls `LoadPackages` with the loot's own list, and ours already inherits the
NPC's. That fallback was not needed.)

Two things were wrong with the first look, each with its own cause:

| Symptom | Cause | Answer |
|---|---|---|
| jagged | `KeepsakeMaxGift_small` is small art drawn larger | `portrait` now means the `_big` variant; `portrait-small` keeps the old one |
| face takes the boon's color | **not** the emblem — `BoonDropIcon` sets `ColorFromOwner = "Ignore"` (`:4907`). It is `BoonDropFrontFlare` drawing *over* it on `GroupName "FX_Add_Top"` (`:4525`) | nothing can stop that layer painting over the picture, but the balance moves: that god's glow **down**, or its emblem brightness **up** — which is why emblem brightness now goes above `1.0` |

Scale is per **art family**, not per god: `DropIconScale` for emblems,
`DropPortraitScale` for portraits. An emblem and a portrait are different source
sizes, while every god using the same family wants the same number — ten gods
with one dial each would be ten dials answering two questions.

## What can be the run's first reward

Twelve things: the nine Olympian boons, a Daedalus Hammer, Hermes, and Selene.
A Pom of Power, a Nectar or Path of Stars never opens a run.

Recorded because it is **not derivable from the data files**, and an hour went
into trying. `RoomDataF.lua:379` gives the opening room
`ForcedRewardStore = "RunProgress"` and `IneligibleRewards =
RewardSets.OpeningRoomBans`, but those bans only exclude Devotion, RoomMoneyDrop,
MaxHealthDrop and MaxManaDrop -- Pom, Nectar and TalentDrop are *not* banned, so
the data suggests they could appear. Every `RunProgress` table findable by grep
belongs to a Bounty, not to a normal run.

So the twelve is established by play, not by reading. If it ever looks wrong,
that is the reason -- and the thing to trust is the run in front of you.

## Narcissus, and who else could follow

Six characters were suggested as candidates. Reading the data files showed the
real question is not "do they have art" but **is their trait pool a boon pool**:

| Character | Traits | Verdict |
|---|---|---|
| Narcissus | `NarcissusA`…`NarcissusI`, each with `RarityLevels` | boon-shaped — **added** |
| Arachne | `AgilityCostume`, `ManaCostume`… | **added** — see below |
| Circe, Echo, Icarus, Medea | found by the candidate log — see below | **added** |

**Arachne was wrongly excluded in v4.17.0**, on the grounds that costumes are not
boons. That was reading the trait *names* and stopping. `AgilityCostume` carries
full `RarityLevels` — Common through Heroic multipliers — and a
`WeaponSpeedMultiplier` (`TraitData_Arachne.lua:3-30`). It is a rarity-scaled
stat trait offered one-of-three; the costume rides along with it. That is a boon.
Worth knowing rather than discovering: taking one **does** change Melinoe's model
for the run, which is how her boons work in the base game, not something added
here.

Both ship **off by default** — not because either is risky, but because "on by
default" is a claim about art nobody has looked at yet. The other four each
earned their default by being checked in game first.

Neither has a hand-picked palette. Their three layers are **derived from the
game's own color for that character** in the Hephaestus shape (dark outer, mid,
saturated core), normalised so the brightest channel is `1.0`. The chain is
`LootColor` → `LightingColor` → `SubtitleColor`: several of these characters have
no `LootColor` at all, having never had a boon on the ground, but every one has a
voice color. Hand-picked literals still win wherever they exist, so the four
approved drops are untouched by the formula.

`LogGodCandidates` (on by default) writes one line per character who has both a
keepsake portrait and a trait pool, naming the first few traits, read from the
**live** `EnemyData` rather than whichever files happened to be to hand. It turned
"who else could be added" from a guess into a log line, and this is what it
returned:

```
candidate: NPC_Circe_01     -- 9 traits (CirceShrinkTrait, CirceEnlargeTrait, ArcanaRarityTrait, ...)
candidate: NPC_Echo_01      -- 8 traits (EchoLastReward, EchoLastRunBoon, EchoDeathDefianceRefill, ...)
candidate: NPC_Icarus_01    -- 8 traits (FocusAttackDamageTrait, FocusSpecialDamageTrait, OmegaExplodeBoon, ...)
candidate: NPC_Medea_01     -- 8 traits (HealingOnDeathCurse, MoneyOnDeathCurse, ManaOverTimeCurse, ...)
```

All four are in, each carrying a note about what its pool actually is. Medea
shipped in v4.24.0, came out in v4.25.0 after a crash, and went back in at v4.27.0
once the stack dump was actually read — the section after next tells that story.

| God | Pool | Worth knowing |
|---|---|---|
| Circe | run modifiers — `ArcanaRarityTrait`, `RemoveShrineTrait`, shrink/enlarge | she closes vows and opens Arcana |
| Echo | `EchoLastReward`, `EchoLastRunBoon` | hers *repeat* things, which makes her an interesting **first** pick — last run's boon, first thing this run |
| Icarus | `FocusAttackDamageTrait`, `OmegaExplodeBoon` | the most conventionally boon-like of the four |
| Medea | `…Curse` throughout | **curses laid on the enemy** — they drop healing, spawn with less armour, their projectiles slow. Favourable to the player, despite the naming |

Ten added gods now, and **all six portrait-only ones ship off by default**. That is
no longer "nobody has looked at their drops" — every one has now been taken in a
real run (see *In-game trial of every added god*). It is that a first-boon god is a
deliberate choice, and six extra faces appearing unasked is not.

**Hades is excluded.** The portrait set has no plain Hades — only
`HadesPersephone`, the joint keepsake, which is a picture of two other people. He
gets no combo at all, and asking for it in the cfg falls back to his emblem and
logs why.

## The halo was never Selene's alone

The portrait icons stood out beside the god symbols in three ways: too small,
hard-edged, no glow. Every one of those is Selene's problem, arriving for the
same reason — **the god symbols carry a glow painted into the texture, and art
from any other set does not.** So the halo built for her generalises:

| Symptom | Cause | Fix |
|---|---|---|
| no glow | portrait art has none painted in | the same additive `particle_glow` halo, tinted per god from the game's own color for that character (`LootColor` → `LightingColor` → `SubtitleColor`) |
| jagged | `KeepsakeMaxGift_small` drawn at tab size | the menu icons read the **`_big`** source, as the drop emblem already does |
| too small (at `_small`), then too big (at `_big`) | different source family from the symbols beside them | `PortraitIconBoost`, which applies in the **grid and the tab strip alike** |

`PortraitIconBoost` reaches the **tab strip** as well as the grid, and it is
deliberately the same number in both. The ratio between the two art families is a
property of the textures, identical wherever they are drawn; only the base scale
differs. A second dial would be a second place to tune the same fact — and until
it reached the strip, the portraits there were too big with no way to move them
without moving every god's.

The size correction runs **downward**, which is where the first attempt went
wrong. `PortraitIconBoost` reused Selene's preset list — but hers corrects art
that draws too *small*, so every value in it is `1.0` or more. Switching the
portraits to the `_big` source solved "too small" and created "too big", and the
only offered values were the wrong half of the range. It has its own list now,
`0.3` to `1.5`, defaulting to `0.7`.

A god that *does* have an emblem gets no halo — painting one under it would double
a glow the texture already has. The halo settings keep their `Selene…` names to
avoid resetting values that have already been tuned, but they now cover any icon
that needs one.

## Every added god has a switch

`Enable<God>` was config-file-only from the day the first one was added. Nobody
noticed while all four shipped **on** — there was no reason to go looking for a
switch. The moment two shipped **off**, the only way to turn them on was to
hand-edit the cfg.

The settings window now draws an "Offer &lt;God&gt;" checkbox per god, iterated from
`EXTRA_GODS`, so the next god added gets one without anyone remembering this list
exists. A test asserts one switch per god — no more, no fewer.

## Two blocks, split by a row break

One long run of icons was fine at thirteen options and stopped being fine at
twenty-two. The Olympians, the odd rewards and the added gods are three different
*kinds* of thing, and reading them as one list means checking every icon to find
the one you want — a row that ends with two Olympians and begins with a hammer is
worse than no grouping at all.

| Block | Contents |
|---|---|
| Standard, the nine Olympians, then Hammer, Hermes, Selene, Chaos | one run — everything vanilla can already give you |
| everything this plugin adds | starts a **new row** — **emblem gods first, then portrait gods**, alphabetical within each, with the portraits taking a row of their own |

The added gods split by art family because the two halves *look* different — a
god's emblem beside a character's face — so interleaving them by name reads as a
mistake even when it is not.

Three earlier attempts at the grouping, and what each got wrong:

| Attempt | Problem |
|---|---|
| a **row** per block | three rows for twelve icons; pushed the grid down until the override squares fell off the bottom and were not on screen at all |
| a **blank slot** before each block | a single empty cell mid-row reads as a *missing icon*, not a boundary — the opposite of its purpose |
| blank slot **plus** a row break for the portraits | the surviving blank slot still read wrong, and the two kinds of separator did not mean the same thing |

So the separators are all row breaks now, and there is only one conceptual
division left: **what the game can already do, and what this plugin adds.** The
Hammer, Hermes, Selene and Chaos belong on the first side of that line — they are
rewards you can already be offered, just not first.

With all ten added gods on:

```
row 0   Standard  Aphrodite  Apollo    Ares     Demeter  Hephaestus  Hera     Hestia
row 1   Poseidon  Zeus       @Hammer   @Hermes  @Selene  @Chaos      ·        ·
row 2   Artemis   Athena     Dionysus  Hades    ·        ·           ·        ·
row 3   Arachne   Circe      Echo      Icarus   Medea    Narcissus   ·        ·
row 4   ·         ·          ·         ·        ·        ·           [gate]   [gate]
```

It costs nothing in rows over any of the earlier schemes.

Note what it does for the **override squares**: they end up in an L-shaped pocket
of six empty cells, with nothing directly above either of them and the nearest
icon only diagonally adjacent. That matters because they are a different kind of
control and a new user should not read them as two more gods. Row 4 is the bottom
row of the grid, so a fully blank row above them is not available — with an
eight-wide grid, twenty-four icons, two block separators and the portrait break,
the rows are spoken for. The pocket does the same job.

Headroom before that stops being true: row 3 holds six of eight. Two more portrait
gods would fill it, and anything beyond that starts creeping toward the squares.
If icons ever reach row 4 the plugin logs a warning rather than overlapping them in
silence.

That was the deeper bug: the gate row had been made **computed** ("one clear row
below the last icon"), which is right in spirit and wrong in practice, because
there is no row below the last one to move to. The squares are back on the fixed
bottom row, in the last two columns. If the icons ever reach that row the plugin
**warns** rather than silently overlapping — the fix then is fewer gods or a wider
grid, not a row that does not exist.

Two per-god corrections came out of the same pass. `HaloStrength<God>` is a
**multiplier** on the shared halo strength, because one strength does not suit
every picture — a pale portrait needs less glow than a dark one to read the same,
and Narcissus's is the palest of the six (he ships at `0.7`). The shared dial
still governs; this only says "less than the others". And `PortraitIconOffsetY`
nudges portrait art down in its slot on top of the nudge every icon gets, since
it is a different shape from a god symbol and does not sit at the same height.

## Chaos, and what Standard becomes

Chaos is a **special**, alongside Hammer, Hermes and Selene — not an added god.
The difference is that nothing had to be invented for him. `TrialUpgrade` is
already a complete `LootData` entry (`LootData_Chaos.lua`): emblem, door icon,
drop animations, sounds. It is `GodLoot = false`, so it never enters the god pool
— exactly like Hermes and Selene. And `"TrialUpgrade"` is a reward **type** the
game knows how to spawn (`RewardLogic.lua:392-394`).

So picking Chaos queues `TrialUpgrade` as the run's first reward priority and the
game builds the rest. No loot name is forced, no art is registered, no shadow
`LootData` entry exists.

What it changes about a run: normally Chaos is met only through a Chaos gate.
This offers that reward once, at the start, **and only when picked**. Everywhere
else the gates behave exactly as they always did.

### Standard needed a new picture

Standard borrowed the Chaos symbol as its "no pick" icon, which stops working the
moment Chaos is something you can pick — one picture, two meanings.

`BoonBackingA` was the reasoned choice — the plate the boon-choice screen draws
*behind* a god symbol, the one image in that folder that is not anybody — and it
came back **wrong on screen**. Which is the risk with all of these: they are art
nobody drew for this purpose, judged from a filename.

So `StandardIcon` is a list to step through rather than a verdict: `pom`
(default), `chaos`, `backing-a`, `backing-b`, `backing-c`, `hammer`. Pom leads
because it is the safest bet rather than the cleverest — a real
`BoonSelectSymbols` icon that certainly renders at this size with the right glow,
not a god, and not otherwise used in this menu, since the Pom of Power is not an
option here. Picking `chaos` is allowed and is the one setting where Standard and
the Chaos option show the same image.

Whatever it lands on lives only in `BoonSelectSymbols`, so Standard keeps it in
every icon style — the door set has no "no god" medallion, vanilla having never
needed a door to promise nothing.

## An added god is a pick, not a new resident of the pool

Registering a god means adding a `LootData` entry with `GodLoot = true` — that is
what makes a drop possible at all. But `GetEligibleLootNames`
(`RewardLogic.lua:186-200`) walks **all** of `LootData` and keeps everything with
that flag whose `GameStateRequirements` pass:

```lua
if lootData and not lootData.DebugOnly and lootData.GodLoot
   and IsGameStateEligible( lootData, lootData.GameStateRequirements ) then
```

Ours pass while no boon has been taken yet. So on the run's first boon the added
gods sat in vanilla's candidate list beside Zeus and Hera, and **the game's own
roll could land on one** — whatever your pick was, including on Standard.

That is a contradiction in a plugin whose claim is that you choose what comes
first. `AddedGodsOnlyWhenPicked` (**on** by default) closes it: an added god is
eligible only while it *is* the pick. Everywhere else they are met the way the
base game means them to be met — by talking to them.

It is deliberately the broad fix rather than the obvious narrow one, because
there are four separate cases where the plugin stands aside and vanilla's roll
runs free:

| Case | Why the plugin stands aside |
|---|---|
| **Standard** | nothing is forced, by design |
| **Keepsake wins** (default on) | the plugin sits out the whole run |
| **Unmet-god skip** | `RespectEligibility` on and the pick has not been met |
| **Hammer / Hermes / Selene pick** | none of the three is a boon — `COUNTS_AS_A_BOON` is the nine Olympians plus the hammer — so the run's first *boon* is still ahead, with the added gods still eligible for it |

The last is the sharpest: ask for Hermes, take him, and the first boon could come
back Narcissus, unasked. A fix aimed only at Standard would have left that alone.

Two guards, because the failure modes here are asymmetric. Emptying the god pool
would be far worse than one unasked god, so if filtering would hand back an empty
list where the game had entries, the list is left alone and the reason is logged.
And a raising base call is re-raised rather than turned into a confident wrong
answer.

## Why a first boon looks less random than it is

Reported as a bug: with a god picked, re-rolling the seed gave what looked like
the same three options every time, only the rarity moving. It is vanilla, and the
diagnostic added in 4.31.0 is what settled it. Four Demeter runs:

```
seed 2404601806   ManaBoon, SpecialBoon, SprintBoon
seed 2449292724   ManaBoon, SpecialBoon, SprintBoon
seed 2492167724   CastBoon, SpecialBoon, SprintBoon
seed 2576125244   CastBoon, SpecialBoon, WeaponBoon
```

Seeds genuinely differing, `DebugRNGSeed` zero, so the RNG was never the problem.
Every name came from `LootData_Demeter.lua:50`:

```lua
PriorityUpgrades = { "DemeterWeaponBoon", "DemeterSpecialBoon", "DemeterCastBoon", "DemeterSprintBoon", "DemeterManaBoon" },
```

`SetTraitsOnLoot` reaches `GetPriorityTraits( lootData.PriorityUpgrades, lootData )`
(`TraitLogic.lua:1806`), which cuts the list down at random and then enforces a
slot guarantee (`UpgradeChoiceLogic.lua:739`):

```lua
while TableLength( priorityOptions ) > GetTotalLootChoices() do
    RemoveRandomValue( priorityOptions )
end
...
if not hasGuarantee then
    priorityOptions[1].ItemName = GetRandomValue( traitsWithGuaranteedSlot )
end
```

Three from five is ten combinations; the guarantee removes the one containing no
Melee or Secondary slot boon, leaving about nine. A repeat across four runs is
therefore around 54% likely, and a guaranteed-slot boon appearing every time is
not chance at all. Every Olympian carries the same five-entry list (Weapon,
Special, Cast, Sprint, Mana), so this is uniform across the vanilla gods, and it
is behavior players already recognise as the game steering early boons toward
the main slots.

A second round on Hephaestus closed it, and incidentally demonstrated what the
diagnostic is for:

```
seed 75613372    Weapon:Common, Mana:Epic, Sprint:Epic
seed 75613372    Weapon:Common, Mana:Epic, Sprint:Epic
seed 75613372    Weapon:Common, Mana:Epic, Sprint:Epic
seed 197092254   Mana:Common, Special:Epic, Sprint:Epic
seed 238844375   Cast:Epic, Mana:Common, Weapon:Common
```

Three runs on an unreset seed produce identical options **and identical
rarities**; the two runs on fresh seeds differ. That also settles the original
report: it described the rarity changing while the option set repeated, and since
rarity is seed-derived, the seed was genuinely moving. A repeated set on differing
seeds is the one-in-nine draw, not a fault.

There is a worse case that did not occur here but is worth knowing about. If
fewer than three priority upgrades survive the eligibility and occupied-slot
filters, the `while` loop above never executes and the same three appear every
time, deterministically. All five were live for both Demeter and Hephaestus.

**A keepsake behaves identically**, because it reaches the same function with the
same `lootData`. The impression that it does not comes from comparing a first
offer against later ones: once the hero holds a priority boon,
`heroHasPriorityTrait` flips and the function returns a single random option
instead, and subsequent offers draw from the full `Traits` pool.

Worth knowing for anything built on this: **the added gods have no
`PriorityUpgrades`**, since `registerGod` copies `Traits` but not that field. So
they go straight to `GetEligibleUpgrades` and their first offer is drawn from the
whole pool, which makes them *more* varied than a vanilla god's first boon rather
than less.

## The eligibility switch is a safety valve, and off by default

`RespectEligibility` sounds like it does more than it does. The only case it can
actually catch is **a god you have never met**: the max-gods cap counts gods
taken *this run*, and at the very first reward that is zero, so the cap can never
apply; and a god already offered at another door is handled separately.

Picking a god you have not met and getting them is the point of the mod, so this
now defaults to **off**. It stays as a switch only because forcing an unmet god
is untested — their dialogue may assume an introduction that has not happened.

## Gods added by other plugins

The catalog is built from the game's own `LootData` — every entry with
`GodLoot = true` that is not `DebugOnly` — rather than a hardcoded list, so a
plugin that adds a god is picked up without a change here. Two things make that
actually work:

**Load order.** Both this plugin and one that adds gods register inside
`modutil.once_loaded.game`, and the order between two of those is not defined. A
catalog built once at load is a coin flip. So it is also rebuilt on demand at the
two moments a stale list would be seen — opening the tab, and opening the
settings window — guarded by a count of `GodLoot` entries, so a rebuild only
happens when the answer has genuinely changed. Removals are picked up too.

**Icons.** Verified against `zannc-GodsAPI` 2.1.5 rather than guessed. It builds
(`src/main.lua:235-259`):

```
upgradeName = "<guid>-<God>Upgrade"
SpeakerName = "<guid>-<God>"
Icon        = "BoonSymbol<guid>-<God>"
GodLoot     = true
```

So `Icon` **does** match `^BoonSymbol(.+)$` — and yields
`zannc-Droppable_Gods-Artemis`, a name no art set carries. v3.3.0 returned that
unconditionally and never reached `SpeakerName`, which would have left every
modded god on the Chaos default. Every candidate is now checked against art we
actually have, and the first that hits wins: `Icon` → `SpeakerName` → either with
its namespace stripped → the god's own `BoonInfoIcon` → the default. Vanilla loot
names contain no dash, so the stripping can only ever fire on a modded god.

Display names get the same treatment. `SpeakerName` defaults to the namespaced
form, and a mod only produces a clean one by overriding it through `ExtraFields`
— Droppable Gods does, but nothing forces it to — so the last dash-separated
segment is taken.

**NPC-style gods are correctly excluded.** GodsAPI sets `GodLoot = false` for a
god registered as `NPCGOD` (`main.lua:352`), exactly as vanilla does for Hermes.
Droppable Gods registers **Hades that way always**, so Hades does not appear in
the god list — and should not, since he is not a boon god. Supporting him would
mean the reward-priority path this plugin already uses for `@Hermes`, not the
`ForceLootName` path.

Artemis, Athena, Dionysus and Hades are registered in the symbol set even though
they never drop as boons in the base game, because **the base game already has
their art** in `BoonSelectSymbols`. That costs nothing and means a mod like
`zannc-Droppable_Gods` gets correct symbols here for free.

**And we do not register a god another plugin already offers.** The loot keys
never collide, since theirs is namespaced by their guid and ours by this mod. What
collides is the only thing the player can actually see: `displayNameFor` resolves
both `zannc-Droppable_Gods-ArtemisUpgrade` and `SelectFirstBoon-ArtemisUpgrade` to
"Artemis", so the tab listed Artemis twice, with identical art, meaning two
different things.

`registerGod` now scans `LootData` for a non-`DebugOnly` `GodLoot` entry whose
display name matches, and stands down if it finds one:

```
Artemis is already offered by zannc-Droppable_Gods-ArtemisUpgrade;
standing down so the list does not show two of him
```

Nothing the player wanted is lost. Their entry is in the catalog, so Artemis is
still pickable as the first boon. The only casualty is this plugin's
"and never again after the first reward" restriction, and installing a mod whose
entire purpose is to lift that restriction is not an accident.

They are deliberately **not** in the door set: `<God>IconSpin` does not exist for
those four in the base game and is shipped by the plugin that adds them.
Registering a `FilePath` that may not exist is a risk taken on behalf of every
user who does not have that plugin, for no gain — `iconInStyle` already falls
through to the symbol when the chosen set has no entry for a name.

## Row layout

The buttons fill a row to `screen.GridWidth` and then wrap — the same loop the
vanilla resource grid runs at `ResourceLogic.lua:614-620`. With `GridWidth 8`
that is eight across and the remainder beneath, which is what every other tab
looks like.

Earlier versions didn't do this. v2.4.2 put all ten on one row at a tighter
pitch, and v2.5.0 went to five per row on *alternate* slot rows. Both were
workarounds for the oversized hitbox — buying vertical clearance by spreading the
icons out — rather than layouts anyone would pick. Once the box is one cell there
is nothing left to work around, so the layout is just the screen's own.

`FALLBACK_ROW_WIDTH` (8) covers a screen that reports no `GridWidth`.

## The controller cursor

Three attempts at the controller problem tuned `FreeFormSelect*` settings. That
was the wrong layer twice over: those are only config options pushed by
`SetGamepadNavigation` (`UILogic.lua:1091`), and the actual defect was that the
cursor never arrived on this page at all.

Vanilla moves the gamepad cursor in three places, two of which branch on whether
the category has an `OpenFunctionName`:

| Path | Where | What it does |
|---|---|---|
| `OpenInventoryScreen` | `ResourceLogic.lua:355-364` | `CursorStartX/Y` if set, else `GridStart` for a plain category, else `PinStart` |
| `InventoryScreenNextCategory` | `ResourceLogic.lua:645-650` | `GridStart` for a plain category, else `PinStart` — `CursorStartX/Y` is **not** consulted |
| `InventoryScreenPrevCategory` | `ResourceLogic.lua:670-675` | same |

"Else `PinStart`" is the bug. `PinStartX/PinStartY` is **(614, 267)** — the
forget-me-not column, a vertical list on the right. Vanilla assumes any category
with an `OpenFunctionName` looks like that, because the two that ship do. This
one is a grid at `GridStart` (149, 252).

So tabbing in with a controller parked the cursor at (614, 267): between the
fourth button (549.8) and the fifth (683.4), on nothing. With the old 340-wide
box that point sat inside two boxes at once — which is precisely the reported
*"you switch between two boons but can't move around the rest"*.

Two fixes, one per path:

- `tabOpen` sets `screen.CursorStartX/Y` to the currently-selected god's slot.
  The open path prefers those fields over both defaults, so no wrap is needed —
  this is the same pair of fields the vanilla resource grid sets at
  `ResourceLogic.lua:590-597`.
- The two tab-switch paths ignore those fields, so they're wrapped: run vanilla,
  then move the cursor again if the category we landed on is ours. Wrapping
  *after* rather than overriding means vanilla's own `wait(0.02)` and
  presentation still happen exactly as before.

Mouse clicks on a tab go through `InventoryScreenSelectCategory`, which doesn't
move the cursor at all. Left alone deliberately — `TeleportCursor` moves the real
pointer, and yanking a mouse user's cursor across the screen is worse than the
problem.

## The info panel

Up to v2.7.0 this tab drew its own text block across the lower half of the grid.
That is not where this screen puts item text. Every vanilla category writes into
the scroll on the right, through four boxes laid out at
`ResourceData.lua:4428-4500` and filled by `MouseOverResourceItem`
(`ResourcePresentation.lua:39-79`):

| Box | Role |
|---|---|
| `InfoBoxName` | the item's name, 32pt small-caps |
| `InfoBoxDescription` | what it is |
| `InfoBoxDetails` | where it comes from, in Hecate purple |
| `InfoBoxFlavor` | italic flavour text, near the bottom |

Those components belong to the **screen**, not to any category, so this tab just
writes to them. Two details make that safe: `InventoryScreenDisplayCategory`
fades all four to zero at `ResourceLogic.lua:396-399`, and that runs *before* our
`OpenFunctionName` at `:437`, so anything written afterwards stands; and vanilla
passes localisation keys, which this plugin has none of — but the same
`ModifyTextBox` accepts `RawText`, which the old text block already used.

Resting state shows the current selection and both gate settings. Hovering a god
replaces it with that god's name and what picking it does, and moving off
restores the resting state rather than blanking the panel. On close the four
boxes are faded back to empty, since they're the screen's and the next category
will want them.

Hover presentation now matches `MouseOverResourceItem` too:

- the slot frame is an **animation** on the highlight component —
  `InventoryScreenSlotIn` / `InventoryScreenSlotOut` — not an alpha fade. Up to
  v2.7.0 this tab faded a highlight that had no animation on it, so nothing was
  ever drawn and there was no visible selection frame at all. That matters for
  the controller specifically: without a frame there is no way to see which
  button the stick is on.
- the icon grows by `screen.IconMouseOverScale` (1.33,
  `ResourceData.lua:3975`) with `SkipGeometryUpdate = true`, so the art scales
  and the hitbox doesn't. Without that flag the box would grow into its
  neighbours on hover and reintroduce the overlap this version just removed.

## Diagnostics

`VerboseTabLog` (on by default while this is being built) logs the tab's grid
geometry, every slot with its position and selection state, each hover, which
slot a click resolved to, and how many components cleanup destroyed. That's
enough to tell "the hit-test picked the wrong button" apart from "the click never
arrived" without needing a screenshot. Turn it off for everyday play.

## An equipped keepsake wins

A keepsake and this plugin want the same thing, and before 3.1.0 you could have
both. The deference was per **offer**: a keepsake claimed room 1, the plugin
stood down for that offer, and then room 2 saw a spent keepsake — `GiveLoot`
drops `Uses` to 0 — and forced a second god. **Two guaranteed gods at the start
of a run**, which is one more than this plugin is for. 3.0.0 made it worse: the
keepsake and the plugin would each push a `"Boon"` priority, so the first *two*
rewards would both be boons.

So the stand-down is per **run**, and it latches. Latching is the whole point —
checking live would unlatch in room 2 the moment the keepsake was spent.
`KeepsakeWins` (default **on**) controls it; off gives you both.

The tab says so while it applies: the panel reads *"Disabled — Apollo keepsake
equipped"*, no option is drawn as active, and the ImGui status line says the
same. That display uses a **separate, read-only probe** — reading the page must
never decide anything about the run, or a player who opened the inventory before
the first room and then swapped keepsakes would have been latched by having
looked. The two delay gates keep working throughout: they decide when Hermes and
Selene may appear at all, which has nothing to do with the pick.

## The delay gates are buttons on the page

Hermes Delay and Selene Delay sit on their own row, three slot rows down, with a
clear empty row between them and the flowing icons. They are deliberately **not**
in the flow: they are a different kind of control, and putting them in the run of
icons would read as two more things to pick. Lit means on; dim means off or
overridden. The panel names whichever one the cursor is on and says what pressing
would do.

## Panel language

Each of the four boxes means one thing and keeps meaning it, at rest and on hover
alike — nothing migrates between them:

| Box | Always |
|---|---|
| Name | what is under the cursor, or the page itself |
| Description | what that does |
| Details | the two delay gates — always, never anywhere else |
| Flavor | what pressing would do |

The unpicked option is **Standard**, not "Random": it is not a new randomised
mode, it is the game's own behavior with nothing touched, and how random that is
underneath is the game's business. Descriptions assert what a pick does rather
than listing what it leaves alone. A gate that a pick has overruled reads
`Overridden` — one word, a state, not a sentence in capitals.

## The hover frame belongs to the slot, not the icon

The icon nudge exists **because the icon and the slot are not the same place** —
the icon shifts down into the space vanilla reserves for a quantity number.
Anything that outlines the *slot* therefore has to stay behind.

Up to v4.0.1 the hover frame was created at the button's position, so it moved
down with the icon and sat `IconOffsetY` units below the slot outline the
background art draws. Reported as "the highlighted part is slightly off."

Now the frame sits on the slot line and the icon alone is nudged.
`HighlightOffsetY` moves the frame independently for fine tuning; `0` means "on
the slot."

## Selene's art is the odd one out in vanilla, not just here

Every god's door icon is `BoonDrop<God>Preview`, inheriting
`BoonDropRoomRewardIconPreviewBase` from `<God>IconSpin0015` — a flat,
squared-up medallion (`Items_General_VFX.sjson:5636`). Selene's is
`SpellDropPreview`, inheriting **`BoonSymbolBaseIsometric`** (`:1063`) — a
different base, which is why it sits at an angle beside the others.

There is no Selene entry in `BoonSelectSymbols` at all. Four candidates were
tried and **cut on evidence**:

| Tried | Result |
|---|---|
| `GUI\Icons\Attributes\Hex` | renders as a **sheep** — it's the hexed *status* icon |
| `SeleneBoonMoonParticle` | blank; particle art isn't addressable here |
| `BiomeMap_Moon_01` | blank, same reason |
| `BoonIcons\Selene_100` | one specific hex, not Selene |

Her world drop was tried too, both centered and anchored at vanilla's
`OriginX 120 / OriginY 400`, and **both were cut in v4.9.0**. The beam is part of
the texture, not a separate animation — `SpellDrop`'s children are a glow emitter
and an orb spawn, no beam — so it cannot be switched off, and anchoring only
moves where it runs out of the slot. Confirmed in game.

What's left is the flat art a door shows, with a halo added underneath it.

### The halo: two dead ends and a live one

**Take one — `Material = "Emissive"`.** Pixel-identical to the flat art in game.
The material lever is dead.

**Take two — a second additive sprite.** This is what vanilla itself does for a
halo: `BoonDropBackGlow` (`Items_General_VFX.sjson:5087`) and `BoonSymbolGlow`
(`GUI_Screens_VFX.sjson:8220`) are both a separate sprite drawn additively, not a
property of the art.

It shipped in v4.9.0 and **never ran once**. There was still an art dropdown with
a flat option, it was set to flat, and the halo code returned before drawing
anything — so turning the strength dial could not have done a thing. The only
evidence was an *absence*: not one halo line in the whole session's log.

v4.10.0 fixes the design, not just the bug:

- The art dropdown is gone. There is one Selene art; **`SeleneGlowStrength` alone**
  decides whether it carries a halo, and `0` is off.
- Every skip now *says why* in the log, so a silent no-op can't happen twice.
- Which **texture** the halo uses is a setting, because that part is still open.

**Take two, actually running.** `particle` draws, and it looks right —
confirmed in game. The two "use the game's own animation by name" options
(`BoonSymbolGlow`, `BoonSymbolFlare`) did their diagnostic job and are cut in
v4.11.0: as *art* in a grid slot they make no sense. The backings stay, since
they were never fairly judged — everything was the wrong size.

`SeleneGlowSource`: `particle` (default), `backing-a`, `backing-b`, `backing-c`.

### Sizing it: the multiplier that wasn't

v4.10.0 multiplied the spread by the icon's own scale, on the theory that a
bigger icon wants a bigger halo. With Selene's boost at 1.5 the *smallest* preset
came out at `1.8` — and `particle_glow` is a large texture, so the halo covered a
serious fraction of the screen. Every art option looked "too big" because every
art option was being sized the same wrong way.

`SeleneHaloSpread` is now the component scale **directly** — the number in the
menu is the number the game uses. Around `0.2` fills a slot. It lives under a new
key because a config still holding `3.5` under the old one would have reproduced
the same wall of light.

`SeleneHaloLayers` (default `2`) draws the sprite more than once. Additive alpha
stops at `1.0`, and one layer read fainter than the bloom painted into the god
symbols; stacking is how additive light gets brighter past that ceiling, and it
is what vanilla does with `BoonDropA/B/C` — three glow layers on one orb.

The component goes in `Combat_Menu_Overlay_Additive` — the group the hover frame
already uses successfully on this screen — tinted with Selene's own `LootColor`
(`{100, 25, 255}`, `LootData_Selene.lua:64`). The two `vanilla-*` sources are
left untinted, since those entries carry their own color behavior.

This is the *inverse* of the god-symbol problem: their bloom is painted into the
texture and cannot be removed, but it **can be added** to art that has none.

## The tab-strip icon is not one of our buttons

The icon on the tab strip is created by vanilla in its category loop
(`ResourceLogic.lua:290`) at `screen.CategoryIconScale`, and only the animation's
own `Scale` decides how big the art lands there. Our per-button `SetScale` never
reaches it — which is why Selene, whose art is smaller than the god symbols, came
out tiny on the strip while looking right in the grid.

The same correction is applied to that component directly, on open and whenever
the pick changes.

**v4.8.0 overcorrected**, and v4.9.0 fixes it. `SetScale`'s `Fraction` is
*absolute*, not a multiplier (`ResourcePresentation.lua:105` resets a button to
its base with it), so reusing the grid's `1.0` there blew every tab icon — Selene
and gods alike — to more than double the size vanilla draws. The base is now the
tab's own `CategoryIconScale` (`0.45`, `ResourceData.lua:3931`), and the only
thing layered on top is Selene's boost. Every other god lands exactly where
vanilla put it.

## The pick is forgotten at launch

The pick is stored in the config file, so it used to survive closing the game —
right for a preference, wrong for a choice about one run. As of v4.9.0 every
launch starts at **Standard**, and the log says what was cleared.
`KeepPickAfterRestart` restores the old behavior.

## The icon glow: three sets of art, one of which has it painted in

v3.1.0 concluded the halo was painted into the BoonSelectSymbols textures and
that no property could touch it. **That was wrong**, and the counter-example was
on the page the whole time: **Hammer and Hermes come from that same folder and do
not glow.** The halo is per *file*, not per folder — the nine Olympians carry
their own color, and the two that have no god color do not.

Which means different art is a real fix rather than a wish. Three sets ship, all
registered every load, so `IconStyle` is a live setting:

| Style | Art | Covers |
|---|---|---|
| `symbol` | `GUI\Screens\BoonSelectSymbols` | all but Selene (borrows her door art) |
| `boondrop` | `Items\Loot\Boon\<Name>IconSpin\<Name>IconSpin0015`, plus `Items\Loot\WeaponUpgrade_Preview` | **every option** |
| `portrait` | `KeepsakeMaxGift_small` | gods, Hermes, Selene, Chaos |

`boondrop` is what a **door** shows for the reward behind it, and it is the only
set that covers every option with no fallback — Standard uses the Chaos door
icon, Selene her own spin frame, Hammer the hammer preview. The game already
treats the god half as matched: every `BoonInfoSymbol<God>Icon` inherits
`BoonInfoSymbolBase` at `Scale = 1.3` and **nothing else**
(`GUI_Screens_VFX.sjson:8089-8154`) — there is no per-god `Scale` override
anywhere. An earlier note in this repo claimed these render at visibly different
sizes; that was inferred, and the absence of a single override is evidence
against it.

`WeaponUpgrade_Preview` is declared at `Scale 0.55` where the spin frames are at
`1.0`, so the hammer carries that factor or it lands twice everyone else's size.
The pulsing a real door shows comes from `BoonSymbolBaseIsometric`'s `AddColor`
and `PingPongColor` (`Items_General_VFX.sjson:1039-1053`), which these entries do
not inherit — they are static, single-frame and Unlit.

`portrait` still works as a `.cfg` value but is no longer offered in the picker:
they are the character faces, and those were not wanted.

### If none of the art suits: dim it

`IconBrightness` multiplies every icon's texture through `SetRGB`, which is what
vanilla does to gray out an item it cannot offer (`SetRGB` with `Color.Black`,
`ResourceLogic.lua:561`). Below `1.0` everything darkens, and the halo — which
reads by *brightness* where the symbol reads by *shape* — loses more than the
symbol does. Presets run 100% down to 50%; `1.0` makes no call at all. Alpha is
untouched, so nothing goes transparent.

## Failure behavior

- Config backend missing or broken → plugin still runs, settings held in memory,
  said so in the log and in the window.
- Any error inside the decision logic → logged, vanilla's already-valid reward
  left in place.
- Any error inside the ImGui window → `End()` still called so no window leaks,
  the window closes itself rather than repeating the failure every frame, and
  the game logic is unaffected.
- Configured god not in the catalog → logged and treated as None.

## Testing done before shipping

`main.lua` parses clean under both the Lua 5.1 and Lua 5.4 parsers. The plugin was then loaded into a mock harness — which reimplements the
boon branch of `SetupRoomReward` and `GiveLoot` from the real source, plus
`rom.gui`, `rom.ImGui`, `rom.log`, the config API and `IsRoomRewardEligible` — and
driven through 479 assertions across 84 scenarios: every v1 invariant re-checked with the god supplied by
config, the full dropdown interaction, persistence and flush-to-disk, the
eligibility toggle, both `LootData` catalog fallbacks, an unknown god name, a
missing config backend, a throwing config backend, drawing before game load,
drawing with no run in progress, a collapsed window, and a forced ImGui
exception; and for the gates, both toggles independently, release by god boon and
by hammer, non-release by Selene spell, no-run safety, coexistence with a forced
god, and proof that a reward vanilla already rejected is never resurrected. The
mock's `rom.log.error` raises, matching the real binding, so the v2.0.0 mistake
cannot come back unnoticed.

Three real bugs were caught this way and fixed: a tail-called `chalk.auto` that
silently defeated its own frame fix, a window that drew its body while ImGui
reported it collapsed, and — this one only in the game, not the harness — the
`rom.log.error` fault above.

That harness is a model of the game, not the game. It cannot catch a wrong
assumption about the engine around it — only in-game use does that. The ImGui
binding in particular is mocked from how ModpackLib calls it, not from the
binding itself.

### In-game trial of every added god

After Medea ate a save, every remaining added god was taken in a real run and the
engine log read afterwards. The bar was not "it did not crash" — it was **a boon
whose handler actually does something at runtime, seen to fire**, because Medea's
crash came twenty-two seconds after pickup rather than at pickup.

| God | Boon taken | Why that one | Result |
|---|---|---|---|
| Narcissus | — | baseline; also the package-load control | clean |
| Arachne | — | first untested god, no `DebugOnly` mark | clean |
| Icarus | `UpgradeHammerBoon` | inconclusive — the one trait in his pool with no runtime handler | re-run |
| Icarus | **`OmegaExplodeBoon`** | `CheckIcarusExplosion` spawns `IcarusExplosion`; the closest structural match to Medea | clean, fired repeatedly |
| Circe | `RandomArcanaTrait` | the only trait in any pool that writes `GameState` rather than `CurrentRun` | clean; `Profile1.sav` grew ~3 KB, as expected |
| Circe | **`ExPolymorphBoon`** | `CircePolymorph` spawns `MorphDamageProjectile` | clean |
| Echo | `DiminishingHealthAndManaBoon` | — | clean |

Every session: zero errors, asserts or exceptions in `Hades II.log`, and the
`.sav` files intact (checked for the interrupted-write signature — a long run of
`0xFF` in the tail — that marked the corrupted save).

**What this establishes.** `OmegaExplodeBoon` and Medea's `NewStatusDamage` are
the same structure: a trait handler spawning a character-named projectile from a
package the plugin never explicitly loads. One of them is fine. **So the failure
does not generalise from the shape**, and there was never a defect common to the
added gods to fix.

**Packages load correctly, measured rather than assumed.** From `Hades II.log`,
our god and a vanilla god in the same run:

```
17:49:09  Voice bank loaded successfully: Narcissus (320 lines in 0.021593 seconds)
17:49:09  Package Loaded: Narcissus 54Mb in 0.03s
17:49:09  Loading package: Claude-NarcissusUpgrade.pkg      <- no "Package Loaded" line

17:49:33  Voice bank loaded successfully: Hestia (254 lines in 0.021324 seconds)
17:49:33  Package Loaded: Hestia 54Mb in 0.03s
17:49:33  Loading package: HestiaUpgrade.pkg                <- no "Package Loaded" line
```

Identical, including the second package that does not exist in either case. This
came from `CreateLoot`'s `AutoLoadPackages` block (`RoomLogic.lua:2256`), which
reads `loot.LoadPackages` — a field `registerGod` copies from the NPC.

There **is** one path our gods miss: `EventLogic.lua:1646` calls
`GetLootSourceName( name, { CheckEnemyData = true, GetPackageName = true } )` at
pickup and loads whatever comes back, and that returns nil for all nine of ours,
because every `PackageName` in those NPC files sits inside `OnUsedFunctionArgs`
rather than at the top level. It is a real gap and it is **inert** — the log
shows vanilla's own version of that call (`HestiaUpgrade.pkg`, 17:49:42) loading
nothing either.

### The game's own trait guards travel with the pool

`Traits = npc.Traits` is by reference, so a god's whole pool comes across —
including each trait's `GameStateRequirements`, which `IsTraitEligible`
(`RunLogic.lua:125`) enforces on our drops exactly as on the god's own screen.
Our LootData entry does not set `StripRequirements`, which is the one flag that
would bypass it.

Tested directly. `EchoLastReward` requires `PathTrue = { "CurrentRun", "LastReward" }`
and `EchoLastRunBoon` requires a non-empty `EligiblePrevRunTraits` — neither can
hold on the first reward of a run. Offered on an Echo first boon:

```
Pom Pom Pom        EchoDoubleLevelBoon
Fight Fight Fight  DiminishingHealthAndManaBoon
Evade Evade Evade  DiminishingDodgeBoon
```

Both guarded traits absent. A single draw is not proof on its own — unfiltered,
that outcome still turns up about a third of the time — but it agrees with the
code, and **it is why there is no per-god trait exclusion list in this plugin.**
Writing one would re-implement a filter the game already runs.

---

## Two investigations, moved out of the code

Both were narrative attached to a line that no longer needs it -- the questions
are settled and the answers are in the code. Kept because the reasoning is what
stops either being reopened.

### Medea, and the crash that was not hers

because it is the most expensive wrong turn in this plugin's history.

Taking her boon as a first reward was followed, twenty-two seconds
later, by EXCEPTION_ACCESS_VIOLATION and a truncated Profile1_Temp.sav
that would not load ("can't load: extra data at end", then
SaveErrorCorrupt). She was pulled from this list on the strength of
that single event.

What the crash actually was, read off the stack dump in the
ReturnOfModding backup log rather than guessed at:

    [0] ltable.cpp:483    luaH_get
    [1] lvm.cpp:116       luaV_gettable
    [2] lvm.cpp:546       luaV_execute
    [3] ldo.cpp:429       unroll
    [5] ldo.cpp:535       lua_resume
    [7] lcorolib.cpp:53   luaB_coresume

A table lookup inside the Lua VM, inside a coroutine being resumed
after a yield, reading through memory that was no longer valid. Not an
asset fault -- a missing texture or projectile crashes in the asset
manager or the renderer, not in ltable.cpp. Causes of that shape are
GC reclaiming something still referenced, a thread resumed after its
state went away, or heap corruption from elsewhere. All of them are
timing-dependent, which is why it has never reproduced.

The same log also shows "Package Loaded: Medea 35Mb" at 16:54:21 in the
crashing run, which disposes of the theory that her assets were absent.

Four Medea boons since, in deliberate tests, all clean -- including
NewStatusDamage, the trait that was accused, with a real vulnerability
effect landing on an enemy to trigger its handler. The whole case
against her had come down to "she was the boon in the run that
crashed", and that is superstition, not evidence.

She ships. The crash was real and the save loss was real, and neither
has a fix in this plugin because neither belongs to it -- that class of
fault can land on any run. The recovery procedure is in
MODDING_HADES2.md section 5f, outside this repo: a SAVE_RECOVERY file
next to a mod reads as an admission the mod eats saves, whatever it
says inside.

### Whether a keepsake portrait renders inside a world orb

"symbol" is GUI\Screens\BoonSelectSymbols\<God> -- the emblem, and what every
one of these gods has used so far.

"portrait" is the keepsake portrait, GUI\Screens\AwardMenu\KeepsakeMaxGift\
KeepsakeMaxGift_small\<God>. It exists here for one reason: six more NPC gods
(Narcissus, Arachne, Circe, Echo, Medea, Icarus) have a portrait and NO emblem,
so whether a portrait renders inside a world orb decides whether they can ever
have a drop. Testing that on a god who already works costs one restart;
building six gods on the assumption costs a great deal more.

Two things are being asked at once and they are separate questions:

  1. Does it RENDER? A texture that is not in a package loaded for the current
     context comes back BLANK rather than erroring -- exactly how
     SeleneBoonMoonParticle and BiomeMap_Moon_01 failed. No Lua script
     references the KeepsakeMaxGift folder at all, so this cannot be settled
     from the data files. In its favour: the inventory tab already draws that
     same folder mid-run in the portrait icon style.
  2. Does it LOOK right? It is a rectangular headshot sized for a menu row,
     where every other drop in the game is a round medallion. Expectations
     should be low, and that is a separate answer from the first.

If it renders blank, the fix to try is packages: CreateLoot calls
LoadPackages with this loot's own LoadPackages list (RoomLogic.lua), and ours
already inherits the NPC's -- { "NPC_Artemis_Field_01", "Artemis" } and so on.
A missing texture would mean adding whichever package holds it to that list.
CONFIRMED IN GAME: a portrait does render inside a world orb. That settles the
question the toggle existed to ask, and it is what makes portrait-only gods
possible at all.

Two things were wrong with the first look, and each has its own answer:

  jagged      KeepsakeMaxGift_small is small art being drawn larger. The same
              folder ships a _big variant, so "portrait" now means the big one
              and the small one stays available as portrait-small.
  washed out  The face took the boon's color. That is not a property of the
              emblem -- BoonDropIcon sets ColorFromOwner = "Ignore"
              (:4907) -- it is BoonDropFrontFlare being drawn OVER it, on
              GroupName "FX_Add_Top" (:4525). Nothing can stop that layer
              painting over the picture, but two dials change the balance:
              that god's glow down, or that god's emblem brightness UP, which
              is why emblem brightness now goes above 1.0.
