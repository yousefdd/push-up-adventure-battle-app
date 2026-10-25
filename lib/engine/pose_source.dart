import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart' as mlkit;

import 'pose.dart';

/// Bridges the pose backend to the engine's own [PoseFrame].
///
/// ML Kit reports landmark positions in image pixels; the engine wants them
/// normalized to [0, 1] with the front camera already mirrored, exactly the
/// convention the source app used. One place does that conversion so the rest
/// of the app never touches ML Kit types.
class PoseSource {
  /// Maps the ML Kit landmark types we care about onto our own enum.
  static const Map<mlkit.PoseLandmarkType, LandmarkType> _map = {
    mlkit.PoseLandmarkType.leftShoulder: LandmarkType.leftShoulder,
    mlkit.PoseLandmarkType.rightShoulder: LandmarkType.rightShoulder,
    mlkit.PoseLandmarkType.leftElbow: LandmarkType.leftElbow,
    mlkit.PoseLandmarkType.rightElbow: LandmarkType.rightElbow,
    mlkit.PoseLandmarkType.leftWrist: LandmarkType.leftWrist,
    mlkit.PoseLandmarkType.rightWrist: LandmarkType.rightWrist,
    mlkit.PoseLandmarkType.leftHip: LandmarkType.leftHip,
    mlkit.PoseLandmarkType.rightHip: LandmarkType.rightHip,
    mlkit.PoseLandmarkType.leftKnee: LandmarkType.leftKnee,
    mlkit.PoseLandmarkType.rightKnee: LandmarkType.rightKnee,
    mlkit.PoseLandmarkType.leftAnkle: LandmarkType.leftAnkle,
    mlkit.PoseLandmarkType.rightAnkle: LandmarkType.rightAnkle,
  };

  /// Converts one detected pose into a [PoseFrame].
  ///
  /// [imageWidth]/[imageHeight] are the analysed frame's dimensions; [mirror]
  /// flips x for a front-facing camera so left/right match the user's view.
  /// [timeSeconds] is a monotonic clock (e.g. from a stopwatch) the rep timing
  /// depends on, so pass a real elapsed time, not frame indices.
  static PoseFrame fromMlkit(
    mlkit.Pose pose, {
    required double imageWidth,
    required double imageHeight,
    required double timeSeconds,
    bool mirror = true,
  }) {
    final out = <LandmarkType, Landmark>{};
    pose.landmarks.forEach((type, lm) {
      final mapped = _map[type];
      if (mapped == null) return;
      var nx = imageWidth > 0 ? lm.x / imageWidth : 0.0;
      final ny = imageHeight > 0 ? lm.y / imageHeight : 0.0;
      if (mirror) nx = 1.0 - nx;
      out[mapped] = Landmark(
        nx.clamp(0.0, 1.0),
        ny.clamp(0.0, 1.0),
        lm.likelihood,
      );
    });
    return PoseFrame(out, timeSeconds, aspect: imageHeight > 0 ? imageWidth / imageHeight : 1.0);
  }
}
