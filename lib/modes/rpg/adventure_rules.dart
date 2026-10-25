// RepRaid adventure rules: one pushup = one day on the road, and in a fight one
// pushup = one strike (or a special, when charged). Started as a port of
// preview/adventure.js; balance is kept by simulation (test/chapters_test).
//
// Pure Dart, no Flutter: all dice go through an injected [Rng] so tests and
// resumed runs are deterministic. Characters, events, skills, gear, text and
// numbers are RepRaid's own.

import 'dart:math' as math;

import 'chapters.dart';
import 'gear.dart';

export 'chapters.dart';
export 'gear.dart';

/// A source of uniform doubles in [0, 1).
typedef Rng = double Function();

Rng seededRng(int seed) {
  final r = math.Random(seed);
  return r.nextDouble;
}

const int baseHp = 120, baseAtk = 14, baseDef = 2;
const int foeHp = 85, foeAtk = 21;
const double bossHpScale = 4.0, bossAtkScale = 1.5;

/// Strikes a world's first foe takes from a hero of that world's level
/// (mid-run), and the same for its boss. Foe HP follows the hero's attack,
/// so nothing dies in one hit, however deep the world.
const double foeHits = 6.0, bossHits = 55.0;

/// The hero's attack around the middle of a run in [ch], with no gear.
double atkRef(ChapterDef ch) => (baseAtk + 3 * (ch.startLevel + 1)).toDouble();
const int xpPerLevel = 60;

/// Seconds between a foe's own attacks.
const double paceNormal = 2.6, paceElite = 2.3, paceBoss = 1.8;

/// Chapter I's road foes (kept for the balance tests).
final foes = chapters.first.foes;

/// Every chapter's road: 30 days, the chapter's boss on the last one.
const chapterOne = [
  'story',
  'foe:0',
  'skill',
  'story',
  'foe:1',
  'wheel',
  'skill',
  'foe:2',
  'choice',
  'chest',
  'foe:3',
  'skill',
  'story',
  'foe:4',
  'wheel',
  'choice',
  'skill',
  'foe:0+',
  'chest',
  'foe:1+',
  'skill',
  'story',
  'foe:2+',
  'wheel',
  'choice',
  'foe:3+',
  'skill',
  'foe:4+',
  'choice',
  'boss',
];

class Hero {
  Hero(
      {required this.lv,
      required this.max,
      required this.atk,
      required this.def,
      this.cls = 'ranger',
      this.gearCrit = 0,
      this.chargeCut = 0,
      this.winHeal = 0})
      : hp = max;

  /// A fresh hero at [level], with the [cls] perk and worn [gear] applied.
  factory Hero.start([int level = 1, String? cls, GearBonus gear = GearBonus.none]) {
    final c = heroClassById(cls);
    return Hero(
      lv: level,
      max: ((baseHp + (level - 1) * 15) * c.power * (1 + gear.hpPct)).round() + gear.hp,
      atk: ((baseAtk + (level - 1) * 3) * c.power * (1 + gear.atkPct)).round() + gear.atk,
      def: baseDef + gear.def,
      cls: c.id,
      gearCrit: gear.crit,
      chargeCut: gear.charge,
      winHeal: gear.winHeal,
    );
  }

  /// From rings: extra crit chance.
  final double gearCrit;

  /// From amulets: fewer strikes to charge the special, and a heal per win.
  final int chargeCut;
  final double winHeal;

  /// Strikes needed to charge the special.
  int get specialCost => math.max(4, 8 - chargeCut);

  /// Class id (see [heroClasses]).
  final String cls;
  HeroClass get heroClass => heroClassById(cls);

  int lv, xp = 0, hp, max, atk, def;

  /// Skill key -> how many times it was picked (stacks).
  final Map<String, int> sk = {};

  int stacks(String key) => sk[key] ?? 0;

  Map<String, dynamic> toJson() => {
        'lv': lv,
        'xp': xp,
        'hp': hp,
        'max': max,
        'atk': atk,
        'def': def,
        'sk': sk,
        'cls': cls,
        'gc': gearCrit,
        'cc': chargeCut,
        'wh': winHeal
      };

