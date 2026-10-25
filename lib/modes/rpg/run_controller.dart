// The adventure run as a state machine with exactly one input: rep().
//
// Time only moves through tick(dt), driven by a Ticker on screen and by a
// plain loop in tests, so foe attacks, the glowing-card cycle and the auto
// closes are deterministic and pause when the app is backgrounded. Every
// state says what the next pushup does (see [RunMode] and [actionLabel]).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'adventure_rules.dart';
import '../../i18n/i18n.dart';

enum RunMode { walk, fight, pick, spin, card, busy, over }

/// Seconds, matching the preview: the glow moves every 1.8 s, a pick is made
/// for you after 12 s, info cards close after 2.6 s.
const double pickCycle = 1.8, pickAuto = 12, cardAuto = 2.6;
const double walkTime = 0.6, wheelSpin = 2.5, bossIntro = 0.9, fightIntro = 0.6;

/// A lucky wheel waits for a pushup to spin it, and spins itself after this.
const double spinAuto = 5;

/// A seeded RNG that counts its draws so a saved run resumes on the same dice.
class RunRng {
  RunRng(this.seed, [int skip = 0]) : _r = math.Random(seed) {
    for (var i = 0; i < skip; i++) {
      _r.nextDouble();
    }
    draws = skip;
  }
  final int seed;
  final math.Random _r;
  int draws = 0;
  double call() {
    draws++;
    return _r.nextDouble();
  }
}

enum LogKind { story, fight, win }

class LogEntry {
  const LogEntry(this.head, this.body, {this.tag, this.kind = LogKind.story});
  final String head;

  /// Plain text; a name wrapped in *stars* is drawn in the keyword colour.
  final String body;
  final String? tag;
  final LogKind kind;

  Map<String, dynamic> toJson() => {'h': head, 'b': body, 't': tag, 'k': kind.index};
  factory LogEntry.fromJson(Map<String, dynamic> j) =>
      LogEntry(j['h'] as String, j['b'] as String, tag: j['t'] as String?, kind: LogKind.values[j['k'] as int]);
}

class PickOption {
  const PickOption(this.title, this.text, {this.skill});
  final String title, text;
  final String? skill;
}

enum OverlayKind { pick, choice, wheel, chestClosed, chest, clear, defeat }

/// What the modal shows. Never covers the action button.
class RunOverlay {
  RunOverlay.pick(this.title, this.subtitle, this.options, {this.kind = OverlayKind.pick})
      : wheelIndex = null,
        loot = null,
        survived = null,
        best = null,
        drops = const [];

  /// A chest standing on the road, waiting to be picked up.
  RunOverlay.chestClosed()
      : kind = OverlayKind.chestClosed,
        title = tr('Chest'),
        subtitle = null,
        options = const [],
        wheelIndex = null,
        loot = null,
        survived = null,
        best = null,
        drops = const [];
  RunOverlay.wheel(this.wheelIndex)
      : kind = OverlayKind.wheel,
        title = tr('Lucky wheel'),
        subtitle = null,
        options = const [],
        loot = null,
        survived = null,
        best = null,
        drops = const [];
  RunOverlay.chest(this.loot)
      : kind = OverlayKind.chest,
        title = tr('Treasure!'),
        subtitle = null,
        options = const [],
        wheelIndex = null,
        survived = null,
        best = null,
        drops = const [];
  RunOverlay.end(this.kind, this.title, this.subtitle, {this.survived, this.best, this.drops = const []})
      : options = const [],
        wheelIndex = null,
        loot = null;

  /// Gear earned by the run, shown on the end card.
  final List<GearItem> drops;

  final OverlayKind kind;
  final String title;
  final String? subtitle;
  final List<PickOption> options;
  final int? wheelIndex;
  final Loot? loot;

  /// End of run: days survived and the longest run so far.
  final int? survived, best;

  /// The wheel is turning (a pushup, or [spinAuto] seconds, started it).
  bool spinning = false;

  /// Set once the wheel has stopped.
  String? result;
}

/// One-shot visual effects for the screen to animate.
sealed class RunFx {}

class FloatFx extends RunFx {
  FloatFx(this.text, this.kind, {required this.onFoe});
  final String text;
  final FloatKind kind;
  final bool onFoe;
}

