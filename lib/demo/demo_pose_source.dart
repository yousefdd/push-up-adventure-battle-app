import 'dart:async';
import 'dart:math' as math;

import '../engine/pose.dart';
import '../modes/online/pose_frame_source.dart';

/// A fake pose source that scripts a steady stream of clean pushups, so the
/// race screen can be run and seen on any device with no camera and no backend.
/// Only in the video build (see demo_race.dart); real races need the camera.
class DemoPoseSource implements PoseFrameSource {
  DemoPoseSource({this.secondsPerRep = 1.4});
  final double secondsPerRep;

  final _controller = StreamController<PoseFrame>.broadcast();
  final _clock = Stopwatch();
  Timer? _timer;

  @override
  Stream<PoseFrame> get frames => _controller.stream;

  @override
  Future<void> start() async {
    _clock.start();
    // ~30 fps of synthetic frames.
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final t = _clock.elapsedMilliseconds / 1000.0;
      _controller.add(_frameAt(t));
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _clock.stop();
    await _controller.close();
  }

  // Oscillate the elbow angle between the top (~170) and bottom (~80) so the
  // rep engine counts a clean rep each cycle.
  PoseFrame _frameAt(double t) {
    final phase = (t % secondsPerRep) / secondsPerRep; // 0..1
    final wave = (1 - math.cos(phase * 2 * math.pi)) / 2; // 0..1..0 smooth
    final deg = 170 - wave * 90; // 170 at top, 80 at bottom
    return _pushupFrame(deg, t);
  }

  // A front-on pushup, as the camera sees it when propped in front of you.
  // Hands stay planted; each elbow is placed so the shoulder-elbow-wrist angle
  // is exactly [deg], which lowers the shoulders naturally as the arms bend.
  PoseFrame _pushupFrame(double deg, double t) {
    const arm = 0.15; // upper arm and forearm length (normalized)
    final out = <LandmarkType, Landmark>{};
    Landmark lm(double x, double y) => Landmark(x, y, 0.95);

    double shoulderY = 0;
    for (final left in [true, false]) {
      final wx = left ? 0.24 : 0.76, wy = 0.80;
      final sx = left ? 0.34 : 0.66;
      final rad = deg * math.pi / 180;
      final reach = math.sqrt(2 * arm * arm * (1 - math.cos(rad)));
      final dx = (sx - wx).abs();
      final sy = wy - math.sqrt(math.max(reach * reach - dx * dx, 0));
      shoulderY = sy;

      // Elbow: where the two arm segments meet, on the outer side.
      final mx = (sx + wx) / 2, my = (sy + wy) / 2;
      final h = math.sqrt(math.max(arm * arm - reach * reach / 4, 0));
      final px = -(wy - sy) / reach, py = (wx - sx) / reach;
      var ex = mx + h * px, ey = my + h * py;
      if (left ? ex > mx : ex < mx) {
        ex = mx - h * px;
        ey = my - h * py;
      }

      out[left ? LandmarkType.leftShoulder : LandmarkType.rightShoulder] = lm(sx, sy);
      out[left ? LandmarkType.leftElbow : LandmarkType.rightElbow] = lm(ex, ey);
      out[left ? LandmarkType.leftWrist : LandmarkType.rightWrist] = lm(wx, wy);
    }

    // Torso and legs recede behind the shoulders in a front view.
    for (final left in [true, false]) {
      final x = left ? 0.43 : 0.57;
      out[left ? LandmarkType.leftHip : LandmarkType.rightHip] = lm(x, shoulderY + 0.10);
      out[left ? LandmarkType.leftKnee : LandmarkType.rightKnee] = lm(left ? 0.45 : 0.55, shoulderY + 0.16);
      out[left ? LandmarkType.leftAnkle : LandmarkType.rightAnkle] = lm(left ? 0.46 : 0.54, shoulderY + 0.20);
    }
    return PoseFrame(out, t);
  }
}
