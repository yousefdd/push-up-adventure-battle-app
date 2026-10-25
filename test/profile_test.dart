import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/modes/online/duel_service.dart';
import 'package:repraid/profile/profile.dart';
import 'package:repraid/profile/profile_screen.dart';
import 'package:repraid/ui/motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> row({String? hostAvatar, String? guestAvatar}) => {
      'id': 'd1',
      'code': 'ABCD',
      'exercise': 'pushup',
      'status': 'live',
      'host': 'h',
      'host_name': 'Larry',
      'host_level': 6,
      'host_reps': 0,
      'host_avatar': hostAvatar,
      'guest': 'g',
      'guest_name': 'Famboy',
      'guest_level': 9,
      'guest_reps': 0,
      'guest_avatar': guestAvatar,
      'lead_secs': 5,
      'fight_secs': 60,
      'go_at': null,
      'winner': null,
    };

void main() {
  // Badges and coins animate forever; tests need still frames.
  setUpAll(() => Motion.loops = false);

  testWidgets('any picture fits: a big wide photo becomes a small square', (tester) async {
    await tester.runAsync(() async {
      // A noisy 1200×800 picture: the kind that used to be "too large".
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      final rnd = math.Random(3);
      for (var i = 0; i < 4000; i++) {
        canvas.drawCircle(Offset(rnd.nextDouble() * 1200, rnd.nextDouble() * 800), 2 + rnd.nextDouble() * 12,
            Paint()..color = Color(0xFF000000 | rnd.nextInt(0xFFFFFF)));
      }
      final big = await (await rec.endRecording().toImage(1200, 800)).toByteData(format: ui.ImageByteFormat.png);
      final bytes = big!.buffer.asUint8List();
      expect(bytes.length, greaterThan(44000));
      final fit = await fitPhoto(bytes);
      expect(fit, isNotNull);
      expect(fit!.length, lessThanOrEqualTo(44000));
      final out = (await (await ui.instantiateImageCodec(fit)).getNextFrame()).image;
      expect(out.width, out.height);
      expect(await fitPhoto(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  test('the record counts wins, losses, draws, push-ups and best', () {
    final p = Profile(name: '  Larry ');
    p.record(mine: 16, theirs: 11);
    p.record(mine: 9, theirs: 12);
    p.record(mine: 30, theirs: 30);
    expect((p.wins, p.losses, p.draws, p.races), (1, 1, 1, 3));
    expect((p.pushups, p.best, p.level), (55, 30, 2));
    expect(p.displayName, 'Larry');
    expect(Profile().displayName, 'Player');
  });

  test('a profile survives a save and load, picture included', () async {
    SharedPreferences.setMockInitialValues({});
    final p = Profile(name: 'Larry', photo: Uint8List.fromList([1, 2, 3]), wins: 4, pushups: 120);
    await ProfileStore.save(p);
    final back = await ProfileStore.load();
    expect(back.name, 'Larry');
    expect(back.photo, [1, 2, 3]);
    expect((back.wins, back.pushups, back.level), (4, 120, 3));
  });

  test('the old lobby name carries over to a new profile', () async {
    SharedPreferences.setMockInitialValues({'player_name': 'Leon'});
    expect((await ProfileStore.load()).name, 'Leon');
  });

  test('a picture too big for the server is not sent', () {
    expect(Profile(photo: Uint8List(1000)).photoB64, isNotNull);
    expect(Profile(photo: Uint8List(50000)).photoB64, isNull);
    expect(Profile().photoB64, isNull);
  });

  test('both pictures come back in the duel, each on the right side', () {
    final a = base64Encode([7, 7]), b = base64Encode([9, 9]);
    final r = DuelRow.fromJson(row(hostAvatar: a, guestAvatar: b));
    final asGuest = r.boutFor('g');
    expect(asGuest.me.photo, [9, 9]);
    expect(asGuest.opponent.photo, [7, 7]);
    expect(asGuest.opponent.name, 'Larry');
    // No picture, or a broken one, falls back to the default.
    final plain = DuelRow.fromJson(row(hostAvatar: 'not base64!!'));
    expect(plain.boutFor('h').me.photo, isNull);
    expect(plain.boutFor('h').opponent.photo, isNull);
  });

  testWidgets('profile screen shows the name, the record and a picture button', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await ProfileStore.save(Profile(name: 'Larry', wins: 3, losses: 1, pushups: 64, best: 22));
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Larry'), findsOneWidget);
    expect(find.text('Add a picture'), findsOneWidget);
    expect(find.text('22'), findsOneWidget); // best
    expect(find.text('64'), findsOneWidget); // push-ups
    await tester.enterText(find.byType(TextField), 'Larry B');
    await tester.pump();
    expect((await ProfileStore.load()).name, 'Larry B');
  });
}