enum FloatKind { hit, crit, heal, hurt, reflect }

class LungeFx extends RunFx {
  LungeFx({required this.byHero});
  final bool byHero;
}

class BannerFx extends RunFx {
  BannerFx(this.text, this.seconds);
  final String text;
  final double seconds;
}

class WalkFx extends RunFx {}

/// A blade (or arrow, or palm) hitting the foe.
class SlashFx extends RunFx {
  SlashFx({this.crit = false});
  final bool crit;
}

/// The camera shakes: crits, heavy blows, specials.
class ShakeFx extends RunFx {
  ShakeFx(this.strength);
  final double strength;
}

/// A class special goes off: its name in a banner and its own effect.
class SpecialFx extends RunFx {
  SpecialFx(this.classId, this.name);
  final String classId, name;
}

/// The foe starts winding up a heavy blow, or the blow was stopped.
class WindupFx extends RunFx {}

class InterruptFx extends RunFx {}

/// The foe falls; [boss] drops a bigger pile of coins.
class FoeDownFx extends RunFx {
  FoeDownFx({this.boss = false});
  final bool boss;
}

/// A new foe walks in from the right edge.
class FoeEnterFx extends RunFx {}

/// The foe dodged the hero's blow (Evasive).
class DodgeFx extends RunFx {}

/// The foe used its ability: the screen draws its projectile or aura.
class AbilityFx extends RunFx {
  AbilityFx(this.ability);
  final FoeAbility ability;
}

/// Where finished runs and the run in progress are kept (`rr.save`).
abstract class RunStore {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> doc);
}

class MemoryRunStore implements RunStore {
  Map<String, dynamic>? doc;
  @override
  Future<Map<String, dynamic>?> load() async => doc;
  @override
  Future<void> save(Map<String, dynamic> d) async => doc = d;
}

class RunController extends ChangeNotifier {
  RunController._(this.rng, this.hero, this.day, this.log, this.chapter, this._doc, this._store,
      [this.tier = Tier.normal])
      : bestDays = bestIn(_doc, chapter) {
    _storyBag = List.generate(stories.length, (i) => i);
    // Shuffle from a fixed sub-seed so the bag survives a resume unchanged.
    final r = math.Random(rng.seed ^ 0x5eed);
    _storyBag.shuffle(r);
  }

  /// A fresh run on day 0 of [chapter], as [heroClass]. [save] is the whole
  /// adventure save; the run keeps its other chapters' records intact.
  factory RunController.start({
    int? seed,
    int bestDays = 0,
    RunStore? store,
    ChapterDef? chapter,
    String? heroClass,
    Map<String, dynamic>? save,
    Tier tier = Tier.normal,
  }) {
    final ch = chapter ?? chapters.first;
    final doc = _docFrom(save, ch, bestDays);
    final cls = heroClass ?? doc['class'] as String?;
    // Worn gear is counted once, at the start of the run.
    final gear = Armory.fromJson(doc['gear']).bonus;
    final c = RunController._(RunRng(seed ?? DateTime.now().microsecondsSinceEpoch & 0x7fffffff),
        Hero.start(ch.startLevel, cls, gear), 0, [], ch, doc, store, tier);
    c._log(LogEntry(
        tr('Day {n}', {'n': 0}),
        tr('{chapter}: *{name}*. {blurb} Pip the slime bounces along beside you.', {
          'chapter': '${trChapter(ch.number, ch.roman)}${tier == Tier.normal ? '' : ' · ${tr(tier.label)}'}',
          'name': tr(ch.name),
          'blurb': tr(ch.blurb),
        })));
    c.mode = RunMode.walk;
    c._persist();
    return c;
  }

  /// Picks up a saved run at the start of its next day.
  factory RunController.resume(Map<String, dynamic> run,
      {int bestDays = 0, RunStore? store, Map<String, dynamic>? save}) {
    final ch = chapterOf(run['chapter']);
    final c = RunController._(
      RunRng(run['seed'] as int, run['draws'] as int),
      Hero.fromJson(Map<String, dynamic>.from(run['hero'] as Map)),
      run['day'] as int,
      [for (final e in run['log'] as List) LogEntry.fromJson(Map<String, dynamic>.from(e as Map))],
      ch,
      _docFrom(save, ch, bestDays),
      store,
      Tier.byName(run['tier']),
    );
    c.mode = RunMode.walk;
    c.specialCharge = run['charge'] as int? ?? 0;
    return c;
  }

