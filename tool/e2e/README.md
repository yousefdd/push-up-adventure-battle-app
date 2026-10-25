# Browser checks (Playwright)

Serve `build/web` on port 8765 (`python3 -m http.server 8765`), then:

```
node tool/e2e/smoke.mjs en 420          # a whole run, Space = pushup; prints states reached and errors
node tool/e2e/smoke.mjs ar 420          # the same in Arabic
node tool/e2e/resp.mjs <out-dir>        # 360 / 390 (ar) / 430 px screenshots
node tool/e2e/states.mjs <out-dir>      # walk, fight, pick, wheel, defeat at 424x720 (for replica-diff)
node tool/e2e/ckcheck.mjs <out-dir> 8765  # taps in both languages + every outside network request
```

`nav.mjs` imports playwright-core from `/tmp/node_modules` and the Chromium at
`/opt/pw-browsers` (the cloud container's paths); change both for your machine.
It turns on Flutter's accessibility tree and taps buttons by their labels.
