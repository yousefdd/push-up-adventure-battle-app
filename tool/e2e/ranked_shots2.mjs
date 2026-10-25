// Lobby, profile and account screens with a cached rank, English and Arabic.
import { launch, open, tap } from './nav.mjs';

const out = process.argv[2] || '.';
const url = process.argv[3] || 'http://localhost:8766/';
const stats = { rating: 1612, peak_rating: 1640, ranked_games: 44, wins: 27, losses: 16, draws: 1, coins: 12, silver: 86 };
const L = {
  en: { race: 'Online race', profile: 'Your profile', account: 'Account and sign-in' },
  ar: { race: 'سباق أونلاين', profile: 'ملفك الشخصي', account: 'الحساب وتسجيل الدخول' },
};

const b = await launch();
for (const lang of ['en', 'ar']) {
  const p = await open(b, { url, lang });
  await p.evaluate((s) => localStorage.setItem('flutter.rr.stats', JSON.stringify(JSON.stringify(s))), stats);
  await p.reload();
  await p.waitForTimeout(4500);
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(800);
  await tap(p, L[lang].race, { wait: 2500 });
  await p.screenshot({ path: `${out}/${lang}_5_lobby.png` });
  await p.mouse.wheel(0, 900);
  await p.waitForTimeout(700);
  await p.screenshot({ path: `${out}/${lang}_6_lobby_bottom.png` });
  await p.goBack();
  await p.waitForTimeout(1500);
  await tap(p, L[lang].profile, { wait: 2000 });
  await p.mouse.wheel(0, 900);
  await p.waitForTimeout(800);
  await p.screenshot({ path: `${out}/${lang}_7_profile.png` });
  await p.mouse.move(195, 500);
  await p.mouse.wheel(0, 2000);
  await p.waitForTimeout(800);
  await tap(p, L[lang].account, { wait: 2000 });
  await p.screenshot({ path: `${out}/${lang}_8_account.png` });
  console.log(lang, 'app errors', p.errs.filter(e => !/ERR_TUNNEL|Failed to load resource/.test(e)).slice(0, 3));
  await p.close();
}
await b.close();