  final RunRng rng;
  final Hero hero;
  final ChapterDef chapter;
  final Tier tier;
  final RunStore? _store;

  /// The whole adventure save (all chapters); this run updates its own parts.
  final Map<String, dynamic> _doc;

  /// The save after this run so far (for screens that show records).
  Map<String, dynamic> get save => _doc;
  late final List<int> _storyBag;

  int day;
  int bestDays;
  RunMode mode = RunMode.busy;
  final List<LogEntry> log;

  /// The fight in progress, if any.
  Battle? battle;
  FightState? get fight => battle?.st;
  RunOverlay? overlay;

  /// 0..1 progress of the foe's next attack (or of its heavy blow).
  double get foeClock => battle?.threat ?? 0;
  double pickTime = 0;

  /// Seconds a lucky wheel has waited for its spin.
  double spinWait = 0;
  double? cardLeft;

  /// True while the camera has lost the player: the foe's clock and the
  /// auto-picks wait, so a slipped phone never costs a fight.
  bool hold = false;

  /// Counters for the simulation and the end card.
  int reps = 0, strikes = 0;

  /// The special meter, kept between fights.
  int specialCharge = 0;

  /// Strikes landed in the current fight, shown as the round number.
  int round = 0;

  final _fx = StreamController<RunFx>.broadcast();
  Stream<RunFx> get effects => _fx.stream;

  double _waitLeft = 0;
  void Function()? _then;
  void Function()? _onCardClosed;
  void Function(int)? _onPicked;

  /// Best days survived in [ch] according to [doc] (old saves: `best_days`).
  static int bestIn(Map<String, dynamic> doc, ChapterDef ch) {
    final best = doc['best'];
    if (best is Map && best[ch.id] is int) return best[ch.id] as int;
    return ch.number == 1 ? (doc['best_days'] as int? ?? 0) : 0;
  }

  static ChapterDef chapterOf(Object? v) => switch (v) {
        int n when n >= 1 && n <= chapters.length => chapters[n - 1],
        String id => chapterById(id),
        _ => chapters.first,
      };

  static Map<String, dynamic> _docFrom(Map<String, dynamic>? save, ChapterDef ch, int bestDays) {
    final doc = save == null ? <String, dynamic>{'version': 1} : Map<String, dynamic>.from(save);
    doc['version'] = 1;
    final best = Map<String, dynamic>.from(doc['best'] as Map? ?? {});
    if (ch.number == 1 && !best.containsKey(ch.id) && doc['best_days'] is int) best[ch.id] = doc['best_days'];
    if (bestDays > (best[ch.id] as int? ?? 0)) best[ch.id] = bestDays;
    doc['best'] = best;
    return doc;
  }

  /// Which tiers of [ch] are open in [doc]: Normal always (once the world
  /// is), Nightmare everywhere once the whole game is cleared on Normal.
  static bool tierOpen(Map<String, dynamic> doc, ChapterDef ch, Tier t) => switch (t) {
        Tier.normal => true,
        Tier.nightmare => gameCleared(doc),
      };

  /// Every world beaten on Normal.
  static bool gameCleared(Map<String, dynamic> doc) {
    final done = (doc['cleared'] as List? ?? const []).cast<Object?>();
    return chapters.every((c) => done.contains(c.id));
  }

  static bool tierCleared(Map<String, dynamic> doc, ChapterDef ch, Tier t) =>
      (doc['cleared'] as List? ?? const []).contains(t == Tier.normal ? ch.id : '${ch.id}:${t.name}');

  bool get boss => fight?.foe.boss ?? (day > 0 && chapterOne[day - 1] == 'boss');
  bool get finished => mode == RunMode.over;
  int get litIndex =>
      overlay == null || overlay!.options.isEmpty ? 0 : (pickTime / pickCycle).floor() % overlay!.options.length;
  double get pickAutoLeft => math.max(0, pickAuto - pickTime);
  List<String> get upcoming => chapterOne.skip(day).take(5).toList();

