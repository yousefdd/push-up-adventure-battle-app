import { launch, open, tap, reps } from './nav.mjs';
const [,, dir] = process.argv;
const b = await launch(['--mute-audio']);
const p = await open(b, { w: 424, h: 720, save: { version: 1, class: 'knight' } });
await tap(p, 'Adventure');
await tap(p, 'Start', { wait: 2000 });
await reps(p, 1, 900);                    // day 1: a story card on the road
await p.screenshot({ path: `${dir}/walk.png` });
await p.keyboard.press('Space'); await p.waitForTimeout(1500);   // day 2: the first fight starts
await p.keyboard.press('Space'); await p.waitForTimeout(230);    // mid-dash, the blow landing
await p.screenshot({ path: `${dir}/fight.png` });
// finish the fight, then walk until a skill pick or the wheel shows
let pick = false, wheel = false;
for (let i = 0; i < 60 && !(pick && wheel); i++) {
  await p.keyboard.press('Space'); await p.waitForTimeout(950);
  const labels = await p.evaluate(() => [...document.querySelectorAll('flt-semantics')].map(e => (e.getAttribute('aria-label') || e.textContent || '').trim()).join('|'));
  if (!pick && labels.includes('Pick,')) { await p.waitForTimeout(500); await p.screenshot({ path: `${dir}/pick.png` }); pick = true; }
  if (!wheel && labels.includes('Spin!,')) { await p.waitForTimeout(600); await p.screenshot({ path: `${dir}/wheel.png` }); wheel = true; }
}
console.log('pick', pick, 'wheel', wheel, 'errors', p.errs.length);
await p.close();
// defeat: fight without pushups
const q = await open(b, { w: 424, h: 720, save: { version: 1, class: 'knight' } });
await tap(q, 'Adventure'); await tap(q, 'Start', { wait: 2000 });
await q.keyboard.press('Space'); await q.waitForTimeout(1200);
await q.keyboard.press('Space'); await q.waitForTimeout(70000);
await q.screenshot({ path: `${dir}/defeat.png` });
console.log('errors', q.errs.length);
await b.close();
