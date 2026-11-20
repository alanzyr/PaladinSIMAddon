-- Reads your character from the game: race, talents, the character sheet's numbers, your weapon and the buffs on you.
-- Everything is read with care, the way Xn's Warlock Sim does: the Forever client hides numbers from addons in combat
-- ("secret values"), so nothing is read then, and every call is wrapped so that a missing function or a hidden value
-- becomes a note, not an error. What the game returned is kept in `raw` for /rsim dump.
local ADDON, RS = ...
if RS.notPaladin then return end

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
-- f(...) -> its results, or nil when the function is missing, fails, or its first result is hidden
local function pass(ok, ...)
  if not ok or isSecret((...)) then return nil end
  return ...
end
local function try(f, ...)
  if type(f) ~= 'function' then return nil end
  return pass(pcall(f, ...))
end
local function num(v) return (type(v) == 'number' and not isSecret(v)) and v or nil end
RS.try, RS.num = try, num

local RACE_BY_FILE = { Human = 'human', Dwarf = 'dwarf', Scourge = 'undead', Undead = 'undead' }
-- Raid buffs of the sim that can sit on you as a buff, with the names they go by.
local BUFF_NAMES = {
  kings = { 'Blessing of Kings', 'Greater Blessing of Kings' },
  might = { 'Blessing of Might', 'Greater Blessing of Might' },
  bow = { 'Blessing of Wisdom', 'Greater Blessing of Wisdom' },
  battleShout = { 'Battle Shout' },
  lotp = { 'Leader of the Pack' },
  soe = { 'Strength of Earth', 'Strength of Earth Totem' },
  goa = { 'Grace of Air', 'Grace of Air Totem' },
  motw = { 'Mark of the Wild', 'Gift of the Wild' },
  arcInt = { 'Arcane Intellect', 'Arcane Brilliance' },
  moonkin = { 'Moonkin Aura' },
  manaSpring = { 'Mana Spring', 'Mana Spring Totem' },
}
-- Buffs that are yours anyway or change nothing the sim reads: not listed as "other buffs".
local IGNORE = { ['Retribution Aura'] = true, ['Devotion Aura'] = true, ['Concentration Aura'] = true, ['Sanctity Aura'] = true,
  ['Seal of Command'] = true, ['Seal of Righteousness'] = true, ['Seal of the Crusader'] = true, ['Seal of Fury'] = true, ['Righteous Fury'] = true }

local function spellName(id)
  if not id then return nil end
  local n = C_Spell and try(C_Spell.GetSpellName, id)
  return type(n) == 'string' and n or nil
end

