// Runs the whole Ret addon against a stand-in for the game (tools/wow-mock.lua plus a paladin on top): start-up, the
// self-test, reading a character, a sim, the window, the dump and the slash commands. It proves that no line of the
// addon's own code fails on the way and that a character sheet is turned back into the right sim values - not that the
// window looks right or that the real game returns what the stand-in does; that is seen in the game only.
//   node check-ret-addon.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const { newLua } = require('./lua-host');
const { toLua } = require('./lua-ser');
const JS = require('./ret-js-engine');
const DIR = path.join(__dirname, '..', 'RetSim');
const toc = fs.readFileSync(path.join(DIR, 'RetSim.toc'), 'utf8').split(/\r?\n/).map(l => l.trim()).filter(l => l && l[0] !== '#');
toc.forEach(f => assert(fs.existsSync(path.join(DIR, f)), 'the .toc lists a file that does not exist: ' + f));
fs.readdirSync(DIR).filter(f => f.endsWith('.lua')).forEach(f => assert(toc.includes(f), f + ' is not in the .toc'));

// the character the stand-in shows: gear values v0, the Unsealed Wrath build, Kings and Mark of the Wild on it
const D = JS.defaults();
const v0 = Object.assign({}, D, { str: 251, int: 118, apGear: 164, crit: 9.4, hit: 4, exp: 1.2, sp: 96, spellCrit: 6.1, spellHit: 2, mana: 3010, mp5: 18, wMin: 152, wMax: 255, wSpeed: 3.6, haste: 1 });
const ranks = JS.PRESETS.ws;
const onYou = { kings: true, motw: true };
const sheetV = JS.applyTalents(ranks, Object.assign({}, v0));
for (const f of JS.FIELDS) if (f.g === 'buff') sheetV[f.k] = !!onYou[f.k];
const sc = JS.derive(sheetV);
const sheet = { str: sc.strF, agi: (65 + 12) * 1.1, int: sc.intF, ap: sc.ap, crit: sc.crit + sheetV.critSupp, hit: sc.hitF, exp: v0.exp, spHoly: v0.sp + sc.champSP, spellCrit: sc.spellCrit, spellHit: sc.spellHitF,
  mana: sc.mana, mp5: sc.mp5, haste: v0.haste, wMin: v0.wMin, wMax: v0.wMax, wSpeed: v0.wSpeed };
const TALENTS = []; { const page = fs.readFileSync(JS.file, 'utf8'); const a = page.indexOf('const TREES'), b = page.indexOf('\n];', a); new Function('return ' + page.slice(a + 14, b + 2))().forEach(tr => tr.t.forEach(t => TALENTS.push(t[0]))); }

