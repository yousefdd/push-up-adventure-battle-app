import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import '../modes/online/pose_frame_source.dart';
import 'pose.dart';

/// The webcam in a browser: web/rr_pose.js opens the front camera and runs
/// MediaPipe Pose Landmarker on every frame; this polls the latest pose and
/// turns it into [PoseFrame]s for the rep engine, and shows the camera behind
/// the race the way the phone app does. If the camera is refused or missing,
/// [start] throws [CameraUnavailable] and no reps are counted.
class WebPoseSource implements PoseFrameSource {
  static const _viewType = 'rr-camera';
  static bool _registered = false;

  /// The bridge script is on the page.
  static bool get available => globalContext.has('rrPose');

  /// Opens the webcam once and closes it again: false if it is missing or
  /// refused. Races need it before they start.
  static Future<bool> check() async {
    if (!available) return false;
    final bridge = globalContext['rrPose'] as JSObject;
    final ok = (await bridge.callMethod<JSPromise<JSBoolean>>('start'.toJS).toDart).toDart;
    if (ok) bridge.callMethod('stop'.toJS);
    return ok;
  }

  final _frames = StreamController<PoseFrame>.broadcast();
  final ValueNotifier<bool> ready = ValueNotifier(false);
  final ValueNotifier<bool> failed = ValueNotifier(false);
  Timer? _poll;
  double _lastT = -1;
  double _aspect = 9 / 16;

  // MediaPipe's 33-point pose: the indices the engine needs.
  static const _index = {
    11: LandmarkType.leftShoulder,
    12: LandmarkType.rightShoulder,
    13: LandmarkType.leftElbow,
    14: LandmarkType.rightElbow,
    15: LandmarkType.leftWrist,
    16: LandmarkType.rightWrist,
    23: LandmarkType.leftHip,
    24: LandmarkType.rightHip,
    25: LandmarkType.leftKnee,
    26: LandmarkType.rightKnee,
    27: LandmarkType.leftAnkle,
    28: LandmarkType.rightAnkle,
  };

  JSObject get _bridge => globalContext['rrPose'] as JSObject;

  @override
  Stream<PoseFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {
    var ok = false;
    if (available) {
      if (!_registered) {
        final video = _bridge.callMethod<JSObject>('video'.toJS);
        ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => video);
        _registered = true;
      }
      ok = (await _bridge.callMethod<JSPromise<JSBoolean>>('start'.toJS).toDart).toDart;
    }
    if (!ok) {
      failed.value = true;
      throw const CameraUnavailable();
    }
    ready.value = true;
    _poll = Timer.periodic(const Duration(milliseconds: 33), (_) => _read());
  }

  void _read() {
    final f = _bridge.callMethod<JSAny?>('frame'.toJS);
    if (f == null) return;
    final o = f as JSObject;
    final t = (o['t'] as JSNumber).toDartDouble;
    if (t == _lastT) return;
    _lastT = t;
    final w = (o['w'] as JSNumber).toDartDouble, h = (o['h'] as JSNumber).toDartDouble;
    if (w > 0 && h > 0) _aspect = w / h;
    final lm = (o['lm'] as JSArray<JSArray<JSNumber>>).toDart;
    final out = <LandmarkType, Landmark>{};
    _index.forEach((i, type) {
      if (i >= lm.length) return;
      final p = lm[i].toDart.map((n) => n.toDartDouble).toList();
      // The video is shown mirrored, so the skeleton is mirrored too.
      out[type] = Landmark((1 - p[0]).clamp(0.0, 1.0), p[1].clamp(0.0, 1.0), p[2]);
    });
    _frames.add(PoseFrame(out, t, aspect: _aspect));
  }

  /// The live camera with [overlay] (the skeleton) laid over it in the same
  /// box, cropped together to fill the screen, so joints land on the body.
  Widget preview({Widget? overlay}) {
    return ValueListenableBuilder<bool>(
      valueListenable: failed,
      builder: (context, isFailed, _) {
        if (isFailed) return const ColoredBox(color: Colors.black);
        return ValueListenableBuilder<bool>(
          valueListenable: ready,
          builder: (context, isReady, _) => ColoredBox(
            color: Colors.black,
            child: !isReady
                ? const SizedBox.expand()
                : ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: 1000 * _aspect,
                        height: 1000,
                        child: Stack(fit: StackFit.expand, children: [
                          const HtmlElementView(viewType: _viewType),
                          if (overlay != null) IgnorePointer(child: overlay),
                        ]),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  @override
  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    // The last camera frame stays up behind the result card.
    if (available && ready.value) _bridge.callMethod('stop'.toJS);
  }
}