  factory Hero.fromJson(Map<String, dynamic> j) {
    final h = Hero(
      lv: j['lv'] as int,
      max: j['max'] as int,
      atk: j['atk'] as int,
      def: j['def'] as int,
      cls: j['cls'] as String? ?? 'ranger',
      gearCrit: (j['gc'] as num?)?.toDouble() ?? 0,
      chargeCut: j['cc'] as int? ?? 0,
      winHeal: (j['wh'] as num?)?.toDouble() ?? 0,
    )
      ..hp = j['hp'] as int
      ..xp = j['xp'] as int;
    (j['sk'] as Map).forEach((k, v) => h.sk[k as String] = v as int);
    return h;
  }
}

void grow(Hero h, String stat, double pct) {
  if (stat == 'hp') {
    final add = (h.max * pct).round();
    h.max += add;
    h.hp += add;
  } else {
    h.atk += math.max(1, (h.atk * pct).round());
  }
}

int heal(Hero h, double pct) => healBy(h, (h.max * pct).round());

int healBy(Hero h, int n) {
  final before = h.hp;
  h.hp = math.min(h.max, h.hp + n);
  return h.hp - before;
}

class Skill {
  const Skill(this.key, this.name, this.text, [this.rarity = Rarity.common]);
  final String key, name, text;

  /// Shown as the tag on the card; plain stat skills are common, skills
  /// that change how a fight plays out are rarer.
  final Rarity rarity;
}

const skills = {
  'edge': Skill('edge', 'Ember Edge', '+20% attack'),
  'hide': Skill('hide', 'Iron Hide', '+30% max HP, healed now'),
  'guard': Skill('guard', 'Stone Guard', '+4 defence'),
  'eye': Skill('eye', 'Keen Eye', '+15% chance to deal double damage', Rarity.rare),
  'twin': Skill('twin', 'Twin Strike', '+25% chance to strike twice', Rarity.rare),
  'leech': Skill('leech', 'Leech Fang', 'Heal 15% of the damage you deal', Rarity.rare),
  'thorns': Skill('thorns', 'Thornmail', 'Attackers take 30% of the damage they deal', Rarity.rare),
  'spark': Skill('spark', 'First Spark', 'Your first hit each fight deals 3×', Rarity.epic),
  'wind': Skill('wind', 'Second Wind', 'Heal 20% after every win', Rarity.epic),
};

void applySkill(Hero h, String key) {
  h.sk[key] = h.stacks(key) + 1;
  if (key == 'edge') grow(h, 'atk', 0.20);
  if (key == 'hide') grow(h, 'hp', 0.30);
  if (key == 'guard') h.def += 4;
}

/// Three different skills, uniformly shuffled.
List<String> skillOffer(Rng rng) {
  final keys = skills.keys.toList();
  for (var i = keys.length - 1; i > 0; i--) {
    final j = (rng() * (i + 1)).floor();
    final t = keys[i];
    keys[i] = keys[j];
    keys[j] = t;
  }
  return keys.take(3).toList();
}

class Effect {
  const Effect(this.tag, this.apply);
  final String tag;
  final void Function(Hero) apply;
}

class Story {
  const Story(this.text, this.effect);
  final String text;
  final Effect effect;
}

final stories = [
  Story('A meadow sprite hums as you pass. You feel lighter on your feet.',
      Effect('Max HP +6%', (h) => grow(h, 'hp', 0.06))),
  Story('You share your bread with a lost traveller. They press a whetstone into your hand.',
      Effect('ATK +4', (h) => h.atk += 4)),
  Story('Pip sniffs out a patch of glowberries.', Effect('Heal 20%', (h) => heal(h, 0.2))),
  Story('An old shrine hums softly. Its stones settle into your boots.', Effect('DEF +2', (h) => h.def += 2)),
  Story(
      'You trip over a root. Pip jiggles, trying not to laugh.', Effect('HP −8', (h) => h.hp = math.max(1, h.hp - 8))),
  Story('A farmer shows you how to swing from the hips.', Effect('ATK +5%', (h) => grow(h, 'atk', 0.05))),
];

class WheelSlice {
  const WheelSlice(this.label, {this.apply, this.xp = 0, this.skill = false});
  final String label;
  final void Function(Hero)? apply;
  final int xp;
  final bool skill;
}

