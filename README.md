# Select First Boon

Pick which god offers the first boon of your run.

That's it. That's the mod.

## What it actually does

You still walk into the boon room. You still get three options. It still happens at the normal time. The only thing that changes is **whose** boon it is.

It is not a boon spawner and it is not a cheat menu. Nothing is added to your run that wasn't going to be there.

You can also do the opposite, and tell the game what you *don't* want first. Hermes and Selene both love turning up as your opening reward, and if that annoys you there are two switches that hold them back until you've taken an actual boon.

## Setting it

Open your inventory in a run. There's a new tab called **First Boon**. Click a god, done. It takes effect at the very next door, so you can change your mind mid run without restarting anything.

Everything is also in the ReturnOfModding menu bar under SelectFirstBoon, and in `Adicon-SelectFirstBoon.cfg` if you'd rather edit a file.

## Who you can pick

**The nine Olympians**, exactly as the game gives them to you.

**Four other rewards** that aren't boons but can be first anyway: a Daedalus Hammer, Hermes, Selene, and Chaos. Chaos normally only shows up in his own rooms, so that one's a bit of a treat.

**Ten more gods** who give boons in the game but never as a room reward: Artemis, Athena, Dionysus, Hades, Arachne, Circe, Echo, Icarus, Medea and Narcissus. These ship **off**, one switch each, because ten extra faces appearing unasked isn't what you signed up for. Turn on the ones you want.

Those ten are a first reward only. Meeting them normally in a run works exactly as it always did, and their boons stay rarity based rather than becoming pom fodder, same as in the base game.

## What's with all the glow?

Fair question. This mod ships no image files at all, so every icon is art that's already in your game. Trouble is, no single set of art in Hades II covers everything on offer here. Six of the gods have no boon symbol, so they borrow their keepsake portrait instead, and those come with no glow painted on where the symbols have one.

So the mod adds a glow to them at runtime, tinted from each character's own colour. It gets close. It doesn't get all the way, and the whole thing ends up brighter and less even than it would be if someone had drawn a proper matching set.

That's why nearly every glow, halo and size value is a setting you can change. No single default looked right on all of them, so they're all yours to move.

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
| `Enable<God>` | off | One per added god. |
| `AddedGodsOnlyWhenPicked` | on | Stops added gods leaking into the game's own random roll. Leave this on. |

## Compatibility

Built to sit alongside other mods rather than fight them. It reads the game's own decisions and only changes the last step, so anything else touching rewards should still get its say.

Known to run happily with the Speedrun Modpack, PonyMenu, and the rest of a fairly loaded profile.

If something else has already decided what a door gives you, this mod stands down and says so in the log.

## If something goes wrong

Check `LogOutput.log`. This thing narrates what it's doing and, more usefully, why it decided not to do something.

There's also `SAVE_RECOVERY.md` in this folder. It covers backing up your Hades II save, and what to do if a save ever won't load. Worth two minutes before you need it. Not specific to this mod, and the short version is: the game keeps a backup of your current run for you, and most people never find out.

## Thanks

Sincere gratitude to the Hades II modding community, and particularly to **SGG_Modding** for Chalk, ModUtil, SJSON and ENVY, without which this plugin cannot load, **adamantSpeedrun** for the Speedrun Modpack, **zannc** for Droppable Gods, and **PonyWarrior**. None of their code is in here, but I learned how this is done by reading what they published, and this wouldn't exist otherwise.

Thank you! You all are incredible.

## Other files here

`TECHNICAL.md` is a long writeup of how Hades II's reward pipeline actually works, with line references into the game's own scripts. If you're modding this game, some of it will save you an afternoon.

`HISTORY.md` is the version by version account, including the parts that went wrong.

## Credits and licence

Built by **Adicon**, with Claude.

MIT licensed. Use it, change it, put it in your modpack. Just keep the copyright line.
