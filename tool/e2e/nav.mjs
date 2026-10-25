import pw from '/tmp/node_modules/playwright-core/index.js';
export const CHROME = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
export async function launch(extra = []) {
  return pw.chromium.launch({ executablePath: CHROME, args: ['--no-sandbox', '--autoplay-policy=no-user-gesture-required', ...extra] });
}
/** A page with a seeded save, errors collected, Flutter's accessibility tree on. */
export async function open(b, { w = 390, h = 844, save = { version: 1, class: 'knight' }, lang = null, url = 'http://localhost:8765/' } = {}) {
  const p = await b.newPage({ viewport: { width: w, height: h } });
  p.errs = [];
  p.on('pageerror', e => p.errs.push(String(e)));
  p.on('console', m => { if (m.type() === 'error' || /exception was thrown|Exception caught/i.test(m.text())) p.errs.push(m.text().slice(0, 200)); });
  await p.addInitScript(([s, l]) => {
    if (!sessionStorage.getItem('seeded')) {
      localStorage.setItem('flutter.rr.save', JSON.stringify(s));
      if (l) localStorage.setItem('flutter.rr.lang', JSON.stringify(l));
      sessionStorage.setItem('seeded', '1');
    }
  }, [save, lang]);
  await p.goto(url);
  await p.waitForTimeout(4500);
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(800);
  return p;
}
/** Every labelled node in the accessibility tree: label, role, box. */
export async function nodes(p) {
  return p.evaluate(() => {
    const out = [];
    for (const e of document.querySelectorAll('flt-semantics')) {
      const label = (e.getAttribute('aria-label') || e.textContent || '').trim();
      const r = e.getBoundingClientRect();
      if (!label || r.width === 0) continue;
      out.push({ label, role: e.getAttribute('role') || '', x: r.x, y: r.y, w: r.width, h: r.height });
    }
    return out;
  });
}
/** Taps the button whose label starts with (or contains) [text]. */
export async function tap(p, text, { wait = 1500 } = {}) {
  const all = await nodes(p);
  const hit = all.find(n => n.role === 'button' && n.label.startsWith(text))
    || all.find(n => n.label.startsWith(text))
    || all.find(n => n.label.includes(text));
  if (!hit) throw new Error('no node: ' + text + ' in [' + all.map(n => n.label.slice(0, 24)).join(' / ') + ']');
  // A node can merge a button with the hint under it: aim at its top part.
  await p.mouse.click(hit.x + hit.w / 2, hit.y + Math.min(hit.h, 56) / 2);
  await p.waitForTimeout(wait);
}
export async function reps(p, n, gap = 800) {
  for (let i = 0; i < n; i++) { await p.keyboard.press('Space'); await p.waitForTimeout(gap); }
}