/// Lucky wheel, clockwise.
final wheel = [
  WheelSlice('Max HP +10%', apply: (h) => grow(h, 'hp', 0.10)),
  const WheelSlice('Learn a skill', skill: true),
  const WheelSlice('EXP +30', xp: 30),
  WheelSlice('Heal 30%', apply: (h) => heal(h, 0.3)),
  WheelSlice('ATK +10%', apply: (h) => grow(h, 'atk', 0.10)),
  const WheelSlice('EXP +60', xp: 60),
];

class ChoiceOption {
  const ChoiceOption(this.label, this.effect);
  final String label;
  final Effect effect;
}

class Choice {
  const Choice(this.text, this.a, this.b);
  final String text;
  final ChoiceOption a, b;
}

final choices = [
  Choice(
      'You reach a campfire at dusk. Rest, or drill until dark?',
      ChoiceOption('Rest', Effect('Heal 30%', (h) => heal(h, 0.3))),
      ChoiceOption('Train', Effect('ATK +12%', (h) => grow(h, 'atk', 0.12)))),
  Choice(
      'A hedge witch offers a charm, or a bowl of hot stew.',
      ChoiceOption('Stew', Effect('Heal 40%', (h) => heal(h, 0.4))),
      ChoiceOption('Charm', Effect('DEF +3', (h) => h.def += 3))),
];

class Loot {
  const Loot(this.rarity, this.img, this.name, this.stat, this.v);
  final Rarity rarity;
  final String img, name, stat;
  final int v;
}

const loot = [
  Loot(Rarity.common, 'gear_sandals', 'Ember Boots', 'hp', 15),
  Loot(Rarity.common, 'gear_fang', 'Sun Charm', 'atk', 3),
  Loot(Rarity.uncommon, 'gear_axe', 'Bloodrune Axe', 'atk', 5),
  Loot(Rarity.uncommon, 'gear_hood', 'Gilded Helm', 'def', 2),
  Loot(Rarity.rare, 'gear_plate', 'Dragon Aegis', 'hp', 40),
  Loot(Rarity.rare, 'gear_sword', 'Amethyst Blade', 'atk', 8),
  Loot(Rarity.epic, 'gear_greaves', 'Shadow Boots', 'def', 5),
  Loot(Rarity.epic, 'gear_star', 'Star Amulet', 'atk', 12),
];

Loot rollLoot(Rng rng, {double luck = 0}) {
  // Luck pulls the roll toward the rare end.
  final r = 1 - (1 - rng()) * (1 - luck);
  final tier = r < 0.5
      ? 0
      : r < 0.8
          ? 2
          : r < 0.95
              ? 4
              : 6;
  final pick = loot[tier + (rng() < 0.5 ? 0 : 1)];
  rng(); // the old look roll: kept so seeded runs and the balance tests stay the same
  return pick;
}

void equip(Hero h, Loot item) {
  switch (item.stat) {
    case 'hp':
      h.max += item.v;
      h.hp += item.v;
    case 'atk':
      h.atk += item.v;
    default:
      h.def += item.v;
  }
}

/// Adds XP; returns how many levels were gained.
int gainXp(Hero h, int xp) {
  h.xp += (xp * h.heroClass.xp).round();
  var ups = 0;
  while (h.xp >= xpPerLevel) {
    h.xp -= xpPerLevel;
    h.lv++;
    ups++;
    h.max += 15;
    h.hp += 15;
    h.atk += 3;
  }
  return ups;
}

class Foe {
  const Foe(this.name, this.img, this.hp, this.atk,
      {this.elite = false,
      this.boss = false,
      this.quote = '',
      this.windsUp = false,
      this.ability = FoeAbility.none,
      this.front = false,
      int? xp})
      : xp = xp ?? hp ~/ 3;

  /// See [FoeKind.front].
  final bool front;

  /// Its creature type's own trick (see FoeAbility).
  final FoeAbility ability;

  /// Experience for beating it.
  final int xp;
  final String name, img, quote;

  /// Winds up a heavy blow every third attack; three quick pushups stop it.
  final bool windsUp;
  final int hp, atk;
  final bool elite, boss;
}

