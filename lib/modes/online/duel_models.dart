import 'dart:typed_data';

import '../../engine/exercise.dart';
import '../../online/ranked.dart';

/// Timing of a duel: a short lead-in countdown, then the race itself.
/// Mirrors the source app's `{ fight_secs, lead_secs }` window, which the
/// server advertises so both clients agree on the clock.
class DuelWindow {
  const DuelWindow({this.fightSecs = 60, this.leadSecs = 5});
  final int fightSecs;
  final int leadSecs;
}

/// Where a bout is in its lifecycle.
enum DuelPhase {
  /// Both players matched; waiting on the agreed exercise + go signal.
  ready,

  /// Lead-in countdown is running (3… 2… 1…).
  countdown,

  /// The race is live; reps count.
  fighting,

  /// Time is up; [DuelController.result] holds the outcome.
  finished,
}

/// Which side won.
enum DuelOutcome { win, loss, draw }

/// One live score update for a player during the race — the thing that is
/// broadcast so the opponent's counter visibly moves. `reps` is the verified
/// count only; `declared` lets the server flag mismatches (anti-cheat), the
/// way the source app's RepCountCheck does.
class LivePulse {
  const LivePulse({
    required this.playerId,
    required this.reps,
    required this.declared,
    required this.atSecond,
  });

  final String playerId;
  final int reps;
  final int declared;
  final int atSecond;

  Map<String, dynamic> toJson() => {
        'player_id': playerId,
        'reps': reps,
        'declared': declared,
        'at_second': atSecond,
      };

  factory LivePulse.fromJson(Map<String, dynamic> j) => LivePulse(
        playerId: j['player_id'] as String,
        reps: (j['reps'] as num).toInt(),
        declared: (j['declared'] as num).toInt(),
        atSecond: (j['at_second'] as num).toInt(),
      );
}

/// Final result of a bout, decided purely on valid rep count.
class DuelResult {
  const DuelResult({
    required this.outcome,
    required this.myReps,
    required this.opponentReps,
    this.ranked = false,
    this.rank,
  });
  final DuelOutcome outcome;
  final int myReps;
  final int opponentReps;

  /// A matchmade race: it moves ratings and embers (friend codes do not).
  final bool ranked;

  /// What the race did to my rating and embers, once the server settled it.
  final RankChange? rank;
}

/// What the scoreboard shows for one side: name, level and avatar.
class DuelPlayer {
  const DuelPlayer({
    required this.name,
    required this.level,
    required this.avatar,
    this.photo,
  });
  final String name;
  final int level;

  /// Asset path (or, later, a URL) for the round avatar.
  final String avatar;

  /// The player's own picture (a small JPEG), shown instead of [avatar].
  final Uint8List? photo;
}

/// A matched bout: both players, the agreed exercise, and the clock.
class DuelBout {
  const DuelBout({
    required this.boutId,
    required this.myId,
    required this.opponentId,
    required this.exercise,
    required this.window,
    this.me = const DuelPlayer(name: 'You', level: 1, avatar: 'assets/rc/Adrian.png'),
    this.opponent = const DuelPlayer(name: 'Rival', level: 1, avatar: 'assets/rc/Leon.png'),
  });

  final String boutId;
  final String myId;
  final String opponentId;
  final DuelPlayer me;
  final DuelPlayer opponent;

  /// Both sides race the SAME exercise — agreed before matchmaking.
  final ExerciseType exercise;
  final DuelWindow window;
}
