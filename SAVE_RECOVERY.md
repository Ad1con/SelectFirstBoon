# Recovering a Hades II save

This document exists because it happened once, during development of this mod, and
the fix took about ninety seconds once the cause was understood. It is written so
that nobody has to work that out under pressure.

None of it is specific to SelectFirstBoon. A Hades II save can be damaged by any
crash that lands mid-write, from any cause. Everything below is the game's own file
layout, not something this mod adds.

---

## Back your save up first — it takes a minute

Do this now, before you need it. Your saves live at:

```
C:\Users\<you>\Saved Games\Hades II\
```

Copy the **whole folder** somewhere outside it to another drive, a cloud folder,
anywhere. The files that matter:

| File | What it is |
|---|---|
| `Profile1.sav` | **your profile.** Every unlock, Arcana, resource, all meta progression |
| `Profile1.sav.bak` … `.bak7` | the game's own rolling backups of the above |
| `Profile1_Temp.sav` | **the run currently in progress**, and nothing else |
| `Profile1_Temp.sav.bak` | the previous checkpoint of that run |
| `Profile1.sjson`, `Profile1.ctrls`, `Profile1.v.sav` | settings, controls, version stamp |

The distinction that matters: **`Profile1.sav` is your account, `Profile1_Temp.sav`
is one run.** Losing the second costs you a run. Losing the first costs everything.

Take a copy before anything experimental — a new mod, a new build, an untested
option. Zip the folder and put the date in the name.

---

## Symptoms

One or both of these:

- A dialog on launch: **"NOTICE: CORRUPTED SAVE DATA"**, offering to restore a
  recent backup.
- The profile loads fine, but **entering the run crashes** or refuses to load.

And in `Hades II.log`, in the same folder as the saves:

```
Main.lua:572: can't load: extra data at end
SaveLoad Error: Code: SaveErrorCorrupt, FileName: Profile1_Temp.sav
```

**Read the `FileName`.** It is almost always `Profile1_Temp.sav` (the run, not the
profile) because that file is written far more often and so is far likelier to be
the one caught mid-write.

---

## Press OK on the in-game dialog

If you get the corrupted-save dialog, **press OK**. It restores a recent backup. It
is easy to dismiss it, find that the profile loads anyway, and conclude the dialog
was noise. It isn't.

Know its limit, though: with the game's default `BackupSaveCount = 1`, that restore
covers the **profile**. In the case observed here it did not replace
`Profile1_Temp.sav`, which was the actually-broken file — so the profile came back
and entering the run still crashed. If that happens, carry on below.

---

## Fixing a damaged `Profile1_Temp.sav`

**Close Hades II completely first** Not just the error dialog, the whole process.
Nothing below is safe against a running game.

### 1. See what each file holds

Every `.sav` starts with a readable header containing a `DevSaveName` line. Open the
file in a text editor; most of it is binary, but that line is plain text:

```
Profile1_Temp.sav      DevSaveName=Run 132, Depth 1, N_Opening01, OpeningGeneratedN (Boon - ...)
Profile1_Temp.sav.bak  DevSaveName=Run 132, Depth 1, N_Opening01, OpeningGeneratedN (PostReward)
```

That tells you which run each file holds and how far into it you are. In the example
both are the **same run in the same room** The `.bak` is the checkpoint immediately
before.

### 2. Check whether the `.bak` is intact

A save interrupted mid-write has a characteristic signature: **a long run of `0xFF`
bytes near the end of the file**, with real data resuming after it. That is Windows
having sized the file and written its tail, with a block in the middle never
reaching disk before the process died.

In the observed case the damaged file had **2,965 consecutive `0xFF` bytes** starting
around 95% of the way through. A healthy save's longest repeated-byte run in that
region is a handful of zeros.

The payload is compressed, so those missing bytes make everything after them
undecodable. **A file with that signature cannot be repaired** The data was never
written, so there is nothing to recover.

If you are comfortable with a terminal, this prints the longest repeated-byte run in
the last few KB of each file:

```
python -c "
import sys
for f in sys.argv[1:]:
    d = open(f,'rb').read(); tail = d[-4000:]
    best = (0,0); run = 1
    for i in range(1,len(tail)):
        if tail[i]==tail[i-1]:
            run += 1
            if run > best[0]: best = (run, tail[i])
        else: run = 1
    print('%-26s %8d bytes   longest tail run: %d of 0x%02X' % (f, len(d), best[0], best[1]))
" Profile1_Temp.sav Profile1_Temp.sav.bak
```

A result in the thousands means that file is the damaged one. Single digits mean it
is fine.

### 3. Promote the backup

If `Profile1_Temp.sav.bak` is intact and holds the run you want:

1. Copy `Profile1_Temp.sav` somewhere safe first — don't delete evidence you haven't
   finished looking at.
2. Copy `Profile1_Temp.sav.bak` **over** `Profile1_Temp.sav`.
3. Leave the `.bak` where it is. Copy it, don't rename it.
4. Start the game.

You lose whatever happened between the two checkpoints, usually one room or one
reward. The run survives.

### 4. If the backup is no good either

Delete or rename `Profile1_Temp.sav`. The game treats its absence as **"no run in
progress"**, which is a completely normal state It is what exists after every run
ends. You start fresh from the Crossroads with your profile untouched.

That costs the run and nothing else.

### 5. If `Profile1.sav` itself is damaged

Much rarer, and much more worth caring about. The game keeps eight rolling backups,
`Profile1.sav.bak` through `.bak7`. Check their `DevSaveName` headers and run the
`0xFF` test above, then copy the newest healthy one over `Profile1.sav`.

If Steam Cloud is enabled it may also hold a copy from before the damage.

---

## The crash this came from

For the record, because "one unexplained crash" deserves detail rather than a vague
warning.

A first boon was taken from an added god. Twenty-two seconds later, with nothing
unusual in between, the process died:

```
16:54:24  boon spawned
16:54:46  EXCEPTION_ACCESS_VIOLATION

[0] ltable.cpp:483    luaH_get
[1] lvm.cpp:116       luaV_gettable
[2] lvm.cpp:546       luaV_execute
[3] ldo.cpp:429       unroll
[5] ldo.cpp:535       lua_resume
[7] lcorolib.cpp:53   luaB_coresume
```

A table lookup inside the Lua VM, inside a coroutine being resumed after a yield,
reading through memory that was no longer valid. Faults of that shape come from
garbage collection reclaiming something still referenced, a thread resumed after its
state has gone, or heap corruption from elsewhere All of those are timing-dependent, and none
of them is a property of boon data. The same log shows that god's asset package loaded
normally in the crashing run.

It has never reproduced. That god was taken four more times afterwards in deliberate
tests, including the specific boon that was blamed, with its trigger condition met,
and every one of those runs was clean.

The honest summary: **a rare, timing-dependent fault that this mod cannot cause and
cannot prevent.** It happened once in development and cost one run. It is written
up here because the recovery is easy when you know it and miserable when you don't.

Back your saves up.