Foe foeFor(String tag, [ChapterDef? chapter, Tier tier = Tier.normal]) {
  final ch = chapter ?? chapters.first;
  final t = tier.mult;
  if (tag == 'boss') {
    final b = ch.boss;
    return Foe(b.name, b.img, (bossHits * atkRef(ch) * t).round(), (foeAtk * b.m * bossAtkScale * t).round(),
        boss: true,
        quote: b.quote,
        windsUp: true,
        ability: b.ability,
        front: b.front,
        xp: (foeHp * b.m * bossHpScale / 3).round());
  }
  final plus = tag.endsWith('+');
  final f = ch.foes[int.parse(tag.replaceAll('+', ''))];
  final m = f.m * (plus ? 1.35 : 1);
  final step = m / ch.foes.first.m;
  return Foe('${f.name}${plus ? ' ★' : ''}', f.img, (foeHits * atkRef(ch) * step * t).round(), (foeAtk * m * t).round(),
      elite: plus,
      quote: f.quote,
      windsUp: plus && tier.elitesWindUp,
      ability: f.ability,
      front: f.front,
      xp: (foeHp * m / 3).round());
}

/// A fight in progress: the foe's remaining HP and its attack clock.
class FightState {
  FightState(this.foe) : hp = foe.hp;
  final Foe foe;
  int hp;
  bool first = true;

  /// Hits left that Stone Skin halves.
  int shield = 0;

  /// Frenzy: below half HP the foe attacks a third faster.
  bool get frenzied => foe.ability == FoeAbility.frenzy && hp * 2 < foe.hp;

  double get pace =>
      (foe.boss
          ? paceBoss
          : foe.elite
              ? paceElite
              : paceNormal) *
      (frenzied ? 0.75 : 1);

  /// A blow of [d] against this foe: Evasive may dodge it, Stone Skin halves it.
  Blow take(int d, bool crit, Rng rng, {int Function(int)? onHit}) {
    if (foe.ability == FoeAbility.evasive && rng() < 0.15) return const Blow(0, false, 0, miss: true);
    if (shield > 0) {
      shield--;
      d = math.max(1, d ~/ 2);
    }
    hp = math.max(0, hp - d);
    return Blow(d, crit, onHit?.call(d) ?? 0);
  }
}

class Blow {
  const Blow(this.dmg, this.crit, this.heal, {this.miss = false});
  final int dmg, heal;
  final bool crit, miss;
}

/// One pushup: one strike, or two with Twin Strike.
List<Blow> heroStrike(Hero h, FightState st, Rng rng) {
  final hits = 1 + (h.stacks('twin') > 0 && rng() < 0.25 * h.stacks('twin') ? 1 : 0);
  final blows = <Blow>[];
  for (var i = 0; i < hits && st.hp > 0; i++) {
    var d = h.atk;
    final c = h.heroClass;
    final crit = rng() < c.critChance + h.gearCrit + 0.15 * h.stacks('eye');
    if (crit) d = (d * c.critMult).round();
    // Spark boosts the opening blow, but never past 60% of the foe: nothing falls to one hit.
    if (st.first && h.stacks('spark') > 0) {
      d = math.max(d, math.min(d * (1 + 2 * h.stacks('spark')), (st.foe.hp * 0.6).round()));
    }
    st.first = false;
    blows.add(st.take(d, crit, rng,
        onHit: (d) => h.stacks('leech') > 0 ? healBy(h, (d * 0.15 * h.stacks('leech')).round()) : 0));
  }
  return blows;
}

/// The foe's own attack, on its timer. Returns (damage taken, reflected).
(int, int) foeStrike(Hero h, FightState st) {
  final taken = math.max(1, st.foe.atk - h.def);
  h.hp = math.max(0, h.hp - taken);
  var reflect = 0;
  if (h.stacks('thorns') > 0) {
    reflect = (taken * 0.3 * h.stacks('thorns')).round();
    st.hp = math.max(0, st.hp - reflect);
  }
  return (taken, reflect);
}

/// After a win: XP, and any Second Wind or amulet heal.
(int, int) winFight(Hero h, FightState st) {
  final windHeal = heal(h, (h.stacks('wind') > 0 ? 0.2 : 0) + h.winHeal);
  return (st.foe.xp, windHeal);
}

