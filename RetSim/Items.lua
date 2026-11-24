-- Items: what an item gives, as the sim's numbers, and your character with one item swapped for another.
-- No game API in this file (ItemUI.lua asks the game); tools/check-ret-items.js runs it over every item of the website.
-- After Xn's Warlock Sim (Items.lua), with a paladin's stats.
--   RS.itemStats        the game's stat list of an item and the lines of its tooltip -> { str = 18, crit = 28, weapon = {...} }
--   RS.valuesWithSwap   the sim's values + the new item - the item(s) it replaces
local ADDON, RS = ...
if RS.notPaladin then return end

-- The sim's stat and the game's name for it on items. The game's stat list (GetItemStats) uses the name + "_SHORT".
-- hit, crit and exp are ratings (the settings say how much rating is 1%); hitPct and critPct are plain percentages.
local ITEM_STATS = {
  { 'str', 'ITEM_MOD_STRENGTH' }, { 'agi', 'ITEM_MOD_AGILITY' }, { 'int', 'ITEM_MOD_INTELLECT' }, { 'sta', 'ITEM_MOD_STAMINA' }, { 'spi', 'ITEM_MOD_SPIRIT' },
  { 'ap', 'ITEM_MOD_ATTACK_POWER' }, { 'ap', 'ITEM_MOD_MELEE_ATTACK_POWER' },
  { 'hit', 'ITEM_MOD_HIT_RATING' }, { 'hit', 'ITEM_MOD_HIT_MELEE_RATING' },
  { 'crit', 'ITEM_MOD_CRIT_RATING' }, { 'crit', 'ITEM_MOD_CRIT_MELEE_RATING' },
  { 'exp', 'ITEM_MOD_EXPERTISE_RATING' },
  { 'sp', 'ITEM_MOD_SPELL_POWER' }, { 'sp', 'ITEM_MOD_SPELL_DAMAGE_DONE' }, { 'holy', 'ITEM_MOD_HOLY_DAMAGE_DONE' },
  { 'mp5', 'ITEM_MOD_MANA_REGENERATION' }, { 'mp5', 'ITEM_MOD_POWER_REGEN0' },
}
-- Tooltip lines in English, as the Forever client and the trackers show them. The first that fits a line counts.
local LINES = {
  { 'str', '^%+(%d+) Strength$' }, { 'agi', '^%+(%d+) Agility$' }, { 'int', '^%+(%d+) Intellect$' }, { 'sta', '^%+(%d+) Stamina$' }, { 'spi', '^%+(%d+) Spirit$' },
  { 'str', '^%-(%d+) Strength$', neg = true }, { 'agi', '^%-(%d+) Agility$', neg = true }, { 'int', '^%-(%d+) Intellect$', neg = true },
  { 'sta', '^%-(%d+) Stamina$', neg = true }, { 'spi', '^%-(%d+) Spirit$', neg = true },
  { 'ap', '^%+(%d+) Attack Power$' }, { 'hit', '^%+(%d+) Hit Rating$' }, { 'crit', '^%+(%d+) Critical Strike Rating$' }, { 'exp', '^%+(%d+) Expertise Rating$' },
  { 'sp', '^%+(%d+) Spell Power$' }, { 'sp', '^%+(%d+) Spell Damage$' }, { 'holy', '^%+(%d+) Holy Spell Damage$' }, { 'mp5', '^%+(%d+) Mana Regeneration$' },
  { 'mp5', '^%+(%d+) [Mm]ana [Ee]very 5 [Ss]ec' },
  -- the classic wording: an item that also carries the short line for the same stat says one bonus twice (the short line counts)
  { 'sp', '^Increases damage and healing done by magical spells and effects by up to (%d+)', classic = true },
  { 'sp', '^Increases healing done by up to %d+ and damage done by up to (%d+) for all magical spells and effects', classic = true },
  { 'holy', '^Increases damage done by Holy spells and effects by up to (%d+)', classic = true },
  { 'ap', '^Increases attack power by (%d+)', classic = true },
  { 'hitPct', '^Improves your chance to hit by (%d+%.?%d*)%%' },
  { 'critPct', '^Improves your chance to get a critical strike by (%d+%.?%d*)%%' },
  { 'mp5', '^Restores (%d+) mana per 5 sec', classic = true },
}
RS.ITEM_STAT_ORDER = { 'str', 'agi', 'ap', 'crit', 'critPct', 'hit', 'hitPct', 'exp', 'sp', 'holy', 'int', 'mp5' }
local STAT_WORDS = { str = ' Strength', agi = ' Agility', ap = ' Attack Power', crit = ' Crit Rating', critPct = '% crit', hit = ' Hit Rating', hitPct = '% hit',
  exp = ' Expertise Rating', sp = ' spell power', holy = ' Holy spell power', int = ' Intellect', mp5 = ' mana per 5 s' }

