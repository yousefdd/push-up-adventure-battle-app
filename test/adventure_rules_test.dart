import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/modes/rpg/adventure_rules.dart';
import 'package:repraid/modes/rpg/run_controller.dart';

/// A steady set: ~1.4 s per pushup (0.9–2.2 s).
double repGap(Rng rng) => 0.9 + rng() * 1.0 + rng() * 0.3;

/// The balance simulation from the preview, on the Dart rules: random
/// decisions, live fights with the foe on its own clock.
({String at, int reps}) simulateRules(Rng rng) {
  final h = Hero.start(chapters.first.startLevel);
  var fightReps = 0;
  for (var day = 1; day <= chapterOne.length; day++) {
    final n = chapterOne[day - 1];
    if (n == 'skill') {
      applySkill(h, skillOffer(rng)[(rng() * 3).floor()]);
    } else if (n == 'story') {
      stories[(rng() * stories.length).floor()].effect.apply(h);
    } else if (n == 'wheel') {
      final s = wheel[(rng() * wheel.length).floor()];
      if (s.skill) {
        applySkill(h, skillOffer(rng)[0]);
      } else if (s.xp > 0) {
        gainXp(h, s.xp);
      } else {
        s.apply!(h);
      }
    } else if (n == 'choice') {
      final c = choices[(rng() * choices.length).floor()];
      (rng() < .5 ? c.a : c.b).effect.apply(h);
    } else if (n == 'chest') {
      equip(h, rollLoot(rng));
    } else {
      final st = FightState(foeFor(n == 'boss' ? 'boss' : n.substring(4)));
      var t = 0.0, nextRep = repGap(rng), nextFoe = st.pace;
      while (st.hp > 0 && h.hp > 0) {
        if (nextRep <= nextFoe) {
          t = nextRep;
          heroStrike(h, st, rng);
          nextRep = t + repGap(rng);
        } else {
          t = nextFoe;
          foeStrike(h, st);
          nextFoe = t + st.pace;
        }
      }
      fightReps += (t / 1.4).round();
      if (!(st.hp <= 0 && h.hp > 0)) return (at: n, reps: day + fightReps);
      gainXp(h, winFight(h, st).$1);
    }
  }
  return (at: 'clear', reps: 30 + fightReps);
}

/// The same chapter, but through RunController: a player who does a pushup
/// every ~1.4 s and never touches the screen.
RunController playHandsFree(int seed) {
  final dice = math.Random(seed * 7 + 1).nextDouble;
  final c = RunController.start(seed: seed);
  var guard = 0;
  while (!c.finished && guard++ < 100000) {
    var gap = repGap(dice);
    while (gap > 0) {
      final dt = math.min(gap, 0.05);
      c.tick(dt);
      gap -= dt;
    }
    c.rep();
  }
  return c;
}

