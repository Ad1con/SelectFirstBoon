# SelectFirstBoon

A Hades II mod. Lua, loaded by ReturnOfModding. One file, `main.lua`, about 5,200
lines, roughly half of it comments explaining why things are the way they are.

## Commands

```
cd test && lua run_tests.lua     # 716 assertions, 107 sections. All should pass.
luac -p main.lua                 # syntax check before shipping anything
```

There is no build step. `main.lua` is the artifact.

## Read before changing behaviour

`TECHNICAL.md` explains the mechanisms, with line references into the game's own
scripts under `Hades II/Content/Scripts`. `HISTORY.md` records what was tried and
failed. Most "obvious improvements" here have been tried already, and the reason
they were rejected is usually written down.

## Invariants that look arbitrary and are not

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
