import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/engine/exercise.dart';
import 'package:repraid/engine/pose.dart';
import 'package:repraid/modes/online/duel_models.dart';
import 'package:repraid/modes/online/duel_screen.dart';
import 'package:repraid/modes/online/pose_frame_source.dart';

class _NoCamera implements PoseFrameSource {
  final _c = StreamController<PoseFrame>.broadcast();
  @override
  Stream<PoseFrame> get frames => _c.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

void main() {
  testWidgets('race at 390 px: taunt bubble, rope, then the result card', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final pulses = StreamController<LivePulse>();
    final taunts = StreamController<String>();
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      home: DuelScreen(
        bout: const DuelBout(
          boutId: 't',
          myId: 'me',
          opponentId: 'opp',
          exercise: ExerciseType.pushup,
          window: DuelWindow(fightSecs: 3, leadSecs: 1),
          me: DuelPlayer(name: 'Larry', level: 6, avatar: 'assets/rc/Adrian.png'),
          opponent: DuelPlayer(name: 'Famboy', level: 9, avatar: 'assets/rc/Leon.png'),
        ),
        poseSource: _NoCamera(),
        opponentPulses: pulses.stream,
        opponentTaunts: taunts.stream,
        onExit: () => exited = true,
      ),
    ));

    // The screen's clock is the wall clock, so let real time pass.
    Future<void> wait(int ms) async {
      await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
      await tester.pump(const Duration(milliseconds: 16));
    }

    await wait(1200); // countdown over, race on
    pulses.add(const LivePulse(playerId: 'opp', reps: 2, declared: 2, atSecond: 0));
    taunts.add('Noob 🤣');
    await wait(100);
    expect(find.text('Noob 🤣'), findsOneWidget);
    expect(find.text('DEPTH'), findsOneWidget);

    for (var i = 0; i < 60 && find.text('Done').evaluate().isEmpty; i++) {
      await wait(100);
    }
    expect(find.text('YOU LOSE'), findsOneWidget);
    expect(find.text('0 – 2'), findsOneWidget);
    expect(find.text('They pulled harder this time.'), findsOneWidget);
    expect(find.text('0 push-ups added to your streak and records.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    expect(exited, isTrue);
    await tester.pump(const Duration(seconds: 3)); // let the taunt bubble's timer run out
    await pulses.close();
    await taunts.close();
  });
}
