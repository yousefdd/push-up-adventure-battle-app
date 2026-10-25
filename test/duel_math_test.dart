import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/modes/online/duel_math.dart';

void main() {
  test('the rope follows the lead, not the share of reps', () {
    expect(DuelMath.tugShare(0, 0), 0.5);
    expect(DuelMath.tugShare(10, 10), 0.5);
    // A 5-rep lead pulls ~88%, the same as in the source app.
    expect(DuelMath.tugShare(15, 10), closeTo(0.881, 0.001));
    expect(DuelMath.tugShare(10, 15), closeTo(0.119, 0.001));
    // Never fully across.
    expect(DuelMath.tugShare(60, 0), 0.98);
    expect(DuelMath.tugShare(0, 60), 0.02);
  });

  test('the final pull ends in the winner\'s half and eases there', () {
    expect(DuelMath.finalPull(8, 8), 0.5);
    expect(DuelMath.finalPull(16, 11), greaterThanOrEqualTo(0.8));
    expect(DuelMath.finalPull(11, 16), lessThanOrEqualTo(0.2));
    expect(DuelMath.pullShare(16, 11, 0), DuelMath.tugShare(16, 11));
    expect(DuelMath.pullShare(16, 11, 1), DuelMath.finalPull(16, 11));
    expect(DuelMath.pullShare(16, 11, 0.5), inExclusiveRange(DuelMath.tugShare(16, 11), DuelMath.finalPull(16, 11)));
  });

  test('the rival counter steps once per 0.4 s at most', () {
    expect(DuelMath.pacedOpponent(3, 9, 0.2), 3);
    expect(DuelMath.pacedOpponent(3, 9, 0.4), 4);
    expect(DuelMath.pacedOpponent(9, 9, 5), 9);
  });

  test('callouts every 5 reps', () {
    expect([for (var i = 1; i <= 16; i++) DuelMath.streakCallout(i)].whereType<int>(), [5, 10, 15]);
  });
}
