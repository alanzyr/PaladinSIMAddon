# Forever Ret Sim (addon)

A Retribution Paladin DPS simulator inside the game, for World of Warcraft: Forever. It is the in-game version of the
website [Forever Ret-sim](https://alanzyr.github.io/Forever-Ret-Sim/) and plays the same fights, to the last digit.

Built on [Xn's Warlock Sim](https://github.com/XNWLK/WarlockSIMAddon), with Xn's permission: the layout of the addon, the
careful way of reading the character, the job that plays fights a little every frame and the test tools are Xn's work.
The folder `WarlockSim` is Xn's addon, kept here as it is; the Ret addon is the folder `RetSim`.

**Status: version 0.1, a first test version.** It reads your character, plays the fights and shows your DPS with a line
per damage source. What the game returns for a paladin has not been seen yet, so the first thing to do is the test below.

## Install

1. Download this branch as a zip: <https://github.com/alanzyr/PaladinSIMAddon/archive/refs/heads/ret-sim.zip>
2. Copy the folder `RetSim` from it into `World of Warcraft\_forever_\Interface\AddOns`, so that there is a folder `AddOns\RetSim`.
3. Restart the game and tick **Forever Ret Sim** in the AddOns list.

## The first test

On your paladin, out of combat, **without raid buffs if you can**:

1. `/rsim test` - the maths check. It should say that the addon plays the same fights as the website.
2. `/rsim` opens the window; press **Sim**.
3. `/rsim dump` opens a window with text. Click in it, Ctrl+A, Ctrl+C, and send the text.

The dump holds what the game returned (stats, talents, weapon, buffs) and what the sim made of it. It contains your
character's level and race, not its name.

## Commands

| Command | |
|---|---|
| `/rsim` | Opens or closes the window (`/retsim` works too). |
| `/rsim sim` | Reads your character and sims it. |
| `/rsim mode auto` | The rotation: `auto`, `socSor`, `sorSoc`, `sorFury`, `socOnly`, `sorOnly`, `shock`. |
| `/rsim fights 500` | How many fights a sim plays (300 to begin with). |
| `/rsim buffs on` / `off` | Every raid buff and debuff on or off. |
| `/rsim test` | The maths check against the website. |
| `/rsim dump` | What the game returned, as text to copy. |

## How your character is read

The character sheet shows totals: gear, enchants, talents and whatever buffs are on you in one number. The sim adds
talents and raid buffs itself, so the addon takes them off again and keeps "base + gear" (`RetSim/Character.lua`).
Buffs it knows (Kings, Might, Wisdom, Mark of the Wild, Arcane Intellect, Battle Shout, the totems, Leader of the Pack,
Moonkin Aura) are taken off; any other buff on you counts as part of your gear and is named in the window.

Which talents and racials the sheet's numbers already hold is set in one place, `RS.SHEET` in `Character.lua`. These are
assumptions until the first dump confirms them.

Not read yet: consumables as settings, set bonuses that are procs, trinkets.

## For maintainers

With the website's repository next to this one (`../repo/ret-sim.html`, or `RETSIM_HTML` pointing at the file):

```
cd tools
npm install                  # once: the Lua runner the checks use
node gen-ret-data.js         # the website's data -> RetSim/Data.lua and RetSim/Expected.lua
node check-ret-engine.js     # the same fights in both engines ("full" for more); takes a few minutes
node check-ret-addon.js      # the whole addon against a stand-in for the game
```

`RetSim/Engine.lua` and `RetSim/Sim.lua` are a function-by-function port of the website's engine. A changed fight rule on
the website has to be carried over by hand; `check-ret-engine.js` fails until it is.