function boot(cls) {
  const host = newLua();
  host.run(fs.readFileSync(path.join(__dirname, 'wow-mock.lua'), 'utf8'), '@wow-mock.lua');
  host.run(`
    PAL = { sheet = ${toLua(sheet)}, ranks = ${toLua(ranks)}, names = ${toLua(TALENTS)}, class = ${toLua(cls)}, combat = false }
    function UnitClass() return 'x', PAL.class end
    function UnitRace() return 'Human', 'Human' end
    function UnitLevel() return 60 end
    function InCombatLockdown() return PAL.combat end
    function UnitStat(_, i) local v = ({ PAL.sheet.str, PAL.sheet.agi, 180, PAL.sheet.int, 90 })[i]; return v, v, 0, 0 end
    function UnitAttackPower() return PAL.sheet.ap - 40, 40, 0 end
    function GetCritChance() return PAL.sheet.crit end
    function GetCombatRatingBonus(id) return ({ [6] = PAL.sheet.hit, [8] = PAL.sheet.spellHit, [18] = PAL.sheet.haste, [24] = PAL.sheet.exp })[id] or 0 end
    function GetHitModifier() return 0 end
    function GetSpellHitModifier() return 0 end
    function GetExpertisePercent() return PAL.sheet.exp end
    function GetMeleeHaste() return PAL.sheet.haste end
    function GetSpellBonusDamage(school) return school == 2 and PAL.sheet.spHoly or PAL.sheet.spHoly end
    function GetSpellCritChance() return PAL.sheet.spellCrit end
    function GetManaRegen() return 3, PAL.sheet.mp5 / 5 end
    function UnitPowerMax() return PAL.sheet.mana end
    function UnitDamage() return 300, 400, 0, 0, 0, 0, 1 end
    function UnitAttackSpeed() return PAL.sheet.wSpeed end
    function GetInventoryItemID(_, slot) return ({ [16] = 19323, [18] = 272435 })[slot] end
    function GetInventoryItemLink(_, slot) if slot == 16 then return '|cffa335ee|Hitem:19323:1900:0:0|h[The Unstoppable Force]|h|r' end end
    C_TooltipInfo = { GetInventoryItem = function() return { lines = { { leftText = 'The Unstoppable Force' }, { leftText = 'Two-Hand', rightText = 'Mace' },
      { leftText = PAL.sheet.wMin .. ' - ' .. PAL.sheet.wMax .. ' Damage', rightText = string.format('Speed %.2f', PAL.sheet.wSpeed) } } } end }
    MOCK.auras = { { name = 'Greater Blessing of Kings', spellId = 25898 }, { name = 'Mark of the Wild', spellId = 9885 }, { name = 'Retribution Aura', spellId = 10301 }, { name = 'Well Fed', spellId = 1 } }
    C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return 7 end }
    C_Traits = {
      GetConfigInfo = function() return { treeIDs = { 1 } } end,
      GetTreeNodes = function() local t = {}; for i = 1, #PAL.names do t[i] = i end; return t end,
      GetNodeInfo = function(_, node) return { ID = node, activeRank = PAL.ranks[PAL.names[node]] or 0, maxRanks = 5, entryIDs = { node } } end,
      GetEntryInfo = function(_, entry) return { definitionID = entry } end,
      GetDefinitionInfo = function(def) return { spellID = 1000 + def } end,
    }
    C_Spell = { GetSpellName = function(id) return PAL.names[id - 1000] end }
    math.random = function() return 4242 end
  `, '=paladin');
  for (const f of toc) {
    const src = fs.readFileSync(path.join(DIR, f), 'utf8');
    assert(!src.includes(']=====]'));
    host.run('return HOST.load([=====[' + src + ']=====], "@' + f + '")', '=load ' + f);
  }
  return host;
}
let failed = 0;
function steps(host) {
  return (name, code) => {
    const r = host.eval('local ok, e = xpcall(function() ' + code + ' end, debug.traceback); if not ok then return "ERR " .. tostring(e) end; return e');
    if (typeof r === 'string' && r.startsWith('ERR ')) { failed++; console.log('FAIL ' + name + '\n' + r.slice(4)); return null; }
    console.log('ok   ' + name + (r !== null && r !== undefined && r !== true ? ': ' + r : ''));
    return r;
  };
}
// another class: only the line in chat
{
  const h = boot('MAGE'), step = steps(h);
  step('a Mage logs in: only the line in chat, nothing else loads', `MOCK.fire("ADDON_LOADED", "RetSim"); MOCK.fire("PLAYER_LOGIN")
    assert(RSX.notPaladin and RSX.simulateOnce == nil and RSX.DEFAULTS == nil and RetSimDB == nil and RetSimFrame == nil, "something loaded")
    SlashCmdList.RETSIM(""); assert(#MOCK.chat == 2 and MOCK.chat[1]:find("cannot be used on other classes", 1, true), table.concat(MOCK.chat, " | "))`);
}
const host = boot('PALADIN'), step = steps(host);
const PUMP = 'local n = 0; while RSX.jobRunning() do MOCK.frame(); n = n + 1; if n > 2000000 then error("the job never ends") end end';
step('start-up', 'MOCK.fire("ADDON_LOADED", "SomethingElse"); assert(RSX.db == nil); MOCK.fire("ADDON_LOADED", "RetSim"); assert(RSX.db and RetSimDB.options.mode == "auto" and RetSimDB.options.fights == 300); MOCK.fire("PLAYER_LOGIN"); return MOCK.chat[#MOCK.chat]');
step('the maths check (/rsim test)', 'SlashCmdList.RETSIM("test"); assert(RSX.db.selfTest.ok, table.concat(RSX.db.selfTest.lines, " | ")); return #RSX.EXPECTED .. " fights equal the website"');
step('sim in combat without a character says so', 'PAL.combat = true; local ok, why = RSX.simCharacter(); PAL.combat = false; assert(not ok and why:find("in combat", 1, true)); return why');
step('read the character: the sheet turned back into the sim\'s values', `SlashCmdList.RETSIM("read"); local c, v = RSX.char, RSX.values; assert(c and v, "no character")
  local want = ${toLua({ str: v0.str + 100 * D.crusaderUptime / 100, int: v0.int, apGear: v0.apGear, crit: v0.crit, hit: v0.hit, exp: v0.exp, sp: v0.sp, spellCrit: v0.spellCrit, spellHit: v0.spellHit, mana: v0.mana, mp5: v0.mp5, wMin: v0.wMin, wMax: v0.wMax, wSpeed: v0.wSpeed, haste: v0.haste })}
  for k, x in pairs(want) do assert(math.abs(v[k] - x) < 1e-6, k .. ": " .. tostring(v[k]) .. " instead of " .. x) end
  local n = 0; for _, r in pairs(c.talents) do n = n + r end; assert(n == 51, "talent points " .. n)
  assert(c.buffsOnYou.kings and c.buffsOnYou.motw and not c.buffsOnYou.might, "buffs on you")
  assert(#c.otherAuras == 1 and c.otherAuras[1] == "Well Fed", "other auras: " .. table.concat(c.otherAuras, ","))
  assert(v.judgeMult == 1.04 and v.hanna == false and c.worn.mainEnchant == 1900 and c.raw.weaponFrom == "tooltip")
  return string.format("Str %.1f, Int %.1f, AP from gear %.1f, crit %.2f, weapon %d-%d at %.1f; notes: %s", v.str, v.int, v.apGear, v.crit, v.wMin, v.wMax, v.wSpeed, table.concat(RSX.valueNotes, " / "))`);
