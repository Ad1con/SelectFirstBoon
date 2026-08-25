# History

The version by version account, including the parts that went wrong. None of this
is needed to use the mod, and most of it is not needed to modify it either. It is
here because the mistakes were expensive and someone else may be about to make
them.

`TECHNICAL.md` has the same material rewritten as "here is how it works and why",
with the dates taken off. This file is the version with the dates left on.

## The shape of it

Roughly forty releases. The rough phases:

| Phase | What happened |
|---|---|
| 1.x | one god, hardcoded in a constant |
| 2.0 - 2.9 | a dropdown, then a real inventory tab, then five rewrites of the tab's hitbox and layout |
| 3.x | the never-first gates for Hermes and Selene, and making a keepsake outrank a menu pick |
| 4.0 - 4.16 | Artemis, Athena, Dionysus and Hades as first-reward-only gods, and the drop art to go with them |
| 4.17 - 4.24 | portrait gods, the halo that had to be invented for them, per-god dials, Chaos |
| 4.25 - 4.28 | Medea removed after a crash, then restored once the crash was read properly; every added god trialled in game; layout settled |

## The five wrong answers about Medea

The single most instructive episode, kept in full because the pattern matters more
than the conclusion.

A first boon was taken from Medea. Twenty-two seconds later the game died with
`EXCEPTION_ACCESS_VIOLATION` and left `Profile1_Temp.sav` unloadable. Over the
next few hours, five separate explanations were constructed and every one was
wrong:

| Claim | How it died |
|---|---|
| Her boons are drawbacks, and a drawback in a reward slot breaks something | "Curse" means a curse on the enemy. They drop healing, spawn with less armour, their projectiles slow. Her kit favours the player. |
| No added god ever gets its asset package loaded | `CreateLoot`'s `AutoLoadPackages` block reads `loot.LoadPackages`, which `registerGod` copies from the NPC. Measured in game: `Package Loaded: Narcissus 54Mb` beside `Package Loaded: Hestia 54Mb`, identical. |
| Echo's boons will nil-deref on the first reward | `EchoLastReward` is guarded twice, by its own `GameStateRequirements` and by a fallback on the first line of its handler. |
| Circe's boons permanently change your profile | Vow removal writes `CurrentRun.ShrineUpgradesDisabled`, which is per-run. |
| `NewStatusDamage` is the culprit, being the only trait in the game using `OnEffectApplyFunction` | Taken deliberately, with a Demeter freeze landing on an enemy to meet its trigger. Clean. |

The answer was in the stack dump the whole time. Only its outermost two frames had
been read, `World::Update` and `GameplayScreen::Update`, which say nothing at all.
The informative frames were at the top:

```
[0] ltable.cpp:483    luaH_get
[1] lvm.cpp:116       luaV_gettable
[3] ldo.cpp:429       unroll
[5] ldo.cpp:535       lua_resume
[7] lcorolib.cpp:53   luaB_coresume
```

A table lookup inside the Lua VM, inside a coroutine resumed after a yield,
reading memory that was no longer valid. Not an asset fault at all. It has never
reproduced across four subsequent Medea runs.

**The lesson, which cost about six hours:** read the whole file before theorising
about what is in it. Every wrong answer above came from inferring a mechanism
from a partial read and then reporting the inference as a finding.

## Sections moved here from the technical doc

What follows is the original write-up of a handful of fixes, kept as written.

## Medea, and the most expensive wrong turn in this project

She is **in**, and the story of why she nearly was not is the best cautionary tale
this plugin has.

A first boon was taken from her. Twenty-two seconds later the process died, and
the next launch could not load the save:

```
16:54:20  forced first boon to Claude-MedeaUpgrade (vanilla had rolled ZeusUpgrade)
16:54:24  Claude-MedeaUpgrade boon spawned; plugin is done for this run
16:54:46  EXCEPTION_ACCESS_VIOLATION

Main.lua:572: can't load: extra data at end
SaveLoad Error: Code: SaveErrorCorrupt, FileName: Profile1_Temp.sav
```

She was pulled from the god list on the strength of that single event, and five
separate explanations were constructed for it over the following hours. Every one
of them was wrong, and every one of them was built by inferring a mechanism from
partial reads instead of opening the one file that had the answer in it.

