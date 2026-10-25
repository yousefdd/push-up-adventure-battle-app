import { launch, open, tap, reps } from './nav.mjs';
const [,, dir] = process.argv;
const b = await launch(['--mute-audio']);
const out = [];
for (const [w, h, lang, adv, start] of [[360, 740, 'en', 'Adventure', 'Start'], [390, 844, 'ar', 'المغامرة', 'ابدأ'], [430, 932, 'en', 'Adventure', 'Start']]) {
  const p = await open(b, { w, h, lang });
  await p.screenshot({ path: `${dir}/home_${w}.png` });
  try {
    await tap(p, adv);
    await p.screenshot({ path: `${dir}/adv_${w}.png` });
    await tap(p, start, { wait: 2000 });
    await reps(p, 3);
    await p.screenshot({ path: `${dir}/run_${w}.png` });
  } catch (e) { out.push('nav failed: ' + e.message); }
  out.push(`${w}x${h} ${lang}: errors ${p.errs.length} ${p.errs.slice(0, 2).join(' | ')}`);
  await p.close();
}
console.log(out.join('\n')); await b.close();
