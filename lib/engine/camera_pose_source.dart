import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart' as mlkit;

import '../modes/online/pose_frame_source.dart';
import 'pose.dart';
import 'pose_source.dart';

/// The real thing: the front camera, shown to the user like a mirror, with
/// every frame run through ML Kit pose detection and turned into a [PoseFrame].
///
/// Detection runs on the analysis stream one frame at a time; frames that
/// arrive while ML Kit is still busy are dropped rather than queued, so the
/// skeleton stays live instead of lagging behind the body.
class CameraPoseSource implements PoseFrameSource {
  CameraController? _camera;
  final _detector = mlkit.PoseDetector(
    options: mlkit.PoseDetectorOptions(
      mode: mlkit.PoseDetectionMode.stream,
      model: mlkit.PoseDetectionModel.base,
    ),
  );
  final _frames = StreamController<PoseFrame>.broadcast();
  final _clock = Stopwatch();

  /// Opens the front camera once and closes it again: false if there is no
  /// camera or the player refused it. Races need it before they start.
  static Future<bool> check() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      final c = CameraController(front, ResolutionPreset.low, enableAudio: false);
      await c.initialize(); // asks for the camera permission if needed
      await c.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }
  bool _busy = false;
  bool _stopped = false;

  /// Notifies once the camera is open, so the screen can swap the placeholder
  /// for the live preview.
  final ValueNotifier<bool> ready = ValueNotifier(false);

  @override
  Stream<PoseFrame> get frames => _frames.stream;

  CameraController? get controller => _camera;

  /// Upright (portrait) width / height of the analysed frames. The preview and
  /// the skeleton are both laid out in a box of this shape, then cropped
  /// together, so joints land exactly on the body.
  double get aspectRatio {
    final size = _camera?.value.previewSize;
    if (size == null) return 3 / 4;
    return size.height / size.width; // previewSize is reported landscape
  }

  @override
  Future<void> start() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final camera = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await camera.initialize(); // asks for the camera permission if needed
    _camera = camera;
    _clock.start();
    await camera.startImageStream(_onImage);
    ready.value = true;
  }

  Future<void> _onImage(CameraImage image) async {
    if (_busy) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final poses = await _detector.processImage(input);
      if (poses.isEmpty || _frames.isClosed) return;

      // ML Kit reports positions in the upright frame, so a 90/270 sensor
      // swaps width and height.
      final sideways = _rotationDegrees % 180 != 0;
      _frames.add(PoseSource.fromMlkit(
        poses.first,
        imageWidth: (sideways ? image.height : image.width).toDouble(),
        imageHeight: (sideways ? image.width : image.height).toDouble(),
        timeSeconds: _clock.elapsedMicroseconds / 1e6,
        mirror: true, // the front preview is mirrored, so mirror joints too
      ));
    } catch (e) {
      debugPrint('pose detection failed: $e');
    } finally {
      _busy = false;
    }
  }

  int get _rotationDegrees => _camera?.description.sensorOrientation ?? 0;

  mlkit.InputImage? _toInputImage(CameraImage image) {
    final rotation = mlkit.InputImageRotationValue.fromRawValue(_rotationDegrees);
    final format = mlkit.InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null || image.planes.length != 1) {
      return null; // only single-plane NV21 (Android) / BGRA (iOS) are handled
    }
    final plane = image.planes.first;
    return mlkit.InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: mlkit.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Live mirror preview, cropped to fill the screen together with [overlay]
  /// (the skeleton), which is drawn in the same frame coordinates.
  Widget preview({Widget? overlay}) {
    return ValueListenableBuilder<bool>(
      valueListenable: ready,
      builder: (context, isReady, _) {
        final camera = _camera;
        if (!isReady || camera == null) {
          return const ColoredBox(color: Colors.black);
        }
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 1000 * aspectRatio,
              height: 1000,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(camera),
                  if (overlay != null) overlay,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Future<void> stop() async {
    if (_stopped) return; // called on race end and again on dispose
    _stopped = true;
    final camera = _camera;
    _camera = null;
    ready.value = false;
    if (camera != null) {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      await camera.dispose();
    }
    await _detector.close();
    if (!_frames.isClosed) await _frames.close();
  }
}
