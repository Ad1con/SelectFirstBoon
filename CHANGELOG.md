# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The release workflow folds the `[Unreleased]` section into the tagged
version, so the square brackets are load-bearing -- the action looks for
`[Unreleased]` exactly and fails the build without it.

## [Unreleased]

First release.

### Added

- **Pick the first boon of your run** from a new **Select First Boon** tab in
  the inventory. The nine Olympians, Daedalus Hammer, Hermes, Selene, Chaos,
  and ten more who normally only give boons in person: Artemis, Athena,
  Dionysus, Hades, Arachne, Circe, Echo, Icarus, Medea, and Narcissus. Each of
  the ten can be switched off in the config.
- **Standard** leaves the game's own first reward alone.
- **Hermes Delay** and **Selene Delay**, on by default: neither can be the
  first boon until you have taken a boon or a hammer.
  With a pick set they have nothing to hold back, so their squares read dim
  until you are back on Standard.
- **Override Special**: on, your pick goes ahead of anything the game has
  scripted for the room (story boons, Chaos Trials). Off by default, so those
  play as designed and your pick comes next.
- **Pause Plugin**: everything off, every setting remembered.
- An equipped boon keepsake forces the first boon and your pick takes the
  next one. `KeepsakeWins` in the config hands the whole run to the keepsake
  instead.
- The panel always states what the first boon will actually be, keepsake and
  delays included.
- Every added god gets a ground drop and a door icon built from the game's
  own art. Nothing is shipped that the game does not already have.
