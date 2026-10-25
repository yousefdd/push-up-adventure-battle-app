import 'package:flutter/material.dart';

import '../engine/pose.dart';
import 'theme/rpg_theme.dart';

/// Skeleton drawn over the camera: limbs as rounded lines, joints as white dots
/// with a dark rim, as in the source app's live duel. Limbs are mana-blue in the
/// lower half of the rep and arcane-violet in the upper half.
class SkeletonPainter extends CustomPainter {
  SkeletonPainter(this.frame, this.depth);

  final PoseFrame? frame;

  /// 0 at the top of the rep, 1 at full depth (RepState.depthProgress).
  final double depth;

  static const _bones = [
    [LandmarkType.leftShoulder, LandmarkType.rightShoulder],
    [LandmarkType.leftShoulder, LandmarkType.leftElbow],
    [LandmarkType.leftElbow, LandmarkType.leftWrist],
    [LandmarkType.rightShoulder, LandmarkType.rightElbow],
    [LandmarkType.rightElbow, LandmarkType.rightWrist],
    [LandmarkType.leftShoulder, LandmarkType.leftHip],
    [LandmarkType.rightShoulder, LandmarkType.rightHip],
    [LandmarkType.leftHip, LandmarkType.rightHip],
    [LandmarkType.leftHip, LandmarkType.leftKnee],
    [LandmarkType.leftKnee, LandmarkType.leftAnkle],
    [LandmarkType.rightHip, LandmarkType.rightKnee],
    [LandmarkType.rightKnee, LandmarkType.rightAnkle],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f == null) return;
    Offset? at(LandmarkType t) {
      final lm = f.reliable(t);
      return lm == null ? null : Offset(lm.x * size.width, lm.y * size.height);
    }

    final color = depthColor(depth);
    // A soft glow under thick limbs, as in the source app's live duel.
    final glow = Paint()
      ..color = color.withOpacity(0.35)
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final limb = Paint()
      ..color = color.withOpacity(0.92)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final joints = <Offset>[];
    for (final b in _bones) {
      final p = at(b[0]), q = at(b[1]);
      if (p != null && q != null) {
        canvas.drawLine(p, q, glow);
        canvas.drawLine(p, q, limb);
      }
    }
    for (final t in LandmarkType.values) {
      final p = at(t);
      if (p != null) joints.add(p);
    }
    // The chest point between the shoulders.
    final ls = at(LandmarkType.leftShoulder), rs = at(LandmarkType.rightShoulder);
    if (ls != null && rs != null) joints.add((ls + rs) / 2);

    // White joints ringed in the limb colour.
    final ring = Paint()..color = color;
    final dot = Paint()..color = Colors.white;
    for (final p in joints) {
      canvas.drawCircle(p, 8, ring);
      canvas.drawCircle(p, 5, dot);
    }
  }

  @override
  bool shouldRepaint(SkeletonPainter oldDelegate) => oldDelegate.frame != frame || oldDelegate.depth != depth;
}

/// Shared colour rule for the skeleton and the depth gauge.
Color depthColor(double depth) => depth >= 0.5 ? Rpg.mana : Rpg.arcane;

/// Tall rounded gauge on the right edge showing how deep the current rep is.
/// It fills from the top down as you lower; the white mark (70% down) is where
/// a rep counts, and a counted-depth rep fills it to the bottom, as in the
/// source app.
class DepthMeter extends StatelessWidget {
  const DepthMeter({super.key, required this.progress, this.mark = 0.7});

  final double progress;
  final double mark;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final fill = p >= 1 ? 1.0 : p * mark;
    return SizedBox(
      width: 20,
      child: LayoutBuilder(builder: (context, c) {
        return Stack(children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Rpg.bgDeep.withOpacity(0.55),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: c.maxHeight * fill,
            decoration: BoxDecoration(
              color: depthColor(progress),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Positioned(
            top: c.maxHeight * mark - 1,
            left: -4,
            right: -4,
            child: Container(height: 2, color: Colors.white),
          ),
        ]);
      }),
    );
  }
}
