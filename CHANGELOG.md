# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The release workflow folds the `[Unreleased]` section into the tagged
version, so the square brackets are load-bearing -- the action looks for
`[Unreleased]` exactly and fails the build without it.

## [Unreleased]

### Fixed

- **Two delays now read "Hermes or Selene", not "and".** There is one first
  boon, so it cannot be either of them; "and" read as though both had to be
  true at once. Every existing test covered a single delay, which is why this
  went unnoticed until a playtest.
- **The Override Story switch no longer overflows its title box.** InfoBoxName is
  32pt small-caps, and the longer name drew across the description beneath it.

### Changed

- **The tab is now called Select First Boon**, matching the mod's name.
- **The two switches are renamed.** "Always First" is now **Override Story** and
  "Turn Everything Off" is now **Pause Plugin**. Both say what
  the switch does to the run rather than what it does to the plugin. The config
  keys are unchanged, so nothing in your `.cfg` resets.
- **Standard now says what it leaves in place**: "No first reward selected."
  plus "Restrictions active." when a delay is actually on -- the delays still
  apply when no pick is set, which the old wording ("the game's own reward
  order, unchanged") did not admit. With both delays off, or the plugin paused,
  the second sentence is dropped rather than claiming a restriction that is not
  there.
- **A keepsake "forces" the first boon**, everywhere it is mentioned. It
  outranks the pick, and "takes" understated that.
- Shorter panel lines throughout: "This mod is **off**" rather than "-- the game
  is untouched", and the delays read "can appear in the first room".

- **Always First no longer warns without saying what happens.** The config
  description dropped a literal "WARNING: that breaks encounters built around a
  specific opening boon, and it breaks them quietly" in favor of stating the
  actual behavior: the scripted boon is replaced rather than delayed. The
  README's settings table says the same. The three section names are unchanged
  -- every setting here already states its own timing, which is finer than a
  section label, so there was nothing to gain by resetting anyone's config.

- **Always First's in-game description is shorter and plainer.** It now reads "Your
  pick goes first even when the game has scripted its own opening boon(s)."
  The old second sentence -- that encounters built around a scripted opening
  would not play as designed -- warned without saying what a player would
  actually see, so it raised more doubt than it settled.

### Fixed

- **Hovering or pressing Always First or Turn Everything Off left the panel
  stale.** Both switches describe themselves in their own words rather than
  naming a god, and the hover handler read a god's name that was never there.
  Pressing one flipped the setting but no word on the panel changed until you
  moved the cursor to a different button. The press now updates the panel
  immediately, and hovering either switch describes what it does.
- **The pause icon on Turn Everything Off was drawn about half the size of the
  switch beside it.** Its source art is 72x72 where the other is 150x150, and
  both were drawn at one shared scale. The size difference is now corrected at
  registration.

### Changed

- **A keepsake and your pick now both land, by default.** `KeepsakeWins` ships
  off instead of on, so an equipped boon keepsake takes the first boon and your
  pick takes the next one -- two guaranteed gods. Previously the mod stood down
  for the whole run whenever a keepsake was equipped.

  **If you already have the mod installed this will not change anything on its
  own.** Your `Adicon-SelectFirstBoon.cfg` already has a `KeepsakeWins` line
  written at first run, and the file always beats the code default. To get the
  new behavior, set `KeepsakeWins = false` in the config or turn it off in the
  in-game menu. Close the game before editing the file; it rewrites the config
  from memory when it exits.

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