  /// The button's label and its small line: what the next pushup does.
  (String, String) get actionLabel => switch (mode) {
        RunMode.walk => (tr('Next Day'), tr('1 pushup')),
        RunMode.fight when battle?.specialReady ?? false => (tr('SPECIAL!'), tr(hero.heroClass.special)),
        RunMode.fight when battle?.windup ?? false => (
            tr('STRIKE!'),
            tr('stop the blow: {n} more', {'n': windupBreak - battle!.windupHits})
          ),
        RunMode.fight => (tr('STRIKE!'), tr('1 pushup = 1 hit')),
        RunMode.pick when overlay?.kind == OverlayKind.choice => (tr('Pick'), tr('a pushup takes the glowing one')),
        RunMode.pick => (tr('Pick'), tr('a pushup takes the glowing card')),
        RunMode.card when cardLeft == null => (tr('Back'), tr('a pushup')),
        RunMode.card when overlay?.kind == OverlayKind.chestClosed => (tr('Pick up'), tr('a pushup')),
        RunMode.card => (tr('Continue'), tr('a pushup, or wait a moment')),
        RunMode.spin => (tr('Spin!'), tr('1 pushup')),
        RunMode.busy when overlay?.kind == OverlayKind.wheel => (tr('Spinning'), '• • •'),
        RunMode.busy when fight != null => (tr('FIGHT!'), '• • •'),
        RunMode.busy => (tr('Moving'), '• • •'),
        RunMode.over => (tr('Back to camp'), tr('a pushup')),
      };

  // ---------------------------------------------------------------- input

  /// One verified pushup (or a tap on the button, or the space bar).
  void rep() {
    switch (mode) {
      case RunMode.walk:
        reps++;
        _nextDay();
      case RunMode.fight:
        reps++;
        _strike();
      case RunMode.pick:
        reps++;
        choose(litIndex);
      case RunMode.spin:
        reps++;
        _startSpin();
      case RunMode.card:
        reps++;
        closeCard();
      case RunMode.busy:
      case RunMode.over:
        break;
    }
    notifyListeners();
  }

  /// A tap on a card picks that card directly.
  void choose(int i) {
    if (mode != RunMode.pick) return;
    final done = _onPicked;
    _onPicked = null;
    overlay = null;
    mode = RunMode.busy;
    done?.call(i);
    notifyListeners();
  }

  void closeCard() {
    if (mode != RunMode.card) return;
    final done = _onCardClosed;
    _onCardClosed = null;
    overlay = null;
    cardLeft = null;
    mode = RunMode.busy;
    done?.call();
    notifyListeners();
  }

  // ----------------------------------------------------------------- time

  void tick(double dt) {
    if (dt <= 0 || finished) return;
    if (hold && mode != RunMode.busy) return;
    switch (mode) {
      case RunMode.busy:
        _waitLeft -= dt;
        if (_waitLeft <= 0 && _then != null) {
          final f = _then!;
          _then = null;
          f();
        }
      case RunMode.fight:
        _events(battle!.advance(dt));
      case RunMode.pick:
        pickTime += dt;
        if (pickTime >= pickAuto) choose(litIndex);
      case RunMode.spin:
        spinWait += dt;
        if (spinWait >= spinAuto) _startSpin();
      case RunMode.card:
        if (cardLeft != null) {
          cardLeft = cardLeft! - dt;
          if (cardLeft! <= 0) closeCard();
        }
      case RunMode.walk:
      case RunMode.over:
        break;
    }
    notifyListeners();
  }

  void _wait(double secs, void Function() then) {
    mode = RunMode.busy;
    _waitLeft = secs;
    _then = then;
  }

  // ---------------------------------------------------------------- days

  void _nextDay() {
    day++;
    _fx.add(WalkFx());
    _wait(walkTime, _resolveDay);
  }

  String get _head => tr('Day {n}', {'n': day});

