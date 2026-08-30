# Select First Boon

Pick which god offers the first boon of your run. Your choice is made in-game using an additional tab in the inventory screen. Options include **all boon givers** including those who ordinarily do not give boons this way (e.g., Circe, Athena, Hades, Chaos, etc.)

This mod is intended to interfere as little as possible with vanilla behavior of the game except to force one boon of your choosing or to defer the appearance of two often undesirable first boon offerings (i.e. Hermes and Selene) until a different boon is received.

This mod does not change the seed of your run, but receiving a boon unintended by the game will of course influence which boons are offered in future rooms. This mod uses only native assets shipped with the game.


## Game behavior (Why aren't I getting the boon I set?)

In vanilla state, the game will first offer any `ForcedBoon` for that run. These are usually forced for story/progression reasons or for Chaos Trials. By default, this mod defers to anything required by `ForcedBoon` and offers your choice of first boon **after** those requirements are met. This behavior can be changed in the mod's in-game menu.

If there is no `ForcedBoon` the game is ordinarily designed to offer 1 of 12 boons for the first boon of the run. These include the nine Olympian gods, Selene, Hermes, and Daedalus Hammer. If you choose a new first boon using this mod, the seed's intended first boon will be overridden. If Hermes and/or Selene are set to be deferred by this mod and they were intended as the first boon of a run's seed, the game will instead determine a new first boon.

## How do I use it?

Open your inventory before a run. There's a new tab called **First Boon**. Click a boon. This will now be the first boon you receive during your next run (barring any additional factors like equipped keepsake or required `ForcedBoon`). There are 5 settings on the top row of the menu but can be ignored. Default settings are recommended but options are available to suit your preferences.

All options are also editable in `Adicon-SelectFirstBoon.cfg` and the ReturnOfModding menu bar under Adicon-SelectFirstBoon. 

## Who you can pick

**The nine Olympians, Daedalus Hammer, Hermes, and Selene** -- the boons that are offered as first room rewards in vanilla state.

**Chaos** -- normally offers a ground boon but not first and only in his own rooms. 

**Artemis, Athena, Dionysus, Hades, Arachne, Circe, Echo, Icarus, Medea, and Narcissus.**  -- those who give boons in the game but only through NPCs not as ground drops. These may only show up as first rewards--they will never be offered from shops or from other rooms unless another mod alters this behavior. You will still be able to meet them later and receive a boon from them like normal. Because these characters do not ordinarily have ground emblems for their rewards, existing in-game art was used to create ground boons for them. 

## Settings worth knowing about

There are around sixty. Most of them are cosmetic dials you'll never touch. These are the ones that change behaviour:

| Setting | Default | What it does |
|---|---|---|
| `God` | none | Your pick. Same thing the tab sets. |
| `KeepPickAfterRestart` | off | Off means your pick is forgotten when you close the game, so every session starts vanilla. |
| `BlockHermesBeforeBoon` | on | Holds Hermes back until you've taken a boon. |
| `BlockSeleneBeforeBoon` | on | Same for Selene. |
| `KeepsakeWins` | on | An equipped keepsake beats your pick, for the whole run. It's a thing you chose to equip, so it should win. |
| `PriorityFirstReward` | on | Makes the first reward a boon at all, the way a god keepsake does. |
| `Enable<God>` | on | One per added god. Off removes that god from the picker. |
| `AddedGodsOnlyWhenPicked` | on | Stops added gods leaking into the game's own random roll. Leave this on. |

## Compatibility

Built to sit alongside other mods and defer to them if necessary. It reads the game's own decisions and only changes the last step. Anything else touching rewards will get priority. 

**Droppable Gods**, or anything else built on **GodsAPI by zannc**, makes some of the same extra boons made droppable by this mod droppable for a whole run. If you have it installed, this mod won't add a copy of its own versions of those extra reward givers, it will defer to the assets packaged with GodsAPI.

## If something goes wrong
 
This mod has numerous moving parts and conditional elements that have required quite a bit of testing and debugging. Implementing a native in-game menu and allowing reward behavior ordinarily unallowed by the game created numerous challenges to work through. If you encounter any bugs or unexpected behavior, please submit an Issue to this repo so I can explore the problem.
Check `LogOutput.log`. This thing narrates what it's doing and, more usefully, why it decided not to do something. The per-decision trace is the **Verbose logging** switch (`LogDecisions`), and it ships on. Leave it on if you ever intend to report a bug: the run only makes that decision once, and once it's over there's nothing left to look at.

There's also `SAVE_RECOVERY.md` in this folder. It covers backing up your Hades II save, and what to do if a save ever won't load. Worth two minutes before you need it. Not specific to this mod, and the short version is: the game keeps a backup of your current run for you, and most people never find out.

## Other files here

`TECHNICAL.md` is a long writeup of how Hades II's reward pipeline actually works, with line references into the game's own scripts. If you're modding this game, some of it will save you an afternoon.

`HISTORY.md` is the version by version account, including the parts that went wrong.

## Credits and licence
Hades II is by [Supergiant Games](https://www.supergiantgames.com/). This is an
unofficial fan mod, not endorsed by or affiliated with them. The icon is a
cropped in-game portrait.

Built on [ReturnOfModding / Hell2Modding](https://github.com/SGG-Modding), with
`SGG_Modding-ModUtil` and `SGG_Modding-ReLoad`.

Thank you to the Hades Modding community!

Built by **Adicon**, with Claude.
