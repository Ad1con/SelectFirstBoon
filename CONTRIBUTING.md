# Contributing

This file is for the repo. It is not in `thunderstore.toml`'s copy list and does
not ship.

## Tests

```bash
cd test && lua run_tests.lua
```

The game ships LuaJIT, and the two interpreters differ in ways that matter
here, so run the suite on both:

```bash
cd test && luajit run_tests.lua
```

Both must be green before and after any change that ships.

## Layout

```
src/          the whole mod: main.lua and manifest.json, nothing else
test/         the suite, which loads ../src/main.lua against fakes
*.md          docs; only README and CHANGELOG ship
guard.sh      refuses edits while Hades II is running
```

`src/` is the boundary. Tests, docs and `.git` sit outside it so they cannot
reach the package by accident, and a test asserts the build copies exactly
three sources.

## Before editing

```bash
source guard.sh && guard
```

If `src/` is junctioned into an r2modman profile, an edit while the game is
running is picked up mid-frame. At best the plugin re-runs and its state
splits in two; at worst the game crashes inside Lua's garbage collector. The
guard refuses the edit while `Hades2.exe` is up.

## Before you change behavior

Read **"Before you change anything"** at the top of `DESIGN.md`: a short list
of invariants that look arbitrary and are not. The rest of `DESIGN.md` explains
each mechanism with citations into the game's own scripts under
`Content\Scripts\`, and records the alternatives that were tried and why they
were rejected.

## Test conventions

1. **Test the configuration that ships.** A test set up off the path players
   take can stay green while users hit the bug. `boot()` defaults to the shipped
   style and icon; pass a different one only when the test is about it.
2. **Pin what you are not measuring.** If a test reads a color, hold brightness
   still. Section 105 is the one place that asserts the shipped values.
3. **Sabotage every new test.** Reintroduce the bug and confirm the test fails
   before trusting it.
4. **Assertions fail; they do not raise.** Guard an index that a regression
   could make `nil`, so one bad value prints one red line instead of aborting
   the run.

## Spelling

American English in all prose, comments and commit messages. Game API
identifiers -- `Color`, `SetColor`, `LootColor` -- are code, not prose, and stay
as the game spells them.

## Releases

Releases are cut from the GitHub workflow by the maintainer. Do not bump the
version in a pull request.
