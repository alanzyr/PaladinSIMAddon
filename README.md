# Forever Ret Sim

A **Retribution Paladin** DPS simulator **inside the game**, for World of Warcraft: Forever. It reads your character -
talents, race, weapon and the numbers on your character sheet - plays a few hundred fights in the background and shows
your DPS and what each ability contributes.

It is the in-game version of the website [Forever Ret-sim](https://alanzyr.github.io/Forever-Ret-Sim/) and plays the same
fights, to the last digit.

## A fork of Xn's Warlock Sim

This addon is a fork of [Xn's Warlock Sim](https://github.com/XNWLK/WarlockSIMAddon) by **Xn**, made for paladins with
Xn's permission. Credit for the foundation goes to Xn:

- the layout of the addon and the way its parts fit together,
- the careful way of reading a character from the Forever client,
- the job that plays fights a little every frame so the game never freezes,
- the random number generator in Lua, and
- the test tools that run the addon's code outside the game.

What is new here is the paladin side: the fight rules of the Ret sim carried over to Lua, the reading of a paladin's
character sheet and weapon, and the window.

If you play a Warlock, you want Xn's addon: [CurseForge](https://www.curseforge.com/wow/addons/xns-warlock-sim) or the
[original repository](https://github.com/XNWLK/WarlockSIMAddon). This repository only holds the paladin addon, in the
folder `RetSim`.

> **Status: version 0.8, a test version.** It reads your character, plays the fights, shows your DPS with a line per
> damage source, and sims a single item against what you wear. Built for the WoW: Forever client (interface 16001).

## Install

1. Download this repository as a zip: <https://github.com/alanzyr/PaladinSIMAddon/archive/refs/heads/main.zip>
2. Copy the folder `RetSim` from it into `World of Warcraft\_forever_\Interface\AddOns`, so that there is a folder
   `AddOns\RetSim`.
3. Restart the game and tick **Forever Ret Sim** in the AddOns list.
4. Click the minimap button to sim your character, or type `/rsim` to open the window; Escape closes it.

The addon only loads on a Paladin. On another class it says so in chat and does nothing else.

## The first test

What the game returns for a paladin has not been seen yet, so the first thing to do is this, out of combat and
**without raid buffs if you can**:

1. `/rsim test` - the maths check. It should say that the addon plays the same fights as the website.
2. `/rsim` opens the window; press **Sim**.
3. `/rsim dump` opens a window with text. Click in it, Ctrl+A, Ctrl+C, and send the text.

The dump holds what the game returned (stats, talents, weapon, buffs) and what the sim made of it. It contains your
character's level and race, not its name.

## What it does

- **A minimap button:** click it and your character is read and simmed, no typing. Right-click opens or closes the
  window; drag it to move it around the minimap.
- **Sim your character:** your DPS with its margin, the lowest and highest fight, and a line per damage source with its
  share.
- **Rotations:** the best seal twist for your weapon is picked automatically, or choose one yourself: 3x Seal of Command
  into Seal of Righteousness, 2x Righteousness into Command, 3x Righteousness into Fury, one seal only, or Shockadin.
- **Sim an item:** Shift + right-click an item in your bags, on your character sheet, at a vendor or in a loot or quest
  window - how much DPS it would gain or lose you against what you wear in its slot (a ring or trinket against each of
  the two). Click an item link in chat and a **Sim this item** button sits under its window; a small **Sim** button sits
  beside every Need / Greed popup. The same fights are played on both sides, so small differences show.
- **Export to the website:** `/rsim export` or the **Export** button makes a code of everything you wear with its
  enchants, your talents, race and rotation. Paste it on the [website](https://alanzyr.github.io/Forever-Ret-Sim/) under
  **Import > Addon** and your character is set up there.
- **Settings from the website:** set up raid buffs, debuffs, consumables, the encounter and the rotation on the
  [website](https://alanzyr.github.io/Forever-Ret-Sim/), choose **Export > Addon settings** there and paste the code in the
  addon with **Import**. The fights are then played with those settings, consumables included. **Settings code** makes the
  same kind of code from the addon, for the website's **Import > Addon**.
- **Gear list:** build the set you are aiming for on the [website](https://alanzyr.github.io/Forever-Ret-Sim/), choose
  **Export > Addon gear list** there and paste the code in the addon with **Import**. **Gear list** (or `/rsim list`) then
  shows every piece, where it comes from, the enchant it should carry, and whether you wear it, have it in your bags
  or still miss it. The list is kept between sessions and follows your bags and gear while it is open.
- **Raid buffs and debuffs** on or off in one click.
- **Your weapon and its enchant:** damage and speed from the tooltip; Blade of Hanna's proc and Libram of Law are played
  in the fight.
- **Procs are played in the fight:** the "Chance on hit" effects of weapons, the procs of trinkets and other slots, the
  weapon enchants (Crusader, the Forever "Grand" enchants, Fiery Blaze) and set bonuses that proc. The table (`RS.PROCS`
  in `Data.lua`) is the website's; an item sim follows a proc or set bonus gained or lost with the swap.

On-use trinkets and the combat potion are used at the pull and again whenever they are ready.

Not there yet: a line per proc in the result window, stat weights, and a window to change single
settings inside the game (for now they come from the website with a settings code).

### Consumables

Consumables are settings, not something read from your character: the ones in your settings are added on top of what
the character sheet shows. So read your character **without** flask, elixirs and food on you - a consumable that is
both on you and in your settings is counted twice. The window names the consumables it is counting.

### Sim an item

The panel that opens tells you the difference in DPS and what was counted ("+18 Strength, +28 Crit Rating, weapon
152-255 at 3.60").

- **An item you are wearing** is simmed against an empty slot: what the item is worth to you.
- **A two-hand weapon** brings its damage and speed with it; with the rotation on auto, each side plays its own best twist.
- **Your enchant on the slot** is taken to move to the new item. Set bonuses are not counted, and "Use:" and "Chance on
  hit:" effects are named, not simulated.
- One-hand weapons, shields and off-hand items are not compared: the sim plays two-hand weapons only.

`/rsim click off` switches the click off if Shift + right-click is taken by another addon.

## Commands

| Command | |
|---|---|
| `/rsim` | Opens or closes the window (`/retsim` works too). |
| `/rsim sim` | Reads your character and sims it. |
| `/rsim mode auto` | The rotation: `auto`, `socSor`, `sorSoc`, `sorFury`, `socOnly`, `sorOnly`, `shock`. |
| `/rsim fights 500` | How many fights a sim plays (300 to begin with). |
| `/rsim buffs on` / `off` | The usual raid buffs and debuffs, or none. |
| `/rsim item [link]` | Sims the item whose link you Shift-click into the chat line. |
| `/rsim click on` / `off` | Shift + right-click on an item sims it, or not. |
| `/rsim export` | A code of your gear, enchants, talents, race and rotation for the website (Import > Addon). |
| `/rsim minimap` | Shows or hides the minimap button. |
| `/rsim settings` | A code of your raid buffs, debuffs, consumables, encounter and rotation, for the website. |
| `/rsim import` | Opens a window to paste a settings code from the website (Export > Addon settings). |
| `/rsim reset` | Every setting back to the website's defaults. |
| `/rsim test` | The maths check against the website. |
| `/rsim dump` | What the game returned, as text to copy. |

## How your character is read

The character sheet shows totals: gear, enchants, talents and whatever buffs are on you in one number. The sim adds
talents and raid buffs itself, so the addon takes them off again and keeps "base + gear" (`RetSim/Character.lua`).
Buffs it knows (Kings, Might, Wisdom, Mark of the Wild, Arcane Intellect, Battle Shout, the totems, Leader of the Pack,
Moonkin Aura) are taken off; any other buff on you counts as part of your gear and is named in the window.

Nothing is read in combat: the Forever client hides your numbers from addons then. A sim started in combat uses the
character as it was read last.

Which talents and racials the sheet's numbers already hold is set in one place, `RS.SHEET` in `Character.lua`. These are
assumptions until the first dump confirms them.

## For maintainers

The addon holds a copy of the website's data (`RetSim/Data.lua`, generated) and a function-by-function port of its
engine (`RetSim/Engine.lua`, `RetSim/Sim.lua`). With the website's repository
([Forever-Ret-Sim](https://github.com/alanzyr/Forever-Ret-Sim)) in a folder called `repo` next to this one, or
`RETSIM_HTML` pointing at its `ret-sim.html`:

```
cd tools
npm install                  # once: the Lua runner the checks use
node gen-ret-data.js         # the website's data -> RetSim/Data.lua and RetSim/Expected.lua
node check-ret-items.js      # every item of the website through the addon's item reader
node check-ret-export.js     # the export code, made by the addon and read back the way the website does
node check-ret-settings.js   # consumables against the website's, and settings codes both ways
node check-ret-engine.js     # the same fights in both engines ("full" for more); takes a few minutes
node check-ret-addon.js      # the whole addon against a stand-in for the game
```

A changed fight rule on the website has to be carried into `Sim.lua` / `Engine.lua` by hand; `check-ret-engine.js` fails
until it is. `lua-host.js`, `lua-ser.js` and `wow-mock.lua`
in `tools` are Xn's: the Lua runner and the stand-in for the game that the checks use.

## Notice

World of Warcraft and Warcraft are trademarks of Blizzard Entertainment, Inc. This is a fan project, not affiliated
with or endorsed by Blizzard. Spell names, values and icons belong to their owner.
