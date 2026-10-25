// Screenshots of the ranked-play screens: home, store, lobby, profile,
// account, in English and Arabic. Seeds a cached rank so it shows offline.
import { launch, open, tap } from './nav.mjs';

const out = process.argv[2] || '.';
const url = process.argv[3] || 'http://localhost:8766/';
const stats = { rating: 1612, peak_rating: 1640, ranked_games: 44, wins: 27, losses: 16, draws: 1, coins: 12, silver: 86 };

const b = await launch();
for (const lang of ['en', 'ar']) {
  const p = await open(b, { url, lang });
  await p.evaluate((s) => localStorage.setItem('flutter.rr.stats', JSON.stringify(JSON.stringify(s))), stats);
  await p.reload();
  await p.waitForTimeout(4500);
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(800);
  await p.screenshot({ path: `${out}/${lang}_1_home.png` });
  await p.mouse.wheel(0, 900);
  await p.waitForTimeout(700);
  await p.screenshot({ path: `${out}/${lang}_2_home_bottom.png` });
  await p.mouse.wheel(0, -2000);
  await p.waitForTimeout(500);
  await tap(p, lang === 'ar' ? 'المتجر' : 'Store');
  await p.screenshot({ path: `${out}/${lang}_3_store.png` });
  await p.mouse.wheel(0, 900);
  await p.waitForTimeout(700);
  await p.screenshot({ path: `${out}/${lang}_4_store_bottom.png` });
  await p.goBack().catch(() => {});
  await p.keyboard.press('Escape');
  await p.waitForTimeout(1200);
  console.log(lang, 'errors', p.errs.length, p.errs.slice(0, 3));
  await p.close();
}
await b.close();
