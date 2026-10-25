import '../../engine/pose.dart';

/// A source of pose frames the race screen listens to. Abstracting it means the
/// screen runs the same way against a real camera (ML Kit) or a fake driver in
/// a demo/test, so the UI can be exercised without a device.
abstract class PoseFrameSource {
  Stream<PoseFrame> get frames;

  /// Throws [CameraUnavailable] when there is no camera to count with.
  Future<void> start();
  Future<void> stop();
}

/// No camera, or it was refused: nothing counts, so nothing can be faked.
class CameraUnavailable implements Exception {
  const CameraUnavailable();
}

/// Where there is no camera at all.
class NoCameraSource implements PoseFrameSource {
  @override
  Stream<PoseFrame> get frames => const Stream.empty();
  @override
  Future<void> start() async => throw const CameraUnavailable();
  @override
  Future<void> stop() async {}
}
