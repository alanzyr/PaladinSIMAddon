-- The Ret sim's rules outside the fight loop, carried over from the website's engine (ret-sim.html, between
-- "ENGINE START" and "ENGINE END") function by function: the random numbers, the rotations, talents and derive().
-- Same formulas, same order of additions, same random numbers: tools/check-ret-engine.js compares both engines fight by fight.
-- No game API in this file (it also runs outside the game in the check).
-- The random number generator and the layout of this addon come from Xn's Warlock Sim, with Xn's permission.
local ADDON, RS = ...
if RS.notPaladin then return end   -- not a Paladin: nothing of the addon loads (Class.lua)

local floor, min, max = math.floor, math.min, math.max
local bxor, bor = bit.bxor, bit.bor
local TWO32 = 4294967296

-- ---------------------------------------------------------------------------------------------------------------------
-- seeded PRNG (mulberry32). All values are kept as unsigned 32-bit numbers.
-- Written out in full (the two 32-bit multiplications and the shifts as divisions): it is called a few hundred times a
-- fight and every function call counts.
-- ---------------------------------------------------------------------------------------------------------------------
function RS.makeRng(seed)
  local a = floor(seed) % TWO32
  return function()
    a = (a + 0x6D2B79F5) % TWO32
    local x = bxor(a, (a - a % 32768) / 32768) % TWO32
    local y = bor(a, 1) % TWO32
    local xl, yl = x % 65536, y % 65536
    local t = ((((x - xl) / 65536 * yl + xl * ((y - yl) / 65536)) % 65536) * 65536 + xl * yl) % TWO32
    x = bxor(t, (t - t % 128) / 128) % TWO32
    y = bor(t, 61) % TWO32
    xl, yl = x % 65536, y % 65536
    t = bxor(t, (t + ((((x - xl) / 65536 * yl + xl * ((y - yl) / 65536)) % 65536) * 65536 + xl * yl) % TWO32) % TWO32) % TWO32
    return (bxor(t, (t - t % 16384) / 16384) % TWO32) / TWO32
  end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- rotations
-- ---------------------------------------------------------------------------------------------------------------------
RS.MODES = {
  socSor  = { name = 'Twist: 3x SoC -> SoR',  P = 'soc', R = 'sor',  N = 3, twist = true },
  sorSoc  = { name = 'Twist: 2x SoR -> SoC',  P = 'sor', R = 'soc',  N = 2, twist = true },
  sorFury = { name = 'Twist: 3x SoR -> Fury', P = 'sor', R = 'fury', N = 3, twist = true },
  socOnly = { name = 'SoC only', P = 'soc', twist = false },
  sorOnly = { name = 'SoR only', P = 'sor', twist = false },
  shock   = { name = 'Shockadin', P = 'sor', twist = false, shock = true },
}
RS.MODE_ORDER = { 'socSor', 'sorSoc', 'sorFury', 'socOnly', 'sorOnly', 'shock' }
RS.SEAL = { soc = 'Seal of Command', sor = 'Seal of Righteousness', fury = 'Seal of Fury', crusader = 'Seal of the Crusader' }

-- key 'auto': the twist found best by the last sim (autoPick), or a weapon-speed rule of thumb until then
function RS.resolveMode(key, speed, autoPick)
  local auto = key == 'auto'
  if auto then key = autoPick or (speed >= 3.3 and 'socSor' or speed >= 2.6 and 'sorSoc' or 'sorFury') end
  local m, o = RS.MODES[key], { key = key, auto = auto or nil }
  for k, x in pairs(m) do o[k] = x end
  return o
end