void main() {
  test('chapter one numbers: tough foes, a boss that takes a while', () {
    expect(chapterOne.length, 30);
    expect(chapterOne.last, 'boss');
    final b = foeFor('boss');
    final slime = foeFor('0'), elite = foeFor('0+');
    expect((b.hp, b.atk), (1430, 35));
    expect((slime.hp, slime.atk), (156, 11));
    expect((elite.hp, elite.atk), (211, 14));
    // Nothing falls to one blow from a hero of the world's level.
    expect(slime.hp, greaterThan(Hero.start(chapters.first.startLevel + 4).atk * 3));
    expect(elite.name, 'Moss Slime ★');
  });

  test('levels, skills and loot apply as written', () {
    final h = Hero.start(1, 'ranger');
    expect(gainXp(h, 125), 2);
    expect((h.lv, h.xp, h.max, h.atk), (3, 5, 150, 20));
    applySkill(h, 'edge');
    expect(h.atk, 24);
    applySkill(h, 'guard');
    expect(h.def, 6);
    equip(h, loot.last);
    expect(h.atk, 36);
  });

  test('balance: above-medium, ~45% clear with no gear (5000 seeded runs)', () {
    final rng = seededRng(42);
    const n = 5000;
    var clears = 0, clearReps = 0, bossLosses = 0;
    for (var i = 0; i < n; i++) {
      final r = simulateRules(rng);
      if (r.at == 'clear') {
        clears++;
        clearReps += r.reps;
      } else if (r.at == 'boss') {
        bossLosses++;
      }
    }
    final clearRate = clears / n, perClear = clearReps / clears;
    // ignore: avoid_print
    print('clear ${(clearRate * 100).toStringAsFixed(1)}%  '
        'boss losses ${(bossLosses / n * 100).toStringAsFixed(1)}%  ~pushups ${perClear.round()}');
    expect(clearRate, inInclusiveRange(0.35, 0.55));
    expect(perClear, inInclusiveRange(100, 140));
    expect(bossLosses, greaterThan((n - clears) * 0.8), reason: 'almost every loss is the boss');
  });

  test('a whole run plays with pushups only, no taps', () {
    var clears = 0;
    for (var seed = 1; seed <= 200; seed++) {
      final c = playHandsFree(seed);
      expect(c.finished, isTrue, reason: 'seed $seed got stuck in ${c.mode}');
      if (c.cleared) clears++;
      expect(c.day, inInclusiveRange(1, 30));
    }
    // Picks follow the glow, not a random choice, so allow a wider band (about 4 in 9 win).
    expect(clears, inInclusiveRange(60, 120));
  });

  test('every state names what the next pushup does', () {
    final c = RunController.start(seed: 3);
    final seen = <RunMode>{};
    while (!c.finished) {
      c.tick(1.4);
      seen.add(c.mode);
      expect(c.actionLabel.$1, isNotEmpty);
      c.rep();
    }
    expect(seen, containsAll([RunMode.walk, RunMode.fight, RunMode.pick, RunMode.card]));
  });

  test('picks glow in turn and auto-pick after 12 s', () {
    final c = RunController.start(seed: 9);
    c.rep(); // day 1: story
    c.tick(1);
    c.rep(); // day 2: the first foe walks in
    c.tick(walkTime + 0.05);
    c.tick(fightIntro + 0.05);
    expect(c.mode, RunMode.fight);
    while (c.mode == RunMode.fight) {
      c.rep();
      c.tick(0.5);
    }
    c.tick(1);
    expect(c.mode, RunMode.walk);
    c.rep(); // day 3: skill pick
    c.tick(walkTime);
    expect(c.mode, RunMode.pick);
    expect(c.litIndex, 0);
    c.tick(pickCycle);
    expect(c.litIndex, 1);
    c.tick(pickCycle);
    expect(c.litIndex, 2);
    c.tick(pickCycle);
    expect(c.litIndex, 0);
    c.tick(pickAuto);
    expect(c.mode, isNot(RunMode.pick));
    expect(c.hero.sk.values.fold(0, (a, b) => a + b), 1);
  });

  test('a saved run resumes on the same day with the same dice', () async {
    final store = MemoryRunStore();
    final a = RunController.start(seed: 77, store: store);
    // Walk the first five days, then stop on a resolved day.
    void settle() {
      while (a.mode != RunMode.walk && !a.finished) {
        a.tick(0.3);
        if (a.mode != RunMode.busy && a.mode != RunMode.walk) a.rep();
      }
    }

    for (var i = 0; i < 5; i++) {
      a.rep();
      settle();
    }
    expect(a.finished, isFalse);
    final saved = (await store.load())!;
    final b = RunController.resume(Map<String, dynamic>.from(saved['run'] as Map));
    expect(b.day, a.day);
    expect(b.hero.toJson(), a.hero.toJson());
    expect(b.log.first.head, a.log.first.head);
    // Same input from here gives the same run.
    for (var i = 0; i < 40 && !a.finished && !b.finished; i++) {
      for (final c in [a, b]) {
        c.tick(1.3);
        c.rep();
      }
      expect(b.day, a.day);
      expect(b.hero.hp, a.hero.hp);
    }
  });

  test('a lucky wheel waits for a pushup to spin, or spins itself after a while', () {
    // Walk until the road offers a wheel.
    RunController wheelRun(int seed) {
      final c = RunController.start(seed: seed);
      for (var i = 0; i < 400 && c.mode != RunMode.spin && !c.finished; i++) {
        if (c.mode == RunMode.busy) {
          c.tick(0.3);
        } else {
          c.rep();
          c.tick(0.05);
        }
      }
      return c;
    }

    final a = wheelRun(9);
    expect(a.mode, RunMode.spin);
    expect(a.overlay!.spinning, isFalse);
    a.tick(spinAuto - 1);
    expect(a.overlay!.spinning, isFalse, reason: 'still waiting for the pushup');
    a.rep();
    expect(a.overlay!.spinning, isTrue);
    expect(a.mode, RunMode.busy);

    final b = wheelRun(9);
    b.tick(spinAuto + 0.1);
    expect(b.overlay!.spinning, isTrue, reason: 'no pushup: it spins itself');
  });
}
