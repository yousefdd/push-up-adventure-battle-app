// Gear kept between runs: six slots, fourteen kinds, six rarities.
// Two identical pieces (same kind, same rarity) merge into one of the next
// rarity, the way the original's equipment fusing works.

import 'dart:math' as math;

import '../../i18n/i18n.dart';

typedef GearRng = double Function();

enum Rarity {
  common('Common', 1.0),
  uncommon('Uncommon', 1.6),
  rare('Rare', 2.5),
  epic('Epic', 4.0),
  legendary('Legendary', 6.5),
  mythic('Mythic', 10.0);

  const Rarity(this.label, this.mult);
  final String label;

  /// Scales the slot's base stats.
  final double mult;

  Rarity? get next => index + 1 < Rarity.values.length ? Rarity.values[index + 1] : null;
}

enum Slot { weapon, armor, helmet, boots, ring, amulet }

class GearKind {
  const GearKind(this.id, this.slot, this.name);
  final String id, name;
  final Slot slot;

  /// Picture in assets/art.
  String get img => 'gear_$id';
}

const gearKinds = [
  GearKind('sword', Slot.weapon, 'Amethyst Blade'),
  GearKind('axe', Slot.weapon, 'Bloodrune Axe'),
  GearKind('bow', Slot.weapon, 'Jade Blade'),
  GearKind('staff', Slot.weapon, 'Frostrune Axe'),
  GearKind('plate', Slot.armor, 'Dragon Aegis'),
  GearKind('robe', Slot.armor, 'Silver Aegis'),
  GearKind('helm', Slot.helmet, 'Winged Helm'),
  GearKind('hood', Slot.helmet, 'Gilded Helm'),
  GearKind('greaves', Slot.boots, 'Shadow Boots'),
  GearKind('sandals', Slot.boots, 'Ember Boots'),
  GearKind('ruby', Slot.ring, 'Ruby Ring'),
  GearKind('sapphire', Slot.ring, 'Sapphire Ring'),
  GearKind('fang', Slot.amulet, 'Sun Charm'),
  GearKind('star', Slot.amulet, 'Star Amulet'),
];

GearKind gearKind(String id) => gearKinds.firstWhere((k) => k.id == id);

/// What one piece (or a whole loadout) adds to a hero.
class GearBonus {
  const GearBonus({
    this.atk = 0,
    this.hp = 0,
    this.def = 0,
    this.atkPct = 0,
    this.hpPct = 0,
    this.crit = 0,
    this.charge = 0,
    this.winHeal = 0,
  });
  final int atk, hp, def;

  /// Percent of the hero's own attack and max HP, so gear matters as much in
  /// the last world as in the first.
  final double atkPct, hpPct;

  /// Extra crit chance (0..1).
  final double crit;

  /// Fewer strikes needed to charge the special.
  final int charge;

  /// Share of max HP healed after each win.
  final double winHeal;

  GearBonus operator +(GearBonus o) => GearBonus(
        atk: atk + o.atk,
        hp: hp + o.hp,
        def: def + o.def,
        atkPct: atkPct + o.atkPct,
        hpPct: hpPct + o.hpPct,
        crit: crit + o.crit,
        charge: charge + o.charge,
        winHeal: winHeal + o.winHeal,
      );

  static const none = GearBonus();

  /// One line per stat that is not zero, for the item card.
  List<String> get lines => [
        if (atk > 0) '+$atk ${tr('ATK')}',
        if (atkPct > 0) '+${(atkPct * 100).round()}% ${tr('ATK')}',
        if (hp > 0) '+$hp ${tr('max HP')}',
        if (hpPct > 0) '+${(hpPct * 100).round()}% ${tr('max HP')}',
        if (def > 0) '+$def ${tr('DEF')}',
        if (crit > 0) '+${(crit * 100).round()}% ${tr('crit')}',
        if (charge > 0) tr('Special −{n}', {'n': charge}),
        if (winHeal > 0) tr('Heal {n}% per win', {'n': (winHeal * 100).round()}),
      ];
}

class GearItem {
  GearItem(this.id, this.kind, this.rarity);
  final int id;
  final String kind;
  final Rarity rarity;

  GearKind get type => gearKind(kind);
  Slot get slot => type.slot;

  /// "Rare Ruby Ring"; in Arabic the rarity follows the name.
  String get name => I18n.isAr ? '${tr(type.name)} ${tr(rarity.label)}' : '${rarity.label} ${type.name}';

  GearBonus get bonus {
    final m = rarity.mult;
    return switch (slot) {
      Slot.weapon => GearBonus(atkPct: 0.06 * m),
      Slot.armor => GearBonus(hpPct: 0.08 * m),
      Slot.helmet => GearBonus(hpPct: 0.04 * m, def: (0.5 * m).round()),
      Slot.boots => GearBonus(def: math.max(1, m.round())),
      Slot.ring => GearBonus(crit: math.min(0.25, 0.02 * m)),
      Slot.amulet => GearBonus(charge: math.min(4, rarity.index), winHeal: 0.02 * m),
    };
  }

