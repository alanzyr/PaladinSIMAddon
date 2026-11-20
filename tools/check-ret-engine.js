// Plays the same fights in the website's engine (JavaScript) and the addon's (Lua) and compares them: DPS, and for every
// damage source the damage, hits, crits and misses, plus mana left, mana spent, echoes, swings and blocked casts.
//   node check-ret-engine.js          a quick run
//   node check-ret-engine.js full     more fights per setup
// A changed fight rule on the website has to be carried into RetSim/Sim.lua or Engine.lua by hand; this fails until it is.
const fs = require('fs'), path = require('path');
const { newLua } = require('./lua-host');
const { toLua } = require('./lua-ser');
const JS = require('./ret-js-engine');
const FIGHTS = process.argv[2] === 'full' ? 200 : 25;

const lua = newLua();
for (const f of ['Engine.lua', 'Sim.lua']) {
  const src = fs.readFileSync(path.join(__dirname, '..', 'RetSim', f), 'utf8');
  if (src.includes(']=====]')) throw new Error(f + ' contains the long-bracket terminator used to load it');
  lua.run('return HOST.load([=====[' + src + ']=====], "@' + f + '")', '=load ' + f);
}
// one fight in Lua, written out as "key=value" lines with every digit (%.17g)
lua.run(`
function CHECK(v, ranks, modeKey, seed)
  local RS = RSX
  RS.applyTalents(v, ranks)
  local c = RS.derive(v)
  local r = RS.simulateOnce(c, RS.resolveMode(modeKey, v.wSpeed), seed)
  local out = { string.format('dps=%.17g', r.dps), string.format('mana=%.17g', r.mana), string.format('manaUsed=%.17g', r.manaUsed),
    'echoes=' .. r.echoes, 'swings=' .. r.swings, 'blocked=' .. r.blocked }
  local names = {}
  for k in pairs(r.S) do names[#names + 1] = k end
  table.sort(names)
  for _, k in ipairs(names) do local s = r.S[k]; out[#out + 1] = string.format('S|%s=%.17g|%d|%d|%d', k, s.dmg, s.n, s.crit, s.miss) end
  return table.concat(out, '\\n')
end`, '=check');

function jsFight(v0, ranks, modeKey, seed) {
  const v = JS.applyTalents(ranks, Object.assign({}, v0));
  const c = JS.derive(v);
  const r = JS.simulate(c, JS.resolveMode(modeKey, v.wSpeed), seed, false);
  const out = { dps: r.dps, mana: r.mana, manaUsed: r.manaUsed, echoes: r.echoes, swings: r.swings, blocked: r.blocked, S: r.S };
  return out;
}
function luaFight(v0, ranks, modeKey, seed) {
  const txt = lua.run('return CHECK(' + toLua(v0) + ', ' + toLua(ranks) + ', ' + JSON.stringify(modeKey) + ', ' + seed + ')', '=fight');
  const out = { S: {} };
  for (const line of txt.split('\n')) {
    if (line.startsWith('S|')) { const [name, rest] = line.slice(2).split('='); const p = rest.split('|'); out.S[name] = { dmg: +p[0], n: +p[1], crit: +p[2], miss: +p[3] }; }
    else { const [k, x] = line.split('='); out[k] = +x; }
  }
  return out;
}

// setups: the page's defaults with one thing changed at a time, the way gear, buffs and settings change them on the page
const D = JS.defaults();
const P = JS.PRESETS;
const with_ = o => Object.assign({}, D, o);
const SETUPS = [
  ['defaults, raid talents', D, P.raid],
  ['defaults, Unsealed Wrath talents', D, P.ws],
  ['defaults, shock talents', D, P.shock],
  ['no talents', D, {}],
  ['geared: slow weapon', with_({ str: 300, apGear: 180, sp: 60, crit: 12, hit: 6, exp: 2, int: 120, mana: 3400, wMin: 187, wMax: 281, wSpeed: 3.8 }), P.ws],
  ['geared: fast weapon, Blade of Hanna, haste', with_({ str: 240, apGear: 90, sp: 260, holyOnly: 40, crit: 9, hit: 4, int: 210, mana: 4800, wMin: 96, wMax: 145, wSpeed: 2.0, hanna: true, haste: 3, judgeMult: 1.04 }), P.ws],
  ['medium weapon', with_({ str: 260, apGear: 60, wMin: 131, wMax: 197, wSpeed: 3.2, crit: 8 }), P.ws],
  ['no buffs or debuffs', with_({ kings: false, might: false, battleShout: false, lotp: false, wfTotem: false, soe: false, goa: false, motw: false, arcInt: false, moonkin: false, bow: false, manaSpring: false, sunder: false, faerieFire: false, cor: false, jow: false }), P.ws],
  ['every extra: chili, sapper, tide, Arthas, Elements, external Crusader', with_({ chili: true, sapper: true, manaTide: true, arthas: true, coe: true, jotcExt: true, opener: false, sp: 180 }), P.ws],
  ['undead target, three targets, swap first', with_({ undead: true, targets: 3, swapFirst: true }), P.ws],
  ['dwarf, no opener, no Hammer of Wrath', with_({ race: 'dwarf', str: 107, int: 69, crit: 3.79, mana: 2267, opener: false, useHoW: false }), P.raid],
  ['undead player, long fight, no potions', with_({ race: 'undead', str: 104, int: 68, crit: 3.89, mana: 2252, fight: 420, potions: false, runes: false }), P.raid],
  ['short fight, high armor, low mana', with_({ fight: 45, bossArmor: 5200, mana: 900, mp5: 0, consMinPct: 80 }), P.ws],
];
const MODES = ['auto', 'socSor', 'sorSoc', 'sorFury', 'socOnly', 'sorOnly', 'shock'];

let fights = 0, bad = 0; const problems = [];
const same = (a, b) => a === b || Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(a), Math.abs(b));
for (const [name, v, ranks] of SETUPS) {
  for (const mode of MODES) {
    for (let j = 0; j < FIGHTS; j++) {
      const seed = 1337 * 7919 + j * 104729 + MODES.indexOf(mode) * 17;
      const a = jsFight(v, ranks, mode, seed), b = luaFight(v, ranks, mode, seed);
      fights++;
      const diffs = [];
      for (const k of ['dps', 'mana', 'manaUsed', 'echoes', 'swings', 'blocked']) if (!same(a[k], b[k])) diffs.push(k + ' ' + a[k] + ' / ' + b[k]);
      const keys = new Set(Object.keys(a.S).concat(Object.keys(b.S)));
      for (const k of keys) {
        const x = a.S[k], y = b.S[k];
        if (!x || !y) { diffs.push(k + ' only in ' + (x ? 'website' : 'addon')); continue; }
        if (!same(x.dmg, y.dmg) || x.n !== y.n || x.crit !== y.crit || x.miss !== y.miss) diffs.push(k + ' ' + [x.dmg, x.n, x.crit, x.miss].join(',') + ' / ' + [y.dmg, y.n, y.crit, y.miss].join(','));
      }
      if (diffs.length) { bad++; if (problems.length < 8) problems.push(name + ' | ' + mode + ' | seed ' + seed + ': ' + diffs.slice(0, 3).join('; ')); }
    }
  }
}
console.log('website engine: ' + path.relative(process.cwd(), JS.file));
console.log(fights + ' fights compared (' + SETUPS.length + ' setups x ' + MODES.length + ' rotations x ' + FIGHTS + ' seeds): ' + (bad ? bad + ' DIFFER' : 'all identical'));
for (const p of problems) console.log('  ' + p);
console.log(lua.limits());
process.exit(bad ? 1 : 0);
