import 'angles.dart';
import 'exercise.dart';
import 'pose.dart';

/// Where the body is in the current rep.
enum RepPhase {
  /// Waiting for the user to reach a clean extended position to arm a rep.
  arming,

  /// Past the top, flexing down toward depth.
  descending,

  /// Reached real depth, dwelling at the bottom.
  bottom,

  /// Rising back toward extension.
  ascending,
}

/// Why a candidate rep was thrown out. These map to the coaching cues the
/// source app shows ("too shallow", "too fast", held too long = rest).
enum RejectReason { tooShallow, tooFast, heldTooLong }

/// Emitted whenever the engine resolves a rep attempt.
class RepEvent {
  RepEvent.counted(this.totalReps, this.scaledTotal)
      : accepted = true,
        reason = null;
  RepEvent.rejected(this.reason)
      : accepted = false,
        totalReps = 0,
        scaledTotal = 0;

  final bool accepted;
  final RejectReason? reason;
  final int totalReps;
  final double scaledTotal;

  String get cue {
    // Wording taken from the source app's coaching lines.
    if (accepted) return 'Every correct rep lands.';
    switch (reason!) {
      case RejectReason.tooShallow:
        return "All the way down between reps — that's what completes it.";
      case RejectReason.tooFast:
        return 'Only correct reps count';
      case RejectReason.heldTooLong:
        return 'Held down too long — that reads as a rest, not a rep';
    }
  }
}

/// Live, per-frame view for the UI (progress ring, angle readout, phase hint).
class RepState {
  const RepState(this.phase, this.angle, this.depthProgress, this.reps);
  final RepPhase phase;
  final double? angle;

  /// 0 at the top, 1 at full depth — drives a progress indicator.
  final double depthProgress;
  final int reps;
}

/// Counts clean reps for one exercise from a stream of pose frames.
///
/// The machine arms at the top, follows the body down to real depth, then back
/// up; the rep only lands if it was deep enough, not a bounce, and not parked
/// at the bottom like a rest. Form gating is what makes online scores fair, so
/// it lives here in shared code rather than in either game mode.
class RepEngine {
  RepEngine(this.profile, {this.onRep});

  ExerciseProfile profile;
  final void Function(RepEvent event)? onRep;

  final MedianWindow _smoother = MedianWindow(5);
  RepPhase _phase = RepPhase.arming;
  int _reps = 0;
  double _scaled = 0;

  // Per-rep bookkeeping.
  double _minAngleThisRep = 180;
  double _repStartTime = 0;
  double _bottomEnterTime = 0;
  bool _depthReached = false;
  bool _leftTop = false;

  int get reps => _reps;
  double get scaledReps => _scaled;

  void reset() {
    _smoother.clear();
    _phase = RepPhase.arming;
    _reps = 0;
    _scaled = 0;
    _depthReached = false;
    _minAngleThisRep = 180;
  }

  /// Feed one pose frame. Returns the current live state for the UI; any
  /// resolved rep (accepted or rejected) is delivered through [onRep].
  RepState update(PoseFrame frame) {
    final raw = profile.measure(frame);
    if (raw == null) {
      // Lost the body — hold state, report no angle so the UI can prompt.
      return RepState(_phase, null, _depthProgressFor(null), _reps);
    }
    final t = frame.timeSeconds;
    _smoother.add(raw, t);
    final angle = _smoother.median ?? raw;

    switch (_phase) {
      case RepPhase.arming:
        if (angle >= profile.upAngle) {
          _beginRep(t);
        }
        break;

      case RepPhase.descending:
        if (angle < _minAngleThisRep) _minAngleThisRep = angle;
        // Require the body to clearly leave the top before a return to the top
        // can be judged; otherwise the frame right after arming (still at the
        // top) would be misread as an instant shallow rep.
        if (angle < profile.upAngle - 15) _leftTop = true;
        if (angle <= profile.downAngle) {
          _depthReached = true;
          _bottomEnterTime = t;
          _phase = RepPhase.bottom;
        } else if (_leftTop && angle >= profile.upAngle) {
          // Dipped and came back up without ever reaching depth.
          _resolve(RepEvent.rejected(RejectReason.tooShallow), t);
        }
        break;

      case RepPhase.bottom:
        if (angle < _minAngleThisRep) _minAngleThisRep = angle;
        // Start counting the climb once we clearly leave the bottom.
        if (angle > profile.downAngle + 15) {
          _phase = RepPhase.ascending;
        }
        break;

      case RepPhase.ascending:
        if (angle >= profile.upAngle) {
          _finishRep(t);
        }
        break;
    }

    return RepState(_phase, angle, _depthProgressFor(angle), _reps);
  }

  void _beginRep(double t) {
    _phase = RepPhase.descending;
    _repStartTime = t;
    _minAngleThisRep = 180;
    _depthReached = false;
    _leftTop = false;
  }

  void _finishRep(double t) {
    final duration = t - _repStartTime;
    final bottomDwell = _bottomEnterTime > 0 ? t - _bottomEnterTime : 0;

    if (!_depthReached || _minAngleThisRep > profile.downAngle) {
      _resolve(RepEvent.rejected(RejectReason.tooShallow), t);
      return;
    }
    if (duration < profile.minRepSeconds) {
      _resolve(RepEvent.rejected(RejectReason.tooFast), t);
      return;
    }
    if (bottomDwell > profile.maxBottomSeconds) {
      _resolve(RepEvent.rejected(RejectReason.heldTooLong), t);
      return;
    }

    _reps += 1;
    _scaled += 1;
    onRep?.call(RepEvent.counted(_reps, _scaled));
    _beginRep(t); // Re-arm from the top for the next rep.
  }

  void _resolve(RepEvent event, double t) {
    onRep?.call(event);
    _beginRep(t);
  }

  double _depthProgressFor(double? angle) {
    if (angle == null) return 0;
    final span = profile.upAngle - profile.downAngle;
    if (span <= 0) return 0;
    final p = (profile.upAngle - angle) / span;
    return p.clamp(0.0, 1.0);
  }
}