step('the weapon without a tooltip comes from the character sheet', `local keep = C_TooltipInfo; C_TooltipInfo = nil
  UnitDamage = function() local ap, s = PAL.sheet.ap, PAL.sheet.wSpeed; return (PAL.sheet.wMin + ap / 14 * s) * 1.06, (PAL.sheet.wMax + ap / 14 * s) * 1.06, 0, 0, 0, 0, 1.06 end
  UnitAttackSpeed = function() return PAL.sheet.wSpeed / (1 + PAL.sheet.haste / 100) end
  assert(RSX.doReadCharacter()); local v = RSX.values; C_TooltipInfo = keep
  assert(math.abs(v.wMin - PAL.sheet.wMin) < 1e-6 and math.abs(v.wMax - PAL.sheet.wMax) < 1e-6 and math.abs(v.wSpeed - PAL.sheet.wSpeed) < 1e-6, v.wMin .. " " .. v.wMax .. " " .. v.wSpeed)
  assert(RSX.doReadCharacter()); return RSX.char.raw.weaponFrom`);
// a sim with a fixed rotation and seed: the same fights in the website's engine
const FIGHTS = 40;
const expV = JS.applyTalents(ranks, Object.assign({}, v0, { str: v0.str + 100 * D.crusaderUptime / 100, judgeMult: 1.04, hanna: false, holyOnly: 0, race: 'human' }));
{
  const c = JS.derive(expV), m = JS.resolveMode('socSor', expV.wSpeed);
  let sum = 0; for (let i = 0; i < FIGHTS; i++) sum += JS.simulate(c, m, 4242 * 7919 + i * 104729, false).dps;
  step('sim (40 fights, 3x SoC -> SoR): the same DPS as the website with these values', `SlashCmdList.RETSIM("fights ${FIGHTS}"); SlashCmdList.RETSIM("mode socSor"); SlashCmdList.RETSIM("sim")
    assert(RetSimFrame and RetSimFrame:IsShown(), "window"); assert(RSX.jobRunning(), "no job"); ${PUMP}
    local r = RSX.last; assert(r and r.fights == ${FIGHTS}); assert(math.abs(r.mean - ${sum / FIGHTS}) < 1e-6, "DPS " .. r.mean .. " instead of ${sum / FIGHTS}")
    assert(MOCK.findLike("FontString", "DPS$"), "DPS not shown"); return string.format("%.2f DPS, %d damage sources, top: %s", r.mean, #r.rows, r.rows[1].name)`);
}
step('auto rotation: the best twist is tried first', `SlashCmdList.RETSIM("mode auto"); SlashCmdList.RETSIM("sim"); local _, total = RSX.jobProgress(); assert(total == ${FIGHTS} + 180, "total " .. tostring(total)); ${PUMP}
  local r = RSX.last; assert(r.mode.auto and RSX.MODES[r.mode.key].twist); return r.mode.name .. string.format(", %.1f DPS", r.mean)`);
