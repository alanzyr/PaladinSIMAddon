-- What ties the parts together inside the game: saved settings, the job that plays fights a little every frame so the
-- game never freezes, the slash commands, the self-test and the dump. The job runner follows Xn's Warlock Sim.
local ADDON, RS = ...
if RS.notPaladin then return end

local floor, max, min = math.floor, math.max, math.min
local function now() return debugprofilestop and debugprofilestop() or (GetTime() * 1000) end
function RS.print(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cfff58cbaRet Sim|r  ' .. tostring(msg)) end end

-- ---------------------------------------------------------------------------------------------------------------------
-- saved settings
-- ---------------------------------------------------------------------------------------------------------------------
local function initDB()
  RetSimDB = type(RetSimDB) == 'table' and RetSimDB or {}
  local db = RetSimDB
  db.options = type(db.options) == 'table' and db.options or {}
  local o = db.options
  if RS.MODES[o.mode or ''] == nil and o.mode ~= 'auto' then o.mode = 'auto' end
  o.fights = max(20, min(20000, floor(tonumber(o.fights) or 300)))
  o.itemFights = max(20, min(2000, floor(tonumber(o.itemFights) or 150)))      -- fights per side when an item is simmed
  if o.itemClick == nil then o.itemClick = true end                              -- Shift + right-click on an item sims it
  db.settings = type(db.settings) == 'table' and db.settings or {}     -- your own choices on top of the defaults (raid buffs)
  RS.db = db
end
function RS.modeName(key) return key == 'auto' and 'Best twist (auto)' or (RS.MODES[key] and RS.MODES[key].name) or key end
function RS.buffsOn() for i = 1, #RS.BUFFS do local k = RS.BUFFS[i].key; local x = RS.db.settings[k]; if x == nil then x = RS.DEFAULTS[k] end; if x then return true end end return false end
-- on: the website's default raid (its usual buffs and debuffs; the optional ones like Gift of Arthas stay off); off: none at all
function RS.setBuffs(on) for i = 1, #RS.BUFFS do local k = RS.BUFFS[i].key; if on then RS.db.settings[k] = nil else RS.db.settings[k] = false end end end

-- ---------------------------------------------------------------------------------------------------------------------
-- reading the character
-- ---------------------------------------------------------------------------------------------------------------------
function RS.doReadCharacter()
  local ch, why, partial = RS.readCharacter()
  if not ch then RS.lastPartial = partial; return false, why end
  RS.char = ch
  RS.values, RS.valueNotes = RS.valuesFromSheet(ch, RS.db.settings)
  return true
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the job: fights played in a coroutine, a few milliseconds every frame
-- ---------------------------------------------------------------------------------------------------------------------
local BUDGET_OUT, BUDGET_COMBAT = 30, 8     -- milliseconds of simulating per frame, out of combat and in combat
local job, deadline
local driver = CreateFrame('Frame')
driver:Hide()
local function tick() if job and now() > deadline then coroutine.yield() end end
RS.tick = tick
function RS.jobRunning() return job ~= nil end
function RS.jobProgress() if job then return job.done, job.total, job.label end end
function RS.cancelJob()
  if not job then return end
  job = nil; driver:Hide()
  if RS.onJobEnd then RS.onJobEnd(nil, 'Stopped.') end
end
driver:SetScript('OnUpdate', function()
  if not job then driver:Hide(); return end
  local j = job
  deadline = now() + ((InCombatLockdown and InCombatLockdown()) and BUDGET_COMBAT or BUDGET_OUT)
  local ok, err = coroutine.resume(j.co)
  if job ~= j then return end
  if not ok then
    job = nil; driver:Hide()
    RS.lastError = tostring(err)
    if RS.onJobEnd then RS.onJobEnd(nil, 'The sim stopped with an error: ' .. tostring(err)) end
  elseif coroutine.status(j.co) == 'dead' then
    job = nil; driver:Hide()
    j.result.seconds = (now() - j.started) / 1000
    if RS.onJobEnd then RS.onJobEnd(j.result) end
  end
end)
local function startJob(label, total, fn)
  if job then return false end
  local j = { label = label, total = total, done = 0, started = now(), result = {} }
  j.co = coroutine.create(function() fn(j) end)
  job = j
  driver:Show()
  return true
end
RS.startJob = startJob

-- The best of the three seal twists for these values: 60 fights each on the same seeds (the website tries 150).
function RS.pickTwist(c, v, seed, onFight)
  local best, pick = -1, nil
  for _, k in ipairs({ 'socSor', 'sorSoc', 'sorFury' }) do
    local m, sum = RS.resolveMode(k, v.wSpeed), 0
    for i = 0, 59 do sum = sum + RS.simulateOnce(c, m, seed * 7919 + i * 104729).dps; if onFight then onFight() end; tick() end
    if sum > best then best, pick = sum, k end
  end
  return pick
end
function RS.wantsTwistPick(v) return RS.db.options.mode == 'auto' and v.unsealedWrath and v.hasSoC end

-- Sim your character: read it (out of combat), find the best twist when the rotation is "auto", then play the fights.
function RS.simCharacter()
  if job then return false, 'A sim is already running.' end
  if not (InCombatLockdown and InCombatLockdown()) then
    local ok, why = RS.doReadCharacter()
    if not ok and not RS.char then return false, why end
  elseif not RS.char then
    return false, 'You are in combat and your character has not been read yet. Sim again after the fight.'
  else
    RS.values, RS.valueNotes = RS.valuesFromSheet(RS.char, RS.db.settings)
  end
  local v, fights, modeKey = RS.values, RS.db.options.fights, RS.db.options.mode
  local seed = math.random(1, 999999)
  local trial = RS.wantsTwistPick(v) and 3 * 60 or 0
  return startJob('Simulating', fights + trial, function(j)
    local c = RS.derive(v)
    local pick
    if trial > 0 then pick = RS.pickTwist(c, v, seed, function() j.done = j.done + 1 end) end
    local mode = RS.resolveMode(modeKey, v.wSpeed, pick)
    local sum, S, dps = 0, {}, {}
    local mana, echoes, blocked = 0, 0, 0
    for i = 0, fights - 1 do
      local r = RS.simulateOnce(c, mode, seed * 7919 + i * 104729)
      dps[i + 1] = r.dps; sum = sum + r.dps
      mana = mana + r.mana; echoes = echoes + r.echoes; blocked = blocked + r.blocked
      for k, b in pairs(r.S) do
        local a = S[k]
        if not a then a = { dmg = 0, n = 0, crit = 0, miss = 0 }; S[k] = a end
        a.dmg = a.dmg + b.dmg; a.n = a.n + b.n; a.crit = a.crit + b.crit; a.miss = a.miss + b.miss
      end
      j.done = j.done + 1
      tick()
    end
    local mean, var, lo, hi = sum / fights, 0, dps[1], dps[1]
    for i = 1, fights do var = var + (dps[i] - mean) ^ 2; if dps[i] < lo then lo = dps[i] end; if dps[i] > hi then hi = dps[i] end end
    local sd = math.sqrt(var / max(1, fights - 1))
    local rows = {}
    for k, a in pairs(S) do rows[#rows + 1] = { name = k, dps = a.dmg / fights / c.fight, n = a.n / fights, crit = a.n > 0 and a.crit / a.n or 0, miss = a.n > 0 and a.miss / a.n or 0 } end
    table.sort(rows, function(x, y) if x.dps ~= y.dps then return x.dps > y.dps end return x.name < y.name end)
    local r = j.result
    r.mean, r.sd, r.margin, r.lo, r.hi, r.fights = mean, sd, 1.96 * sd / math.sqrt(fights), lo, hi, fights
    r.rows, r.mode, r.manaLeft, r.echoesPerMin, r.blocked = rows, mode, mana / fights, echoes / fights / c.fight * 60, blocked / fights
    r.totals = RS.totals(v)
    RS.last = r
  end)
end

-- The maths check: the fights of Expected.lua played here must give the website's numbers.
function RS.selfTest()
  local okAll, lines = true, {}
  for i = 1, #RS.EXPECTED do
    local e = RS.EXPECTED[i]
    local v = {}
    for k, x in pairs(RS.DEFAULTS) do v[k] = x end
    RS.applyTalents(v, RS.PRESETS.ws)
    local r = RS.simulateOnce(RS.derive(v), RS.resolveMode(e.mode, v.wSpeed), e.seed)
    local ok = math.abs(r.dps - e.dps) < 1e-6 and r.swings == e.swings and math.abs(r.mana - e.mana) < 1e-6
    if not ok then okAll = false end
    lines[#lines + 1] = string.format('%s  %s: %.4f DPS here, %.4f on the website', ok and 'ok  ' or 'FAIL', e.mode, r.dps, e.dps)
  end
  RS.db.selfTest = { ok = okAll, lines = lines, version = RS.VERSION }
  return okAll, lines
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the dump: what the game returned and what the sim made of it, as text to copy
-- ---------------------------------------------------------------------------------------------------------------------
local function ser(v, indent, depth, out)
  if type(v) ~= 'table' then out[#out + 1] = tostring(v); return end
  if depth > 6 then out[#out + 1] = '{...}'; return end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  if #keys == 0 then out[#out + 1] = '{}'; return end
  out[#out + 1] = '{\n'
  for _, k in ipairs(keys) do
    out[#out + 1] = indent .. '  ' .. tostring(k) .. ' = '
    ser(v[k], indent .. '  ', depth + 1, out)
    out[#out + 1] = '\n'
  end
  out[#out + 1] = indent .. '}'
end
function RS.dumpText()
  local d = { at = date and date('%Y-%m-%d %H:%M:%S') or '', version = RS.VERSION }
  if GetBuildInfo then d.build = { GetBuildInfo() } end
  local ok, why
  if not (InCombatLockdown and InCombatLockdown()) then ok, why = RS.doReadCharacter() end
  d.readOk, d.readNote = ok, why
  local ch = RS.char or RS.lastPartial
  if ch then
    d.character = { level = ch.level, raceKey = ch.raceKey, sheet = ch.sheet, talents = ch.talents, buffsOnYou = ch.buffsOnYou, otherAuras = ch.otherAuras, notes = ch.notes, worn = ch.worn, raw = ch.raw }
  end
  if RS.values then
    local v, keep = RS.values, {}
    for _, k in ipairs({ 'race', 'str', 'int', 'apGear', 'crit', 'hit', 'exp', 'sp', 'holyOnly', 'spellCrit', 'spellHit', 'mana', 'mp5', 'haste', 'wMin', 'wMax', 'wSpeed', 'hanna', 'judgeMult' }) do keep[k] = v[k] end
    d.simValues, d.simNotes, d.simTotals = keep, RS.valueNotes, RS.totals(v)
  end
  d.options, d.selfTest, d.lastError = RS.db.options, RS.db.selfTest, RS.lastError
  d.lastItem = RS.db.lastItem                               -- what the game returned for the items of the last item comparison
  if RS.last then d.lastResult = { mean = RS.last.mean, margin = RS.last.margin, fights = RS.last.fights, mode = RS.last.mode and RS.last.mode.key, seconds = RS.last.seconds, rows = RS.last.rows } end
  local out = {}
  ser(d, '', 0, out)
  local text = 'Forever Ret Sim dump\n' .. table.concat(out)
  RS.db.dump = text
  return text
end

-- ---------------------------------------------------------------------------------------------------------------------
-- start-up and slash commands
-- ---------------------------------------------------------------------------------------------------------------------
local events = CreateFrame('Frame')
events:RegisterEvent('ADDON_LOADED')
events:SetScript('OnEvent', function(self, event, name)
  if event == 'ADDON_LOADED' and name == ADDON then
    initDB()
    self:UnregisterEvent('ADDON_LOADED')
    if RS.onLoaded then RS.onLoaded() end
  end
end)

local HELP = {
  '/rsim - open or close the window',
  '/rsim sim - read your character and sim it',
  '/rsim mode auto | socSor | sorSoc | sorFury | socOnly | sorOnly | shock - the rotation',
  '/rsim fights 500 - how many fights a sim plays',
  '/rsim buffs on | off - every raid buff and debuff on or off',
  '/rsim item [shift-click an item] - sim that item against what you wear',
  '/rsim click on | off - Shift + right-click on an item sims it',
  '/rsim test - the maths check against the website',
  '/rsim dump - what the game returned, as text to copy and send',
}
SLASH_RETSIM1, SLASH_RETSIM2 = '/rsim', '/retsim'
SlashCmdList['RETSIM'] = function(msg)
  if not RS.db then return end
  local cmd, arg = strtrim(msg or ''):match('^(%S*)%s*(.-)$')
  cmd = (cmd or ''):lower()
  if cmd == '' then if RS.toggleWindow then RS.toggleWindow() end
  elseif cmd == 'sim' then
    if RS.showWindow then RS.showWindow() end
    local ok, why = RS.simCharacter()
    if not ok then RS.print(why); if RS.refresh then RS.refresh(why) end end
  elseif cmd == 'read' then
    local ok, why = RS.doReadCharacter()
    RS.print(ok and 'Character read.' or why)
    if RS.refresh then RS.refresh() end
  elseif cmd == 'mode' then
    local key
    for _, k in ipairs(RS.MODE_ORDER) do if k:lower() == arg:lower() then key = k end end
    if arg:lower() == 'auto' then key = 'auto' end
    if key then RS.db.options.mode = key; RS.print('Rotation: ' .. RS.modeName(key)); if RS.refresh then RS.refresh() end
    else RS.print('Rotations: auto, ' .. table.concat(RS.MODE_ORDER, ', ')) end
  elseif cmd == 'fights' then
    local n = tonumber(arg)
    if n then RS.db.options.fights = max(20, min(20000, floor(n))) end
    RS.print('A sim plays ' .. RS.db.options.fights .. ' fights.')
  elseif cmd == 'buffs' then
    if arg == 'on' or arg == 'off' then RS.setBuffs(arg == 'on') end
    RS.print('Raid buffs and debuffs: ' .. (RS.buffsOn() and 'on' or 'off') .. '.')
    if RS.refresh then RS.refresh() end
  elseif cmd == 'item' then
    local link = arg:match('(|c%x+|Hitem:.-|h.-|h|r)') or arg:match('(|Hitem:.-|h.-|h)')
    if not link then RS.print('Type /rsim item, a space, then Shift-click an item to put its link there.')
    elseif RS.showItem then RS.showItem(link) end
  elseif cmd == 'click' then
    if arg == 'on' or arg == 'off' then RS.db.options.itemClick = arg == 'on' end
    RS.print('Shift + right-click on an item ' .. (RS.db.options.itemClick and 'sims it.' or 'does nothing here.'))
  elseif cmd == 'test' then
    local ok, lines = RS.selfTest()
    for i = 1, #lines do RS.print(lines[i]) end
    RS.print(ok and 'The maths check passed: the addon plays the same fights as the website.' or 'The maths check FAILED. Type /rsim dump and send the text.')
  elseif cmd == 'dump' then
    local text = RS.dumpText()
    if RS.showDump then RS.showDump(text) else RS.print('The dump is saved; it is written to the saved variables when you log out.') end
  else
    for i = 1, #HELP do RS.print(HELP[i]) end
  end
end