### What the crash actually was

The ReturnOfModding backup log contains the full stack dump. Only its outermost
two frames had been read — `World::Update`, `GameplayScreen::Update`, which say
nothing. The informative frames are at the top:

```
[0] ltable.cpp:483    luaH_get
[1] lvm.cpp:116       luaV_gettable
[2] lvm.cpp:546       luaV_execute
[3] ldo.cpp:429       unroll
[5] ldo.cpp:535       lua_resume
[7] lcorolib.cpp:53   luaB_coresume
```

**A table lookup inside the Lua VM, inside a coroutine being resumed after a
yield, reading through memory that was no longer valid.** Not an asset fault — an
absent texture or projectile crashes in the asset manager or the renderer, not in
`ltable.cpp`. Faults of this shape come from GC reclaiming something still
referenced, a thread resumed after its state has gone, or heap corruption from
elsewhere. All timing-dependent, which is exactly why it has never reproduced.

The same log also records `Package Loaded: Medea 35Mb` in the crashing run, which
disposes of the theory that her assets were missing.

### The five wrong answers

Kept because the pattern is more useful than any of them individually.

| Claim | How it died |
|---|---|
| Her boons are drawbacks, and a drawback in a reward slot breaks something | Read the data: "Curse" means a curse on the **enemy** — they drop healing, spawn with less armour, their projectiles slow. Her whole kit favours the player. |
| No added god ever gets its package loaded | `CreateLoot`'s `AutoLoadPackages` block (`RoomLogic.lua:2256`) reads `loot.LoadPackages`, which `registerGod` copies from the NPC. Measured in game: `Package Loaded: Narcissus 54Mb` beside `Package Loaded: Hestia 54Mb`, identical. |
| Echo's boons will nil-deref on the first reward | `EchoLastReward` is guarded twice — its own `GameStateRequirements`, and a fallback on the first line of its handler. |
| Circe's boons permanently change your profile | Vow removal writes `CurrentRun.ShrineUpgradesDisabled` — per-run. (The Arcana one *is* permanent, but does the same from her cauldron.) |
| `NewStatusDamage` is the culprit — the only trait in the game using `OnEffectApplyFunction` | Tested directly: taken deliberately, with a Demeter freeze landing on an enemy to meet its `IsVulnerabilityEffect` trigger. Clean. |

Four Medea boons across deliberate tests since, including the accused one with its
trigger condition met, all clean. The entire remaining case against her was "she
was the boon in the run that crashed", which is superstition rather than evidence.

### Why she ships anyway

The crash was real and the lost run was real. Neither is fixable here, because
neither belongs to this plugin — that class of fault can land on any run, modded
or not, and nothing this code could add would guard against it.

What *is* actionable is recovery, and that turned out to be easy: the damaged file
was `Profile1_Temp.sav` (one run), not `Profile1.sav` (the profile), and its
`.bak` — the checkpoint immediately before — was intact and held the same run in
the same room. Copying it over the damaged file restored everything but one
reward. **`SAVE_RECOVERY.md`** documents the whole procedure, including the
`0xFF`-run signature that identifies an interrupted write and tells you when a
file is beyond repair.

She ships **off by default**, like every portrait god.


### A removed god leaves a pick behind

Which exposed a real gap. Every downstream guard is keyed on the catalog —
`applyForcedGod` and `priorityNameFor` both return early on
`not catalog.index[chosen]` — so a config naming a god that no longer exists was
already *inert*. But it sat there: the menu showed a pick, and nothing would ever
answer to it. With `KeepPickAfterRestart` on, it sat there for good.

`buildCatalog` now clears it and says so, instead of only warning:

```
configured god 'Claude-MedeaUpgrade' no longer exists; reset to Standard
```

Only against a **real `LootData` read**. When the static fallback list is in play —
which is what happens when `LootData` is not readable yet — the pick is left alone
and that is logged instead. A guess about which gods exist must never be allowed
to throw away a valid choice.

## Two gate-button bugs