step('buffs off lowers the result; on again', `local with = RSX.last.mean; SlashCmdList.RETSIM("buffs off"); assert(not RSX.buffsOn()); SlashCmdList.RETSIM("sim"); ${PUMP}
  local without = RSX.last.mean; assert(without < with * 0.9, with .. " -> " .. without); SlashCmdList.RETSIM("buffs on"); assert(RSX.buffsOn() and RSX.db.settings.jotcExt == false); return string.format("%.1f -> %.1f DPS", with, without)`);
step('the buttons: Sim, Stop, rotation, buffs', `MOCK.click("Sim"); assert(RSX.jobRunning()); MOCK.frame(); MOCK.click("Stop"); assert(not RSX.jobRunning())
  local before = RSX.db.options.mode; MOCK.click(RSX.modeName(before)); assert(RSX.db.options.mode ~= before); MOCK.click("Buffs: on"); assert(not RSX.buffsOn()); MOCK.click("Buffs: off"); assert(RSX.buffsOn())
  return "rotation now " .. RSX.modeName(RSX.db.options.mode)`);
step('sim in combat uses the character read before', `PAL.combat = true; local ok = RSX.simCharacter(); assert(ok); ${PUMP}; PAL.combat = false; return string.format("%.1f DPS", RSX.last.mean)`);
step('the dump', `SlashCmdList.RETSIM("dump"); assert(RetSimDumpFrame and RetSimDumpFrame:IsShown()); local t = RSX.db.dump
  for _, w in ipairs({ "attackPower", "weaponFrom = tooltip", "talentsFound = 51", "simValues", "Well Fed", "selfTest" }) do assert(t:find(w, 1, true), "the dump lacks " .. w) end; return #t .. " characters"`);
step('open and close with /rsim; help and unknown words', 'RetSimFrame:Hide(); SlashCmdList.RETSIM(""); assert(RetSimFrame:IsShown()); SlashCmdList.RETSIM(""); assert(not RetSimFrame:IsShown()); local n = #MOCK.chat; SlashCmdList.RETSIM("help"); assert(#MOCK.chat > n + 4); SlashCmdList.RETSIM("mode nonsense"); SlashCmdList.RETSIM("fights x")');
step('a value the game hides becomes a sentence, not an error', `local keep = GetCritChance; GetCritChance = function() error("hidden") end; local ok, why = RSX.doReadCharacter(); GetCritChance = keep
  assert(not ok and why:find("melee crit", 1, true), tostring(why)); assert(RSX.doReadCharacter()); return why`);
console.log(host.limits());
console.log(failed ? failed + ' step(s) FAILED' : 'all steps passed');
process.exit(failed ? 1 : 0);
