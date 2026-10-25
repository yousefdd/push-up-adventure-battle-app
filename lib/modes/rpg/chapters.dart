// Worlds, difficulty tiers and hero classes.
//
// Every character is painted art built by tool/art (roster.py, build.py)
// from the user's reference cut-outs; the world list itself is
// generated into world_data.dart so names, pictures and numbers never drift.

part 'world_data.dart';

/// Every creature type fights with one trick of its own, on top of its plain
/// attacks. Active ones fire on every fourth attack; passive ones always hold.
enum FoeAbility {
  none('', ''),
  regen('Regrowth', 'Every 4th attack it heals 10% of its HP instead'),
  stoneSkin('Stone Skin', 'Every 4th attack it hardens: your next 3 hits do half damage'),
  frenzy('Frenzy', 'Below half HP it attacks a third faster'),
  drain('Life Drain', 'Its hits heal it for half the damage'),
  venom('Venom', 'Every 4th attack poisons you: 3% of max HP a second for 4 seconds'),
  breath('Fire Breath', 'Every 4th attack is a breath: 1.6× damage, armour does not help'),
  hex('Hex', 'Every 4th attack drains half your special meter'),
  evasive('Evasive', 'Dodges 15% of your hits');

  const FoeAbility(this.label, this.text);
  final String label, text;

  /// Fires on its own turn (every [abilityEvery] attacks), not all the time.
  bool get active => this == regen || this == stoneSkin || this == venom || this == breath || this == hex;
}

/// Attacks between a foe's ability turns.
const abilityEvery = 4;

class FoeKind {
  const FoeKind(this.name, this.img, this.m, [this.quote = '', this.ability = FoeAbility.none, this.front = false]);
  final String name;
  final FoeAbility ability;

  /// Drawn facing the viewer; turned a little toward the hero in a fight.
  final bool front;

  /// Picture in assets/art (no extension).
  final String img;

  /// Toughness: HP and attack scale with it.
  final double m;
  final String quote;
}

class ChapterDef {
  const ChapterDef({
    required this.number,
    required this.id,
    required this.roman,
    required this.name,
    required this.blurb,
    required this.foes,
    required this.boss,
    required this.startLevel,
    required this.ground,
  });

  final int number;
  final String id, roman, name, blurb;

  /// The five road foes, weakest first; elites ("+") are these at 1.35×.
  final List<FoeKind> foes;
  final FoeKind boss;

  /// The hero's level at day 0, before gear. Tuned by simulation so Normal
  /// clears about three runs in four with no gear (test/chapters_test.dart).
  final int startLevel;

  /// The world's ground colour (ARGB); the road in a fight is painted from it.
  final int ground;

  /// Two-layer pixel background: the far sky and the near ground.
  String get far => 'bg_${id}_far';
  String get near => 'bg_${id}_near';
}

ChapterDef chapterById(String id) => chapters.firstWhere((c) => c.id == id, orElse: () => chapters.first);

/// How hard a world is played. Normal is the game; Nightmare opens on every
/// world once the last one is cleared, hits far harder and drops far better gear.
enum Tier {
  normal('Normal', 1.0),
  nightmare('Nightmare', 2.0);

  const Tier(this.label, this.mult);
  final String label;

  /// Foe HP and attack multiplier.
  final double mult;

  int get stars => this == Tier.normal ? 1 : 3;

  /// How much better the drops are (see rollDrops).
  int get dropBoost => this == Tier.normal ? 0 : 3;

  /// Nightmare elites wind up heavy blows too, not only bosses.
  bool get elitesWindUp => this != Tier.normal;

  static Tier byName(Object? n) => Tier.values.firstWhere((t) => t.name == n, orElse: () => Tier.normal);
}

/// A playable class: its perk for the whole run, and its special attack,
/// which charges one step per strike and fires on the next pushup when full.
class HeroClass {
  const HeroClass(
    this.id,
    this.name,
    this.perk,
    this.perkText, {
    required this.special,
    required this.specialText,
    this.critChance = 0,
    this.critMult = 2,
    this.power = 1,
    this.xp = 1,
    this.lootLuck = 0,
  });

  final String id, name, perk, perkText, special, specialText;

  /// Base chance of a double hit, before Keen Eye and rings.
  final double critChance;

  /// Damage multiplier of a crit.
  final double critMult;

  /// Start-of-run attack and max HP multiplier.
  final double power;

  /// EXP multiplier.
  final double xp;

  /// Pushes chest rolls toward rarer loot (0..1).
  final double lootLuck;

  String get sprite => 'hero_$id';
}

const heroClasses = [
  HeroClass('knight', 'Knight', 'Bulwark', '+5% attack and max HP',
      power: 1.05,
      special: 'Shield Bash',
      specialText: '2.5× hit, stuns: the foe\'s clock and any heavy blow are reset'),
  HeroClass('ranger', 'Ranger', 'Keen Eye', '+6% crit chance',
      critChance: 0.06, special: 'Arrow Rain', specialText: 'Five arrows at 0.7× each, every one can crit'),
  HeroClass('monk', 'Monk', 'Inner Calm', '+3% EXP · better chest loot',
      xp: 1.03, lootLuck: 0.25, special: 'Palm of Dawn', specialText: '3× hit and heal 15% of max HP'),
  HeroClass('berserker', 'Berserker', 'Blood Rage', '+3% crit · crits hit 2.5×',
      critChance: 0.03, critMult: 2.5, special: 'Blood Frenzy', specialText: 'Three 1.4× hits; costs 5% of current HP'),
];

HeroClass heroClassById(String? id) => heroClasses.firstWhere((c) => c.id == id, orElse: () => heroClasses.first);
