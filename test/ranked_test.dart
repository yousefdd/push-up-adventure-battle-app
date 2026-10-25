import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/modes/online/duel_models.dart';
import 'package:repraid/modes/online/duel_service.dart';
import 'package:repraid/online/ranked.dart';
import 'package:repraid/ui/ads.dart';
import 'package:repraid/ui/rank_widgets.dart';
import 'package:repraid/ui/store_screen.dart';

Map<String, dynamic> _row({bool ranked = true, String? winner = 'h'}) => {
      'id': 'd1',
      'code': 'QABC',
      'exercise': 'pushup',
      'status': 'finished',
      'host': 'h',
      'host_name': 'Host',
      'host_level': 1,
      'host_reps': 20,
      'guest': 'g',
      'guest_name': 'Guest',
      'guest_level': 1,
      'guest_reps': 12,
      'lead_secs': 5,
      'fight_secs': 60,
      'go_at': null,
      'winner': winner,
      'ranked': ranked,
      'host_rating': 1040,
      'guest_rating': 1110,
      'host_rating_delta': 19,
      'guest_rating_delta': -19,
      'host_coins_delta': 3,
      'guest_coins_delta': -2,
    };

void main() {
  test('ratings map to ranks and divisions', () {
    expect(Rank.of(1000).name, 'Bronze II');
    expect(Rank.of(900).name, 'Bronze III');
    expect(Rank.of(1099).name, 'Bronze I');
    expect(Rank.of(1100).name, 'Silver III');
    expect(Rank.of(1300).name, 'Gold II');
    expect(Rank.of(1560).tier, RankTier.diamond);
    expect(Rank.of(1750).tier, RankTier.master);
    expect(Rank.of(2000).tier, RankTier.grandmaster);
    expect(Rank.of(2150).name, 'Champion III');
    expect(RankTier.values.length, 8);
    expect(Rank.of(2500).name, 'Champion I');
    expect(Rank.of(2500).next, isNull);
    expect(RankTier.platinum.paysGold, isFalse);
    expect(RankTier.diamond.paysGold, isTrue);
    expect(Rank.of(1000).progress(1025), closeTo(0.5, 0.01));
    expect(Rank.of(1000) < Rank.of(1050), isTrue);
  });

  test('a ranked result carries my rating and embers change', () {
    final row = DuelRow.fromJson(_row());
    final me = row.resultFor('g');
    expect(me.outcome, DuelOutcome.loss);
    expect(me.ranked, isTrue);
    expect(me.rank!.before, 1110);
    expect(me.rank!.after, 1091);
    expect(me.rank!.gold, -2);
    expect(me.rank!.demoted, isTrue); // Silver III → Bronze I
    final host = row.resultFor('h');
    expect(host.rank!.delta, 19);
    expect(host.rank!.promoted, isTrue); // Bronze II → Bronze I
  });

  test('a friendly result has no rank change', () {
    final r = DuelRow.fromJson(_row(ranked: false)).resultFor('h');
    expect(r.ranked, isFalse);
    expect(r.rank, isNull);
  });

  testWidgets('badges, the store and the ad break render', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          for (final t in RankTier.values) RankBadge(Rank.of(const {
            RankTier.bronze: 1000,
            RankTier.silver: 1120,
            RankTier.gold: 1300,
            RankTier.platinum: 1450,
            RankTier.diamond: 1600,
            RankTier.master: 1800,
            RankTier.grandmaster: 2000,
            RankTier.champion: 2300,
          }[t]!)),
          const CoinChip(gold: 12, silver: 30),
          const RankCard(PlayerStats(rating: 1234, gold: 7)),
          const AdSlot(),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Ad space'), findsOneWidget);
    expect(find.text('Silver I'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: StoreScreen()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Coming soon'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Silver coin rewards'), 300);
    expect(find.text('Silver coin rewards'), findsOneWidget);
    expect(find.text('Free Fire top-up cards'), findsOneWidget);

    // The ad break can't be closed for five seconds.
    await tester.pumpWidget(const MaterialApp(home: AdBreak()));
    expect(find.text('5'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