-- The buffs on you: a list of { name, id }.
local function readAuras()
  local list = {}
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return list, false end
  for i = 1, 80 do
    local a = try(C_UnitAuras.GetAuraDataByIndex, 'player', i, 'HELPFUL')
    if type(a) ~= 'table' then break end
    local name, id = a.name, a.spellId
    if type(name) == 'string' and not isSecret(name) then list[#list + 1] = { name = name, id = num(id) } end
  end
  return list, true
end

-- Talent ranks by talent name, and a note when something could not be read.
local function readTalents(raw)
  local byName, nodes = {}, 0
  local configID
  if C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_SpecializationInfo.GetActiveSpecGroup then
    local group = try(C_SpecializationInfo.GetActiveSpecGroup)
    if group then configID = num((try(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, group))) end
    raw.specGroup = group
  end
  if not configID and C_ClassTalents and C_ClassTalents.GetActiveConfigID then configID = num((try(C_ClassTalents.GetActiveConfigID))) end
  raw.configID = configID
  if not configID or not C_Traits then return {}, 'The game did not give out your talents (no talent set found). The sim plays without talents.' end
  local info = try(C_Traits.GetConfigInfo, configID)
  local treeIDs = type(info) == 'table' and info.treeIDs or {}
  raw.treeIDs, raw.nodes = treeIDs, {}
  for _, treeID in ipairs(treeIDs) do
    local ids = try(C_Traits.GetTreeNodes, treeID)
    for _, nodeID in ipairs(type(ids) == 'table' and ids or {}) do
      local node = try(C_Traits.GetNodeInfo, configID, nodeID)
      if type(node) == 'table' then
        local rank = num(node.activeRank) or num(node.currentRank) or num(node.ranksPurchased) or 0
        nodes = nodes + 1
        local entryID = (type(node.activeEntry) == 'table' and node.activeEntry.entryID) or (type(node.entryIDs) == 'table' and node.entryIDs[1])
        local entry = entryID and try(C_Traits.GetEntryInfo, configID, entryID)
        local defID = type(entry) == 'table' and entry.definitionID
        local def = defID and try(C_Traits.GetDefinitionInfo, defID)
        local sid = type(def) == 'table' and (def.spellID or def.overriddenSpellID)
        local name = (type(def) == 'table' and type(def.overrideName) == 'string' and def.overrideName ~= '' and def.overrideName) or spellName(sid)
        if name then byName[name] = rank end
        if rank > 0 then raw.nodes[#raw.nodes + 1] = { node = nodeID, rank = rank, max = num(node.maxRanks), spell = sid, name = name } end
      end
    end
  end
  raw.nodeCount = nodes
  local talents, found, unknown = {}, 0, {}
  for i = 1, #RS.TALENTS do
    local t = RS.TALENTS[i]
    local rank = byName[t.name]
    if rank ~= nil then
      found = found + 1
      if rank > 0 then talents[t.name] = math.min(rank, t.max) end
    else unknown[#unknown + 1] = t.name end
  end
  raw.talentsFound, raw.talentsMissing = found, unknown
  if found == 0 then return talents, 'The game gave out a talent tree, but none of its talents could be matched by name (' .. nodes .. ' talents seen). The sim plays without talents.' end
  if found < #RS.TALENTS then return talents, (#RS.TALENTS - found) .. ' of the sim\'s ' .. #RS.TALENTS .. ' talents were not found in your talent tree; they count as 0 points.' end
  return talents, nil
end

-- The tooltip of the main hand: "152 - 255 Damage" and "Speed 3.60" (English client).
local function readWeaponTooltip(raw)
  local data = C_TooltipInfo and try(C_TooltipInfo.GetInventoryItem, 'player', 16)
  if type(data) ~= 'table' or type(data.lines) ~= 'table' then return nil end
  local lo, hi, speed
  raw.weaponLines = {}
  for i = 1, #data.lines do
    local l = data.lines[i]
    local left, right = type(l) == 'table' and l.leftText, type(l) == 'table' and l.rightText
    if type(left) == 'string' and not isSecret(left) then
      if #raw.weaponLines < 8 then raw.weaponLines[#raw.weaponLines + 1] = left .. (type(right) == 'string' and not isSecret(right) and ('  |  ' .. right) or '') end
      local a, b = left:match('^(%d+) %- (%d+) Damage')
      if a then lo, hi = tonumber(a), tonumber(b) end
      local s = left:match('Speed (%d+%.?%d*)')
      if s then speed = tonumber(s) end
    end
    if type(right) == 'string' and not isSecret(right) then
      local s = right:match('Speed (%d+%.?%d*)')
      if s then speed = tonumber(s) end
    end
  end
  if lo and hi and speed then return lo, hi, speed end
  return nil
end

-- Returns the character (a table), or nil and a plain sentence why not.
function RS.readCharacter()
  if InCombatLockdown and InCombatLockdown() then return nil, 'You are in combat. The game hides your numbers from addons then - read again after the fight.' end
  local raw, notes = {}, {}
  local c = { raw = raw, notes = notes, readAt = time and time() or 0 }
  local _, class = try(UnitClass, 'player')
  c.class = class
  if class ~= 'PALADIN' then return nil, 'This character is not a Paladin.' end
  c.name, c.realm, c.level = try(UnitName, 'player'), try(GetRealmName), num((try(UnitLevel, 'player')))
  local _, raceFile = try(UnitRace, 'player')
  raw.raceFile = raceFile
  c.raceKey = RACE_BY_FILE[raceFile or ''] or 'human'
  if not RACE_BY_FILE[raceFile or ''] then notes[#notes + 1] = 'Your race (' .. tostring(raceFile) .. ') is not one the sim knows: it is played as a Human.' end
  if c.level and c.level ~= 60 then notes[#notes + 1] = 'The sim is built for level 60; you are level ' .. c.level .. '.' end

  -- the character sheet
  local sheet = {}
  local STAT = { str = 1, agi = 2, sta = 3, int = 4, spi = 5 }
  for k, i in pairs(STAT) do
    local base, eff, pos, neg = try(UnitStat, 'player', i)
    sheet[k] = num(eff) or num(base)
    raw['stat' .. i] = { num(base), num(eff), num(pos), num(neg) }
  end
  local apBase, apPos, apNeg = try(UnitAttackPower, 'player')
  raw.attackPower = { num(apBase), num(apPos), num(apNeg) }
  if num(apBase) then sheet.ap = apBase + (num(apPos) or 0) + (num(apNeg) or 0) end
  sheet.crit = num((try(GetCritChance)))
  local hitRating, hitMod = num((try(GetCombatRatingBonus, CR_HIT_MELEE or 6))), num((try(GetHitModifier)))
  raw.hit = { hitRating, hitMod }
  sheet.hit = (hitRating or 0) + (hitMod or 0)
  local expPct, expRating, expPoints = num((try(GetExpertisePercent))), num((try(GetCombatRatingBonus, CR_EXPERTISE or 24))), num((try(GetExpertise)))
  raw.expertise = { expPct, expRating, expPoints }
  sheet.exp = expPct or expRating or 0
  local hasteRating, hastePct = num((try(GetCombatRatingBonus, CR_HASTE_MELEE or 18))), num((try(GetMeleeHaste)))
  raw.haste = { hasteRating, hastePct }
  sheet.haste = hastePct or hasteRating or 0

  -- spells: Holy is school 2; the lowest school is the spell power that counts for everything
  local sps, spMin = {}, nil
  for school = 2, 7 do
    sps[school] = num((try(GetSpellBonusDamage, school)))
    if sps[school] and (not spMin or sps[school] < spMin) then spMin = sps[school] end
  end
  raw.spellPower = sps
  sheet.spHoly, sheet.spAll = sps[2], spMin
  sheet.spellCrit = num((try(GetSpellCritChance, 2))) or num((try(GetSpellCritChance)))
  local sHitRating, sHitMod = num((try(GetCombatRatingBonus, CR_HIT_SPELL or 8))), num((try(GetSpellHitModifier)))
  raw.spellHit = { sHitRating, sHitMod }
  sheet.spellHit = (sHitRating or 0) + (sHitMod or 0)
  local regenBase, regenCasting = try(GetManaRegen)
  raw.manaRegen = { num(regenBase), num(regenCasting) }
  sheet.mp5 = num(regenCasting) and regenCasting * 5 or nil
  sheet.maxMana = num((try(UnitPowerMax, 'player', 0)))

  -- the weapon: the tooltip's own numbers; failing that, the character sheet's damage with Attack Power taken off again
  local lo, hi, _, _, _, _, pct = try(UnitDamage, 'player')
  local speed = num((try(UnitAttackSpeed, 'player')))
  raw.damage = { num(lo), num(hi), num(pct), speed }
  local tLo, tHi, tSpeed = readWeaponTooltip(raw)
  if tLo then
    sheet.wMin, sheet.wMax, sheet.wSpeed, raw.weaponFrom = tLo, tHi, tSpeed, 'tooltip'
  elseif num(lo) and num(hi) and speed and sheet.ap then
    local base = speed * (1 + sheet.haste / 100)
    local mult = (num(pct) and pct > 0) and pct or 1
    sheet.wMin, sheet.wMax, sheet.wSpeed, raw.weaponFrom = lo / mult - sheet.ap / 14 * base, hi / mult - sheet.ap / 14 * base, base, 'character sheet'
    notes[#notes + 1] = 'Your weapon\'s tooltip could not be read; its damage was worked out from the character sheet instead.'
  end

  local missing = {}
  local NEED = { { 'str', 'Strength' }, { 'int', 'Intellect' }, { 'ap', 'Attack Power' }, { 'crit', 'melee crit' }, { 'spHoly', 'Holy spell power' }, { 'spellCrit', 'spell crit' }, { 'maxMana', 'mana' } }
  for i = 1, #NEED do if sheet[NEED[i][1]] == nil then missing[#missing + 1] = NEED[i][2] end end
  c.sheet = sheet
  if #missing > 0 then return nil, 'The game did not give out: ' .. table.concat(missing, ', ') .. '. Without them the sim cannot play your character. Type /rsim dump and send the text.' , c end

  -- talents
  local talents, talentNote = readTalents(raw)
  c.talents = talents
  if talentNote then notes[#notes + 1] = talentNote end

  -- buffs on you
  local auras, aurasOk = readAuras()
  raw.auras = auras
  if not aurasOk then notes[#notes + 1] = 'The buffs on you could not be read: buffs that give stats count as part of your gear.' end
  local buffs, used = {}, {}
  for key, names in pairs(BUFF_NAMES) do
    for i = 1, #auras do
      for j = 1, #names do if auras[i].name == names[j] then buffs[key] = true; used[i] = true end end
    end
  end
  c.buffsOnYou = buffs
  local others = {}
  for i = 1, #auras do if not used[i] and not IGNORE[auras[i].name] then others[#others + 1] = auras[i].name end end
  c.otherAuras = others

  -- the items with an effect of their own in the fight: main hand (and its enchant) and the libram
  local worn = { mainHand = num((try(GetInventoryItemID, 'player', 16))), relic = num((try(GetInventoryItemID, 'player', 18))) }
  local mainLink = try(GetInventoryItemLink, 'player', 16)
  if type(mainLink) == 'string' then worn.mainEnchant = tonumber(mainLink:match('item:%d+:(%d+)')) end
  worn.items = {}
  for inv = 1, 18 do local id = num((try(GetInventoryItemID, 'player', inv))); if id then worn.items[inv] = id end end
  c.worn = worn
  return c
end
