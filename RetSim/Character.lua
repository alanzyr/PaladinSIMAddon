-- From a character as the game shows it to the settings the sim plays. No game API in this file (Reader.lua does the
-- reading); tools/check-ret-addon.js runs it outside the game.
--
-- The character sheet shows totals: gear, enchants, talents and whatever buffs are on you, all in one number. The sim
-- adds talents and raid buffs itself, so they are taken off again here and what is left is "base + gear".
--   RS.valuesFromSheet(character, settings) -> the sim's settings for this character, and a list of notes
local ADDON, RS = ...
if RS.notPaladin then return end

local max = math.max

-- What the character sheet's numbers already hold. These are the points the first test in the game has to confirm;
-- each can be switched without touching the formulas below.
RS.SHEET = {
  critHasConviction = true,     -- melee crit includes the Conviction talent
  critHasRace = true,           -- melee and spell crit include the Human racial (+1%)
  hitHasPrecision = true,       -- melee and spell hit include the Precision talent
  hitHasRace = true,            -- hit includes the Dwarf racial (+1%)
  spellHitHasDivinePrecision = true,
  spHasChampion = true,         -- Holy spell power includes Champion of the Light (a share of Intellect)
}

-- Main-hand enchants that are a timed buff: Strength or spell power for a while (enchant id -> what and how long).
-- Counted as an average: the Crusader uptime from the settings, stretched to the buff's length.
local PROC_ENCHANTS = {
  [1900] = { str = 100, dur = 15 },   -- Crusader
  [7940] = { str = 120, dur = 20 },   -- Grand Crusader
  [7943] = { str = 200, dur = 20 },   -- Grand Inquisitor
  [7941] = { sp = 140, dur = 20 },    -- Grand Arcanist
  [7942] = { sp = 70, dur = 20 },     -- Grand Sorcerer
}
RS.BLADE_OF_HANNA, RS.LIBRAM_OF_LAW = 2801, 272435

function RS.valuesFromSheet(ch, settings)
  local notes = {}
  local sheet, on, worn = ch.sheet, ch.buffsOnYou or {}, ch.worn or {}
  local v = {}
  for k, x in pairs(RS.DEFAULTS) do v[k] = x end
  for k, x in pairs(settings or {}) do v[k] = x end        -- your own choices: buffs, encounter, rotation options
  v.race = ch.raceKey
  RS.applyTalents(v, ch.talents or {})
  local H = RS.SHEET
  local human, dwarf = ch.raceKey == 'human' and 1 or 0, ch.raceKey == 'dwarf' and 1 or 0
  local kings = on.kings and 1.1 or 1

  -- Strength, Intellect, Agility: buffs off, then the talent's share off
  local strNoBuff = sheet.str / kings - (on.soe and 52 or 0) - (on.motw and 12 or 0)
  local intNoBuff = sheet.int / kings - (on.arcInt and 39 or 0) - (on.motw and 12 or 0)
  v.str = strNoBuff / (1 + v.divineStrength / 100)
  v.int = intNoBuff / (1 + v.divineIntellect / 100)
  local agiFromBuffs = sheet.agi and (sheet.agi - (sheet.agi / kings - (on.goa and 80 or 0) - (on.motw and 12 or 0))) or 0

  -- Attack Power from gear: the total minus 160, minus two per point of Strength, minus the buffs on you
  v.apGear = sheet.ap - 160 - 2 * sheet.str - (on.might and 133 or 0) - (on.battleShout and 94 or 0)

  v.crit = sheet.crit - (on.lotp and 3 or 0) - agiFromBuffs / v.agiPerCrit
    - (H.critHasConviction and v.conviction or 0) - (H.critHasRace and human or 0)
  v.hit = sheet.hit - (H.hitHasPrecision and v.precision or 0) - (H.hitHasRace and dwarf or 0)
  v.exp = sheet.exp or 0
  v.spellHit = (sheet.spellHit or 0) - (H.hitHasPrecision and v.precision or 0) - (H.spellHitHasDivinePrecision and v.divinePrecision or 0) - (H.hitHasRace and dwarf or 0)
  v.sp = sheet.spHoly - (H.spHasChampion and v.champion / 100 * sheet.int or 0)
  v.holyOnly = max(0, sheet.spHoly - (sheet.spAll or sheet.spHoly))      -- spell power that only counts for Holy
  v.spellCrit = sheet.spellCrit - (H.critHasConviction and v.conviction or 0) - (H.critHasRace and human or 0)
    - (on.moonkin and 3 or 0) - (sheet.int - 70) / 59.9
  v.mana = sheet.maxMana - (sheet.int - v.int) * v.manaPerInt
  v.mp5 = (sheet.mp5 or 0) - (on.bow and 36 or 0) - (on.manaSpring and 25 or 0)
  v.haste = sheet.haste or 0

  -- the weapon
  if sheet.wMin and sheet.wMax and sheet.wSpeed then v.wMin, v.wMax, v.wSpeed = sheet.wMin, sheet.wMax, sheet.wSpeed
  else notes[#notes + 1] = 'Your weapon could not be read: the website\'s default weapon is used (' .. v.wMin .. '-' .. v.wMax .. ' at ' .. v.wSpeed .. ').' end

  -- items and enchants with an effect of their own in the fight
  v.hanna = worn.mainHand == RS.BLADE_OF_HANNA
  v.judgeMult = worn.relic == RS.LIBRAM_OF_LAW and 1.04 or 1
  local pe = worn.mainEnchant and PROC_ENCHANTS[worn.mainEnchant]
  if pe then
    local up = 1 - (1 - v.crusaderUptime / 100) ^ (pe.dur / 15)
    if pe.str then v.str = v.str + pe.str * up end
    if pe.sp then v.sp = v.sp + pe.sp * up end
  end

  -- a number below zero means the sheet held less than was taken off: say so and stop at zero
  local FLOOR = { apGear = 'Attack Power from gear', crit = 'melee crit', hit = 'hit', spellHit = 'spell hit', sp = 'spell power', spellCrit = 'spell crit', mp5 = 'mana per 5 s', mana = 'mana' }
  for k, label in pairs(FLOOR) do
    if v[k] < -0.05 then notes[#notes + 1] = 'Your ' .. label .. ' came out below zero (' .. string.format('%.1f', v[k]) .. ') after talents and buffs were taken off; it counts as 0.' end
    if v[k] < 0 then v[k] = 0 end
  end
  -- your settings on top, as the website does after gear: consumables, and another paladin's Judgement of the Crusader
  RS.applyConsumables(v)
  if v.jotcExt then v.opener = false end
  if ch.otherAuras and #ch.otherAuras > 0 then
    notes[#notes + 1] = 'Other buffs on you count as part of your gear: ' .. table.concat(ch.otherAuras, ', ') .. '.'
  end
  return v, notes
end

-- The sim's totals for a set of values, to put beside the character sheet (My DPS and /rsim dump).
function RS.totals(v)
  local c = RS.derive(v)
  return { str = c.strF, int = c.intF, ap = c.ap, crit = c.crit + v.critSupp, hit = c.hitF, spHoly = c.sp + c.champSP, spellCrit = c.spellCrit, mana = c.mana }
end