  /// Same kind and rarity: these two can merge.
  bool twin(GearItem o) => o.kind == kind && o.rarity == rarity;

  Map<String, dynamic> toJson() => {'id': id, 'k': kind, 'r': rarity.index};
  factory GearItem.fromJson(Map<String, dynamic> j) =>
      GearItem(j['id'] as int, j['k'] as String, Rarity.values[j['r'] as int]);
}

/// The player's gear: everything owned, and what is worn in each slot.
class Armory {
  Armory({List<GearItem>? items, Map<Slot, int>? equipped, this.nextId = 1})
      : items = items ?? [],
        equipped = equipped ?? {};

  final List<GearItem> items;
  final Map<Slot, int> equipped;
  int nextId;

  GearItem? worn(Slot s) {
    final id = equipped[s];
    if (id == null) return null;
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  bool isWorn(GearItem i) => equipped[i.slot] == i.id;

  GearBonus get bonus => Slot.values.map(worn).whereType<GearItem>().fold(GearBonus.none, (a, i) => a + i.bonus);

  GearItem add(String kind, Rarity r) {
    final item = GearItem(nextId++, kind, r);
    items.add(item);
    // A free slot is filled straight away.
    equipped.putIfAbsent(item.slot, () => item.id);
    return item;
  }

  void equip(GearItem i) => equipped[i.slot] = i.id;
  void unequip(Slot s) => equipped.remove(s);

  /// Items identical to [i] (including it), worn ones last so they are kept.
  List<GearItem> twins(GearItem i) =>
      items.where(i.twin).toList()..sort((a, b) => (isWorn(a) ? 1 : 0).compareTo(isWorn(b) ? 1 : 0));

  /// Two identical pieces (same kind, same rarity) make one of the next.
  static const mergeCost = 2;

  bool canMerge(GearItem i) => i.rarity.next != null && twins(i).length >= mergeCost;

  /// The player drops [dragged] onto [target]: if they are two identical
  /// pieces, both become one piece of the next rarity, worn if either was
  /// (or if its slot is empty). Returns the new piece, or null if they don't
  /// merge. Merging only ever happens this way, never on its own.
  GearItem? mergeInto(GearItem dragged, GearItem target) {
    if (dragged.id == target.id || !dragged.twin(target) || target.rarity.next == null) return null;
    if (!items.contains(dragged) || !items.contains(target)) return null;
    final wasWorn = isWorn(dragged) || isWorn(target);
    for (final u in [dragged, target]) {
      items.remove(u);
      if (isWorn(u)) equipped.remove(u.slot);
    }
    final up = GearItem(nextId++, target.kind, target.rarity.next!);
    items.add(up);
    if (wasWorn || !equipped.containsKey(up.slot)) equip(up);
    return up;
  }

  /// Puts on the strongest piece for every slot (by rarity).
  void equipBest() {
    for (final s in Slot.values) {
      final pick = items.where((i) => i.slot == s).toList()..sort((a, b) => b.rarity.index.compareTo(a.rarity.index));
      if (pick.isNotEmpty) equip(pick.first);
    }
  }

  Map<String, dynamic> toJson() => {
        'items': [for (final i in items) i.toJson()],
        'equipped': {for (final e in equipped.entries) e.key.name: e.value},
        'next': nextId,
      };

  factory Armory.fromJson(Object? j) {
    if (j is! Map) return Armory();
    final items = [
      for (final i in (j['items'] as List? ?? const [])) GearItem.fromJson(Map<String, dynamic>.from(i as Map))
    ];
    final eq = <Slot, int>{};
    (j['equipped'] as Map? ?? const {}).forEach((k, v) => eq[Slot.values.byName(k as String)] = v as int);
    return Armory(items: items, equipped: eq, nextId: j['next'] as int? ?? items.length + 1);
  }
}

/// Gear earned by one run: more for longer runs, clears and harder tiers;
/// rarer the further and harder the world.
List<(String, Rarity)> rollDrops(GearRng rng,
    {required int chapter, required int tierIndex, required int days, required bool cleared}) {
  // Two pieces merge into one, so drops stay modest: a cleared 30-day run gives 4.
  final n = 1 + days ~/ 15 + (cleared ? 1 : 0) + tierIndex;
  final level = chapter - 1 + tierIndex * 4;
  const base = [60.0, 28.0, 9.0, 2.5, 0.45, 0.05];
  final w = [for (var i = 0; i < base.length; i++) base[i] * math.pow(1 + 0.3 * level, i)];
  final total = w.fold(0.0, (a, b) => a + b);
  return [
    for (var d = 0; d < n; d++)
      () {
        var r = rng() * total;
        var pick = 0;
        while (pick < w.length - 1 && r >= w[pick]) {
          r -= w[pick];
          pick++;
        }
        // A cleared run's first drop is at least Uncommon.
        if (cleared && d == 0 && pick == 0) pick = 1;
        return (gearKinds[(rng() * gearKinds.length).floor()].id, Rarity.values[pick]);
      }(),
  ];
}