// ----------------------------------------------------------------- battle

/// Seconds a heavy blow takes to land, and the pushups that stop it.
const double windupTime = 2.4;
const int windupBreak = 3;

/// The class special: blows plus what else it did.
class SpecialResult {
  const SpecialResult(this.blows, {this.healed = 0, this.selfHit = 0, this.stun = false});
  final List<Blow> blows;
  final int healed, selfHit;
  final bool stun;
}

SpecialResult heroSpecial(Hero h, FightState st, Rng rng) {
  final c = h.heroClass;
  Blow hit(double mult, {bool canCrit = false}) {
    var d = (h.atk * mult).round();
    final crit = canCrit && rng() < c.critChance + h.gearCrit + 0.15 * h.stacks('eye');
    if (crit) d = (d * c.critMult).round();
    return st.take(d, crit, rng);
  }

  switch (c.id) {
    case 'knight':
      return SpecialResult([hit(2.5)], stun: true);
    case 'ranger':
      return SpecialResult([for (var i = 0; i < 5 && st.hp > 0; i++) hit(0.7, canCrit: true)]);
    case 'monk':
      final b = hit(3.0);
      return SpecialResult([b], healed: heal(h, 0.15));
    default: // berserker
      final cost = (h.hp * 0.05).round();
      h.hp = math.max(1, h.hp - cost);
      return SpecialResult([for (var i = 0; i < 3 && st.hp > 0; i++) hit(1.4, canCrit: true)], selfHit: cost);
  }
}

sealed class BattleEvent {}

class StrikeEvent extends BattleEvent {
  StrikeEvent(this.blows);
  final List<Blow> blows;
}

class SpecialEvent extends BattleEvent {
  SpecialEvent(this.name, this.result);
  final String name;
  final SpecialResult result;
}

class FoeHitEvent extends BattleEvent {
  FoeHitEvent(this.dmg, this.reflect, {this.heavy = false, this.drained = 0});
  final int dmg, reflect;
  final bool heavy;

  /// HP the foe took back with Life Drain.
  final int drained;
}

/// The foe used its ability. [amount] is HP healed (Regrowth), hits
/// shielded (Stone Skin), charge drained (Hex) or damage dealt (Venom tick,
/// Fire Breath); [tick] marks a poison tick rather than the bite itself.
class FoeAbilityEvent extends BattleEvent {
  FoeAbilityEvent(this.ability, this.amount, {this.tick = false});
  final FoeAbility ability;
  final int amount;
  final bool tick;
}

class WindupEvent extends BattleEvent {}

class InterruptEvent extends BattleEvent {}

/// One fight, in time: the hero's pushups, the special meter, and the foe's
/// clock with its heavy blows. The screen and the balance tests both drive it.
class Battle {
  /// [charge] carries the special meter over from the last fight.
  Battle(this.hero, Foe foe, this.rng, {this.charge = 0}) : st = FightState(foe);

  final Hero hero;
  final FightState st;
  final Rng rng;

  /// Seconds into the foe's current attack.
  double clock = 0;
  int attacks = 0;

  /// A heavy blow is coming: seconds left, and pushups landed against it.
  bool windup = false;
  double windupLeft = 0;
  int windupHits = 0;

  /// Special meter, in strikes.
  int charge;

  /// Venom on the hero: seconds left, and time to the next tick.
  double poisonLeft = 0, poisonTick = 0;

  /// Frenzy is announced once.
  bool _frenzyShown = false;

  Foe get foe => st.foe;
  bool get over => st.hp <= 0 || hero.hp <= 0;
  bool get won => st.hp <= 0 && hero.hp > 0;
  bool get specialReady => charge >= hero.specialCost;
  double get pace => st.pace;

  /// 0..1 progress of the foe's next attack (or of the heavy blow).
  double get threat => windup ? 1 - windupLeft / windupTime : (clock / pace).clamp(0.0, 1.0);