-- Where an item goes: the game's "equip location" -> inventory slot numbers (two for rings and trinkets).
RS.ITEM_SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_RELIC = { 18 },
}
-- What a paladin can wear but the sim does not play: said in words instead of simmed.
RS.ITEM_NOT_PLAYED = {
  INVTYPE_WEAPON = 'The sim plays two-hand weapons only.', INVTYPE_WEAPONMAINHAND = 'The sim plays two-hand weapons only.',
  INVTYPE_WEAPONOFFHAND = 'The sim plays two-hand weapons only.', INVTYPE_SHIELD = 'The sim plays two-hand weapons only: a shield cannot be compared.',
  INVTYPE_HOLDABLE = 'The sim plays two-hand weapons only: an off-hand item cannot be compared.',
}

local function clean(line)
  return (line:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

-- api     the game's stat list of the item ({ ITEM_MOD_STRENGTH_SHORT = 18, ... }) or nil
-- lines   the tooltip's lines as texts; a weapon's damage and speed may sit in one line or in two parts joined by a tab
-- Returns the stats and the "Equip:" / "Use:" / "Chance on hit:" lines that were not understood (they are not counted).
function RS.itemStats(api, lines)
  local fromApi, fromTip, fromClassic = {}, {}, {}
  if type(api) == 'table' then
    for i = 1, #ITEM_STATS do
      local e = ITEM_STATS[i]
      local v = api[e[2] .. '_SHORT']
      if type(v) == 'number' and v ~= 0 then fromApi[e[1]] = (fromApi[e[1]] or 0) + v end
    end
  end
  local unknown, weapon = {}, {}
  for li = 1, #(lines or {}) do
    local raw = type(lines[li]) == 'string' and clean(lines[li]) or ''
    local lo, hi = raw:match('(%d+) %- (%d+) Damage')
    if lo then weapon.min, weapon.max = tonumber(lo), tonumber(hi) end
    local sp = raw:match('Speed (%d+%.?%d*)')
    if sp then weapon.speed = tonumber(sp) end
    local isSet = raw:find('^%(%d+%) Set:') or raw:find('^Set:')
    local isUse = raw:find('^Use:') or raw:find('^Chance on hit:')
    local isEquip = raw:find('^Equip:')
    local s = isEquip and clean(raw:sub(7)) or raw
    local found = false
    if not isSet and not isUse then
      for i = 1, #LINES do
        local c = LINES[i]
        local n = tonumber((s:match(c[2])))
        if n then
          local to = c.classic and fromClassic or fromTip
          to[c[1]] = (to[c[1]] or 0) + (c.neg and -n or n); found = true; break
        end
      end
    end
    if not found and (isEquip or isUse) then unknown[#unknown + 1] = raw end
  end
  local stats = {}
  for i = 1, #RS.ITEM_STAT_ORDER do
    local k = RS.ITEM_STAT_ORDER[i]
    local v = fromApi[k] or fromTip[k] or fromClassic[k]
    if v and v ~= 0 then stats[k] = v end
  end
  -- a percentage in the tooltip and a rating in the stat list are the same bonus said twice: the rating counts
  if stats.hit and stats.hitPct then stats.hitPct = nil end
  if stats.crit and stats.critPct then stats.critPct = nil end
  for _, k in ipairs({ 'sta', 'spi' }) do local v = fromApi[k] or fromTip[k]; if v and v ~= 0 then stats[k] = v end end   -- read, not counted by the sim
  if weapon.min and weapon.max and weapon.speed then stats.weapon = weapon end
  return stats, unknown
end

-- v: the sim's values; new: the stats of the item put on (nil = an empty slot); olds: a list of the stats of the item(s)
-- taken off; slot: the inventory slot; newID: the new item's id.
-- Returns the new values and the difference per stat. An enchant on the slot stays: it is assumed to move to the new item.
function RS.valuesWithSwap(v, new, olds, slot, newID)
  new = new or {}
  local o, d = {}, {}
  for k, x in pairs(v) do o[k] = x end
  for i = 1, #RS.ITEM_STAT_ORDER do
    local k = RS.ITEM_STAT_ORDER[i]
    local x = new[k] or 0
    for j = 1, #olds do x = x - (olds[j][k] or 0) end
    d[k] = x
  end
  o.str = v.str + d.str
  o.int = v.int + d.int
  o.mana = v.mana + d.int * v.manaPerInt
  o.apGear = v.apGear + d.ap
  local crit = d.crit / v.critRating + d.critPct
  o.crit = v.crit + crit + d.agi / v.agiPerCrit
  o.spellCrit = v.spellCrit + crit
  local hit = d.hit / v.hitRating + d.hitPct
  o.hit = v.hit + hit
  o.spellHit = v.spellHit + hit
  o.exp = v.exp + d.exp / v.expRating
  o.sp = v.sp + d.sp + d.holy
  o.holyOnly = (v.holyOnly or 0) + d.holy
  o.mp5 = v.mp5 + d.mp5
  if slot == 16 then
    if new.weapon then o.wMin, o.wMax, o.wSpeed = new.weapon.min, new.weapon.max, new.weapon.speed end
    o.hanna = newID == RS.BLADE_OF_HANNA
    d.weapon = new.weapon
  elseif slot == 18 then
    o.judgeMult = newID == RS.LIBRAM_OF_LAW and 1.04 or 1
    o.jotcLibram = newID == RS.LIBRAM_OF_FERVOR and 33 or 0
  end
  -- the effects played in the fight follow the swap (a proc on the new item, a set bonus gained or lost)
  if v.wornItems then
    local items = {}
    for k, x in pairs(v.wornItems) do items[k] = x end
    items[slot] = newID
    o.wornItems = items
    o.procs = RS.wornProcs(items, v.wornEnchant, v.procPPM)
  end
  for _, k in ipairs({ 'apGear', 'crit', 'spellCrit', 'hit', 'spellHit', 'exp', 'sp', 'holyOnly', 'mp5' }) do if o[k] < 0 then o[k] = 0 end end
  return o, d
end

-- "+18 Strength, +28 Crit Rating, -10 Hit Rating"; "nothing the sim counts" when all are zero.
function RS.describeStats(d, signed)
  local parts = {}
  for i = 1, #RS.ITEM_STAT_ORDER do
    local k = RS.ITEM_STAT_ORDER[i]
    local v = d[k] or 0
    if math.abs(v) > 1e-9 then
      local n = math.floor(math.abs(v) * 100 + 0.5) / 100
      local text = n == math.floor(n) and string.format('%.0f', n) or tostring(n)
      parts[#parts + 1] = ((v < 0) and '-' or (signed and '+' or '')) .. text .. STAT_WORDS[k]
    end
  end
  if d.weapon then parts[#parts + 1] = string.format('weapon %d-%d at %.2f', d.weapon.min, d.weapon.max, d.weapon.speed) end
  if #parts == 0 then return 'nothing the sim counts' end
  return table.concat(parts, ', ')
end
