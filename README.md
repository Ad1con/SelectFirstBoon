# Select First Boon

Pick which reward will be the first one of your run. Your choice is made in-game using an additional tab in the inventory screen. Options include **all boon givers** including those who ordinarily do not give boons this way (e.g., Circe, Athena, Hades, Chaos, etc.)

This mod is intended to interfere as little as possible with vanilla behavior of the game except to force one boon of your choosing or to defer the appearance of two often undesirable first boon offerings (i.e. Hermes and Selene) until you have taken a boon or a Daedalus Hammer.

This mod does not change the seed of your run, but receiving a boon unintended by the game will of course influence which boons are offered in future rooms. This mod uses only native assets shipped with the game.

## How do I use it?

Open your inventory before a run. There's a new tab called **Select First Boon**. Click a boon. That is now your pick, and it governs the **first** boon of your next run (barring any additional factors like an equipped keepsake or a boon the game has scripted). Once that boon has been given, this mod's functionality is finished for that run. Changing the pick during a run has no effect. The top row holds Standard, which means "leave the game alone," and four switches: the two delays, Override Special, and Pause Plugin. Defaults are recommended, but options are there to suit your preferences.

All options are also editable in `Adicon-SelectFirstBoon.cfg` and the ReturnOfModding menu bar under Adicon-SelectFirstBoon.

## Who can I pick?

**The nine Olympians, Daedalus Hammer, Hermes, and Selene** — the boons that are offered as first room rewards in vanilla state.

**Chaos** — normally offers a ground boon but not first and only in his own rooms.

**Artemis, Athena, Dionysus, Hades, Arachne, Circe, Echo, Icarus, Medea, and Narcissus** — those who give boons in the game but only through NPCs not as ground drops. These may only show up as first rewards. They will never be offered from shops or from other rooms unless another mod alters this behavior. You will still be able to meet them later and receive a boon from them like normal. Because these characters do not ordinarily have ground emblems for their rewards, existing in-game art was used to create ground boons for them.

## Game behavior (Why aren't I getting the boon I set?)

**Forced boons** In vanilla state, the game will first offer any boon it has already hard scripted for that room. These are usually forced for story/progression reasons or for Chaos Trials. By default, this mod defers to anything the game has scripted itself and offers your choice of first boon **after** those requirements are met. This behavior can be changed with the **Override Special** switch on the tab (`AlwaysFirst` in the config).

**Equipped keepsake** By default, when you have a keepsake equipped and choose a boon from this mod, you will get both: the keepsake forces the first boon and your pick takes the next one. `KeepsakeWins` ships off. Turn it on and the mod stands down for the whole run whenever a keepsake is equipped, so the keepsake forces the first boon and your pick is not used at all. If your keepsake and your pick name the same god, you will get that god once, not twice. The panel on the right of the tab always states what the first boon will actually be, keepsake included.

**Remaining behavior** If the game has no scripted rewards and no keepsake is equipped, the game will ordinarily offer 1 of 12 rewards as the run's first reward. These include the nine Olympian gods, Selene, Hermes, and Daedalus Hammer. If you choose a new first boon using this mod, the seed's intended first boon will be overridden. If Hermes and/or Selene are set to be deferred by this mod and they were intended to be the first boon of that run's seed, the game will instead determine a new first boon.

**Major rewards only** If any of the above scenarios occur that would delay this mod's forced boon, that reward will not override minor reward rooms. This mod only alters what a boon will be, it does not change what would ordinarily be a minor reward (ashes, bones, etc) into the mod's first boon.

## Settings worth knowing about

There are about forty: the ones below, an on/off switch for each added god, a few log switches, and a dozen choices about how the tab looks (which icon set, how the pick is lit, what Standard's icon is). These are the ones that change behavior:

| Setting | Default | What it does |
|---|---|---|
| `God` | none | Your pick. Same thing the tab sets. |
| `KeepPickAfterRestart` | off | Off means your pick is forgotten when you close the game, so every session starts vanilla. |
| `BlockHermesBeforeBoon` | on | Holds Hermes back until you've taken a boon or hammer. |
| `BlockSeleneBeforeBoon` | on | Holds Selene back until you've taken a boon or hammer. |
| `KeepsakeWins` | off | Off, an equipped keepsake forces the first boon and your pick takes the next one. On, the keepsake wins for the whole run. |
| `AlwaysFirst` | off | On, your pick replaces a boon the game had scripted for that room rather than waiting until after it. Ships off, so scripted openings play as the game intended. |
| `DisableEverything` | off | The master switch. On, this mod does nothing at all and everything you have set is remembered for when you turn it back off. |
| `RespectEligibility` | off | On, a god you have not met yet cannot be your first boon and the pick is ignored. Off, you get them regardless, which is what an equipped keepsake does. |
| `ShowInventoryTab` | on | Off hides the tab; the overlay menu and the config file are the only way in. Takes a restart. |
| `Enable<God>` | on | One per added god. Off removes that god from the picker. |

## Compatibility

Built to sit alongside other mods and defer to them if necessary. It reads the game's own decisions and only changes the last step. Anything else touching rewards will get priority.

**[Droppable Gods](https://github.com/excellent-ae/zannc-Droppable_Gods)**, or anything else built on **[GodsAPI](https://github.com/excellent-ae/zannc-GodsAPI) by zannc**, makes some of the same extra boons made droppable by this mod droppable for a whole run. If you have it installed, this mod won't add a copy of its own versions of those extra reward givers, it will defer to the assets packaged with GodsAPI.

**[PonyMenu](https://github.com/PonyWarrior/PonyMenu) by PonyWarrior** replaces the inventory screen's tab code with its own copy. This mod adds its tab through the game's own tab mechanism instead, and PonyMenu's copy keeps that path, so the two work together. Every playtest of this mod has been on a profile with PonyMenu installed.

## If something goes wrong

If you encounter any bugs or unexpected behavior, please submit an Issue to the GitHub repo so I can explore the problem.
Check `LogOutput.log`. This mod narrates what it's doing and why it decided not to do something. The per-decision trace is the **Verbose logging** switch (`LogDecisions`), and it ships on. Leave it on if you ever intend to report a bug.

If you have any other requests or ideas for this mod, feel free to add them as an Issue as well.

## More, in the repo

[`CHANGELOG.md`](https://github.com/Ad1con/SelectFirstBoon/blob/main/CHANGELOG.md) is what changed and when.

[`DESIGN.md`](https://github.com/Ad1con/SelectFirstBoon/blob/main/DESIGN.md) is a long writeup of how Hades II's reward pipeline works, with line references into the game's own scripts, and of what this mod does with it. It includes other technical discoveries and how failures were fixed. If you're modding this game, some of it may be useful.

## Credits
Hades II is by [Supergiant Games](https://www.supergiantgames.com/). This is an
unofficial fan mod, not endorsed by or affiliated with them. The icon is a
cropped in-game portrait.

Built on [ReturnOfModding / Hell2Modding](https://github.com/SGG-Modding). This
mod cannot load without `SGG_Modding-ModUtil`, `SGG_Modding-SJSON` and
`LuaENVY-ENVY`: the function wrapping, the art registration and the
environment isolation are all theirs.

**[PonyWarrior](https://github.com/PonyWarrior)**'s [PonyMenu](https://github.com/PonyWarrior/PonyMenu)
showed that a mod could live inside the game's own inventory screen, and its
art registration is the pattern this mod's icons use.

Thank you to the Hades II modding community. Your work is astounding.

Built by **Adicon**, with Claude.