  void _resolveDay() {
    final node = chapterOne[day - 1];
    switch (node) {
      case 'story':
        final st = stories[_storyBag[day % _storyBag.length]];
        st.effect.apply(hero);
        _log(LogEntry(_head, tr(st.text), tag: tr(st.effect.tag)));
        _endDay();
      case 'skill':
        _log(LogEntry(_head, tr('You sit down to think. Pip wobbles with an idea.')));
        _chooseSkill(_endDay);
      case 'wheel':
        _log(LogEntry(_head, tr('You find an old *lucky wheel* nailed to a fence post.')));
        _spinWheel();
      case 'chest':
        _log(LogEntry(_head, tr('A mossy *chest* sits by the roadside.')));
        _card(RunOverlay.chestClosed(), () {
          final l = rollLoot(rng.call, luck: hero.heroClass.lootLuck);
          equip(hero, l);
          _log(LogEntry(_head, tr('You prise open the chest and find *{item}*.', {'item': tr(l.name)}),
              tag: '${rarityName(l.rarity)} · +${l.v} ${statName(l.stat)}'));
          _card(RunOverlay.chest(l), _endDay);
        });
      case 'choice':
        final c = choices[day % choices.length];
        _log(LogEntry(_head, tr(c.text)));
        _pick(
            RunOverlay.pick(
                tr('Make a choice'),
                tr(c.text),
                [
                  PickOption(tr(c.a.label), tr(c.a.effect.tag)),
                  PickOption(tr(c.b.label), tr(c.b.effect.tag)),
                ],
                kind: OverlayKind.choice), (i) {
          final o = i == 0 ? c.a : c.b;
          o.effect.apply(hero);
          _log(LogEntry(_head, tr('You chose *{choice}*.', {'choice': tr(o.label)}), tag: tr(o.effect.tag)));
          _endDay();
        });
      default:
        _startFight(foeFor(node == 'boss' ? 'boss' : node.substring(4), chapter, tier));
    }
  }

  void _endDay() {
    if (day >= chapterOne.length) return;
    mode = RunMode.walk;
    _persist();
  }

  // --------------------------------------------------------------- events

  void _pick(RunOverlay o, void Function(int) then) {
    overlay = o;
    pickTime = 0;
    _onPicked = then;
    mode = RunMode.pick;
  }

  void _card(RunOverlay o, void Function() then, {bool auto = true}) {
    overlay = o;
    cardLeft = auto ? cardAuto : null;
    _onCardClosed = then;
    mode = RunMode.card;
  }

  void _chooseSkill(void Function() then) {
    final keys = skillOffer(rng.call);
    _pick(
      RunOverlay.pick(tr('Choose a skill'), null, [
        for (final k in keys) PickOption(tr(skills[k]!.name), tr(skills[k]!.text), skill: k),
      ]),
      (i) {
        final s = skills[keys[i]]!;
        applySkill(hero, s.key);
        _log(LogEntry(_head, tr('You learned *{skill}*.', {'skill': tr(s.name)}), tag: tr(s.text)));
        then();
      },
    );
  }

  /// The wheel comes up and waits; a pushup (or [spinAuto]) spins it.
  void _spinWheel() {
    final idx = (rng() * wheel.length).floor();
    overlay = RunOverlay.wheel(idx);
    spinWait = 0;
    mode = RunMode.spin;
  }

  void _startSpin() {
    final o = overlay!;
    final idx = o.wheelIndex!;
    o.spinning = true;
    _wait(wheelSpin, () {
      final s = wheel[idx];
      if (s.skill) {
        overlay = null;
        _chooseSkill(_endDay);
        return;
      }
      if (s.xp > 0) {
        gainXp(hero, s.xp);
      } else {
        s.apply!(hero);
      }
      o.result = '${tr(s.label)}!';
      _log(LogEntry(_head, tr('The wheel clicks to a stop.'), tag: tr(s.label)));
      _card(o, _endDay);
    });
  }

  // ---------------------------------------------------------------- fights

  void _startFight(Foe f) {
    // The bestiary remembers every creature met.
    final seen = {...(_doc['seen'] as List? ?? const []).cast<Object?>()};
    if (seen.add(f.img)) _doc['seen'] = seen.toList();
    _log(LogEntry(
      _head,
      f.boss
          ? tr('The ground shakes. *{foe}* blocks the way! “{quote}”', {'foe': trName(f.name), 'quote': tr(f.quote)})
          : tr('A *{foe}* blocks the road! “{quote}”', {'foe': trName(f.name), 'quote': tr(f.quote)}),
      kind: LogKind.fight,
    ));
    battle = Battle(hero, f, rng.call, charge: specialCharge);
    round = 0;
    void go() => mode = RunMode.fight;
    // The foe slides in, a banner swoops across, then the clock starts.
    _fx.add(FoeEnterFx());
    if (f.boss) {
      _fx.add(BannerFx(tr('BOSS!'), bossIntro));
      _wait(bossIntro, go);
    } else {
      _fx.add(BannerFx(tr('FIGHT!'), fightIntro));
      _wait(fightIntro, go);
    }
  }

