import 'package:flutter/material.dart' hide Hero;
import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/i18n/i18n.dart';
import 'package:repraid/ui/ads.dart';
import 'package:repraid/modes/rpg/chapters.dart';
import 'package:repraid/modes/rpg/run_controller.dart';
import 'package:repraid/modes/rpg/ui/adventure_home.dart';
import 'package:repraid/modes/rpg/ui/run_screen.dart';
import 'package:repraid/ui/motion.dart';

Future<void> phone(WidgetTester tester, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  // Looping motion (floating sprites, pulsing buttons) never settles.
  setUpAll(() {
    Motion.loops = false;
    Ads.enabled = false;
  });

  for (final (width, lang) in [(390.0, Lang.en), (1440.0, Lang.en), (390.0, Lang.ar)]) {
    testWidgets('a whole run renders at ${width.toInt()} px in ${lang.name} with no overflow', (tester) async {
      await phone(tester, width: width);
      I18n.lang.value = lang;
      addTearDown(() => I18n.lang.value = Lang.en);
      final store = MemoryRunStore();
      final run = RunController.start(seed: 5, store: store);
      final seen = <RunMode>{};
      await tester.pumpWidget(MaterialApp(
        // Like the app: right to left in Arabic.
        builder: (context, child) => Directionality(textDirection: I18n.direction, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RunScreen(run: run))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      // The screen's ticker never idles, so step time instead of settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The first day by a tap on the button, the rest as pushups (or Space).
      // StrokeText draws its label twice (outline + fill).
      expect(find.text(tr('Next Day')), findsNWidgets(2));
      await tester.tap(find.text(tr('Next Day')).last);
      var guard = 0;
      while (!run.finished && guard++ < 2000) {
        await tester.pump(const Duration(milliseconds: 700));
        seen.add(run.mode);
        if (run.mode == RunMode.pick) {
          // Skill cards in a modal, or the two choice buttons in the bottom bar.
          expect(
              find.textContaining(tr('No pushup? Picking the glowing one in {n}s').split('{n}').first).evaluate().length +
                  find.textContaining(tr('A pushup takes the glowing one · auto in {n}s').split('{n}').first).evaluate().length,
              1);
        }
        run.rep();
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(run.finished, isTrue);
      expect(seen, containsAll([RunMode.walk, RunMode.fight, RunMode.pick, RunMode.card]));
      // The screen closed itself and the save has no run in progress.
      expect(find.text('open'), findsOneWidget);
      expect((await store.load())!['run'], isNull);
      run.dispose();
    });
  }

  testWidgets('adventure home offers Continue for a saved run', (tester) async {
    await phone(tester);
    final store = MemoryRunStore();
    final run = RunController.start(seed: 1, store: store);
    run.rep();
    run.tick(1);
    await tester.pumpWidget(MaterialApp(home: AdventureHome(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsNWidgets(2));
    expect(find.text('Day 1 · Lv.${chapters.first.startLevel}'), findsOneWidget);
    expect(find.text('Start a new run'), findsOneWidget);
  });

  testWidgets('a fresh home shows Start and 0 days', (tester) async {
    await phone(tester);
    await tester.pumpWidget(MaterialApp(home: AdventureHome(store: MemoryRunStore())));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget); // gold buttons use plain text
    expect(find.textContaining('Longest survived'), findsWidgets);
  });
}
