import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/modes/rpg/adventure_rules.dart';
import 'package:repraid/modes/rpg/run_controller.dart';

double repGap(Rng rng) => 0.9 + rng() * 1.0 + rng() * 0.3;

GearBonus kit(Rarity? r) {
  if (r == null) return GearBonus.none;
  final a = Armory();
  for (final k in ['sword', 'plate', 'helm', 'greaves', 'ruby', 'star']) {
    a.add(k, r);
  }
  return a.bonus;
}

/// One run with random decisions, a pushup every ~1.4 s, live battles with
/// specials and heavy blows.
bool clears(Rng rng, ChapterDef ch, Tier tier, String cls, GearBonus gear) {
  final h = Hero.start(ch.startLevel, cls, gear);
  var charge = 0;
  for (final n in chapterOne) {
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
      equip(h, rollLoot(rng, luck: h.heroClass.lootLuck));
    } else {
      final b = Battle(h, foeFor(n == 'boss' ? 'boss' : n.substring(4), ch, tier), rng, charge: charge);
      if (!simulateFight(b, () => repGap(rng))) return false;
      charge = b.charge;
      gainXp(h, winFight(h, b.st).$1);
    }
  }
  return true;
}

double rate(ChapterDef ch, Tier t, GearBonus g, {int n = 120}) {
  var w = 0;
  for (final c in heroClasses) {
    final rng = seededRng(ch.number * 131 + t.index * 17 + c.id.length);
    for (var i = 0; i < n; i++) {
      if (clears(rng, ch, t, c.id, g)) w++;
    }
  }
  return w / (n * heroClasses.length);
}

