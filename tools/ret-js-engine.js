// The website's engine, taken straight out of ret-sim.html (the text between "ENGINE START" and "ENGINE END"), so the
// checks always compare the addon with the page as it is now. Also the talent rules and presets from the page.
// The page is looked for next to this repository (../../repo/ret-sim.html) or where RETSIM_HTML points.
const fs = require('fs'), path = require('path');
const file = process.env.RETSIM_HTML || path.join(__dirname, '..', '..', 'repo', 'ret-sim.html');
if (!fs.existsSync(file)) throw new Error('ret-sim.html not found at ' + file + ' (set RETSIM_HTML to its path)');
const page = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
const a = page.indexOf('/* ===== ENGINE START ===== */'), b = page.indexOf('/* ===== ENGINE END ===== */');
if (a < 0 || b < a) throw new Error('engine markers not found in ' + file);
const engine = new Function(page.slice(a, b) + '\nreturn { FIELDS, MODES, SEAL, derive, simulate, resolveMode, procList, PROCS };')();
// applyTalents(v) reads ranks through rk(name); here it is given a ranks table instead of the page's state
const ta = page.indexOf('function applyTalents(v){'), tb = page.indexOf('\n}\n', ta);
if (ta < 0) throw new Error('applyTalents not found');
const applyTalents = new Function('ranks', 'v', 'const rk = n => ranks[n] || 0, treePts = () => 0;\n' + page.slice(ta, tb + 2) + '\napplyTalents(v); delete v.talStr; return v;');
const pa = page.indexOf('const PRESETS = {'), pb = page.indexOf('const TAL_LS', pa);
const PRESETS = new Function(page.slice(pa, pb) + '\nreturn PRESETS;')();
// applyConsumables(v): the consumables chosen in the settings added to the values
const ca = page.indexOf('function applyConsumables(v){'), cb = page.indexOf('\n}\n', ca);
if (ca < 0) throw new Error('applyConsumables not found');
const applyConsumables = new Function('v', page.slice(ca, cb + 2) + '\napplyConsumables(v); return v;');
// the page's default settings: every field's default value
function defaults() { const v = {}; for (const f of engine.FIELDS) v[f.k] = f.d; return v; }
module.exports = Object.assign({ file, applyTalents, applyConsumables, PRESETS, defaults }, engine);