-- ---------------------------------------------------------------------------------------------------------------------
-- talents: ranks by talent name -> the numbers the fight uses
-- ---------------------------------------------------------------------------------------------------------------------
function RS.applyTalents(v, ranks)
  local function rk(n) return ranks[n] or 0 end
  v.divineStrength = rk('Divine Strength') * 2
  v.improvedSeals = rk('Improved Seals') * 3
  v.holyConduit = rk('Holy Conduit') * 20
  v.divinePrecision = rk('Divine Precision') * 4
  v.consecratedGround = rk('Consecrated Ground') * 5
  v.hasShock = rk('Holy Shock') > 0
  v.divineIntellect = rk('Divine Intellect') * 2
  v.precision = rk('Precision')
  v.benediction = rk('Benediction') * 2
  v.impJudge = rk('Improved Judgement')
  v.conviction = rk('Conviction') * 2
  v.sanctified = rk('Sanctified Judgement') / 3
  v.hasSoC = rk('Seal of Command') > 0
  v.sacredArbiter = rk('Sacred Arbiter') > 0
  v.twoHand = rk('Two-Handed Weapon Specialization') * 2
  v.vengRank = rk('Vengeance')
  v.champion = rk('Champion of the Light') * 12
  v.unsealedWrath = rk('Unsealed Wrath') > 0
  return v
end

-- ---------------------------------------------------------------------------------------------------------------------
-- derive(): settings + talents + gear -> the values one fight is played with
-- ---------------------------------------------------------------------------------------------------------------------
function RS.derive(v)
  local kings = v.kings and 1.1 or 1
  local bInt = (v.arcInt and 39 or 0) + (v.motw and 12 or 0)
  local bAgi = (v.goa and 80 or 0) + (v.motw and 12 or 0) + (v.kings and 6.5 / 1.1 or 0)
  local str = (v.str * (1 + v.divineStrength / 100) + (v.soe and 52 or 0) + (v.motw and 12 or 0)) * kings
  local int = (v.int * (1 + v.divineIntellect / 100) + bInt) * kings
  local ap = 160 + 2 * str + v.apGear + (v.might and 133 or 0) + (v.battleShout and 94 or 0)
  local hit = v.hit + v.precision + (v.race == 'dwarf' and 1 or 0)
  local spellHit = v.spellHit + v.precision + v.divinePrecision + (v.race == 'dwarf' and 1 or 0)
  local crit = max(0, v.crit + (v.lotp and 3 or 0) + bAgi * kings / v.agiPerCrit + v.conviction + (v.race == 'human' and 1 or 0) - v.critSupp)
  local spellCrit = max(0, v.spellCrit + v.conviction + (v.race == 'human' and 1 or 0) + (v.moonkin and 3 or 0) + (int - 70) / 59.9)
  -- tooltip values 2250 + 505 + 505; the calibrated total is shared out in those proportions
  local armor = max(0, v.bossArmor - v.armorDebuff * ((v.sunder and 2250 or 0) + (v.faerieFire and 505 or 0) + (v.cor and 505 or 0)) / 3260)
  local c = {}
  for k, x in pairs(v) do c[k] = x end
  c.mana = v.mana + (int - v.int) * v.manaPerInt
  c.mp5 = v.mp5 + (v.bow and 36 or 0) + (v.manaSpring and 25 or 0)
  c.formAP = 40 * kings * (1 + v.divineStrength / 100)
  c.formCrit = 20 * kings / v.agiPerCrit
  c.formSP = 20 * kings * (1 + v.divineIntellect / 100) * v.champion / 100
  c.strF, c.intF, c.ap, c.hitF, c.spellHitF, c.crit, c.spellCrit = str, int, ap, hit, spellHit, crit, spellCrit
  c.miss = max(0, v.baseMiss - hit)
  c.dodge = max(0, v.baseDodge - v.exp)
  c.spellMiss = min(99, max(1, v.spellMissBase - spellHit))
  c.armorMult = 1 - armor / (armor + 400 + 85 * (60 + 4.5))
  c.champSP = v.champion / 100 * int
  c.bened = 1 - v.benediction / 100
  c.conduit = 1 - v.holyConduit / 100
  c.twoH = 1 + v.twoHand / 100
  c.impSeals = 1 + v.improvedSeals / 100
  c.arbiter = v.sacredArbiter and 1.2 or 1
  return c
end
