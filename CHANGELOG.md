# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The release workflow folds the `[Unreleased]` section into the tagged
version, so the square brackets are load-bearing -- the action looks for
`[Unreleased]` exactly and fails the build without it.

## [Unreleased]

### Changed

- **The panel gives the two delays one line instead of two.** Each delay used to
  own a permanent line, shown whether or not it was relevant -- two of five
  lines, always. One line now names whatever is held back and disappears when
  nothing is, so with both delays off the panel is down to the single line that
  answers the question. A god your pick overrides is simply absent from the list
  rather than carrying a parenthetical to explain itself.
- A pass over every line the panel can show: "Idle this run" read as an
  instruction rather than a status and put effect before cause, one line
  repeated held/hold in seven words, and "so it happens once" left the reader to
  work out the contrast on their own.

### Removed

- `AddedGodsOnlyWhenPicked`, which is now always on. Off, the game's own roll
  could land an added god without being asked -- including on Standard, whose
  whole meaning is that nothing is forced. A setting the docs tell you never to
  change is not a setting. Existing config files keep the key; it is ignored.

## [4.32.0] - 2026-08-30

### Fixed

- **A clean install could fail to load entirely.** The manifest declared
  `LuaENVY-ENVY` while the code called `SGG_Modding-ENVY`, a deprecation shim it
  never declared. It resolved only where another mod happened to pull that shim
  in; anyone installing this on its own got a nil index before the mod started.
- **The pick never arrived with a keepsake equipped.** Scheduling a boon reward
  had been moved behind `AlwaysFirst`, which ships off, so the keepsake's own
  priority supplied the single boon and the pick waited on a second that nothing
  had asked for.
- Circe's familiar boon crashed the run when taken from this mod's drop. Each
  god with its own encounter now has its offer gates evaluated at offer time --
  24 of them across five gods -- instead of the raw trait pool being handed over.
- Installing the hooks twice when the loader re-runs every plugin, which it does
  whenever any mod reloads.

### Added

- **Always First** and a **master off switch**, as buttons on the top row beside
  Standard. The master switch turns everything off and the page reads off with
  it; nothing is cleared, so turning it back on restores every setting. Picking
  any god also clears it.
- A permanent first line in the info panel stating what the first boon will
  **actually** be -- including an equipped keepsake, and the case where keepsake
  and pick name the same god and one boon satisfies both.
- Hovering an icon now lights it, so a god's color can be seen without picking.

### Changed

- The controls moved to the top row and the boons flow continuously beneath
  them, which is what makes them fit in the five rows the grid has.
- Stated light colors for the gods whose derived color was wrong: Circe was
  green, Hades was near-white bone, Hermes had none at all, Chaos and Selene had
  nothing to derive from.
- The selection light is a ring rather than a glow behind the art, which is what
  let its strength rise far enough to show a color.
- The ground drops are dimmer. The glow dial had only ever reached the outer
  layers, never the orb they sit on.
