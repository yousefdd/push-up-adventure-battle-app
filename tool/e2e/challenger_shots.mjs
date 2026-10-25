// Profile ladder before Grandmaster (Champion hidden) and as a Champion, in Arabic.
import { launch, open, tap } from './nav.mjs';
const out = process.argv[2] || '.';
const b = await launch();
for (const [tag, rating] of [['low', 1320], ['top', 2560]]) {
  const p = await open(b, { lang: 'ar' });
  await p.evaluate((s) => localStorage.setItem('flutter.rr.stats', JSON.stringify(JSON.stringify(s))),
    { rating, peak_rating: rating, ranked_games: 90, wins: 60, losses: 30, draws: 0, coins: 40, silver: 120 });
  await p.reload(); await p.waitForTimeout(4500);
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(800);
  await p.screenshot({ path: `${out}/ch_${tag}_home.png` });
  await tap(p, 'ملفك الشخصي', { wait: 2000 });
  await p.mouse.move(195, 500); await p.mouse.wheel(0, 900); await p.waitForTimeout(900);
  await p.screenshot({ path: `${out}/ch_${tag}_profile.png` });
  {
    await p.mouse.move(195, 490); await p.mouse.wheel(0, 0); await p.keyboard.down('Shift'); await p.mouse.wheel(0, 900); await p.keyboard.up('Shift'); await p.mouse.wheel(900, 0); await p.waitForTimeout(900);
    await p.screenshot({ path: `${out}/ch_${tag}_ladder.png` });
  }
  console.log(tag, p.errs.filter(e => !/ERR_TUNNEL|Failed to load resource/.test(e)).slice(0, 3));
  await p.close();
}
await b.close();
