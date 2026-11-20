// Settings and consumables: the addon's applyConsumables() against the website's, and settings codes both ways
// (made by the addon and read as the website does; made as the website does and read by the addon).
//   node check-ret-settings.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const { newLua } = require('./lua-host');
const { toLua } = require('./lua-ser');
const JS = require('./ret-js-engine');
const lua = newLua();
for (const f of ['Data.lua', 'Engine.lua', 'Codes.lua']) {
  const src = fs.readFileSync(path.join(__dirname, '..', 'RetSim', f), 'utf8');
  lua.run('return HOST.load([=====[' + src + ']=====], "@' + f + '")', '=load ' + f);
}
const D = JS.defaults();
const SEL = JS.FIELDS.filter(f => f.g === 'cons' && f.t === 'sel'), CHK = JS.FIELDS.filter(f => f.g === 'cons' && f.t === 'chk');
const NUM = ['str', 'int', 'apGear', 'crit', 'spellCrit', 'hit', 'spellHit', 'exp', 'sp', 'holyOnly', 'mana', 'mp5', 'haste', 'wMin', 'wMax'];
lua.run(`function CONS(v)
  RSX.applyConsumables(v)
  local out = {}
  for _, k in ipairs(${toLua(NUM)}) do out[#out + 1] = string.format('%s=%.17g', k, v[k] or 0) end
  out[#out + 1] = 'potions=' .. tostring(v.potions)
  return table.concat(out, ';')
end`, '=cons');

// every single choice on its own, then random mixes
let seed = 12345; const rnd = n => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
const sets = [{}];
for (const f of SEL) for (const o of f.o) if (o[0] !== 'none') sets.push({ [f.k]: o[0] });
for (let i = 0; i < 60; i++) { const s = {}; for (const f of SEL) s[f.k] = f.o[rnd(f.o.length)][0]; for (const f of CHK) s[f.k] = rnd(2) === 1; s.fight = [45, 180, 300, 600][rnd(4)]; sets.push(s); }
let bad = 0;
for (const s of sets) {
  const v = Object.assign({}, D, { holyOnly: 0, haste: 0 }, s);
  const a = JS.applyConsumables(Object.assign({}, v));
  const txt = lua.run('return CONS(' + toLua(v) + ')', '=cons run');
  for (const p of txt.split(';')) {
    const [k, x] = p.split('=');
    const want = k === 'potions' ? String(a.potions) : (a[k] || 0);
    if (k === 'potions' ? x !== want : Math.abs(+x - want) > 1e-9) { bad++; if (bad < 6) console.log('  ' + JSON.stringify(s) + ': ' + k + ' ' + x + ' (website ' + want + ')'); }
  }
}
assert.strictEqual(bad, 0, bad + ' consumable values differ');
console.log('ok   consumables: ' + sets.length + ' sets give the website\'s values (every choice on its own, and 60 mixes)');

// a settings code made by the addon, read the way the website does
const mine = { kings: false, flask: 'supreme', food: 'fishap', fight: 240, bossArmor: 4200, undead: true, consMinPct: 55, latency: 0.15, mode: 'sorFury' };
const code = lua.run('return RSX.encodeSettings(' + toLua(mine) + ')', '=encode');
assert(/^RSS1:[A-Za-z0-9+/]+=*$/.test(code));
const back = JSON.parse(Buffer.from(code.slice(5), 'base64').toString('utf8'));
assert.strictEqual(back.v, 1); assert.deepStrictEqual(back.settings, mine);
console.log('ok   a settings code made by the addon is read back as the website reads it (' + code.length + ' characters)');

// a settings code made the way the website makes one, read by the addon
const all = {}; for (const f of JS.FIELDS) if (['buff', 'cons', 'tgt', 'rot'].includes(f.g)) all[f.k] = D[f.k];
Object.assign(all, { flask: 'aggression', elixAp: 'juju', chili: true, moonkin: false, fight: 300.5, mode: 'shock' });
const site = 'RSS1:' + Buffer.from(JSON.stringify({ v: 1, settings: all })).toString('base64');
lua.run(`function READ(code)
  local kind, data = RSX.decodeCode(code)
  if not kind then return 'ERR ' .. tostring(data) end
  local keys = {}
  for k in pairs(data.settings or data.items or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = { kind }
  for _, k in ipairs(keys) do local x = (data.settings or data.items)[k]; out[#out + 1] = k .. '=' .. (type(x) == 'number' and string.format('%.17g', x) or tostring(x)) end
  return table.concat(out, ';')
end`, '=read');
const got = lua.run('return READ(' + JSON.stringify(site) + ')', '=decode').split(';');
assert.strictEqual(got[0], 'settings');
const seen = Object.fromEntries(got.slice(1).map(p => { const i = p.indexOf('='); return [p.slice(0, i), p.slice(i + 1)]; }));
for (const k in all) assert.strictEqual(seen[k], typeof all[k] === 'number' ? String(all[k]) : String(all[k]), 'setting ' + k);
assert.strictEqual(Object.keys(seen).length, Object.keys(all).length);
console.log('ok   a settings code made by the website is read by the addon: ' + Object.keys(all).length + ' settings');
// spaces and line breaks from copying, the URL-safe alphabet, and codes that are not settings codes
assert.strictEqual(lua.run('return READ(' + JSON.stringify(site.replace(/(.{40})/g, '$1\n ')) + ')', '=wrapped').split(';')[0], 'settings');
assert.strictEqual(lua.run('return READ(' + JSON.stringify(site.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')) + ')', '=urlsafe').split(';')[0], 'settings');
for (const [text, want] of [['', 'Paste a settings code first'], ['RS1:abcdef', 'share code of the website'], ['hello', 'not a code the addon knows'], [site.slice(0, 60), 'incomplete or damaged'],
  ['RSS1:' + Buffer.from('{"v":1}').toString('base64'), 'holds no settings'], ['RSS1:' + Buffer.from('[1,2').toString('base64'), 'incomplete or damaged']]) {
  const r = lua.run('return READ(' + JSON.stringify(text) + ')', '=bad');
  assert(r.startsWith('ERR ') && r.includes(want), JSON.stringify(text.slice(0, 30)) + ' -> ' + r);
}
assert.strictEqual(lua.run('return READ(' + JSON.stringify('RSA1:' + Buffer.from('{"v":1,"items":{"16":{"id":5}}}').toString('base64')) + ')', '=gear').split(';')[0], 'gear');
console.log('ok   wrapped lines, the URL-safe alphabet, damaged codes and other kinds of codes are told apart');
// JSON the addon must read: escapes, nested values, numbers
assert.strictEqual(lua.run(`local v = RSX.jsonDecode('{"a":"q\\\\"b\\\\\\\\c\\\\n","n":-1.5e2,"t":true,"f":false,"z":null,"l":[1,[2,3],{"k":"v"}]}')
  return v.a .. '|' .. v.n .. '|' .. tostring(v.t) .. tostring(v.f) .. tostring(v.z) .. '|' .. #v.l .. v.l[2][2] .. v.l[3].k`, '=json').replace(/\.0\b/g, ''), 'q"b\\c\n|-150|truefalsenil|33v');
fs.writeFileSync(path.join(__dirname, 'settings-sample.txt'), code + '\n');
console.log('ok   JSON with escapes, nesting and numbers is read');
console.log('A sample settings code made by the addon is in tools/settings-sample.txt');
