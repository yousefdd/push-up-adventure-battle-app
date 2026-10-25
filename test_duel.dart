// Pure race-logic test (no network, no camera). Run: dart test_duel.dart
import 'lib/engine/exercise.dart';
import 'lib/modes/online/duel_models.dart';
import 'lib/modes/online/duel_controller.dart';

DuelBout bout() => const DuelBout(
      boutId: 'b1',
      myId: 'me',
      opponentId: 'opp',
      exercise: ExerciseType.pushup,
      window: DuelWindow(fightSecs: 60, leadSecs: 5),
    );

void main() {
  final results = <String>[];
  void check(String name, bool ok) =>
      results.add('${ok ? "PASS" : "FAIL"}  $name');

  // 1. Reps thrown during the lead-in countdown do NOT count.
  {
    final c = DuelController(bout())..start();
    c.advanceTo(2); // still in countdown
    c.onMyRep(verifiedReps: 3, declaredReps: 3);
    check('reps during countdown ignored', c.myReps == 0);
  }

  // 2. Reps during the race count; more reps than opponent = win.
  {
    final broadcasts = <LivePulse>[];
    final c = DuelController(bout(), onBroadcast: broadcasts.add)..start();
    c.advanceTo(5); // countdown -> fighting
    check('phase is fighting at t=5', c.phase == DuelPhase.fighting);
    c.onMyRep(verifiedReps: 10, declaredReps: 10); // my live count
    c.onOpponentPulse(const LivePulse(
        playerId: 'opp', reps: 7, declared: 7, atSecond: 30));
    check('my live counter moved', c.myReps == 10);
    // The rival's counter climbs one rep per 0.4 s, never in a jump.
    c.advanceTo(5.5);
    check('opponent counter steps by one', c.opponentReps == 1);
    for (var t = 5.9; t < 9; t += 0.4) {
      c.advanceTo(t);
    }
    check('opponent live counter caught up', c.opponentReps == 7);
    check('my rep was broadcast', broadcasts.length == 1 && broadcasts.first.reps == 10);
    c.advanceTo(65); // race over
    check('phase finished at end', c.phase == DuelPhase.finished);
    check('I win with more reps', c.result!.outcome == DuelOutcome.win);
  }

  // 3. Reps after time is up do not count.
  {
    final c = DuelController(bout())..start();
    c.advanceTo(5);
    c.onMyRep(verifiedReps: 4, declaredReps: 4);
    c.advanceTo(65); // finished
    c.onMyRep(verifiedReps: 99, declaredReps: 99); // too late
    check('late reps ignored', c.result!.myReps == 4);
  }

  // 4. Out-of-order opponent pulse can't lower their shown score.
  {
    final c = DuelController(bout())..start();
    c.advanceTo(5);
    c.onOpponentPulse(const LivePulse(
        playerId: 'opp', reps: 12, declared: 12, atSecond: 40));
    c.onOpponentPulse(const LivePulse(
        playerId: 'opp', reps: 9, declared: 9, atSecond: 35)); // stale
    c.advanceTo(65);
    check('opponent counter is monotonic', c.opponentReps == 12);
  }

  // 5. Equal reps = draw.
  {
    final c = DuelController(bout())..start();
    c.advanceTo(5);
    c.onMyRep(verifiedReps: 8, declaredReps: 8);
    c.onOpponentPulse(const LivePulse(
        playerId: 'opp', reps: 8, declared: 8, atSecond: 59));
    c.advanceTo(65);
    check('equal reps is a draw', c.result!.outcome == DuelOutcome.draw);
  }

  // 6. Countdown reports the right numbers.
  {
    final c = DuelController(bout())..start();
    c.advanceTo(2);
    check('countdown shows 3 left at t=2', c.countdownLeft == 3);
    c.advanceTo(5);
    c.advanceTo(5); // fighting, full clock
    check('60s left at race start', c.secondsLeft == 60);
    c.advanceTo(35); // 30s into race
    check('30s left mid-race', c.secondsLeft == 30);
  }

  // 7. Re-sending an unchanged count (every camera frame) does not re-broadcast.
  {
    final sent = <LivePulse>[];
    final c = DuelController(bout(), onBroadcast: sent.add)..start();
    c.advanceTo(5);
    for (var i = 0; i < 30; i++) {
      c.onMyRep(verifiedReps: 2, declaredReps: 2); // 30 frames, same count
    }
    c.onMyRep(verifiedReps: 3, declaredReps: 3);
    check('only changed counts are broadcast', sent.length == 2);
  }

  // 8. The server's verdict replaces the local one once the race is over.
  {
    final c = DuelController(bout())..start();
    c.advanceTo(5);
    c.onMyRep(verifiedReps: 9, declaredReps: 9);
    c.advanceTo(65);
    c.settle(const DuelResult(
        outcome: DuelOutcome.loss, myReps: 9, opponentReps: 11));
    check('server verdict is final', c.result!.outcome == DuelOutcome.loss);
  }

  for (final r in results) {
    print(r);
  }
  final failed = results.where((r) => r.startsWith('FAIL')).length;
  print('\n${results.length - failed}/${results.length} passed');
}