**Pressing a button reverted the panel.** `pickGod` redrew the *resting* text, so
pressing a gate snapped the panel back to "First Boon" while the cursor was still
on the gate. Both branches now call `onButtonOver` for the button just pressed,
so the panel keeps describing what is under the cursor — and shows the new state
immediately.

**An overridden gate hid its own setting.** `gateState` returned only
`Overridden`, whichever way the gate was set, so pressing it appeared to do
nothing even though the setting really was flipping. It now reports the setting
first and the override second — `On (overridden)` — so the press is always
visible. The hover text says the press works but is idle while that is your pick.

## Icons sit high in their slots — fixed

Every vanilla grid button has a quantity number beneath it
(`CreateTextBoxWithScreenFormat` with `ResourceCountFormat.OffsetY = 58`,
`ResourceLogic.lua:583`), and the icon is placed to leave room for it. This tab
has no quantity to show, so without a nudge every icon reads as sitting high in
an otherwise empty slot.

PonyMenu solves it with a flat `+10` on the button Y (its `ready.lua:383`), which
is the only measured value available, so that is the default. `IconOffsetY` is a
preset combo in the settings window — 0, 5, 10, 15, 20, 29, 40 — read when the
tab opens, so comparing two values means changing it and reopening the inventory.

## One Selene, one size

Her art appears in three places — the tab strip, the grid, and the Selene delay
gate — and until v4.9.0 all three could differ. The gate was the third case: gate
buttons were sized by their own on/off state through the same "the pick is drawn
bigger" rule, so an **off or overridden gate shrank**.

v4.9.0 pinned them to one size. That fixed the reported problem and created a
smaller one: picks change size with their state, gates only change brightness.
Both readings are defensible, so v4.10.0 makes it `GateStateStyle`:

| Value | Behaviour |
|---|---|
| `brightness` | one fixed size; brightness carries on/off (default) |
| `size-only` | held at the same dimmed level an unpicked boon sits at; **size** carries on/off, and an off square rests at the unpicked grid size |
| `size` | both move, exactly the way a picked boon does |
| `none` | never reacts at all; the panel text is the only signal |

Brightness and size are independent signals, and each style is a choice of which
one carries the state — which is why the code splits them (`gateFreezesBrightness`
/ `gateFreezesSize`) rather than sharing one flag. The press works identically in
all four; only the drawing changes.

## Selene's icon size

Selene's symbol art is the SpellDrop door preview, from a different folder than
the god symbols, and it draws visibly smaller at the same scale. Size is now a
**component scale applied at draw time** rather than a number baked into the
sjson animation — PonyMenu does the same (`ready.lua:390`) — which buys two
things: it is tunable without a restart, and `SkipGeometryUpdate` means the art
grows while the hitbox stays exactly one grid cell.

`SeleneIconBoost` defaults to `2.0` and is a preset combo in the settings window.
Hover multiplies that scale rather than replacing it, matching vanilla's
`IconScale * IconMouseOverScale` (`ResourcePresentation.lua:88`) — replacing it
would have *shrunk* her on hover, from 2.0 to 1.33.

In the portrait style she uses her keepsake portrait instead and needs no boost.

## The pick reads by size, not only by brightness

Unpicked icons sat at `0.4` alpha, which made them nearly invisible against the
slot. They are now at `0.7` by default (`UnselectedBrightness`), and the pick
carries a second signal: it rests **larger** than the rest
(`SelectedIconScale`, default `1.25`).

Hovering multiplies the button's *resting* scale rather than replacing it, so a
hovered pick grows from its own size instead of shrinking to everyone else's.
Changing the pick moves both signals — size and brightness — together.

## Hover style

`HighlightStyle` picks what hovering does:

| Value | Behaviour |
|---|---|
| `frame` | the slot outline appears, as every vanilla tab does |
| `grow` | no outline at all — the icon growing is the whole signal, as PonyMenu does |

The scale change happens either way, so `grow` is simply the frame left undrawn.
Both are live: change it and reopen the inventory. **`grow` is the default** as
of v4.2.0.

## The tab-strip icon has its own size knob

Beyond the base fix above, vanilla's own `0.45` reads slightly small on this
page, so `TabIconBoost` (default `1.15`) multiplies **every** god's tab icon.
`1.0` is exactly vanilla. Selene's correction stacks on top of it.
