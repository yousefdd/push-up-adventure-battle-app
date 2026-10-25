import 'duel_math.dart';
import 'duel_models.dart';

/// Pure, transport-agnostic race logic for a timed duel (1, 3 or 5 minutes).
///
/// It owns the clock, the two scores, and the win decision; it knows nothing
/// about Supabase or cameras. The network layer feeds it opponent pulses and
/// the rep engine feeds it my verified reps; a ticker advances its clock. This
/// separation is what makes the race testable without a network or a camera.
class DuelController {
  DuelController(
    this.bout, {
    this.onBroadcast,
    this.onPhaseChanged,
  });

  final DuelBout bout;

  /// Called whenever my score should be pushed to the opponent (live counter).
  final void Function(LivePulse pulse)? onBroadcast;

  /// Called on every phase transition so the UI can react.
  final void Function(DuelPhase phase)? onPhaseChanged;

  DuelPhase _phase = DuelPhase.ready;
  int _myReps = 0;
  int _myDeclared = 0;
  int _opponentReps = 0; // what the scoreboard shows
  int _opponentTarget = 0; // what the network last said
  double _lastRaise = 0;
  double _elapsed = 0; // seconds since start() (includes lead-in)
  DuelResult? _result;

  DuelPhase get phase => _phase;
  int get myReps => _myReps;
  int get opponentReps => _opponentReps;
  DuelResult? get result => _result;

  /// Seconds left in the race (0 during lead-in and after the end).
  int get secondsLeft {
    if (_phase == DuelPhase.finished) return 0;
    if (_phase != DuelPhase.fighting) return bout.window.fightSecs;
    final left = _fightEnd - _elapsed;
    return left < 0 ? 0 : left.ceil();
  }

  /// Seconds left in the lead-in countdown (3… 2… 1…).
  int get countdownLeft {
    final left = bout.window.leadSecs - _elapsed;
    return left < 0 ? 0 : left.ceil();
  }

  double get _fightEnd => (bout.window.leadSecs + bout.window.fightSecs).toDouble();

  void start() {
    _elapsed = 0;
    _setPhase(DuelPhase.countdown);
  }

  /// Advance the clock to [seconds] since start(). A real ticker calls this
  /// every frame; tests call it with explicit values.
  void advanceTo(double seconds) {
    if (_phase == DuelPhase.ready || _phase == DuelPhase.finished) return;
    _elapsed = seconds;

    if (_phase == DuelPhase.countdown && _elapsed >= bout.window.leadSecs) {
      _setPhase(DuelPhase.fighting);
    }
    // The rival's counter climbs one rep at a time, never in jumps.
    final raised = DuelMath.pacedOpponent(_opponentReps, _opponentTarget, _elapsed - _lastRaise);
    if (raised != _opponentReps) {
      _opponentReps = raised;
      _lastRaise = _elapsed;
    }
    if (_phase == DuelPhase.fighting && _elapsed >= _fightEnd) {
      _finish();
    }
  }

  /// Called by the rep engine. Only reps that land during the race count;
  /// reps thrown before "go" or after "time" are ignored. [verifiedReps] is
  /// the counted reps; [declaredReps] is whatever the raw counter claimed, kept
  /// only so the server can spot tampering.
  void onMyRep({required int verifiedReps, required int declaredReps}) {
    if (_phase != DuelPhase.fighting) return;
    // The screen calls this every camera frame; only a changed count is worth
    // sending over the network.
    if (verifiedReps == _myReps && declaredReps == _myDeclared) return;
    _myReps = verifiedReps;
    _myDeclared = declaredReps;
    onBroadcast?.call(LivePulse(
      playerId: bout.myId,
      reps: _myReps,
      declared: _myDeclared,
      atSecond: _raceSecond,
    ));
  }

  /// Replaces the locally decided result with the server's verdict, which is
  /// final online (it applies the same rules to both sides' reported reps).
  void settle(DuelResult serverResult) {
    if (_phase == DuelPhase.finished) _result = serverResult;
  }

  /// Called by the network layer with the opponent's latest pulse. Monotonic:
  /// a late or out-of-order packet can never lower their shown score.
  void onOpponentPulse(LivePulse pulse) {
    if (pulse.playerId != bout.opponentId) return;
    if (pulse.reps > _opponentTarget) _opponentTarget = pulse.reps;
    // After the bell the true count shows at once.
    if (_phase == DuelPhase.finished) _opponentReps = _opponentTarget;
  }

  int get _raceSecond {
    final s = _elapsed - bout.window.leadSecs;
    return s < 0 ? 0 : s.floor();
  }

  void _finish() {
    _opponentReps = _opponentTarget;
    final DuelOutcome outcome;
    if (_myReps > _opponentReps) {
      outcome = DuelOutcome.win;
    } else if (_myReps < _opponentReps) {
      outcome = DuelOutcome.loss;
    } else {
      outcome = DuelOutcome.draw;
    }
    _result = DuelResult(
      outcome: outcome,
      myReps: _myReps,
      opponentReps: _opponentReps,
    );
    _setPhase(DuelPhase.finished);
  }

  void _setPhase(DuelPhase p) {
    _phase = p;
    onPhaseChanged?.call(p);
  }
}
