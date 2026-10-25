/// Pose data types shared by the rep engine.
///
/// Landmarks are normalized to the [0, 1] range the way the source app does it:
/// x and y are the fraction across the frame, origin at top-left, already
/// mirrored for a front camera. This keeps the engine independent of whichever
/// pose backend feeds it (MediaPipe Pose Landmarker or ML Kit both map cleanly).
library;

/// The subset of body points the exercises actually need.
enum LandmarkType {
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}

/// A single normalized body point plus how confident the detector is that the
/// point is actually in frame. Mirrors ML Kit's `inFrameLikelihood`.
class Landmark {
  const Landmark(this.x, this.y, this.confidence);

  final double x;
  final double y;
  final double confidence;
}

/// One detected pose: whatever landmarks were visible this frame, plus the
/// timestamp in seconds. Missing points are simply absent from the map.
class PoseFrame {
  PoseFrame(this.landmarks, this.timeSeconds, {this.aspect = 1.0});

  final Map<LandmarkType, Landmark> landmarks;
  final double timeSeconds;

  /// Width / height of the analysed image. x and y are fractions of
  /// different lengths on a portrait camera, so angles scale x by this.
  final double aspect;

  /// Returns the landmark only when it clears the confidence floor, so the
  /// engine never reasons about a joint the detector is guessing at.
  Landmark? reliable(LandmarkType type, {double minConfidence = 0.18}) {
    final lm = landmarks[type];
    if (lm == null || lm.confidence < minConfidence) return null;
    return lm;
  }
}
