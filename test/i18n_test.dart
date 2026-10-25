import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/engine/exercise.dart';
import 'package:repraid/i18n/ar.dart';
import 'package:repraid/i18n/i18n.dart';
import 'package:repraid/i18n/world_ar.dart';
import 'package:repraid/modes/online/duel_math.dart';
import 'package:repraid/modes/rpg/adventure_rules.dart';
import 'package:repraid/online/ranked.dart';
import 'package:repraid/ui/store_screen.dart';

/// Every literal key passed to tr('...') anywhere in lib/.
Set<String> literalKeys() {
  final keys = <String>{};
  final lit = RegExp(r"\btr\(\s*'((?:[^'\\]|\\.)*)'");
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    for (final m in lit.allMatches(f.readAsStringSync())) {
      keys.add(m.group(1)!.replaceAll(r"\'", "'"));
    }
  }
  return keys;
}

/// The data the screens translate where they show it.
Set<String> dataKeys() => {
      for (final s in skills.values) ...[s.name, s.text],
      for (final s in stories) ...[s.text, s.effect.tag],
      for (final w in wheel) w.label,
      for (final c in choices) ...[c.text, c.a.label, c.a.effect.tag, c.b.label, c.b.effect.tag],
      for (final l in loot) l.name,
      for (final c in heroClasses) ...[c.name, c.perk, c.perkText, c.special, c.specialText],
      for (final t in Tier.values) t.label,
      for (final r in Rarity.values) r.label,
      for (final k in gearKinds) k.name,
      for (final p in ExerciseProfile.defaults.values) ...[p.label, p.blurb],
      ...taunts,
      for (final t in RankTier.values) t.label,
      for (final r in [...StoreScreen.rewards, ...StoreScreen.silverRewards]) ...[r.$2, r.$3],
    };

Set<String> slots(String s) => RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  test('every English string has Arabic, with the same {slots}', () {
    final missing = <String>[], badSlots = <String>[];
    for (final k in {...literalKeys(), ...dataKeys()}) {
      final a = ar[k] ?? worldAr[k];
      if (a == null) {
        missing.add(k);
      } else if (!slots(a).containsAll(slots(k))) {
        badSlots.add(k);
      }
    }
    expect(missing, isEmpty, reason: 'no Arabic for these');
    expect(badSlots, isEmpty, reason: 'Arabic drops a {slot}');
  });

  test('every world, foe, boss and line has Arabic', () {
    for (final ch in chapters) {
      for (final s in [
        ch.name,
        ch.blurb,
        for (final f in [...ch.foes, ch.boss]) ...[f.name, f.quote]
      ]) {
        expect(worldAr[s], isNotNull, reason: s);
      }
    }
  });

  test('tr fills slots, follows the language, and keeps elite stars', () async {
    expect(tr('Day {n}', {'n': 4}), 'Day 4');
    I18n.lang.value = Lang.ar;
    expect(tr('Day {n}', {'n': 4}), 'اليوم 4');
    expect(trName('Moss Slime ★'), 'هلام الطحلب ★');
    expect(trChapter(4, 'Chapter IV'), 'الفصل الرابع');
    expect(tr('not a key'), 'not a key');
    I18n.lang.value = Lang.en;
    expect(trChapter(4, 'Chapter IV'), 'Chapter IV');
  });

  test('day counts read naturally in both languages', () {
    I18n.lang.value = Lang.en;
    expect(trDays(1), '1 day');
    expect(trDays(39), '39 days');
    I18n.lang.value = Lang.ar;
    expect(trDays(1), 'يوم واحد');
    expect(trDays(2), 'يومان');
    expect(trDays(7), '7 أيام');
    expect(trDays(30), '30 يومًا');
    expect(trDays(100), '100 يوم');
    I18n.lang.value = Lang.en;
  });
}