  void _strike() {
    strikes++;
    round++;
    _events(battle!.rep());
  }

  /// Turns what happened in the fight into effects and log lines.
  void _events(List<BattleEvent> events) {
    final b = battle;
    if (b == null) return;
    for (final e in events) {
      switch (e) {
        case StrikeEvent(:final blows):
          _fx.add(LungeFx(byHero: true));
          for (final x in blows) {
            if (x.miss) {
              _fx.add(DodgeFx());
              _fx.add(FloatFx(tr('MISS'), FloatKind.reflect, onFoe: true));
              continue;
            }
            _fx.add(SlashFx(crit: x.crit));
            _fx.add(FloatFx('${x.crit ? '${tr('CRIT')} ' : ''}−${x.dmg}', x.crit ? FloatKind.crit : FloatKind.hit,
                onFoe: true));
            if (x.crit) _fx.add(ShakeFx(0.6));
            if (x.heal > 0) _fx.add(FloatFx('+${x.heal}', FloatKind.heal, onFoe: false));
          }
        case SpecialEvent(:final name, :final result):
          _fx.add(SpecialFx(hero.cls, name));
          _fx.add(ShakeFx(1));
          for (final x in result.blows) {
            if (x.miss) {
              _fx.add(DodgeFx());
              _fx.add(FloatFx(tr('MISS'), FloatKind.reflect, onFoe: true));
              continue;
            }
            _fx.add(FloatFx('${x.crit ? '${tr('CRIT')} ' : ''}−${x.dmg}', x.crit ? FloatKind.crit : FloatKind.hit,
                onFoe: true));
          }
          if (result.healed > 0) _fx.add(FloatFx('+${result.healed}', FloatKind.heal, onFoe: false));
          if (result.selfHit > 0) _fx.add(FloatFx('−${result.selfHit}', FloatKind.hurt, onFoe: false));
        case FoeHitEvent(:final dmg, :final reflect, :final heavy, :final drained):
          _fx.add(LungeFx(byHero: false));
          _fx.add(FloatFx('−$dmg', FloatKind.hurt, onFoe: false));
          if (heavy) _fx.add(ShakeFx(1.2));
          if (reflect > 0) _fx.add(FloatFx('−$reflect', FloatKind.reflect, onFoe: true));
          if (drained > 0) _fx.add(FloatFx('+$drained', FloatKind.heal, onFoe: true));
        case FoeAbilityEvent(:final ability, :final amount, :final tick):
          if (tick) {
            _fx.add(FloatFx('−$amount', FloatKind.hurt, onFoe: false));
            break;
          }
          _fx.add(BannerFx(tr(ability.label), 0.8));
          _fx.add(AbilityFx(ability));
          switch (ability) {
            case FoeAbility.regen:
              _fx.add(FloatFx('+$amount', FloatKind.heal, onFoe: true));
            case FoeAbility.breath:
              _fx.add(LungeFx(byHero: false));
              _fx.add(FloatFx('−$amount', FloatKind.crit, onFoe: false));
              _fx.add(ShakeFx(1));
            case FoeAbility.hex when amount > 0:
              _fx.add(FloatFx(tr('Special −{n}', {'n': amount}), FloatKind.reflect, onFoe: false));
            default:
              break;
          }
        case WindupEvent():
          _fx.add(WindupFx());
        case InterruptEvent():
          _fx.add(InterruptFx());
          _fx.add(BannerFx(tr('STAGGERED!'), 0.7));
      }
    }
    if (b.over) _endFight(won: b.won);
  }

