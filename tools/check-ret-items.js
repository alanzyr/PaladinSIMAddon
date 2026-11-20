// Reads every item of the website through the addon's item reader (RetSim/Items.lua) and compares the stats with the
// website's own: the tooltip lines of an item must give the numbers the website sims it with.
//   node check-ret-items.js
const fs = require('fs'), path = require('path');
const { newLua } = require('./lua-host');
const { toLua } = require('./lua-ser');
const JS = require('./ret-js-engine');
const page = fs.readFileSync(JS.file, 'utf8').replace(/\r\n/g, '\n');
const ia = page.indexOf('const ITEMS = '), ib = page.indexOf(';\nconst ITEM_ICONS', ia);
const ITEMS = JSON.parse(page.slice(ia + 14, ib));
const D = JS.defaults();

const lua = newLua();
for (const f of ['Engine.lua', 'Items.lua']) {
  const src = fs.readFileSync(path.join(__dirname, '..', 'RetSim', f), 'utf8');
  lua.run('return HOST.load([=====[' + src + ']=====], "@' + f + '")', '=load ' + f);
}
lua.run(`function READ(lines)
  local s, unknown = RSX.itemStats(nil, lines)
  local out = {}
  for _, k in ipairs({ 'str', 'agi', 'int', 'ap', 'sp', 'holy', 'hit', 'hitPct', 'crit', 'critPct', 'exp', 'mp5' }) do out[#out + 1] = k .. '=' .. (s[k] or 0) end
  if s.weapon then out[#out + 1] = 'w=' .. s.weapon.min .. '/' .. s.weapon.max .. '/' .. s.weapon.speed end
  out[#out + 1] = 'unknown=' .. #unknown
  return table.concat(out, ';')
end`, '=read');

// Items where the website's own data misses a line of the tooltip (the reader is right): named here so the check stays strict for the rest.
const WEBSITE_MISSES = new Set(['Deathbone Chestplate', 'Deathbone Gauntlets', 'Deathbone Girdle', 'Deathbone Legguards', 'Deathbone Sabatons', 'Briarwood Reed', "Nature's Embrace"]);
let bad = 0, withUnknown = 0, weapons = 0, known = 0; const problems = [];
for (const it of ITEMS) {
  const txt = lua.run('return READ(' + toLua(it.ln || []) + ')', '=item');
  const s = {}; let w = null;
  for (const p of txt.split(';')) { const [k, x] = p.split('='); if (k === 'w') w = x.split('/').map(Number); else s[k] = +x; }
  if (s.unknown) withUnknown++;
  const st = it.st || {}, diffs = [];
  const want = { str: st.str || 0, agi: st.agi || 0, int: st.int || 0, ap: st.ap || 0, sp: st.sp || 0, holy: st.holy || 0, exp: st.exp || 0, mp5: st.mp5 || 0, hit: st.hit || 0, crit: st.crit || 0 };
  const got = { str: s.str, agi: s.agi, int: s.int, ap: s.ap, sp: s.sp, holy: s.holy, exp: s.exp, mp5: s.mp5, hit: s.hit + s.hitPct * D.hitRating, crit: s.crit + s.critPct * D.critRating };
  for (const k in want) if (Math.abs(want[k] - got[k]) > 0.51) diffs.push(k + ' ' + got[k] + ' (website ' + want[k] + ')');
  if (it.d) { weapons++; if (!w || w[0] !== it.d[0] || w[1] !== it.d[1] || Math.abs(w[2] - it.d[2]) > 1e-9) diffs.push('weapon ' + (w ? w.join('/') : 'not read') + ' (website ' + it.d.join('/') + ')'); }
  if (diffs.length && WEBSITE_MISSES.has(it.n)) { known++; continue; }
  if (diffs.length) { bad++; if (problems.length < 25) problems.push(it.n + ' [' + it.s + ']: ' + diffs.join('; ')); }
}
console.log(ITEMS.length + ' items read from their tooltip lines (' + weapons + ' weapons): ' + (bad ? bad + ' differ from the website' : 'all give the website\'s stats'));
for (const p of problems) console.log('  ' + p);
console.log(known + ' items where the data of the website misses a tooltip line (mana per 5 s, a spell power line): the reader counts it.');
console.log(withUnknown + ' items have an Equip:, Use: or Chance on hit: line the reader does not count (procs, on-use effects, stats the sim has no use for).');
process.exit(bad ? 1 : 0);
