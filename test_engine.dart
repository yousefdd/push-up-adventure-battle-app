// Standalone sanity test for the rep engine (pure Dart, no Flutter needed).
// Run: dart test_engine.dart
import 'lib/engine/pose.dart';
import 'lib/engine/exercise.dart';
import 'lib/engine/rep_engine.dart';

// Build a pushup pose at a given elbow angle by placing shoulder/elbow/wrist.
// We fake the elbow bend by moving the wrist around the elbow; the exact
// coordinates don't matter, only that the shoulder-elbow-wrist angle equals
// the target. Easiest: put shoulder straight above elbow, wrist at `angle`.
import 'dart:math' as math;

PoseFrame frameAtAngle(double deg, double t, {double conf = 0.9}) {
  // elbow at origin (0.5,0.5); shoulder straight up; wrist rotated by `deg`.
  const ex = 0.5, ey = 0.5;
  const sx = ex, sy = ey - 0.2; // shoulder above
  final rad = deg * math.pi / 180;
  // wrist placed so the angle shoulder-elbow-wrist == deg
  final wx = ex + 0.2 * math.sin(rad);
  final wy = ey - 0.2 * math.cos(rad);
  Landmark lm(double x, double y) => Landmark(x, y, conf);
  return PoseFrame({
    LandmarkType.leftShoulder: lm(sx, sy),
    LandmarkType.leftElbow: lm(ex, ey),
    LandmarkType.leftWrist: lm(wx, wy),
    LandmarkType.rightShoulder: lm(sx, sy),
    LandmarkType.rightElbow: lm(ex, ey),
    LandmarkType.rightWrist: lm(wx, wy),
  }, t);
}

// Push a smooth down-up motion through the engine.
void motion(RepEngine e, double fromDeg, double toDeg, double startT,
    double seconds, int steps) {
  for (var i = 0; i <= steps; i++) {
    final f = i / steps;
    final deg = fromDeg + (toDeg - fromDeg) * f;
    final t = startT + seconds * f;
    e.update(frameAtAngle(deg, t));
  }
}

void main() {
  final results = <String>[];
  void check(String name, bool ok) =>
      results.add('${ok ? "PASS" : "FAIL"}  $name');

  // 1. A clean deep pushup at a sane pace counts exactly one rep.
  {
    var counted = 0;
    RejectReason? lastReject;
    final e = RepEngine(ExerciseProfile.defaults[ExerciseType.pushup]!,
        onRep: (ev) => ev.accepted ? counted++ : lastReject = ev.reason);
    e.update(frameAtAngle(170, 0.0)); // arm at top
    motion(e, 170, 80, 0.0, 0.6, 12); // down to 80deg (past 100)
    motion(e, 80, 170, 0.7, 0.6, 12); // back up
    check('clean deep rep counts once', counted == 1 && lastReject == null);
  }

  // 2. A shallow rep (never reaches 100deg) is rejected as too shallow.
  {
    var counted = 0;
    RejectReason? lastReject;
    final e = RepEngine(ExerciseProfile.defaults[ExerciseType.pushup]!,
        onRep: (ev) => ev.accepted ? counted++ : lastReject = ev.reason);
    e.update(frameAtAngle(170, 0.0));
    motion(e, 170, 120, 0.0, 0.5, 10); // only to 120deg
    motion(e, 120, 170, 0.5, 0.5, 10);
    check('shallow rep rejected',
        counted == 0 && lastReject == RejectReason.tooShallow);
  }

  // 3. A deep but lightning-fast rep is rejected as too fast.
  {
    var counted = 0;
    RejectReason? lastReject;
    final e = RepEngine(ExerciseProfile.defaults[ExerciseType.pushup]!,
        onRep: (ev) => ev.accepted ? counted++ : lastReject = ev.reason);
    e.update(frameAtAngle(170, 0.0));
    // Deep but rushed: ~30fps worth of frames, full depth, ~0.3s total.
    motion(e, 170, 75, 0.0, 0.15, 20); // down fast and deep
    motion(e, 75, 170, 0.15, 0.15, 20); // up fast -> ~0.30s total (< 0.5s)
    check('too-fast rep rejected',
        counted == 0 && lastReject == RejectReason.tooFast);
  }

  // 4. Three good reps in a row count to three.
  {
    var counted = 0;
    final e = RepEngine(ExerciseProfile.defaults[ExerciseType.pushup]!,
        onRep: (ev) { if (ev.accepted) counted++; });
    e.update(frameAtAngle(170, 0.0));
    var t = 0.0;
    for (var i = 0; i < 3; i++) {
      motion(e, 170, 80, t, 0.6, 12);
      t += 0.6;
      motion(e, 80, 170, t, 0.6, 12);
      t += 0.6;
    }
    check('three reps count to three', counted == 3);
  }

  for (final r in results) {
    print(r);
  }
  final failed = results.where((r) => r.startsWith('FAIL')).length;
  print('\n${results.length - failed}/${results.length} passed');
}