void main() {
  test('fifteen worlds, ninety painted foes, each world harder', () {
    expect(chapters.length, 15);
    expect(chapters.expand((c) => [...c.foes, c.boss]).length, 90);
    expect(chapters.expand((c) => [...c.foes, c.boss]).map((f) => f.img).toSet().length, 90);
    for (var i = 1; i < chapters.length; i++) {
      expect(chapters[i].boss.m, greaterThan(chapters[i - 1].boss.m));
      expect(chapters[i].startLevel, greaterThanOrEqualTo(chapters[i - 1].startLevel));
    }
    expect(foeFor('boss', chapters.last).name, 'The Void Eye');
    expect(foeFor('boss').windsUp, isTrue);
    expect(foeFor('2+', chapters[1], Tier.nightmare).windsUp, isTrue);
    expect(foeFor('2+', chapters[1]).windsUp, isFalse);
    expect(foeFor('0', chapters[0], Tier.nightmare).hp, closeTo(foeFor('0').hp * 2.0, 1.5));
    expect(Tier.values, [Tier.normal, Tier.nightmare]);
  });

  test('normal is hard (abilities included); nightmare is for mythic gear', () {
    for (final ch in [chapters[0], chapters[4], chapters[9], chapters[14]]) {
      expect(rate(ch, Tier.normal, GearBonus.none), inInclusiveRange(0.22, 0.58), reason: '${ch.name} normal');
      expect(rate(ch, Tier.normal, kit(Rarity.rare)), greaterThan(0.7), reason: '${ch.name} normal, rare');
      expect(rate(ch, Tier.nightmare, kit(Rarity.mythic)), inInclusiveRange(0.15, 0.65),
          reason: '${ch.name} nightmare, mythic');
      expect(rate(ch, Tier.nightmare, GearBonus.none, n: 60), lessThan(0.05), reason: '${ch.name} nightmare bare');
    }
  });

  test('no foe falls to one blow, however deep the world', () {
    for (final ch in chapters) {
      final h = Hero.start(ch.startLevel + 4, 'berserker', kit(Rarity.rare));
      final crit = (h.atk * h.heroClass.critMult).round();
      for (var i = 0; i < 5; i++) {
        expect(foeFor('$i', ch).hp, greaterThan(h.atk * 3), reason: '${ch.name} foe $i: four plain hits or more');
        expect(foeFor('$i', ch).hp, greaterThan(crit), reason: '${ch.name} foe $i: a crit is not enough');
      }
      expect(foeFor('boss', ch).hp, greaterThan(h.atk * 25), reason: '${ch.name} boss');
    }
    // Even a stacked Spark opening blow leaves the foe standing.
    final h = Hero.start(9, 'berserker', kit(Rarity.epic))..sk['spark'] = 3;
    final st = FightState(foeFor('0', chapters.first));
    heroStrike(h, st, () => 0.0);
    expect(st.hp, greaterThan(0));
  });

  test('specials charge on strikes and fire on the next pushup', () {
    for (final c in heroClasses) {
      final h = Hero.start(5, c.id);
      final b = Battle(h, foeFor('boss', chapters[3]), seededRng(1));
      for (var i = 0; i < h.specialCost; i++) {
        expect(b.rep().single, isA<StrikeEvent>());
      }
      expect(b.specialReady, isTrue);
      final e = b.rep().first as SpecialEvent;
      expect(e.name, c.special);
      expect(e.result.blows, isNotEmpty);
      expect(b.charge, 0);
    }
  });

  test('three quick pushups stagger a heavy blow; otherwise it lands hard', () {
    final h = Hero.start(10, 'ranger');
    final b = Battle(h, foeFor('boss'), seededRng(2));
    // Two normal attacks, then the wind-up on the third.
    final events = <BattleEvent>[];
    for (var i = 0; i < 3; i++) {
      events.addAll(b.advance(b.pace + 0.01));
    }
    expect(events.whereType<FoeHitEvent>().length, 2);
    expect(events.last, isA<WindupEvent>());
    expect(b.windup, isTrue);
    b.rep();
    b.rep();
    expect(b.rep().whereType<InterruptEvent>(), isNotEmpty);
    expect(b.windup, isFalse);

    final h2 = Hero.start(10, 'ranger');
    final b2 = Battle(h2, foeFor('boss'), seededRng(2));
    for (var i = 0; i < 3; i++) {
      b2.advance(b2.pace + 0.01);
    }
    final before = h2.hp;
    final heavy = b2.advance(windupTime + 0.01).single as FoeHitEvent;
    expect(heavy.heavy, isTrue);
    expect(before - h2.hp, greaterThan(foeFor('boss').atk * 2 - h2.def - 2));
  });

  test('dropping a piece on its twin merges the two, and only that way', () {
    final a = Armory();
    final first = a.add('sword', Rarity.common);
    expect(a.canMerge(first), isFalse);
    final second = a.add('sword', Rarity.common);
    final axe = a.add('axe', Rarity.common);
    expect(a.isWorn(first), isTrue);
    expect(a.canMerge(first), isTrue);
    // Nothing merges on its own; a different piece, or a piece on itself, does not merge.
    expect(a.items.length, 3);
    expect(a.mergeInto(axe, first), isNull);
    expect(a.mergeInto(first, first), isNull);
    // Dropping the spare sword on the worn one makes an Uncommon, still worn.
    final up = a.mergeInto(second, first)!;
    expect(up.rarity, Rarity.uncommon);
    expect(a.items.where((i) => i.kind == 'sword').single, up);
    expect(a.worn(Slot.weapon), up);
    // Different rarities don't merge.
    final common = a.add('sword', Rarity.common);
    expect(a.mergeInto(common, up), isNull);
    // And the bag survives a save.
    final back = Armory.fromJson(a.toJson());
    expect(back.items.length, a.items.length);
    expect(back.worn(Slot.weapon)?.rarity, Rarity.uncommon);
  });

  test('gear makes the hero stronger at the start of a run', () {
    final bare = Hero.start(5, 'knight');
    final geared = Hero.start(5, 'knight', kit(Rarity.epic));
    expect(geared.atk, greaterThan(bare.atk));
    expect(geared.max, greaterThan(bare.max));
    expect(geared.def, greaterThan(bare.def));
    expect(geared.specialCost, lessThan(bare.specialCost));
  });

  test('drops: more for long runs and clears, rarer in later worlds and tiers', () {
    double avgRarity(int chapter, int tier) {
      final rng = seededRng(chapter * 7 + tier);
      var sum = 0, n = 0;
      for (var i = 0; i < 400; i++) {
        for (final d in rollDrops(rng, chapter: chapter, tierIndex: tier, days: 30, cleared: true)) {
          sum += d.$2.index;
          n++;
        }
      }
      return sum / n;
    }

    expect(rollDrops(seededRng(1), chapter: 1, tierIndex: 0, days: 3, cleared: false).length, 1);
    expect(rollDrops(seededRng(1), chapter: 1, tierIndex: 0, days: 30, cleared: true).length, 4);
    expect(avgRarity(10, 0), greaterThan(avgRarity(1, 0)));
    expect(avgRarity(5, Tier.nightmare.dropBoost), greaterThan(avgRarity(5, 0)));
  });

  test('clearing opens the next world, keeps the loot; beating all opens Nightmare', () async {
    final store = MemoryRunStore();
    final c = RunController.start(seed: 3, store: store, save: {'version': 1}, heroClass: 'knight');
    var guard = 0;
    while (!c.finished && guard++ < 5000) {
      c.tick(1.0);
      c.rep();
    }
    final doc = (await store.load())!;
    expect(Armory.fromJson(doc['gear']).items, isNotEmpty);
    // The bestiary remembers who was met, by picture id.
    expect((doc['seen'] as List).cast<String>(), contains(chapters[0].foes.first.img));
    if (c.cleared) {
      expect(doc['unlocked'], 2);
      expect(RunController.tierOpen(doc, chapters[0], Tier.nightmare), isFalse);
    }
    // Nightmare opens everywhere once every world is beaten on Normal.
    final done = {
      'cleared': [for (final ch in chapters) ch.id]
    };
    expect(RunController.tierOpen(done, chapters[3], Tier.nightmare), isTrue);
    expect(
        RunController.gameCleared({
          'cleared': [for (final ch in chapters.skip(1)) ch.id]
        }),
        isFalse);
  });

  test('every creature, hero, background and gear piece has its picture', () {
    final missing = <String>[];
    void need(String f) {
      if (!File('assets/art/$f.webp').existsSync()) missing.add(f);
    }

    for (final ch in chapters) {
      for (final f in [...ch.foes, ch.boss]) {
        need(f.img);
      }
      need(ch.far);
      need(ch.near);
    }
    for (final c in heroClasses) {
      need(c.sprite);
    }
    for (final k in gearKinds) {
      need(k.img);
    }
    for (final l in loot) {
      need(l.img);
    }
    need('pet_pip');
    expect(missing, isEmpty);
  });

  test('every creature has an ability, and each one does its job', () {
    final all = chapters.expand((c) => [...c.foes, c.boss]).toList();
    expect(all.where((f) => f.ability == FoeAbility.none), isEmpty);
    expect(all.map((f) => f.ability).toSet().length, FoeAbility.values.length - 1);

    Battle fight(FoeAbility a) {
      final kind = all.firstWhere((f) => f.ability == a);
      final ch = chapters.firstWhere((c) => c.foes.contains(kind) || c.boss == kind);
      final tag = ch.boss == kind ? 'boss' : '${ch.foes.indexOf(kind)}';
      return Battle(Hero.start(ch.startLevel, 'knight', GearBonus.none), foeFor(tag, ch), () => 0.5);
    }

    // Plays out the foe's attacks up to its first ability turn.
    List<BattleEvent> toAbility(Battle b) {
      final out = <BattleEvent>[];
      while (b.attacks < abilityEvery && !b.over) {
        out.addAll(b.advance(0.05));
        if (b.windup) b.windupLeft = 0;
      }
      return out;
    }

    final regen = fight(FoeAbility.regen);
    regen.st.hp = regen.foe.hp ~/ 2;
    expect(toAbility(regen).whereType<FoeAbilityEvent>().single.amount, greaterThan(0));
    expect(regen.st.hp, greaterThan(regen.foe.hp ~/ 2));

    final stone = fight(FoeAbility.stoneSkin);
    toAbility(stone);
    expect(stone.st.shield, 3);
    final full = stone.hero.atk;
    expect((stone.rep().single as StrikeEvent).blows.single.dmg, lessThan(full));

    final hex = fight(FoeAbility.hex)..charge = 6;
    toAbility(hex);
    expect(hex.charge, 3);

    final venom = fight(FoeAbility.venom);
    toAbility(venom);
    final hp = venom.hero.hp;
    final ticks = <BattleEvent>[];
    for (var i = 0; i < 20; i++) {
      ticks.addAll(venom.advance(0.1));
    }
    expect(ticks.whereType<FoeAbilityEvent>().where((e) => e.tick), isNotEmpty);
    expect(venom.hero.hp, lessThan(hp));

    final drain = fight(FoeAbility.drain);
    drain.st.hp = drain.foe.hp ~/ 2;
    final hit = toAbility(drain).whereType<FoeHitEvent>().first;
    expect(hit.drained, greaterThan(0));

    final frenzy = fight(FoeAbility.frenzy);
    final calm = frenzy.pace;
    frenzy.st.hp = frenzy.foe.hp ~/ 3;
    expect(frenzy.pace, lessThan(calm));

    final dodge = fight(FoeAbility.evasive);
    final b2 = Battle(dodge.hero, dodge.foe, () => 0.01);
    expect((b2.rep().single as StrikeEvent).blows.single.miss, isTrue);
  });
}
