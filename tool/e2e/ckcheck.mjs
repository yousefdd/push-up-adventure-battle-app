import { launch } from './nav.mjs';
const [,, dir, port] = process.argv;
const b = await launch(['--mute-audio']);
for (const lang of ['ar', 'en']) {
  const p = await b.newPage({ viewport: { width: 412, height: 860 } });
  const logs = [], net = [];
  p.on('console', m => { if (/exception|Error|error/.test(m.text())) logs.push(m.type() + ': ' + m.text().slice(0, 200)); });
  p.on('pageerror', e => logs.push('PAGEERROR ' + String(e).slice(0, 200)));
  p.on('requestfailed', r => net.push(r.url().slice(0, 120)));
  p.on('request', r => { if (!r.url().startsWith(`http://localhost:${port}`)) net.push('EXTERNAL ' + r.url().slice(0, 120)); });
  await p.addInitScript((l) => { localStorage.setItem('flutter.rr.save', JSON.stringify({ version: 1, class: 'knight' })); localStorage.setItem('flutter.rr.lang', JSON.stringify(l)); }, lang);
  await p.goto(`http://localhost:${port}/`); await p.waitForTimeout(7000);
  await p.screenshot({ path: `${dir}/ck_${lang}_home.png` });
  await p.mouse.click(206, lang === 'ar' ? 548 : 521); await p.waitForTimeout(1800);
  await p.screenshot({ path: `${dir}/ck_${lang}_adv.png` });
  await p.mouse.click(206, 552); await p.waitForTimeout(2500);
  for (let i = 0; i < 3; i++) { await p.keyboard.press('Space'); await p.waitForTimeout(900); }
  await p.screenshot({ path: `${dir}/ck_${lang}_run.png` });
  console.log(lang, 'logs', logs.length, logs.slice(0, 3), 'net', [...new Set(net)].slice(0, 6));
  await p.close();
}
await b.close();
