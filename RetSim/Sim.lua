-- The fight itself, carried over from the website's simulate() function by function (same names, same order, same
-- random numbers). RS.simulateOnce = one fight; RS.simulate = many fights averaged.
-- Left out on purpose (nothing here changes a fight): the fight log and the timeline lists (events, mana, casts).
-- tools/check-ret-engine.js compares damage, hits, crits, misses and mana with the website's engine, fight by fight.
-- No game API in this file.
-- The fight's state lives in one table (st) instead of local variables: the game's Lua allows 60 upvalues a function.
local ADDON, RS = ...
if RS.notPaladin then return end   -- not a Paladin: nothing of the addon loads (Class.lua)

local min, max, huge, sort, remove, floor = math.min, math.max, math.huge, table.sort, table.remove, math.floor

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
    cdTotg = 0, cdChili = 0, formStacks = 0, formUntil = -1, nowT = 0, curT = 0, nextMana = 2, inExtra = false,
    echoes = 0, swings = 0, blocked = 0, manaUsed = 0,
  }
  local consTicks, blk = {}, {}
  local execAt = T * (1 - c.executePct / 100)
  local chili, wf, itemProcs, swing   -- defined further down, used by the seal effects
  local CAST_EV = { cast = true, cons = true, how = true, judge = true, sealcast = true }
  -- "Chance on hit" effects of the worn items: up = buff or armour debuff runs until, left/next = damage over time, late = delayed hit
  local PR = {}
  local function addEffect(p) PR[#PR + 1] = { p = p, up = -1, left = 0, next = huge, late = huge, cd = -1, n = 0, upT = 0, useAt = p.use and 0 or huge, need = 0, needEnd = huge, stk = 0 } end
  for i = 1, #(c.procs or {}) do addEffect(c.procs[i]) end
  if RS.COMBAT_POTS[c.combatPot] then
    local pots = RS.procList({ RS.COMBAT_POTS[c.combatPot] }, 1)
    for i = 1, #pots do addEffect(pots[i]) end
  end
  local useLock = {}
  local function pBuff(t, k)
    local a = 0
    for i = 1, #PR do local x = PR[i]; if t < x.up and x.p.buff and x.p.buff[k] then a = a + x.p.buff[k] end end
    return a
  end
  -- a buff to all stats counts as Blade of Hanna's does: Attack Power from Strength, crit from Agility, spell damage from Intellect
  local function pAP(t) if #PR == 0 then return 0 end return (pBuff(t, 'str') + pBuff(t, 'all')) * c.strAP + pBuff(t, 'ap') end
  local function pCrit(t) if #PR == 0 then return 0 end return pBuff(t, 'crit') + (pBuff(t, 'all') + pBuff(t, 'agi')) * c.formCrit / 20 end
  local function pStack(t)
    local a = 0
    for i = 1, #PR do local x = PR[i]; if x.p.stack and t < x.up then a = a + x.stk * x.p.stack.sp end end
    return a
  end
  local function pSP(t) if #PR == 0 then return 0 end return pBuff(t, 'sp') + pBuff(t, 'all') * c.formSP / 20 + pStack(t) end
  local function armorAt(t)
    local a = 0
    for i = 1, #PR do local x = PR[i]; if t < x.up and x.p.armor then a = a + x.p.armor[1] end end
    if a == 0 then return c.armorMult end
    local ar = max(0, c.armorF - a)
    return 1 - ar / (ar + 400 + 85 * (60 + 4.5))
  end

  local function veng(t) return 1 + (t < st.vExp and st.vSt * c.vengPct * c.vengRank / 100 or 0) end
  local function onCrit(t)
    -- a buff that ends on your next crit
    for i = 1, #PR do local x = PR[i]; if x.p.buff and x.p.buff.tillCrit and t < x.up then x.upT = x.upT - max(0, min(x.up, T) - t); x.up = t end end
    st.vSt = min(c.vengStacks, (t < st.vExp and st.vSt or 0) + 1); st.vExp = t + 30
  end
  local jotcVal = c.jotc + (c.jotcExt and (c.jotcExtFervor and 33 or 0) or (c.jotcLibram or 0))   -- the Judgement carries the libram of whoever put it up
  local function spNow(t) return sp0 + (t < st.jotcExp and jotcVal or 0) + (t < st.formUntil and c.formSP or 0) + pSP(t) end
  local function holy(t) return veng(t) * c.twoH * (t < st.consUntil and 1 + c.consecratedGround / 100 or 1) end
  local function wpn() return c.wMin + R() * (c.wMax - c.wMin) + (c.ap + (st.nowT < st.formUntil and c.formAP or 0) + pAP(st.curT)) / 14 * c.wSpeed end
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
    a = a + c.crit + (st.nowT < st.formUntil and c.formCrit or 0) + pCrit(st.curT); if r < a then return 'crit' end
    return 'hit'
  end
  local function rollMelee(dodgeable)
    local r = R() * 100
    local a = c.miss
    if r < a then return 'miss' end
    if dodgeable then a = a + c.dodge; if r < a then return 'dodge' end end
    a = a + c.crit + pCrit(st.curT); if r < a then return 'crit' end
    return 'hit'
  end
  local function rollSpell()
    if R() * 100 < (#PR > 0 and max(1, c.spellMiss - pBuff(st.curT, 'spellHit')) or c.spellMiss) then return 'miss' end
    return R() * 100 < c.spellCrit + pCrit(st.curT) and 'crit' or 'hit'
  end
  local function pay(key, cost)
    if #PR > 0 then cost = max(0, cost - pBuff(st.curT, 'cost')) end
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
      local sc = R() * 100 < c.crit + pCrit(t)
      if sc then d = d * 2; onCrit(t) end
      rec('Seal of Righteousness' .. tag, d, sc and 'crit' or 'hit')
      if not echo then itemProcs(t, 'sor') end
    elseif type == 'soc' then
      if R() < c.socPPM * c.wSpeed / 60 then
        local res = rollMelee(true)
        if missed(res) then rec('Seal of Command' .. tag, 0, res); return end
        local w = wpn()
        local d = (w * c.socPct / 100 + c.socSpCoef * spNow(t)) * c.impSeals * holy(t)
        if res == 'crit' then d = d * 2 end
        rec('Seal of Command' .. tag, d, res)
        if res == 'crit' then onCrit(t) end
        chili(t); if not echo then itemProcs(t, 'soc') end
      end
    elseif type == 'fury' then
      local d = (c.furyFlat + c.furyCoef * spNow(t)) * c.impSeals * holy(t)
      rec('Seal of Fury' .. tag, d, 'hit')
    end
  end

  function swing(t)
    st.swings = st.swings + 1; st.nowT = t; st.curT = t
    local res = rollWhite()
    if missed(res) then rec('Autoattack', 0, res); return end
    local w = wpn()
    local d = (w + (c.arthas and 8 or 0)) * c.twoH * armorAt(t) * veng(t)
    if res == 'glance' then d = d * c.glanceDmg / 100 end
    if res == 'crit' then d = d * 2 end
    rec('Autoattack', d, res)
    if not c.jotcExt and t < st.jotcExp then st.jotcExp = t + c.jotcDur end   -- a landed swing keeps your own Judgement up
    if res == 'crit' then onCrit(t) end
    if c.hanna then
      st.formStacks = st.formStacks + 1
      if st.formStacks >= 30 then
        st.formStacks = 0; st.formUntil = t + 20
        local fr = rollMelee(true)
        if missed(fr) then rec('Perfected Form', 0, fr)
        else
          local fd = 490 * c.twoH * armorAt(t) * veng(t) * (fr == 'crit' and 2 or 1)
          rec('Perfected Form', fd, fr)
          if fr == 'crit' then onCrit(t) end
        end
      end
    end
    wf(t); chili(t); itemProcs(t, 'white')
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
    itemProcs(t, 'judge')
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
    if isC then wf(t); chili(t); itemProcs(t, 'joc'); itemProcs(t, 'joc2') end
  end

  local function castSeal(type, t)
    if not pay('seal', c.sealCost * c.bened) then return false end
    st.seal = type; st.sealExp = t + 30
    if mode.twist and type == mode.R then st.released = false end
    itemProcs(t, 'sealcast')
    return true
  end

  local function spell(name, mn, mx, t)
    itemProcs(t, 'cast')
    local r = rollSpell()
    if r == 'miss' then rec(name, 0, 'miss'); return end
    local d = (rnd(mn, mx) + c.spellCoef * spNow(t)) * holy(t)
    if r == 'crit' then d = d * 1.5 end
    rec(name, d, r)
    if r == 'crit' then onCrit(t) end
  end

  local function ranged(name, mn, mx, t)
    itemProcs(t, 'how')
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
    local cr = R() * 100 < c.crit + pCrit(t)
    local w = wpn()
    local d = (w + c.wfAP / 14 * c.wSpeed + (c.arthas and 8 or 0)) * c.twoH * armorAt(t) * veng(t)
    if cr then d = d * 2 end
    chili(t)
    rec('Windfury Totem', d, cr and 'crit' or 'hit')
    if not c.jotcExt and t < st.jotcExp then st.jotcExp = t + c.jotcDur end
    if cr then onCrit(t) end
    itemProcs(t, 'wf')
  end
  -- "Chance on hit" effects of items, as measured on Forever: a white hit, a Windfury attack, Holy Strike, a Seal of Command
  -- strike and a Seal of Righteousness hit each roll once, Judgement of Command twice; Unsealed Wrath copies do not roll.
  -- Chance per roll = procs per minute x weapon speed / 60 (base speed, haste does not lower it). No spell power in the damage.
  -- A Physical proc is a melee strike (melee table, armor); cast off a white swing it rolls the procs once more.
  local function pTg(p)
    if not p.aoe then return 1 end
    local k = min(max(1, c.targets), p.aoe)
    if not p.chain then return k end
    local a, m = 0, 1
    for i = 1, k do a = a + m; m = m * p.chain end
    return a
  end
  local function pHit(x, d, school, t)
    local p, tg = x.p, pTg(x.p)
    if p.ah then
      local cr = R() * 100 < c.crit + pCrit(t)
      d = d * ((cr and 2 or 1) * tg)
      rec(p.n, d, cr and 'crit' or 'hit')
      return true
    end
    if school == 'phys' then
      local r = rollMelee(true)
      if missed(r) then rec(p.n, 0, r); return false end
      d = d * (armorAt(t) * veng(t) * (r == 'crit' and 2 or 1) * tg)
      rec(p.n, d, r)
      if r == 'crit' then onCrit(t) end
      return true
    end
    local r
    if p.nc then r = R() * 100 < c.spellMiss and 'miss' or 'hit' else r = rollSpell() end
    if r == 'miss' then rec(p.n, 0, 'miss'); return false end
    d = d * ((r == 'crit' and 1.5 or 1) * (school == 'fire' and c.coe and 1.1 or 1) * tg)
    rec(p.n, d, r)
    if r == 'crit' then onCrit(t) end
    return true
  end
  local function pTick(x, d, school, t, res)
    local p, tg = x.p, pTg(x.p)
    local m = 1
    if school == 'phys' or school == 'bleed' then m = veng(t) elseif school == 'fire' and c.coe then m = 1.1 end
    rec(p.n, d * tg * m, res or 'hit')
  end
  local function pFire(x, t, ev)
    local p = x.p
    x.n = x.n + 1
    local melee
    if p.dd then melee = p.dd[3] == 'phys' else melee = p.dot ~= nil and (p.dot[4] == 'bleed' or p.dot[4] == 'phys') end
    local landed = true
    if p.after and ev == 'use' then x.need = floor(rnd(p.after[1], p.after[2] + 1)); x.needEnd = t + (p.afterDur or huge); return end
    if p.stack then x.stk = 0 end
    if p.dd then
      local d = rnd(p.dd[1], p.dd[2])
      if p.exec and t >= T * (1 - p.exec[1] / 100) then d = d * p.exec[2] end
      landed = pHit(x, d, p.dd[3], t)
    elseif p.dot and not p.sure then
      if melee then
        local r = rollMelee(true)
        if missed(r) then rec(p.n, 0, r); landed = false end
      elseif R() * 100 < c.spellMiss then
        rec(p.n, 0, 'miss'); landed = false
      end
    end
    if not landed then return end
    if p.dot then x.left = p.dot[3]; x.next = t + p.dot[2] end
    if p.late and x.late == huge then x.late = t + p.late[2] end   -- a second proc neither adds nor refreshes the delayed hit
    local dur = p.buff and p.buff.dur or p.armor and p.armor[2] or 0
    if dur ~= 0 then
      x.upT = x.upT + max(0, min(t + dur, T) - max(t, min(x.up, T)))
      x.up = t + dur
    end
    if p.mana then st.mana = min(c.mana, st.mana + p.mana) end
    if p.extra then st.inExtra = true; swing(t); st.inExtra = false end
    if melee and ev == 'white' then itemProcs(t, 'chain') end
  end
  function itemProcs(t, ev)
    for i = 1, #PR do
      local x = PR[i]
      local p = x.p
      if ev ~= 'joc' and ev ~= 'joc2' and ev ~= 'chain' and ev ~= 'sealcast' then
        if x.need > 0 then
          if t > x.needEnd then x.need = 0
          else
            x.need = x.need - 1
            if x.need == 0 then x.n = x.n - 1; pFire(x, t, 'after') end
          end
        end
        if p.stack and t < x.up and ev ~= 'white' and ev ~= 'wf' and x.stk < p.stack.max then x.stk = x.stk + 1 end
      end
      if not p.follow and p.ev[ev] and t >= x.cd and not (p.extra and st.inExtra)
        and R() < (p.pct and p.pct / 100 or p.ppm * (CAST_EV[ev] and 1.5 or c.wSpeed) / 60) then
        if p.icd then x.cd = t + p.icd end
        local y = x
        if p.pick then
          local r, k = R() * p.pickW, -1
          for q = 1, #p.pick do
            local e = p.pick[q]
            if r < e[1] then k = e[2]; break end
            r = r - e[1]
          end
          y = k >= 0 and PR[i + k] or nil
        end
        if y then pFire(y, t, ev) end
      end
    end
  end
  local function procTicks(t)
    for i = 1, #PR do
      local x = PR[i]
      while x.next <= t + 1e-9 do
        pTick(x, x.p.dot[1], x.p.dot[4], x.next)
        x.left = x.left - 1
        x.next = x.left > 0 and x.next + x.p.dot[2] or huge
      end
      if x.late <= t + 1e-9 then
        local cr = R() * 100 < c.spellCrit + pCrit(t)
        pTick(x, x.p.late[1] * (cr and 1.5 or 1), x.p.late[3], x.late, cr and 'crit' or 'hit')
        x.late = huge
      end
    end
  end
  local function holyStrike(t)
    local r = rollMelee(true)
    if missed(r) then rec('Holy Strike', 0, r); return end
    local a = rnd(c.wMin, c.wMax)
    local b = rnd(c.hsMin, c.hsMax)
    local d = ((a + (c.ap + pAP(t)) / 14 * c.hsNorm) * c.hsPct / 100 + b + c.hsCoef * spNow(t)) * c.arbiter * holy(t)
    if r == 'crit' then d = d * 2 end
    rec('Holy Strike', d, r)
    if r == 'crit' then onCrit(t) end
    if c.sacredArbiter and t < st.jotcExp and not c.jotcExt then st.jotcExp = t + c.jotcDur end
    if st.seal ~= 'crusader' then sealEffect(st.seal, t, false) end
    wf(t); chili(t); itemProcs(t, 'hs')
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
          itemProcs(t, 'cons')
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
    st.curT = t
    if #PR > 0 then procTicks(t) end
    for i = 1, #PR do
      local x = PR[i]
      local u = x.p.use
      if x.need > 0 and t > x.needEnd then x.need = 0 end
      if u and t >= x.useAt - 1e-9 and t >= (useLock[u.g or 0] or 0) - 1e-9 and x.need <= 0
        and not (u.need and st.mana > c.mana - u.need) and not (u.gcd and t < st.gcd) then
        if u.gcd then st.gcd = t + c.gcd + c.latency end
        x.useAt = t + u.cd
        if u.lock then useLock[u.g or 0] = t + u.lock end
        pFire(x, t, 'use')
      end
    end
    while st.nextSwing <= t + 1e-9 do
      swing(st.nextSwing)
      st.nextSwing = st.nextSwing + swingT / (#PR > 0 and 1 + pBuff(st.nextSwing, 'haste') / 100 or 1)
    end
    st.curT = t
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
    for i = 1, #PR do
      local q = PR[i]
      if q.next < n then n = q.next end
      if q.late < n then n = q.late end
      if q.p.use then local a = max(q.useAt, useLock[q.p.use.g or 0] or 0); if a > t + 1e-9 and a < n then n = a end end
    end
    if n >= T then break end
    t = n
  end
  local procs = {}
  for i = 1, #PR do procs[i] = { n = PR[i].p.n, tx = PR[i].p.tx, count = PR[i].n, up = PR[i].upT / T } end
  return { dps = st.total / T, S = S, mana = st.mana, echoes = st.echoes, swings = st.swings, blocked = st.blocked, manaUsed = st.manaUsed, procs = procs }
end

-- Many fights with the website's seeds (seed * 7919 + fight * 104729): mean DPS and the totals per damage source.
function RS.simulate(c, mode, seed, fights)
  local sum, S = 0, {}
  local mana, echoes, blocked, manaUsed = 0, 0, 0, 0
  local dps, procs = {}, {}
  for j = 0, fights - 1 do
    local r = RS.simulateOnce(c, mode, seed * 7919 + j * 104729)
    dps[j + 1] = r.dps; sum = sum + r.dps
    mana = mana + r.mana; echoes = echoes + r.echoes; blocked = blocked + r.blocked; manaUsed = manaUsed + r.manaUsed
    for q = 1, #r.procs do
      local p = r.procs[q]
      local a = procs[q]
      if not a then a = { n = p.n, tx = p.tx, count = 0, up = 0 }; procs[q] = a end
      a.count = a.count + p.count / fights; a.up = a.up + p.up / fights
    end
    for k, b in pairs(r.S) do
      local a = S[k]
      if not a then a = { dmg = 0, n = 0, crit = 0, miss = 0 }; S[k] = a end
      a.dmg = a.dmg + b.dmg; a.n = a.n + b.n; a.crit = a.crit + b.crit; a.miss = a.miss + b.miss
    end
  end
  local n = fights
  local mean, var = sum / n, 0
  for i = 1, n do var = var + (dps[i] - mean) ^ 2 end
  return { mean = mean, sd = math.sqrt(var / max(1, n - 1)), n = n, dps = dps, S = S, mana = mana / n, echoes = echoes / n, blocked = blocked / n, manaUsed = manaUsed / n, procs = procs }
end
