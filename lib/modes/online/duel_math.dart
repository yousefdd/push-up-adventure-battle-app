import 'dart:math' as math;

/// The tug-of-war numbers, ported from the friend's Pushup.RPG (used with
/// consent) so the rope moves exactly the way it does in their race video.
class DuelMath {
  DuelMath._();

  /// A lead of this many reps pulls the rope about three quarters across.
  static const double tugLeadScale = 5.0;

  /// The rival's shown count never rises faster than one rep per 0.4 s, so a
  /// burst of network updates still ticks up one by one.
  static const double minShownInterval = 0.4;

  /// End of race: hold the rope, pause, then glide it to the winner's side.
  static const int finalPullHoldMs = 400, finalPullPauseMs = 300, finalPullGlideMs = 1000;
  static const int finalPullBeatMs = 1700;

  /// A callout pops at every 5th rep.
  static const int streakStep = 5;

  /// My share of the rope, 0..1 (0.5 = level). Never fully 0 or 1.
  static double tugShare(int mine, int theirs) => (_tanh((mine - theirs) / tugLeadScale) * 0.5 + 0.5).clamp(0.02, 0.98);

  /// Where the rope ends after the final pull: well into the winner's half.
  static double finalPull(int mine, int theirs) {
    if (mine == theirs) return 0.5;
    final share = tugShare(mine, theirs);
    final lead = math.max(share, 1 - share);
    final end = math.max(lead, math.min(1.0, (lead - 0.5) / 0.25) * 0.15 + 0.8);
    return mine > theirs ? end : 1 - end;
  }

  /// The rope during the final pull; [progress] runs 0..1 over the glide.
  static double pullShare(int mine, int theirs, double progress) {
    final p = progress.clamp(0.0, 1.0);
    final eased = (3 - 2 * p) * p * p; // smoothstep
    final share = tugShare(mine, theirs);
    return (finalPull(mine, theirs) - share) * eased + share;
  }

  /// The rival's shown count after one tick: one step toward [target] at most.
  static int pacedOpponent(int shown, int target, double sinceLastRaise) =>
      target > shown && sinceLastRaise >= minShownInterval ? shown + 1 : shown;

  /// 5, 10, 15… get a callout; everything else none.
  static int? streakCallout(int reps) => reps >= streakStep && reps % streakStep == 0 ? reps : null;

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }
}

/// Quick taunts a player can throw at the rival mid-race.
const taunts = ['Noob 🤣', 'Too slow 🐢', 'Catch me 😎', 'Is that all? 😏', 'GG 🤝', '💪💪'];
