import 'dart:math' as math;
import 'pose.dart';

/// Geometry helpers for turning landmarks into joint angles.
///
/// The joint angle is the same construction the source app uses: the angle at
/// vertex B formed by the rays B->A and B->C, taken as the absolute signed
/// angle via atan2 so it stays stable near 180 degrees.
class Angles {
  /// Angle in degrees at [vertex], between [a] and [c]. Null if any point is
  /// missing or the limb has zero length (nothing to measure).
  ///
  /// [aspect] is the frame's width / height: landmarks are fractions of the
  /// frame, so on a portrait camera x is scaled back to the same unit as y.
  static double? jointAngle(Landmark? a, Landmark? vertex, Landmark? c, {double aspect = 1.0}) {
    if (a == null || vertex == null || c == null) return null;

    final ax = (a.x - vertex.x) * aspect;
    final ay = a.y - vertex.y;
    final cx = (c.x - vertex.x) * aspect;
    final cy = c.y - vertex.y;

    final lenA = math.sqrt(ax * ax + ay * ay);
    final lenC = math.sqrt(cx * cx + cy * cy);
    if (lenA <= 0 || lenC <= 0) return null;

    final cross = ax * cy - ay * cx;
    final dot = ax * cx + ay * cy;
    return (math.atan2(cross, dot) * 180 / math.pi).abs();
  }

  /// Averages the left/right version of a joint angle, using whichever side is
  /// available. Returns null only when neither side can be measured.
  static double? bilateral(double? left, double? right) {
    if (left != null && right != null) return (left + right) / 2;
    return left ?? right;
  }
}

/// Rolling median smoother. The source app medians recent samples before
/// trusting a depth reading; a short window kills single-frame jitter from the
/// detector without adding much lag.
///
/// The window is the last [size] samples, and never older than [maxAge]
/// seconds when a time is given: a slow detector (a few frames a second) then
/// smooths over fewer samples instead of averaging away the bottom of a rep.
class MedianWindow {
  MedianWindow(this.size, {this.maxAge = 0.3});
  final int size;
  final double maxAge;
  final List<double> _values = [];
  final List<double> _times = [];

  void add(double v, [double? time]) {
    _values.add(v);
    _times.add(time ?? double.nan);
    if (_values.length > size) {
      _values.removeAt(0);
      _times.removeAt(0);
    }
    if (time != null) {
      while (_values.length > 1 && !(time - _times.first <= maxAge)) {
        _values.removeAt(0);
        _times.removeAt(0);
      }
    }
  }

  void clear() {
    _values.clear();
    _times.clear();
  }

  double? get median {
    if (_values.isEmpty) return null;
    final sorted = List<double>.from(_values)..sort();
    return sorted[sorted.length ~/ 2];
  }
}