  /// One pushup.
  List<BattleEvent> rep() {
    if (over) return const [];
    final out = <BattleEvent>[];
    if (specialReady) {
      charge = 0;
      final r = heroSpecial(hero, st, rng);
      out.add(SpecialEvent(hero.heroClass.special, r));
      if (r.stun) {
        clock = 0;
        if (windup) {
          windup = false;
          out.add(InterruptEvent());
        }
      }
    } else {
      charge++;
      out.add(StrikeEvent(heroStrike(hero, st, rng)));
    }
    if (windup) {
      windupHits++;
      if (windupHits >= windupBreak) {
        windup = false;
        clock = 0;
        out.add(InterruptEvent());
      }
    }
    return out;
  }

  /// Time passes; the foe attacks on its own clock.
  List<BattleEvent> advance(double dt) {
    if (over || dt <= 0) return const [];
    final out = <BattleEvent>[];
    if (poisonLeft > 0) {
      poisonLeft -= dt;
      poisonTick -= dt;
      if (poisonTick <= 0) {
        poisonTick += 1;
        final d = math.max(1, (hero.max * 0.03).round());
        hero.hp = math.max(0, hero.hp - d);
        out.add(FoeAbilityEvent(FoeAbility.venom, d, tick: true));
        if (over) return out;
      }
    }
    if (!_frenzyShown && st.frenzied) {
      _frenzyShown = true;
      out.add(FoeAbilityEvent(FoeAbility.frenzy, 0));
    }
    if (windup) {
      windupLeft -= dt;
      if (windupLeft <= 0) {
        windup = false;
        clock = 0;
        out.add(_foeHit(2.2, heavy: true));
      }
      return out;
    }
    clock += dt;
    if (clock >= pace) {
      clock -= pace;
      attacks++;
      if (foe.windsUp && attacks % 3 == 0) {
        windup = true;
        windupLeft = windupTime;
        windupHits = 0;
        out.add(WindupEvent());
      } else if (foe.ability.active && attacks % abilityEvery == 0) {
        out.addAll(_ability());
      } else {
        out.add(_foeHit(1));
      }
    }
    return out;
  }

  List<BattleEvent> _ability() {
    final a = foe.ability;
    switch (a) {
      case FoeAbility.regen:
        final before = st.hp;
        st.hp = math.min(foe.hp, st.hp + (foe.hp * 0.10).round());
        return [FoeAbilityEvent(a, st.hp - before)];
      case FoeAbility.stoneSkin:
        st.shield = 3;
        return [FoeAbilityEvent(a, 3)];
      case FoeAbility.venom:
        poisonLeft = 4;
        poisonTick = 1;
        return [FoeAbilityEvent(a, 0), _foeHit(1)];
      case FoeAbility.breath:
        final d = math.max(1, (foe.atk * 1.6).round());
        hero.hp = math.max(0, hero.hp - d);
        return [FoeAbilityEvent(a, d)];
      case FoeAbility.hex:
        final lost = charge - charge ~/ 2;
        charge ~/= 2;
        return [FoeAbilityEvent(a, lost), _foeHit(1)];
      default:
        return [_foeHit(1)];
    }
  }

  FoeHitEvent _foeHit(double mult, {bool heavy = false}) {
    final taken = math.max(1, (st.foe.atk * mult).round() - hero.def);
    hero.hp = math.max(0, hero.hp - taken);
    var reflect = 0;
    if (hero.stacks('thorns') > 0) {
      reflect = (taken * 0.3 * hero.stacks('thorns')).round();
      st.hp = math.max(0, st.hp - reflect);
    }
    var drained = 0;
    if (foe.ability == FoeAbility.drain && st.hp > 0) {
      final before = st.hp;
      st.hp = math.min(foe.hp, st.hp + taken ~/ 2);
      drained = st.hp - before;
    }
    return FoeHitEvent(taken, reflect, heavy: heavy, drained: drained);
  }
}

/// Plays one fight with a pushup every [gap] seconds; for the simulations.
bool simulateFight(Battle b, double Function() gap) {
  var nextRep = gap();
  var t = 0.0;
  const step = 0.05;
  while (!b.over) {
    if (nextRep <= step) {
      b.advance(nextRep);
      b.rep();
      nextRep = gap();
    } else {
      b.advance(step);
      nextRep -= step;
    }
    t += step;
    if (t > 3600) break;
  }
  return b.won;
}
