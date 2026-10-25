# Push Up Adventure Battle

A pushup/fitness app that fuses **live online competition** with an **offline RPG**.
Every real rep is verified on-device for correct form, then spent as either damage
in a live match or XP/loot in a solo adventure.

> Name is a placeholder — swap `RepRaid` / `com.repraid.app` for your final choice.

## Run it on your phone (camera + skeleton)

On a phone the camera plugin and ML Kit count reps; in a browser the web build
uses the webcam through MediaPipe (`web/rr_pose.js`), and taps or the Space bar
also count as reps.

1. Install Flutter (latest stable) and Android Studio, then connect your
   Android phone with USB debugging on.
2. In this folder:
   ```
   flutter pub get
   flutter run --release
   ```
   or build an installable file with `flutter build apk --release` and copy
   `build/app/outputs/flutter-apk/app-release.apk` to the phone.
3. Allow the camera when asked. Prop the phone in front of you, facing you,
   so your shoulders and hands are in frame.

Use a current Flutter: it resolves a `camera_android_camerax` with the
front-camera mirroring fix (0.6.18+3 or newer), so the skeleton lines up with
the mirrored preview.

## Web build

```
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn
```

Then upload `build/web` (for example to Netlify Drop). Why these flags:
CanvasKit lays Arabic text out correctly (the HTML renderer throws while
hit-testing right-to-left text, so taps on Arabic buttons were lost), and
`--no-web-resources-cdn` bundles CanvasKit so the game needs no network at
all; every font is bundled too (a "Roboto" stand-in is declared in
`pubspec.yaml` for the engine's last fallback).

## Play online with a friend (one-time setup)

1. Create a free project at supabase.com.
2. Authentication → Sign In / Providers → turn on **Allow anonymous sign-ins**
   (players get an account without a password).
3. SQL Editor → paste all of `supabase/schema.sql` → **Run**.
4. Project Settings → API Keys: copy the **Project URL** and the
   **publishable** key (or the legacy **anon public** key) into
   `lib/online/supabase_config.dart`. Never use the secret / service_role key.
5. Build the app and install it on both phones.

Then: **Begin → Create duel** shows a 4-letter code; your friend taps
**Begin → Join**, types it, and both phones count down together. Each verified
rep is sent to the server and pushed to the other phone live; when the 60 s
are up the server picks the winner (it caps scores at 2 reps/second and
ignores reps outside the race).

`schema.sql` was run and exercised on PostgreSQL 16 (15 scenarios: wrong /
reused / own codes, strangers, direct writes, early and late reps, the pace
cap, settling the winner). `test/duel_row_test.dart` checks the app against
rows captured from that run.

## Where this came from

The rep-counting core is a clean-room rebuild, in Dart, of the pose → rep logic
observed in a friend's app (analyzed with permission). No code was copied; only
the *approach* and sensible thresholds were carried over, then re-implemented and
unit-tested here.

## Two modes, one engine

```
            ┌─────────────────────────┐
            │   Pose backend (camera)  │   MediaPipe Pose Landmarker
            │   → normalized landmarks │   (already in your RepChamp app)
            └───────────┬─────────────┘
                        │  PoseFrame per camera frame
            ┌───────────▼─────────────┐
            │       RepEngine          │   lib/engine/  ← DONE + tested
            │  angle state machine +   │   counts honest reps, rejects
            │  form gates (anti-cheat) │   shallow / too-fast / held-too-long
            └─────┬───────────────┬────┘
                  │ RepEvent      │ RepEvent
        ┌─────────▼──────┐  ┌─────▼───────────┐
        │  ONLINE mode   │  │   RPG mode      │
        │  (realtime)    │  │  (offline)      │
        │  each rep =    │  │  each rep =     │
        │  an attack vs  │  │  XP + loot;     │
        │  live opponent │  │  dungeons, gear │
        │  / world boss  │  │  heroes, quests │
        └────────────────┘  └─────────────────┘
```

The form gating lives in the shared engine on purpose: that is what makes online
scores fair, so both modes count a rep exactly the same way.

## Status

| Piece | State |
|---|---|
| Rep engine (pushup, knee, squat, situp, pullup) | **Built + unit-tested (4/4)** |
| Form anti-cheat (depth / pace / rest) | **Built + tested** |
| Online duel: 60s race logic (countdown, live counters, winner) | **Built + unit-tested (13/13)** |
| Online duel: Supabase realtime + matchmaking service | **Built (needs backend + device to run)** |
| Flutter app shell, camera + pose wiring | Not started |
| Offline RPG (heroes, dungeons, loot) | Designed, not built |
| "Hand-made" indie UI theme | Designed, not built |

### Online duel — how it works (matches the app you sent)

1. Both players pick and **agree on the same exercise**, then queue.
2. The server pairs them into a *bout* with a `{ leadSecs, fightSecs: 60 }` window.
3. A **5-second countdown**, then a **60-second race**.
4. Each verified rep is broadcast on the bout's realtime channel, so **both
   counters move live** on screen.
5. At `0:00`, **more valid reps wins** — no attacks, no HP. Reps must pass the
   same form gates, and the server cross-checks counted-vs-declared to stop
   cheating.

Pure race logic: `lib/modes/online/duel_controller.dart` (run `dart test_duel.dart`).
Network layer + backend contract: `lib/modes/online/duel_service.dart`.

## Engine files (ready to drop into a Flutter project)

- `lib/engine/pose.dart` — landmark types + a `PoseFrame` with a confidence floor.
- `lib/engine/angles.dart` — joint-angle math (atan2) + a median smoother.
- `lib/engine/exercise.dart` — per-exercise thresholds (pushup/squat/situp/pullup…).
- `lib/engine/rep_engine.dart` — the down/up state machine + form gates.
- `test_engine.dart` — run `dart test_engine.dart` to see the 4 checks pass.

## How a rep is judged (pushup example)

1. **Arm** at the top (elbow extended ≥ 150°).
2. **Descend** — must actually leave the top, then reach **≤ 100°** (real depth).
3. **Bottom** — short pause required; parking there too long reads as a rest.
4. **Ascend** back to ≥ 150° → **+1 rep**, but only if:
   - depth was reached (else *"go lower"*),
   - the whole rep took ≥ 0.5 s (else *"that was a bounce"*),
   - the bottom dwell wasn't a rest (else *"held too long"*).

Squat uses the knee angle, situp the trunk angle, pullup the (inverted) elbow
angle — same machine, different thresholds in `exercise.dart`.

## Design direction

Deliberately **hand-made / indie** look: simple flat colors, doodle-style icons,
system font, slightly imperfect edges — friendly and honest, not corporate-glossy.

## Next steps (suggested order)

1. Flutter shell + camera preview + MediaPipe pose stream → feed `RepEngine`.
2. A single working "free workout" screen showing live reps + form cues.
3. Offline RPG loop (hero, XP from reps, first dungeon, loot).
4. Online: a realtime backend (Supabase Realtime), 1v1 duel first, then world-boss raids.
5. Polish the indie theme across screens.
