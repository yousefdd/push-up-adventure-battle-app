// A race can't start without the camera: refused, the lobby says so;
// allowed (a fake camera), it goes on to the server.
import { launch, open, tap, nodes } from './nav.mjs';
const out = process.argv[2];
for (const [tag, args] of [['nocam', []], ['cam', ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream']]]) {
  const b = await launch(args);
  const p = await open(b, { lang: 'ar' });
  await tap(p, 'سباق أونلاين', { wait: 2500 });
  await tap(p, 'ابحث عن منافس', { wait: 6000 });
  await p.screenshot({ path: `${out}/gate_${tag}.png` });
  const text = (await nodes(p)).map(n => n.label).join(' | ');
  console.log(tag, /اسمح بالكاميرا/.test(text) ? 'BLOCKED' : 'not blocked', '|', /الاتصال|connection|Could not/.test(text) ? 'server error shown' : '');
  await b.close();
}
