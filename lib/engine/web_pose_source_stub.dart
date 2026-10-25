import 'package:flutter/widgets.dart';

import '../modes/online/pose_frame_source.dart';

/// Not a browser: there is no webcam bridge, so there is nothing to count with.
class WebPoseSource extends NoCameraSource {
  static bool get available => false;
  static Future<bool> check() async => false;

  final ValueNotifier<bool> ready = ValueNotifier(false);
  final ValueNotifier<bool> failed = ValueNotifier(true);

  Widget preview({Widget? overlay}) => overlay ?? const SizedBox.shrink();
}
