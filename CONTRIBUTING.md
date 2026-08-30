# Contributing

This file is for the repo. It is not in `thunderstore.toml`'s copy list and does
not ship.

## Tests

```bash
cd test && lua run_tests.lua
```

880 assertions. Run them on **both** interpreters — the game ships LuaJIT, and
the two differ in ways that have caught real bugs here.

```bash
cd test && luajit run_tests.lua
```

Both must be green before and after any change that ships.

## Layout

```
src/          the whole mod -- main.lua and manifest.json, and nothing else
test/         the suite, which loads ../src/main.lua against fakes
*.md          docs; none of them ship except README and CHANGELOG
guard.sh      refuses edits while Hades II is running
```

`src/` is the boundary. Tests, docs and `.git` sit outside it so they cannot
reach the package by accident, and a test asserts the build copies exactly three
sources.

## Before editing

```bash
source guard.sh && guard
```

Only necessary if you junction `src/` into an r2modman profile. This repo does
not do that today — the plugin folder is a real directory and `src/main.lua` is
copied into it — but the guard is cheap and the failure it prevents is a hard
crash inside Lua's garbage collector.

## Four rules the suite learned the hard way

1. **Test the configuration that ships.** Seven separate tests were configured
   away from the path players take; the whole suite once ran `IconStyle`
   `"symbol"` while every real config said `"boondrop"`. A test configured off
   the shipping path is worse than no test — it is green while users hit the bug.
2. **Neutralize unrelated dials in `boot()`.** If a test measures a color, pin
   brightness. Section 105 is the one place that asserts what actually ships.
3. **Sabotage every new test.** Reintroduce the bug and confirm it fails. Thirty
   seconds, and several tests here have passed while asserting nothing.
4. **Assertions must fail, not raise.** One regression made a value `nil`, the
   test indexed it, and the suite aborted mid-run and printed no summary at all.

## Spelling

American English in all prose, comments and commit messages. Game API
identifiers — `Color`, `SetColor`, `LootColor` — are code, not prose, and stay
as the game spells them.

## Releases

Caleb handles releases and the Thunderstore token. Do not bump the version or
publish. Never ask for, accept, or handle a token.
