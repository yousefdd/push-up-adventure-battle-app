import { launch, open, tap, nodes } from './nav.mjs';
const [,, lang, maxReps] = process.argv;
const b = await launch();
const p = await open(b, { w: 412, h: 860, lang: lang === 'ar' ? 'ar' : null });
const sfx = new Set();
p.on('request', r => { if (r.url().includes('/sfx/')) sfx.add(r.url().split('/').pop()); });
await tap(p, lang === 'ar' ? 'المغامرة' : 'Adventure');
await tap(p, lang === 'ar' ? 'ابدأ' : 'Start', { wait: 2000 });
const seen = {};
let ended = null, i = 0;
const t0 = Date.now();
for (; i < +maxReps; i++) {
  const ns = await nodes(p);
  const btn = ns.filter(n => n.role === 'button').map(n => n.label.split(',')[0].trim()).pop() || '';
  seen[btn] = (seen[btn] || 0) + 1;
  const all = ns.map(n => n.label).join('|');
  if (/Victory|Defeat|انتصار|هزيمة/.test(all) && !ended) ended = /Victory|انتصار/.test(all) ? 'victory' : 'defeat';
  if (ended && /Start,|ابدأ،|ابدأ,/.test(all) && !/STRIKE|Next Day/.test(all)) break;   // back on the world screen
  await p.keyboard.press('Space');
  await p.waitForTimeout(650);
}
console.log(JSON.stringify({ lang: lang || 'en', reps: i, ended, secs: Math.round((Date.now() - t0) / 1000), states: seen, sfx: [...sfx].sort(), errors: p.errs.slice(0, 3), errorCount: p.errs.length }));
await b.close();
