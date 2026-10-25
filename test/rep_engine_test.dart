import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/engine/exercise.dart';
import 'package:repraid/engine/pose.dart';
import 'package:repraid/engine/rep_engine.dart';

/// A frame whose elbows bend to [deg] (both arms), on a portrait camera.
PoseFrame armsAt(double deg, double t, {double aspect = 9 / 16}) {
  final out = <LandmarkType, Landmark>{};
  for (final left in [true, false]) {
    final s = left ? -1.0 : 1.0;
    const ey = 0.6, len = 0.12;
    final ex = 0.5 + s * 0.15;
    // Upper arm straight up; forearm turned out by (180 - deg).
    final a = (180 - deg) * math.pi / 180;
    out[left ? LandmarkType.leftShoulder : LandmarkType.rightShoulder] = Landmark(ex, ey - len, 1);
    out[left ? LandmarkType.leftElbow : LandmarkType.rightElbow] = Landmark(ex, ey, 1);
    out[left ? LandmarkType.leftWrist : LandmarkType.rightWrist] =
        Landmark(ex + s * math.sin(a) * len / aspect, ey + math.cos(a) * len, 1);
  }
  return PoseFrame(out, t, aspect: aspect);
}

void main() {
  test('angles are measured in true proportions on a portrait camera', () {
    final f = armsAt(90, 0);
    final measured = ExerciseProfile.defaults[ExerciseType.pushup]!.measure(f)!;
    expect(measured, closeTo(90, 1));
  });

  test('a front-view push-up (bottom ~110°) counts, even at 3 detections a second', () {
    // Elbow angles sampled from a real front-facing push-up clip at ~3 fps.
    const cycle = <double>[172, 174, 161, 151, 124, 111, 122, 137, 159, 172];
    var reps = 0;
    final engine = RepEngine(ExerciseProfile.defaults[ExerciseType.pushup]!, onRep: (e) {
      if (e.accepted) reps++;
    });
    var t = 0.0;
    for (var r = 0; r < 5; r++) {
      for (final a in cycle) {
        engine.update(armsAt(a, t));
        t += 0.33;
      }
    }
    expect(reps, 5);
  });

  test('a half rep (~135°) still does not count', () {
    const cycle = <double>[172, 160, 145, 136, 134, 140, 158, 172];
    var reps = 0;
    final engine = RepEngine(ExerciseProfile.defaults[ExerciseType.pushup]!, onRep: (e) {
      if (e.accepted) reps++;
    });
    var t = 0.0;
    for (var r = 0; r < 4; r++) {
      for (final a in cycle) {
        engine.update(armsAt(a, t));
        t += 0.1;
      }
    }
    expect(reps, 0);
  });
}
