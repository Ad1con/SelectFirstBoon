# Select First Boon

Pick which god offers the first boon of your run. Your choice is made in-game using an additional tab in the inventory screen. Options include **all boon givers** including those who ordinarily do not give boons this way (e.g., Circe, Athena, Hades, Chaos, etc.)

This mod is intended to interfere as little as possible with vanilla behavior of the game except to force one boon of your choosing or to defer the appearance of two often undesirable first boon offerings (i.e. Hermes and Selene) until you have taken a boon or a Daedalus Hammer.

This mod does not change the seed of your run, but receiving a boon unintended by the game will of course influence which boons are offered in future rooms. This mod uses only native assets shipped with the game.


## Game behavior (Why aren't I getting the boon I set?)

In vanilla state, the game will first offer any boon it has already scripted for that room. These are usually forced for story/progression reasons or for Chaos Trials. By default, this mod defers to anything the game has scripted and offers your choice of first boon **after** those requirements are met. This behavior can be changed in the mod's in-game menu.

**An equipped god keepsake also claims the first boon**, because that is what a keepsake is for. By default this mod stands down for the whole run when one is equipped (`KeepsakeWins`). Turn that off and you get both: the keepsake takes the first boon and your pick takes the next one. If your keepsake and your pick name the same god, one boon satisfies both -- you get that god once, not twice. The panel on the right of the tab always states what the first boon will actually be, keepsake included.

If the game has scripted nothing, it is ordinarily designed to offer 1 of 12 rewards as the run's first boon. These include the nine Olympian gods, Selene, Hermes, and Daedalus Hammer. If you choose a new first boon using this mod, the seed's intended first boon will be overridden. If Hermes and/or Selene are set to be deferred by this mod and they were intended as the first boon of a run's seed, the game will instead determine a new first boon.

## How do I use it?

Open your inventory before a run. There's a new tab called **First Boon**. Click a boon. That is now your pick, and it governs the **first** boon of your next run (barring any additional factors like an equipped keepsake or a boon the game has scripted). Once that boon has been given, this mod is finished for the run -- changing the pick after that applies to the run after. The top row holds Standard -- which means "leave the game alone" -- and four switches: the two delays, Always First, and a master off switch. Defaults are recommended, but they are all there to suit your preferences.

All options are also editable in `Adicon-SelectFirstBoon.cfg` and the ReturnOfModding menu bar under Adicon-SelectFirstBoon. 

## Who you can pick

**The nine Olympians, Daedalus Hammer, Hermes, and Selene** -- the boons that are offered as first room rewards in vanilla state.

**Chaos** -- normally offers a ground boon but not first and only in his own rooms. 

**Artemis, Athena, Dionysus, Hades, Arachne, Circe, Echo, Icarus, Medea, and Narcissus.**  -- those who give boons in the game but only through NPCs not as ground drops. These may only show up as first rewards--they will never be offered from shops or from other rooms unless another mod alters this behavior. You will still be able to meet them later and receive a boon from them like normal. Because these characters do not ordinarily have ground emblems for their rewards, existing in-game art was used to create ground boons for them. 

## Settings worth knowing about

There are around 180. Most of them are cosmetic dials you'll never touch. These are the ones that change behaviour:

| Setting | Default | What it does |
|---|---|---|
| `God` | none | Your pick. Same thing the tab sets. |
| `KeepPickAfterRestart` | off | Off means your pick is forgotten when you close the game, so every session starts vanilla. |
| `BlockHermesBeforeBoon` | on | Holds Hermes back until you've taken a boon or a hammer. |
| `BlockSeleneBeforeBoon` | on | Same for Selene. |
| `KeepsakeWins` | on | An equipped keepsake beats your pick, for the whole run. It's a thing you chose to equip, so it should win. |
| `AlwaysFirst` | off | On, your pick overrides even a boon the game had scripted for that room. That breaks encounters built around a specific opening, and it breaks them quietly, so it ships off. |
| `DisableEverything` | off | The master switch. On, this mod does nothing at all and everything you have set is remembered for when you turn it back off. |
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

Built on [ReturnOfModding / Hell2Modding](https://github.com/SGG-Modding). This
mod cannot load without `SGG_Modding-ModUtil`, `SGG_Modding-SJSON` and
`LuaENVY-ENVY` -- the function wrapping, the art registration and the
environment isolation are all theirs.

Thank you to the Hades II modding community, and to **SGG_Modding** for those
libraries and the [wiki](https://sgg-modding.github.io/Hades2ModWiki/), to
**zannc** for GodsAPI, and to **PonyWarrior** and **adamantSpeedrun**, whose
published mods are how I learned how this is done.

Built by **Adicon**, with Claude.