  void _endFight({required bool won}) {
    specialCharge = battle!.charge;
    final st = battle!.st;
    battle = null;
    if (won) _fx.add(FoeDownFx(boss: st.foe.boss));
    if (!won) {
      _wait(0.5, () => _defeat(st.foe));
      return;
    }
    final (xp, windHeal) = winFight(hero, st);
    final ups = gainXp(hero, xp);
    final text = st.foe.boss
        ? tr('CHAPTER CLEAR!')
        : st.foe.elite
            ? tr('Big win!')
            : tr('Victory!');
    final secs = st.foe.boss ? 1.3 : 0.8;
    _fx.add(BannerFx(text, secs));
    _wait(secs, () {
      _log(LogEntry(tr('Victory'), tr('The *{foe}* is defeated.', {'foe': trName(st.foe.name)}),
          tag: [
            '${tr('EXP')} +$xp',
            if (windHeal > 0) tr('Heal +{n}', {'n': windHeal}),
            if (ups > 0) tr('Level {n}!', {'n': hero.lv}),
          ].join(' · '),
          kind: LogKind.win));
      if (st.foe.boss) {
        final drops = _finish(day, cleared: true);
        final next = switch (tier) {
          Tier.normal when chapter.number < chapters.length =>
            ' ${tr('{world} is open.', {'world': tr(chapters[chapter.number].name)})}',
          Tier.normal => ' ${tr('The game is beaten. Nightmare is open on every world.')}',
          Tier.nightmare => ' ${tr('Nothing in {world} can stop you now.', {'world': tr(chapter.name)})}',
        };
        _card(
            RunOverlay.end(OverlayKind.clear, tr('Victory'),
                '${tr('{boss} is down. Hero level {n}.', {'boss': tr(chapter.boss.name), 'n': hero.lv})}$next',
                survived: day, best: bestDays, drops: drops),
            _over,
            auto: false);
      } else {
        _endDay();
      }
    });
  }

  void _defeat(Foe f) {
    final drops = _finish(day - 1, cleared: false);
    _card(
        RunOverlay.end(OverlayKind.defeat, tr('Defeat'),
            tr('The {foe} won on day {n}. Better gear hits harder.', {'foe': trName(f.name), 'n': day}),
            survived: day - 1, best: bestDays, drops: drops),
        _over,
        auto: false);
  }

  void _over() => mode = RunMode.over;

  // ------------------------------------------------------------- the log

  void _log(LogEntry e) {
    log.insert(0, e);
    if (log.length > 8) log.removeRange(8, log.length);
  }

  // ------------------------------------------------------------- saving

  bool cleared = false;

  /// Records the run and hands out its gear. Returns the new pieces.
  List<GearItem> _finish(int survived, {required bool cleared}) {
    this.cleared = cleared;
    bestDays = math.max(bestDays, survived);
    final armory = Armory.fromJson(_doc['gear']);
    final drops = [
      for (final (kind, r)
          in rollDrops(rng.call, chapter: chapter.number, tierIndex: tier.dropBoost, days: survived, cleared: cleared))
        armory.add(kind, r),
    ];
    _doc['gear'] = armory.toJson();
    (_doc['best'] as Map)[chapter.id] = bestDays;
    _doc['best_days'] = math.max(_doc['best_days'] as int? ?? 0, bestDays);
    if (cleared) {
      if (tier == Tier.normal) {
        final unlocked = _doc['unlocked'] as int? ?? 1;
        _doc['unlocked'] = math.min(chapters.length, math.max(unlocked, chapter.number + 1));
      }
      final mark = tier == Tier.normal ? chapter.id : '${chapter.id}:${tier.name}';
      _doc['cleared'] = {...(_doc['cleared'] as List? ?? const []), mark}.toList();
    }
    _doc['run'] = null;
    _store?.save(_doc);
    return drops;
  }

  Map<String, dynamic> runJson() => {
        'chapter': chapter.id,
        'tier': tier.name,
        'day': day,
        'seed': rng.seed,
        'draws': rng.draws,
        'hero': hero.toJson(),
        'charge': specialCharge,
        'log': [for (final e in log) e.toJson()],
      };

  void _persist() {
    _doc['run'] = runJson();
    _doc['class'] = hero.cls;
    _store?.save(_doc);
  }

  @override
  void dispose() {
    _fx.close();
    super.dispose();
  }
}

String rarityName(Rarity r) => tr(r.label);

String statName(String stat) => tr(switch (stat) { 'hp' => 'max HP', 'atk' => 'ATK', _ => 'DEF' });
