-- The fight itself, carried over from the website's simulate() function by function (same names, same order, same
-- random numbers). RS.simulateOnce = one fight; RS.simulate = many fights averaged.
-- Left out on purpose (nothing here changes a fight): the fight log and the timeline lists (events, mana, casts).
-- tools/check-ret-engine.js compares damage, hits, crits, misses and mana with the website's engine, fight by fight.
-- No game API in this file.
-- The fight's state lives in one table (st) instead of local variables: the game's Lua allows 60 upvalues a function.
local ADDON, RS = ...

local min, max, huge, sort, remove = math.min, math.max, math.huge, table.sort, table.remove

function RS.simulateOnce(c, mode, seed)
  local R = RS.makeRng(seed)
  if not c.hasSoC and (mode.P == 'soc' or mode.R == 'soc') then
    local m = {}
    for k, x in pairs(mode) do m[k] = x end
    m.P, m.twist = 'sor', false
    mode = m
  end
  local T = c.fight
  local S = {}
  local useUW = c.unsealedWrath and mode.twist
  local sp0 = c.sp + c.champSP
  local st = {
    mana = c.mana, total = 0,
    seal = c.opener and 'crusader' or mode.P, sealExp = 28.5,
    storeType = nil, storeN = 0, storeExp = 0, released = false,
    vSt = 0, vExp = -1, jotcExp = c.jotcExt and huge or -1, consUntil = -1, cdTide = 0,
    nextSwing = 0.5, gcd = 0, cdJ = 0, cdHS = 0, cdExo = 0, cdHoW = 0, cdCons = 0, cdShock = 0, cdPot = 0, cdRune = 0,
    cdTotg = 0, cdChili = 0, formStacks = 0, formUntil = -1, nowT = 0, nextMana = 2,
    echoes = 0, swings = 0, blocked = 0, manaUsed = 0,
  }
  local consTicks, blk = {}, {}
  local execAt = T * (1 - c.executePct / 100)
  local chili, wf   -- defined further down, used by the seal effects

  local function veng(t) return 1 + (t < st.vExp and st.vSt * c.vengPct * c.vengRank / 100 or 0) end
  local function onCrit(t) st.vSt = min(c.vengStacks, (t < st.vExp and st.vSt or 0) + 1); st.vExp = t + 30 end
  local function spNow(t) return sp0 + (t < st.jotcExp and c.jotc or 0) + (t < st.formUntil and c.formSP or 0) end
  local function holy(t) return veng(t) * c.twoH * (t < st.consUntil and 1 + c.consecratedGround / 100 or 1) end
  local function wpn() return c.wMin + R() * (c.wMax - c.wMin) + (c.ap + (st.nowT < st.formUntil and c.formAP or 0)) / 14 * c.wSpeed end
  local function rnd(a, b) return a + R() * (b - a) end
  local function rec(src, dmg, res)
    local s = S[src]
    if not s then s = { dmg = 0, n = 0, crit = 0, miss = 0 }; S[src] = s end
    s.n = s.n + 1; s.dmg = s.dmg + dmg; st.total = st.total + dmg
    if res == 'crit' then s.crit = s.crit + 1 end
    if res == 'miss' or res == 'dodge' then s.miss = s.miss + 1 end
  end
  local function rollWhite()
    local r = R() * 100
    local a = c.miss
    if r < a then return 'miss' end
    a = a + c.dodge; if r < a then return 'dodge' end
    a = a + c.glance; if r < a then return 'glance' end
    a = a + c.crit + (st.nowT < st.formUntil and c.formCrit or 0); if r < a then return 'crit' end
    return 'hit'
  end
  local function rollMelee(dodgeable)
    local r = R() * 100
    local a = c.miss
    if r < a then return 'miss' end
    if dodgeable then a = a + c.dodge; if r < a then return 'dodge' end end
    a = a + c.crit; if r < a then return 'crit' end
    return 'hit'
  end
  local function rollSpell()
    if R() * 100 < c.spellMiss then return 'miss' end
    return R() * 100 < c.spellCrit and 'crit' or 'hit'
  end
  local function pay(key, cost)
    if st.mana >= cost then st.mana = st.mana - cost; st.manaUsed = st.manaUsed + cost; blk[key] = false; return true end
    if not blk[key] then blk[key] = true; st.blocked = st.blocked + 1 end
    return false
  end
  local function missed(r) return r == 'miss' or r == 'dodge' end

  local function sealEffect(type, t, echo)
    local tag = echo and ' (echo)' or ''
    if type == 'sor' then
      local lo, hi = 2068 / 87 + 0.0765 * spNow(t), 2068 / 25 + 0.12 * spNow(t)
      local d = (lo + (c.sorF0 + c.sorF1 * c.wSpeed) * (hi - lo)) * c.impSeals * holy(t)
      local sc = R() * 100 < c.crit
      if sc then d = d * 2; onCrit(t) end
      rec('Seal of Righteousness' .. tag, d, sc and 'crit' or 'hit')
    elseif type == 'soc' then
      if R() < c.socPPM * c.wSpeed / 60 then
        local res = rollMelee(true)
        if missed(res) then rec('Seal of Command' .. tag, 0, res); return end
        local w = wpn()
        local d = (w * c.socPct / 100 + c.socSpCoef * spNow(t)) * c.impSeals * holy(t)
        if res == 'crit' then d = d * 2 end
        rec('Seal of Command' .. tag, d, res)
        if res == 'crit' then onCrit(t) end
        chili(t)
      end
    elseif type == 'fury' then
      local d = (c.furyFlat + c.furyCoef * spNow(t)) * c.impSeals * holy(t)
      rec('Seal of Fury' .. tag, d, 'hit')
    end
  end

  local function swing(t)
    st.swings = st.swings + 1; st.nowT = t
    local res = rollWhite()
    if missed(res) then rec('Autoattack', 0, res); return end
    local w = wpn()
    local d = (w + (c.arthas and 8 or 0)) * c.twoH * c.armorMult * veng(t)
    if res == 'glance' then d = d * c.glanceDmg / 100 end
    if res == 'crit' then d = d * 2 end
    rec('Autoattack', d, res)
    if res == 'crit' then onCrit(t) end
    if c.hanna then
      st.formStacks = st.formStacks + 1
      if st.formStacks >= 30 then
        st.formStacks = 0; st.formUntil = t + 20
        local fr = rollMelee(true)
        if missed(fr) then rec('Perfected Form', 0, fr)
        else
          local fd = 490 * c.twoH * c.armorMult * veng(t) * (fr == 'crit' and 2 or 1)
          rec('Perfected Form', fd, fr)
          if fr == 'crit' then onCrit(t) end
        end
      end
    end
    wf(t); chili(t)
    local seal = st.seal
    if useUW and st.storeN > 0 and t < st.storeExp and st.storeType ~= seal and seal ~= 'crusader' then
      local n, ty = st.storeN, st.storeType
      for i = 1, n do sealEffect(ty, t, true) end
      st.echoes = st.echoes + n
      st.storeType, st.storeN, st.storeExp = nil, 0, 0
    end
    if seal ~= 'crusader' then sealEffect(seal, t, false) end
    if mode.twist and seal == mode.R then st.released = true end
    if useUW and seal ~= 'crusader' then
      if st.storeType ~= seal or t >= st.storeExp then st.storeType, st.storeN, st.storeExp = seal, 0, 0 end
      st.storeN = min(3, st.storeN + 1); st.storeExp = t + c.uwDur
    end
    if c.jow and R() < 0.5 then st.mana = min(c.mana, st.mana + c.jowMana) end
    if c.race == 'undead' and t >= st.cdTotg and R() < 0.2 then rec('Touch of the Grave', c.totgDmg, 'hit'); st.cdTotg = t + 15 end
  end

  local function judge(t)
    if not pay('judge', c.judgeCost * c.bened) then return end
    st.cdJ = t + c.judgeCd - c.impJudge
    if R() < c.sanctified then st.mana = min(c.mana, st.mana + 0.6 * c.sealCost * c.bened) end
    if st.seal == 'crusader' then
      local r = rollMelee(false)
      rec('Judgement of the Crusader', 0, r == 'miss' and 'miss' or 'hit')
      if r ~= 'miss' then st.jotcExp = t + c.jotcDur end
      return
    end
    local isC = st.seal == 'soc'
    local name = isC and 'Judgement of Command' or 'Judgement of Righteousness'
    local r = rollMelee(isC)   -- Judgement of Command is a melee attack, the others ranged
    if missed(r) then rec(name, 0, r); return end
    local base
    if isC then base = rnd(c.jocMin, c.jocMax) + c.jocCoef * spNow(t) else base = rnd(c.jorMin, c.jorMax) + c.jorCoef * spNow(t) end
    local d = base * c.impSeals * holy(t) * (c.judgeMult or 1)
    if r == 'crit' then d = d * 2 end
    rec(name, d, r)
    if r == 'crit' then onCrit(t) end
    if isC then wf(t); chili(t) end
  end

  local function castSeal(type, t)
    if not pay('seal', c.sealCost * c.bened) then return false end
    st.seal = type; st.sealExp = t + 30
    if mode.twist and type == mode.R then st.released = false end
    return true
  end

  local function spell(name, mn, mx, t)
    local r = rollSpell()
    if r == 'miss' then rec(name, 0, 'miss'); return end
    local d = (rnd(mn, mx) + c.spellCoef * spNow(t)) * holy(t)
    if r == 'crit' then d = d * 1.5 end
    rec(name, d, r)
    if r == 'crit' then onCrit(t) end
  end

  local function ranged(name, mn, mx, t)
    local r = rollMelee(false)
    if missed(r) then rec(name, 0, r); return end
    local d = (rnd(mn, mx) + c.spellCoef * spNow(t)) * holy(t)
    if r == 'crit' then d = d * 2 end
    rec(name, d, r)
    if r == 'crit' then onCrit(t) end
  end

  function chili(t)
    if not c.chili or t < st.cdChili or R() * 100 >= c.chiliChance then return end
    st.cdChili = t + c.chiliCd
    local r = rollSpell()
    if r == 'miss' then rec('Dragonbreath Chili', 0, 'miss'); return end
    local d = (c.chiliBase + c.chiliCoef * (c.sp + c.champSP - (c.holyOnly or 0))) * (r == 'crit' and 1.5 or 1) * (c.coe and 1.1 or 1)
    rec('Dragonbreath Chili', d, r)
  end
  -- Windfury Totem: chance for an extra weapon attack with bonus attack power; it neither stores nor releases Unsealed Wrath copies
  function wf(t)
    if not c.wfTotem or R() * 100 >= c.wfChance then return end
    local cr = R() * 100 < c.crit
    local w = wpn()
    local d = (w + c.wfAP / 14 * c.wSpeed + (c.arthas and 8 or 0)) * c.twoH * c.armorMult * veng(t)
    if cr then d = d * 2 end
    chili(t)
    rec('Windfury Totem', d, cr and 'crit' or 'hit')
    if cr then onCrit(t) end
  end
  local function holyStrike(t)
    local r = rollMelee(true)
    if missed(r) then rec('Holy Strike', 0, r); return end
    local a = rnd(c.wMin, c.wMax)
    local b = rnd(c.hsMin, c.hsMax)
    local d = ((a + c.ap / 14 * c.hsNorm) * c.hsPct / 100 + b + c.hsCoef * spNow(t)) * c.arbiter * holy(t)
    if r == 'crit' then d = d * 2 end
    rec('Holy Strike', d, r)
    if r == 'crit' then onCrit(t) end
    if c.sacredArbiter and t < st.jotcExp and not c.jotcExt then st.jotcExp = t + c.jotcDur end
    if st.seal ~= 'crusader' then sealEffect(st.seal, t, false) end
    wf(t); chili(t)
  end

  local function wantSeal(t)
    if not useUW then return mode.P end
    if st.seal == mode.R then return st.released and mode.P or mode.R end
    if st.seal == mode.P and st.storeType == mode.P and st.storeN >= mode.N and t < st.storeExp then return mode.R end
    return mode.P
  end

  local ORDER = mode.shock and { 'shock', 'hs', 'cons', 'how', 'exo' }
    or c.swapFirst and { 'how', 'swap', 'hs', 'exo', 'cons' } or { 'how', 'hs', 'exo', 'swap', 'cons' }
  local function gcdAction(t)
    local w = wantSeal(t)
    if st.seal == 'crusader' or st.sealExp - t < c.gcd + 0.5 then
      if castSeal(st.seal == 'crusader' and mode.P or w, t) then return true end
    end
    local exec = t >= execAt
    for i = 1, #ORDER do
      local a = ORDER[i]
      if a == 'swap' and w ~= st.seal then
        if castSeal(w, t) then return true end
      elseif a == 'how' and c.useHoW and exec and t >= st.cdHoW then
        if pay('how', c.howCost * c.bened * c.conduit) then st.cdHoW = t + c.howCd; ranged('Hammer of Wrath', c.howMin, c.howMax, t); return true end
      elseif a == 'hs' and t >= st.cdHS then
        if pay('hs', c.hsCost * c.bened) then st.cdHS = t + c.hsCd; holyStrike(t); return true end
      elseif a == 'exo' and c.undead and t >= st.cdExo then
        if pay('exo', c.exoCost * c.bened * c.conduit) then st.cdExo = t + c.exoCd; spell('Exorcism', c.exoMin, c.exoMax, t); return true end
      elseif a == 'shock' and c.hasShock and t >= st.cdShock then
        if pay('shock', c.shockCost * c.bened) then st.cdShock = t + c.shockCd; spell('Holy Shock', c.shockMin, c.shockMax, t); return true end
      elseif a == 'cons' and t >= st.cdCons and st.mana >= c.consMinPct / 100 * c.mana then
        if pay('cons', c.consCost * c.bened * c.conduit) then
          st.cdCons = t + c.consCd; st.consUntil = t + 8
          for k = 1, 8 do consTicks[#consTicks + 1] = t + k end
          sort(consTicks)
          return true
        end
      end
    end
    return false
  end

  local function consTick(t)
    local d = (c.consTotal / 8 + c.consCoef * spNow(t)) * holy(t) * min(max(1, c.targets), 4)
    local cr = rollSpell()
    if cr == 'miss' then rec('Consecration', 0, 'miss'); return end
    rec('Consecration', cr == 'crit' and d * 1.5 or d, cr)
  end

  if c.sapper then
    local r = rollSpell()
    if r == 'miss' then rec('Goblin Sapper Charge', 0, 'miss') else rec('Goblin Sapper Charge', c.sapperDmg * (r == 'crit' and 1.5 or 1), r) end
  end
  local swingT = c.wSpeed / (1 + (c.haste or 0) / 100)
  local t = 0
  for guard = 1, 200000 do
    while st.nextSwing <= t + 1e-9 do swing(st.nextSwing); st.nextSwing = st.nextSwing + swingT end
    while consTicks[1] and consTicks[1] <= t + 1e-9 do consTick(remove(consTicks, 1)) end
    while st.nextMana <= t + 1e-9 do st.mana = min(c.mana, st.mana + c.mp5 * 0.4); st.nextMana = st.nextMana + 2 end
    if c.manaTide and t >= st.cdTide and st.mana <= c.mana - 1160 then st.mana = st.mana + 1160; st.cdTide = t + 300 end
    if c.potions and t >= st.cdPot and st.mana <= c.mana - 2250 then st.mana = st.mana + rnd(1350, 2250); st.cdPot = t + 120 end
    if c.runes and t >= st.cdRune and st.mana <= c.mana - 1500 then st.mana = st.mana + rnd(900, 1500); st.cdRune = t + 120 end
    if t >= st.cdJ and st.seal ~= 'fury' then judge(t) end
    if t >= st.gcd then if gcdAction(t) then st.gcd = t + c.gcd + c.latency end end
    local n = min(st.nextSwing, st.nextMana, consTicks[1] or huge)
    local x = st.gcd;     if x > t + 1e-9 and x < n then n = x end
    x = st.cdJ;           if x > t + 1e-9 and x < n then n = x end
    x = st.cdHS;          if x > t + 1e-9 and x < n then n = x end
    x = st.cdExo;         if x > t + 1e-9 and x < n then n = x end
    x = st.cdHoW;         if x > t + 1e-9 and x < n then n = x end
    x = st.cdCons;        if x > t + 1e-9 and x < n then n = x end
    x = st.cdShock;       if x > t + 1e-9 and x < n then n = x end
    x = execAt;           if x > t + 1e-9 and x < n then n = x end
    if n >= T then break end
    t = n
  end
  return { dps = st.total / T, S = S, mana = st.mana, echoes = st.echoes, swings = st.swings, blocked = st.blocked, manaUsed = st.manaUsed }
end

-- Many fights with the website's seeds (seed * 7919 + fight * 104729): mean DPS and the totals per damage source.
function RS.simulate(c, mode, seed, fights)
  local sum, S = 0, {}
  local mana, echoes, blocked, manaUsed = 0, 0, 0, 0
  local dps = {}
  for j = 0, fights - 1 do
    local r = RS.simulateOnce(c, mode, seed * 7919 + j * 104729)
    dps[j + 1] = r.dps; sum = sum + r.dps
    mana = mana + r.mana; echoes = echoes + r.echoes; blocked = blocked + r.blocked; manaUsed = manaUsed + r.manaUsed
    for k, b in pairs(r.S) do
      local a = S[k]
      if not a then a = { dmg = 0, n = 0, crit = 0, miss = 0 }; S[k] = a end
      a.dmg = a.dmg + b.dmg; a.n = a.n + b.n; a.crit = a.crit + b.crit; a.miss = a.miss + b.miss
    end
  end
  local n = fights
  local mean, var = sum / n, 0
  for i = 1, n do var = var + (dps[i] - mean) ^ 2 end
  return { mean = mean, sd = math.sqrt(var / max(1, n - 1)), n = n, dps = dps, S = S, mana = mana / n, echoes = echoes / n, blocked = blocked / n, manaUsed = manaUsed / n }
end
