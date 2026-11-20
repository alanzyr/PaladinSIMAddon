// The export code: made by the addon's own Lua (RetSim/Codes.lua) and read back the way the website does
// (the text after "RSA1:" is base64 of JSON). Prints the code so it can be pasted into the website's Import > Addon.
//   node check-ret-export.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const { newLua } = require('./lua-host');
const { toLua } = require('./lua-ser');
const JS = require('./ret-js-engine');
const lua = newLua();
for (const f of ['Data.lua', 'Engine.lua', 'Codes.lua']) {
  const src = fs.readFileSync(path.join(__dirname, '..', 'RetSim', f), 'utf8');
  lua.run('return HOST.load([=====[' + src + ']=====], "@' + f + '")', '=load ' + f);
}
// a character with real item and enchant ids: The Unstoppable Force with Crusader, Lionheart Helm, Don Julio's Band, Libram of Law, a shirt
const items = { 16: { id: 19323, enchant: 1900 }, 1: { id: 12640 }, 11: { id: 19325 }, 12: { id: 284715, enchant: 0 }, 18: { id: 272435 }, 4: { id: 2575 } };
for (const [name, ranks, want] of [['Unsealed Wrath build', JS.PRESETS.ws, '050250002-501-05233011201301351'], ['no talents', {}, '--'], ['shock build', JS.PRESETS.shock, null]]) {
  const code = lua.run('return RSX.encodeExport({ race = "dwarf", mode = "sorFury", talents = ' + toLua(ranks) + ', items = ' + toLua(Object.fromEntries(Object.entries(items).map(([k, v]) => ['_' + k, v]))).replace(/_(\d+) =/g, '[$1] =') + ' })', '=export');
  assert(/^RSA1:[A-Za-z0-9+/]+=*$/.test(code), 'not a code: ' + code.slice(0, 40));
  const j = JSON.parse(Buffer.from(code.slice(5), 'base64').toString('utf8'));
  assert.strictEqual(j.v, 1); assert.strictEqual(j.race, 'dwarf'); assert.strictEqual(j.mode, 'sorFury');
  if (want !== null) assert.strictEqual(j.talents, want, name);
  assert.deepStrictEqual(j.items, { 1: { id: 12640 }, 4: { id: 2575 }, 11: { id: 19325 }, 12: { id: 284715 }, 16: { id: 19323, enchant: 1900 }, 18: { id: 272435 } });
  console.log('ok   ' + name + ': talents ' + j.talents + ', ' + Object.keys(j.items).length + ' items, ' + code.length + ' characters');
  if (name === 'Unsealed Wrath build') fs.writeFileSync(path.join(__dirname, 'export-sample.txt'), code + '\n');
}
// base64 of every remainder length, and JSON escapes
for (const s of ['', 'a', 'ab', 'abc', 'abcd', '{"k":"v\\"x"}', 'x'.repeat(100)]) {
  const got = lua.run('return RSX.base64(' + JSON.stringify(s) + ')', '=b64');
  assert.strictEqual(got, Buffer.from(s).toString('base64'), 'base64 of ' + JSON.stringify(s));
}
assert.strictEqual(lua.run('return RSX.jsonEncode({ a = "q\\"b\\\\c", n = 1.5, t = true, l = { 1, 2 } })', '=json'), '{"a":"q\\"b\\\\c","l":[1,2],"n":1.5,"t":true}');
console.log('ok   base64 and JSON written by the addon are read back exactly');
console.log('A sample code is in tools/export-sample.txt');
