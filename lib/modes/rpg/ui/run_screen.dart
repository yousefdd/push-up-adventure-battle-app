// S02–S12 in one screen: the road, the fights and every event card, played
// with pushups only. Taps and the space bar do the same thing as a pushup.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Hero;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../engine/exercise.dart';
import '../../../engine/pose.dart';
import '../../../engine/rep_engine.dart';
import '../../../ui/pose_overlay.dart';
import '../../../ui/theme/adventure_tokens.dart';
import '../../online/pose_frame_source.dart';
import '../adventure_rules.dart';
import '../run_controller.dart';
import 'adv_widgets.dart';
import 'fx.dart';
import '../../../i18n/i18n.dart';
import '../../../ui/motion.dart';
import '../../../online/ranked.dart';
import '../../../ui/ads.dart';
import '../../../ui/rank_widgets.dart';

const _t = AdvTokens.space;

/// How long the camera may lose the player before the foe's clock waits.
const _lostAfter = Duration(seconds: 3);

class RunScreen extends StatefulWidget {
  const RunScreen({
    super.key,
    required this.run,
    this.exercise = ExerciseType.pushup,
    this.poseSource,
    this.cameraBuilder,
  });

  final RunController run;
  final ExerciseType exercise;

  /// The camera on a phone; null on the web, where taps and Space stand in.
  final PoseFrameSource? poseSource;
  final Widget Function(Widget overlay)? cameraBuilder;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _Float {
  _Float(this.fx, this.x, this.y);
  final FloatFx fx;
  final double x, y;
}

class _RunScreenState extends State<RunScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  RunController get run => widget.run;
  late final Ticker _ticker;
  late final AnimationController _heroLunge, _foeLunge, _shake, _flash, _breath, _hurt, _enter, _death, _dodge;
  late final StreamSubscription<RunFx> _fxSub;
  StreamSubscription<PoseFrame>? _poseSub;
  RepEngine? _engine;
  final _focus = FocusNode();
  final _rand = math.Random();

  Duration _last = Duration.zero;
  final List<_Float> _floats = [];
  String? _banner;
  PoseFrame? _frame;
  RepState _rep = const RepState(RepPhase.arming, null, 0, 0);
  DateTime _lastSeen = DateTime.now();
  String? _cue;
  bool _left = false;

  /// Coins the server granted for clearing this world (null until it answers).
  Reward? _reward;

  // One-shot effects on screen right now.
  final List<Widget> _shots = [];
  double _shakeStrength = 0;
  String? _special;
  int _shotId = 0;

  /// Blows landed in this fight, shown as a combo counter.
  int _hits = 0;

  /// The foe on screen, kept for its fall after the fight ends.
  Foe? _lastFoe, _dying;

  /// What the last frame showed, to sound the moments that change it.
  OverlayKind? _lastOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A strike is a dash across the field, a blow, and a hop back.
    _heroLunge = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _foeLunge = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
    _hurt = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 520), value: 1);
    _death = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _dodge = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    // Sprites breathe: a slow squash and stretch, forever.
    _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _ticker = createTicker(_onTick)..start();
    run.addListener(_onRun);
    _fxSub = run.effects.listen(_onFx);

    final source = widget.poseSource;
    if (source != null) {
      _engine = RepEngine(ExerciseProfile.defaults[widget.exercise]!, onRep: (ev) {
        // Only a verified rep moves the hero; a rejected one says why.
        if (ev.accepted) {
          run.rep();
          _cue = null;
        } else {
          _cue = ev.cue;
        }
      });
      _poseSub = source.frames.listen(_onFrame);
      source.start();
    }
  }

  void _onTick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (_engine != null) {
      run.hold = DateTime.now().difference(_lastSeen) > _lostAfter;
    }
    // A long frame (debugger, app switch) must not land several foe attacks at once.
    run.tick(math.min(dt, 0.25));
  }

  void _onFrame(PoseFrame frame) {
    _frame = frame;
    _rep = _engine!.update(frame);
    if (_rep.angle != null) _lastSeen = DateTime.now();
  }

  void _onRun() {
    if (!mounted) return;
    if (run.finished && !_left) {
      _left = true;
      // Back to camp, then the ad break.
      final nav = Navigator.of(context);
      nav.maybePop().then((_) => AdBreak.show(nav));
      return;
    }
    final kind = run.overlay?.kind;
    if (kind != _lastOverlay) {
      if (kind == OverlayKind.clear) {
        // A cleared world pays silver, or gold from world 8 or Nightmare (the server limits how often).
        Ranked.claimAdventure(run.chapter.number, hard: run.tier != Tier.normal).then((r) {
          if (mounted) setState(() => _reward = r);
        });
      }
      _lastOverlay = kind;
    }
    setState(() {});
  }

  void _onFx(RunFx fx) {
    switch (fx) {
      case LungeFx(:final byHero):
        (byHero ? _heroLunge : _foeLunge).forward(from: 0);
        _shot(
            const Duration(milliseconds: 420),
            (t) => DustPainter(t, byHero ? heroSpot + const Offset(-0.05, 0.2) : foeSpot + const Offset(0.05, 0.2),
                toLeft: byHero));
      case FloatFx(:final kind, :final onFoe):
        // The one hit flashes white, the moment the blow lands.
        if (!onFoe && kind == FloatKind.hurt) {
          _later(120, () => _hurt.forward(from: 0));
        }
        if (!onFoe && kind == FloatKind.heal) {
          _shot(const Duration(milliseconds: 800), (t) => AuraPainter(t, AdvTokens.rewardText, onFoe: false));
        }
        if (onFoe && kind == FloatKind.heal) {
          _shot(const Duration(milliseconds: 800), (t) => AuraPainter(t, AdvTokens.rewardText));
        }
        final f = _Float(fx, 0.12 + _rand.nextDouble() * 0.1, 0.24 + _rand.nextDouble() * 0.12);
        _floats.add(f);
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setState(() => _floats.remove(f));
        });
      case BannerFx(:final text, :final seconds):
        _banner = text;
        Future.delayed(Duration(milliseconds: (seconds * 1000).round()), () {
          if (mounted && _banner == text) setState(() => _banner = null);
        });
      case WalkFx():
        _shot(const Duration(milliseconds: 500), (t) => DustPainter(t, heroSpot + const Offset(-0.06, 0.2)));
      case SlashFx(:final crit):
        // The hero reaches the foe a beat after the dash starts.
        _later(120, () {
          _flash.forward(from: 0);
          setState(() => _hits++);
          _shot(const Duration(milliseconds: 260),
              (t) => SlashPainter(t, classColor(run.hero.cls), crit: crit, angle: -0.6 + _rand.nextDouble() * 1.2));
        });
      case FoeEnterFx():
        setState(() {
          _hits = 0;
          _dying = null;
        });
        _enter.forward(from: 0);
        _shot(
            const Duration(milliseconds: 520), (t) => DustPainter(t, foeSpot + const Offset(0.06, 0.2), toLeft: false));
      case DodgeFx():
        _dodge.forward(from: 0);
      case AbilityFx(:final ability):
        _abilityFx(ability);
      case ShakeFx(:final strength):
        _shakeStrength = strength;
        _shake.forward(from: 0);
      case SpecialFx(:final classId, :final name):
        _special = tr(name);
        _shot(const Duration(milliseconds: 950), (t) => SpecialPainter(t, classId),
            done: () => setState(() => _special = null));
        _flash.forward(from: 0);
      case WindupFx():
        break; // drawn from the battle state
      case InterruptFx():
        _shakeStrength = 0.8;
        _shake.forward(from: 0);
      case FoeDownFx():
        // It topples over and fades in a burst of shards.
        setState(() => _dying = _lastFoe);
        _death.forward(from: 0).then((_) {
          if (mounted) setState(() => _dying = null);
        });
        _shot(const Duration(milliseconds: 700), (t) => BurstPainter(t, classColor(run.hero.cls)));
    }
  }

  void _later(int ms, VoidCallback f) => Future.delayed(Duration(milliseconds: ms), () {
        if (mounted) f();
      });

  /// Each ability is drawn: a thrown ball for attacks, an aura for buffs.
  void _abilityFx(FoeAbility a) {
    const d = Duration(milliseconds: 700);
    switch (a) {
      case FoeAbility.breath:
        _foeLunge.forward(from: 0);
        _shot(d, (t) => ProjectilePainter(t, AdvTokens.orangeTop, size: 18));
      case FoeAbility.venom:
        _shot(d, (t) => ProjectilePainter(t, AdvTokens.rareUncommon));
      case FoeAbility.hex:
        _shot(d, (t) => ProjectilePainter(t, AdvTokens.ability));
        _shot(const Duration(milliseconds: 900), (t) => AuraPainter(t, AdvTokens.ability, onFoe: false, rising: false));
      case FoeAbility.regen:
        _shot(const Duration(milliseconds: 900), (t) => AuraPainter(t, AdvTokens.rewardText));
      case FoeAbility.stoneSkin:
        _shot(const Duration(milliseconds: 900), (t) => AuraPainter(t, AdvTokens.textMuted, rising: false));
      case FoeAbility.frenzy:
        _shot(const Duration(milliseconds: 900), (t) => AuraPainter(t, AdvTokens.hp));
        _shakeStrength = 0.5;
        _shake.forward(from: 0);
      default:
        break;
    }
  }

  void _shot(Duration d, CustomPainter Function(double) painter, {VoidCallback? done}) {
    late final Widget w;
    w = OneShot(
      key: ValueKey(_shotId++),
      duration: d,
      painter: painter,
      onDone: () {
        if (!mounted) return;
        setState(() => _shots.remove(w));
        done?.call();
      },
    );
    setState(() => _shots.add(w));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounded: time stops, so nothing attacks a pocketed phone.
    if (state == AppLifecycleState.resumed) {
      if (!_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    run.removeListener(_onRun);
    _fxSub.cancel();
    _poseSub?.cancel();
    widget.poseSource?.stop();
    _ticker.dispose();
    _heroLunge.dispose();
    _foeLunge.dispose();
    _shake.dispose();
    _flash.dispose();
    _breath.dispose();
    _hurt.dispose();
    _enter.dispose();
    _death.dispose();
    _dodge.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.space || e.logicalKey == LogicalKeyboardKey.enter)) {
      run.rep();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final (label, sub) = run.actionLabel;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: AdvTokens.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AdvTokens.sizeMaxWidth),
              child: Column(children: [
                Expanded(
                  child: Stack(children: [
                    Column(children: [
                      _scene(),
                      StatBar(run.hero),
                      if (run.hero.sk.isNotEmpty) _skills(),
                      Expanded(child: _log()),
                    ]),
                    if (_modal) Positioned.fill(child: EventModal(child: _overlay(run.overlay!))),
                  ]),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(_t[4], _t[2], _t[4], _t[2]),
                  child: _actions(label, sub),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  bool get _modal =>
      run.overlay != null && run.overlay!.kind != OverlayKind.choice && run.overlay!.kind != OverlayKind.chestClosed;

  ActionVariant get _variant => switch (run.overlay?.kind) {
        OverlayKind.chestClosed || OverlayKind.clear || OverlayKind.defeat => ActionVariant.orange,
        _ => variantFor(run.mode),
      };

  /// The bottom bar: one big button, or the two choice buttons.
  Widget _actions(String label, String sub) {
    final o = run.overlay;
    if (o != null && o.kind == OverlayKind.choice && run.mode == RunMode.pick) {
      return Column(children: [
        Row(children: [
          for (var i = 0; i < o.options.length; i++) ...[
            if (i > 0) SizedBox(width: _t[3]),
            Expanded(
              child: ChoiceButton(option: o.options[i], lit: i == run.litIndex, onTap: () => run.choose(i)),
            ),
          ],
        ]),
        SizedBox(height: _t[2]),
        Text(tr('A pushup takes the glowing one · auto in {n}s', {'n': run.pickAutoLeft.ceil()}),
            style: AdvTokens.xs.copyWith(color: AdvTokens.textMuted)),
      ]);
    }
    return Column(children: [
      ActionButton(
        variant: _variant,
        label: label,
        sub: run.hold && run.mode == RunMode.fight ? tr('Paused: get back in frame') : sub,
        onPressed: run.rep,
      ),
      SizedBox(height: _t[1]),
      Text(
        (_cue == null ? null : tr(_cue!)) ??
            tr(widget.poseSource == null ? 'Tap or press Space for each pushup' : 'Only correct reps count'),
        textAlign: TextAlign.center,
        style: AdvTokens.xs.copyWith(color: AdvTokens.textMuted),
      ),
    ]);
  }

  // ------------------------------------------------------------- the scene

  /// The battle scene keeps the hero on the left in both languages.
  Widget _scene() => Directionality(textDirection: TextDirection.ltr, child: _sceneLtr());

  Widget _sceneLtr() {
    final f = run.fight;
    final b = run.battle;
    return SizedBox(
      height: AdvTokens.sizeScene,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        // Fighters stand in the middle of the road, well below the scenery.
        final strip = h * AdvTokens.sceneryShare;
        final feet = h * 0.2;
        if (f != null) _lastFoe = f.foe;
        // How far a dash carries a fighter: up to its opponent.
        final foeSize = f?.foe.boss == true ? AdvTokens.sizeFighterBoss : AdvTokens.sizeFighter;
        final gap = math.max(0.0, w * 0.68 - AdvTokens.sizeFighter - foeSize - _t[2]);
        final scene = Stack(clipBehavior: Clip.hardEdge, children: [
          // A strip of painted scenery on top, a wide road below it.
          Positioned(left: 0, right: 0, top: strip - 2, bottom: 0, child: _road()),
          Positioned(left: 0, right: 0, top: 0, height: strip, child: _backdrop(strip, run.chapter.far, 40)),
          Positioned(left: 0, right: 0, top: 0, height: strip, child: _backdrop(strip, run.chapter.near, 140)),
          Positioned(
            left: _t[3],
            right: _t[3],
            top: _t[2],
            child: Row(children: [
              _closeButton(),
              SizedBox(width: _t[2]),
              Expanded(
                child: f != null
                    ? Center(child: StrokeText(tr('Round {n}', {'n': run.round + 1}), style: AdvTokens.lg))
                    : DayStrip(day: run.day, upcoming: run.upcoming, chapter: run.chapter),
              ),
              // Balances the close button so the strip stays centred.
              SizedBox(width: _t[2] + AdvTokens.sizeEvent * 0.8),
            ]),
          ),
          // Pip and the hero on the left.
          Positioned(
            left: w * 0.06,
            bottom: feet,
            child: _walkBob(_breathe(const Sprite('pet_pip', size: AdvTokens.sizeCinder * 0.55)), delay: 0.25),
          ),
          Positioned(
            left: w * 0.18,
            bottom: feet,
            child: _heroMove(
              gap,
              Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_heroLunge, _hurt]),
                  builder: (_, __) => Transform.rotate(
                    angle: _dash(_heroLunge.value) * 0.2 - _knock(_hurt) * 0.12,
                    alignment: Alignment.bottomCenter,
                    child: _walkBob(_breathe(
                        Sprite(run.hero.heroClass.sprite, size: AdvTokens.sizeFighter, flash: _flashOf(_hurt)))),
                  ),
                ),
              ]),
            ),
          ),
          // Health bars stand on the ground under each fighter's feet.
          if (f != null)
            Positioned(
              left: w * 0.18 + AdvTokens.sizeFighter * 0.05,
              top: h - feet + _t[1],
              child: _heroMove(
                  gap,
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    FighterBar(value: run.hero.hp / run.hero.max, label: '${run.hero.hp}', foe: false),
                    _specialMeter(),
                  ])),
            ),
          if (f != null) ...[
            Positioned(
              right: w * 0.14,
              bottom: feet,
              child: _foeMove(
                gap,
                Column(mainAxisSize: MainAxisSize.min, children: [
                  if (b != null && b.windup) _windupBadge(b),
                  StrokeText(trName(f.foe.name), style: AdvTokens.sm),
                  AbilityTag(f.foe.ability),
                  SizedBox(height: _t[1]),
                  _foeSprite(f.foe, b != null && b.windup, b),
                ]),
              ),
            ),
            Positioned(
              right: w * 0.14 +
                  ((f.foe.boss ? AdvTokens.sizeFighterBoss : AdvTokens.sizeFighter) - AdvTokens.sizeFighter * 0.9) / 2,
              top: h - feet + _t[1],
              child: _foeMove(
                gap,
                FighterBar(
                  value: f.hp / f.foe.hp,
                  label: '${f.hp}',
                  foe: true,
                  clock: run.hold ? 0 : run.foeClock,
                ),
              ),
            ),
          ],
          // The fallen foe topples and fades after the fight.
          if (f == null && _dying != null)
            Positioned(
              right: w * 0.14,
              bottom: feet,
              child: _fallen(_dying!),
            ),
          if (f != null && _hits > 0) Positioned(right: _t[3], top: _t[6] * 1.7, child: _hitsCounter()),
          if (run.overlay?.kind == OverlayKind.chestClosed)
            Positioned(
              right: w * 0.14,
              bottom: feet,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.3, end: 1),
                duration: AdvTokens.hit * 2,
                curve: Curves.easeOutBack,
                builder: (_, v, c) => Transform.scale(scale: v, alignment: Alignment.bottomCenter, child: c),
                child: const Wiggle(child: ChestSprite()),
              ),
            ),
          ..._shots.map((s) => Positioned.fill(child: s)),
          for (final fl in _floats) _float(fl, w, h),
          if (_special != null)
            Align(
              alignment: const Alignment(0, -0.35),
              child: BannerText(_special!),
            ),
          if (_banner != null) Center(child: BannerText(_banner!)),
          if (widget.cameraBuilder != null) _camera(),
        ]);
        // Crits, heavy blows and specials shake the whole scene.
        return AnimatedBuilder(
          animation: _shake,
          builder: (_, child) {
            final k = (1 - _shake.value) * _shakeStrength * _t[2];
            final o = _shake.isAnimating
                ? Offset(math.sin(_shake.value * 40) * k, math.cos(_shake.value * 33) * k)
                : Offset.zero;
            return Transform.translate(offset: o, child: child);
          },
          child: ClipRect(child: scene),
        );
      }),
    );
  }

  /// A slow breathing squash and stretch, so nobody stands frozen.
  Widget _breathe(Widget child) => AnimatedBuilder(
        animation: _breath,
        builder: (_, c) => Transform.scale(
          scaleY: 1 + _breath.value * 0.035,
          scaleX: 1 - _breath.value * 0.015,
          alignment: Alignment.bottomCenter,
          child: c,
        ),
        child: child,
      );

  /// The foe: breathing and bobbing, flashing white and knocked back when
  /// hit, glowing red while it winds up a heavy blow, tinted while frenzied.
  Widget _foeSprite(Foe foe, bool windup, Battle? b) {
    final size = foe.boss ? AdvTokens.sizeFighterBoss : AdvTokens.sizeFighter;
    final frenzied = b?.st.frenzied ?? false;
    final shielded = (b?.st.shield ?? 0) > 0;
    return AnimatedBuilder(
      animation: Listenable.merge([_flash, _breath, _foeLunge]),
      builder: (_, __) {
        final hit = _knock(_flash);
        return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          if (windup || frenzied)
            Container(
              width: size * 0.7,
              height: size * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AdvTokens.hp.withOpacity((windup ? 0.45 : 0.2) + 0.4 * _breath.value),
                    blurRadius: size * 0.35,
                    spreadRadius: size * 0.08 * (1 + _breath.value),
                  ),
                ],
              ),
            ),
          // Knocked back and squashed by the blow; leaning in when it attacks.
          Transform.translate(
            offset: Offset(hit * _t[4], 0),
            child: Transform.rotate(
              angle: -_dash(_foeLunge.value) * 0.2 + hit * 0.12,
              alignment: Alignment.bottomCenter,
              child: Transform.scale(
                scaleX: 1 - hit * 0.1,
                scaleY: 1 + hit * 0.06,
                alignment: Alignment.bottomCenter,
                child: Transform.scale(
                  scale: windup ? 1 + 0.04 * _breath.value : 1,
                  child: _breathe(Transform.translate(
                    offset: Offset(0, -_breath.value * _t[1]),
                    child: TurnToHero(
                      on: foe.front,
                      child: Sprite(foe.img,
                          size: size,
                          flash: _flashOf(_flash),
                          tint: frenzied ? AdvTokens.hp : null,
                          tintAmount: frenzied ? 0.15 + 0.15 * _breath.value : 0),
                    ),
                  )),
                ),
              ),
            ),
          ),
          if (shielded)
            IgnorePointer(
              child: Container(
                width: size * 0.95,
                height: size * 0.95,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AdvTokens.textMuted.withOpacity(0.5 + 0.3 * _breath.value), width: 4),
                  color: AdvTokens.textMuted.withOpacity(0.12),
                ),
              ),
            ),
        ]);
      },
    );
  }

  /// A dash: quick out, a held blow, a hop back. 0..1 of the way.
  double _dash(double v) {
    if (v <= 0 || v >= 1) return 0;
    if (v < 0.3) return Curves.easeOutCubic.transform(v / 0.3);
    if (v < 0.55) return 1;
    return 1 - Curves.easeInOutCubic.transform((v - 0.55) / 0.45);
  }

  /// A hit's knockback: strong at once, eased away.
  double _knock(AnimationController c) => c.isAnimating ? Curves.easeOutCubic.transform(1 - c.value) : 0;

  /// White flash: full on the first frames of a hit, then gone.
  double _flashOf(AnimationController c) => c.isAnimating && c.value < 0.6 ? 0.9 : 0;

  Widget _heroMove(double gap, Widget child) => AnimatedBuilder(
        animation: Listenable.merge([_heroLunge, _hurt]),
        builder: (_, c) =>
            Transform.translate(offset: Offset(_dash(_heroLunge.value) * gap - _knock(_hurt) * _t[4], 0), child: c),
        child: child,
      );

  Widget _foeMove(double gap, Widget child) => AnimatedBuilder(
        animation: Listenable.merge([_foeLunge, _enter, _dodge]),
        builder: (_, c) {
          // Slides in from the right edge, dashes left to attack, hops back to dodge.
          final enter = (1 - Curves.easeOutCubic.transform(_enter.value)) * AdvTokens.sizeScene;
          final dodge = math.sin(_dodge.value * math.pi);
          return Transform.translate(
            offset: Offset(enter - _dash(_foeLunge.value) * gap + dodge * _t[6], -dodge * _t[5]),
            child: c,
          );
        },
        child: child,
      );

  /// The beaten foe tips over backwards, lies a moment, and fades.
  Widget _fallen(Foe foe) {
    final size = foe.boss ? AdvTokens.sizeFighterBoss : AdvTokens.sizeFighter;
    return AnimatedBuilder(
      animation: _death,
      builder: (_, __) {
        final v = _death.value;
        final fall = Curves.easeInCubic.transform((v / 0.4).clamp(0.0, 1.0));
        final fade = v < 0.6 ? 1.0 : 1 - (v - 0.6) / 0.4;
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(fall * size * 0.25, 0),
            child: Transform.rotate(
              angle: fall * math.pi / 2.2,
              alignment: Alignment.bottomRight,
              child: TurnToHero(on: foe.front, child: Sprite(foe.img, size: size, flash: v < 0.12 ? 0.9 : 0)),
            ),
          ),
        );
      },
    );
  }

  /// "Hits 7" in the corner, popping on every blow.
  Widget _hitsCounter() {
    return TweenAnimationBuilder<double>(
      key: ValueKey(_hits),
      tween: Tween(begin: 1.6, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (_, sc, child) => Transform.scale(scale: sc, alignment: Alignment.centerRight, child: child),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        StrokeText(tr('Hits'), style: AdvTokens.xs, color: AdvTokens.goldTop),
        StrokeText('$_hits', style: AdvTokens.banner.copyWith(fontSize: AdvTokens.title.fontSize! * 1.4, height: 1)),
      ]),
    );
  }

  /// The special meter under the hero's HP: purple, glowing when ready.
  Widget _specialMeter() {
    final b = run.battle;
    if (b == null) return const SizedBox.shrink();
    final ready = b.specialReady;
    return Padding(
      padding: EdgeInsets.only(top: _t[1] / 2),
      child: SizedBox(
        width: AdvTokens.sizeFighter,
        child: Container(
          decoration: ready
              ? BoxDecoration(borderRadius: BorderRadius.circular(AdvTokens.radiusPill), boxShadow: [
                  BoxShadow(color: AdvTokens.specialTop.withOpacity(0.5 + 0.5 * _breath.value), blurRadius: _t[3])
                ])
              : null,
          child: Track(
            value: b.charge / b.hero.specialCost,
            color: ready ? AdvTokens.specialTop : AdvTokens.special,
            height: AdvTokens.sizeBarThin + 2,
            label: ready ? tr('READY') : null,
          ),
        ),
      ),
    );
  }

  /// "!" over the foe and three pips: pushups needed to stop the heavy blow.
  Widget _windupBadge(Battle b) {
    return Padding(
      padding: EdgeInsets.only(bottom: _t[1]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Transform.scale(
          scale: 1 + 0.15 * _breath.value,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: _t[2]),
            decoration: BoxDecoration(
              color: AdvTokens.hp,
              borderRadius: BorderRadius.circular(AdvTokens.radiusCard),
              border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeText),
            ),
            child: StrokeText(tr('! HEAVY'), style: AdvTokens.lg),
          ),
        ),
        SizedBox(height: _t[1] / 2),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < windupBreak; i++)
            Container(
              margin: EdgeInsets.symmetric(horizontal: _t[1] / 2),
              width: _t[3],
              height: _t[3],
              decoration: BoxDecoration(
                color: i < b.windupHits ? AdvTokens.goldTop : AdvTokens.surfaceDeep,
                border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeText),
              ),
            ),
        ]),
      ]),
    );
  }

  /// The road under the fighters, sliding with the near layer.
  Widget _road() {
    final c = Color(run.chapter.ground);
    final sand = Color.lerp(c, AdvTokens.road, 0.78)!;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: run.day * 140.0 + run.round * 140 / 8),
      duration: AdvTokens.walk,
      curve: Curves.easeInOut,
      builder: (_, x, __) => CustomPaint(painter: RoadPainter(sand, x)),
    );
  }

  /// One pixel layer of the world, two copies side by side, sliding [step]
  /// pixels a day (the far layer moves less: parallax).
  Widget _backdrop(double h, String layer, double step) {
    // Whole pixels, and one pixel of overlap, so no seam shows between tiles.
    final tileW = (h * 256 / 112).ceilToDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(end: run.day * step + run.round * step / 8),
      duration: AdvTokens.walk,
      curve: Curves.easeInOut,
      builder: (_, x, __) => ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: double.infinity,
          child: Transform.translate(
            offset: Offset(-(x % tileW), 0),
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                Transform.translate(
                  offset: Offset(-i.toDouble(), 0),
                  child: Image.asset(rpgAsset(layer),
                      width: tileW + 1,
                      height: h,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  /// One day's walk: a waddle from foot to foot with a hop on each step.
  Widget _walkBob(Widget child, {double delay = 0}) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(run.day),
      tween: Tween(begin: 0, end: 1),
      duration: AdvTokens.walk,
      builder: (_, v, c) {
        final k = ((v - delay) / (1 - delay)).clamp(0.0, 1.0);
        final step = math.sin(k * math.pi * 2);
        return Transform.translate(
          offset: Offset(0, -step.abs() * _t[2]),
          child: Transform.rotate(angle: step * 0.09, alignment: Alignment.bottomCenter, child: c),
        );
      },
      child: child,
    );
  }

  Widget _float(_Float fl, double w, double h) {
    final color = switch (fl.fx.kind) {
      FloatKind.hit => AdvTokens.text,
      FloatKind.crit => AdvTokens.goldTop,
      FloatKind.heal || FloatKind.reflect => AdvTokens.rewardText,
      FloatKind.hurt => AdvTokens.hp,
    };
    final x = fl.fx.onFoe ? w * (1 - fl.x) - AdvTokens.sizeFighter * 0.6 : w * (fl.x + 0.1);
    return Positioned(
      left: x,
      top: h * fl.y,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 800),
        builder: (_, v, child) {
          // Pops big, settles, drifts up and fades.
          final pop = v < 0.18
              ? 0.6 + 0.9 * Curves.easeOut.transform(v / 0.18)
              : 1.5 - 0.5 * ((v - 0.18) / 0.82).clamp(0.0, 0.4) / 0.4;
          return Opacity(
            opacity: (v < 0.7 ? 1.0 : (1 - v) / 0.3).clamp(0.0, 1.0),
            child: Transform.translate(
                offset: Offset(0, -Curves.easeOut.transform(v) * _t[6]),
                child: Transform.scale(scale: pop, child: child)),
          );
        },
        child: StrokeText(fl.fx.text, style: AdvTokens.title, color: color),
      ),
    );
  }

  Widget _camera() {
    final lost = run.hold;
    return Positioned(
      right: _t[3],
      top: AdvTokens.sizeEventNext + _t[3],
      width: AdvTokens.sizeLoot,
      height: AdvTokens.sizeLoot * 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AdvTokens.radiusCard),
          border: Border.all(color: lost ? AdvTokens.hp : AdvTokens.outline, width: AdvTokens.strokeOutline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          widget.cameraBuilder!(CustomPaint(painter: SkeletonPainter(_frame, _rep.depthProgress))),
          Align(alignment: Alignment.centerLeft, child: DepthMeter(progress: _rep.depthProgress)),
          if (lost) Center(child: StrokeText(tr('Get in frame'), style: AdvTokens.xs, align: TextAlign.center)),
        ]),
      ),
    );
  }

  Widget _closeButton() {
    return Semantics(
      container: true,
      button: true,
      label: tr('Leave the run. Progress is saved at the end of each day.'),
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          width: AdvTokens.sizeEvent,
          height: AdvTokens.sizeEvent,
          decoration: BoxDecoration(
            color: AdvTokens.surfaceDeep.withOpacity(0.85),
            shape: BoxShape.circle,
            border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeText),
          ),
          child: const Icon(Icons.close, color: AdvTokens.text),
        ),
      ),
    );
  }

  Widget _skills() {
    return Container(
      color: AdvTokens.surfaceDeep,
      padding: EdgeInsets.symmetric(horizontal: _t[3], vertical: _t[1]),
      child: Wrap(spacing: _t[1], runSpacing: _t[1], children: [
        for (final e in run.hero.sk.entries)
          Container(
            padding: EdgeInsets.symmetric(horizontal: _t[2], vertical: _t[1] / 2),
            decoration:
                BoxDecoration(color: AdvTokens.surface, borderRadius: BorderRadius.circular(AdvTokens.radiusPill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(skillIcon(e.key), size: AdvTokens.sizeIcon / 2, color: AdvTokens.goldTop),
              SizedBox(width: _t[1]),
              Text('${tr(skills[e.key]!.name)}${e.value > 1 ? ' ×${e.value}' : ''}',
                  style: AdvTokens.xs.copyWith(color: AdvTokens.text)),
            ]),
          ),
      ]),
    );
  }

  Widget _log() {
    return Container(
      color: AdvTokens.bg,
      child: ListView(
        padding: EdgeInsets.fromLTRB(_t[3], _t[3], _t[3], 0),
        children: [for (final e in run.log) LogCard(e, key: ObjectKey(e))],
      ),
    );
  }

  // ---------------------------------------------------------- the modals

  Widget _overlay(RunOverlay o) {
    switch (o.kind) {
      case OverlayKind.pick:
        final lit = run.litIndex;
        final cycle = (run.pickTime % pickCycle) / pickCycle;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          // The hero, glowing, above the ribbon: a level-up moment.
          RayBurst(
            color: AdvTokens.goldTop,
            size: AdvTokens.sizeLoot * 1.9,
            child: Pop(
              trigger: o.title,
              from: 0.5,
              child: Sprite(run.hero.heroClass.sprite, size: AdvTokens.sizeLoot * 1.25),
            ),
          ),
          Transform.translate(offset: Offset(0, -_t[5]), child: Ribbon(o.title)),
          if (o.subtitle != null) ...[
            SizedBox(height: _t[2]),
            Text(o.subtitle!, textAlign: TextAlign.center, style: AdvTokens.sm.copyWith(color: AdvTokens.text)),
          ],
          SizedBox(height: _t[3]),
          for (var i = 0; i < o.options.length; i++)
            PickCard(option: o.options[i], lit: i == lit, cycle: cycle, onTap: () => run.choose(i)),
          Text(tr('No pushup? Picking the glowing one in {n}s', {'n': run.pickAutoLeft.ceil()}),
              style: AdvTokens.xs.copyWith(color: AdvTokens.textMuted)),
        ]);
      case OverlayKind.wheel:
        // A big wheel on its stand, no banner: the prize shows under it.
        return Semantics(
          label: o.title,
          child: WheelView(index: o.wheelIndex!, result: o.result, spinning: o.spinning),
        );
      case OverlayKind.chest:
        final l = o.loot!;
        final c = rarityColor(l.rarity);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Ribbon(o.title),
          SizedBox(height: _t[4]),
          RayBurst(
            color: c,
            size: (AdvTokens.sizeLoot + _t[4]) * 1.7,
            child: Pop(
              trigger: l.name,
              from: 0.2,
              child: Container(
                width: AdvTokens.sizeLoot + _t[4],
                height: AdvTokens.sizeLoot + _t[4],
                padding: EdgeInsets.all(_t[2]),
                decoration: BoxDecoration(
                  color: AdvTokens.surface,
                  borderRadius: BorderRadius.circular(AdvTokens.radiusTile),
                  border: Border.all(color: c, width: AdvTokens.strokeOutline),
                  boxShadow: [BoxShadow(color: c.withOpacity(0.6), blurRadius: _t[3])],
                ),
                child: Image.asset(rpgAsset(l.img), semanticLabel: l.name, filterQuality: FilterQuality.medium),
              ),
            ),
          ),
          SizedBox(height: _t[2]),
          StrokeText(rarityName(l.rarity), style: AdvTokens.sm, color: c),
          StrokeText(tr(l.name), style: AdvTokens.title),
          Text('+${l.v} ${statName(l.stat)} · ${tr('equipped')}',
              style: AdvTokens.sm.copyWith(color: AdvTokens.rewardText)),
        ]);
      case OverlayKind.clear:
      case OverlayKind.defeat:
        final won = o.kind == OverlayKind.clear;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (won)
            Bob(
              child: Image.asset(rpgAsset('pet_pip'),
                  width: AdvTokens.sizeLoot, height: AdvTokens.sizeLoot, filterQuality: FilterQuality.medium),
            ),
          EndBanner(
            won: won,
            title: o.title,
            survived: o.survived ?? run.day,
            best: o.best ?? run.bestDays,
            note: o.subtitle,
            chapterLabel: '${trChapter(run.chapter.number, run.chapter.roman)} · ${tr(run.chapter.name)}',
          ),
          SizedBox(height: _t[2]),
          Text(tr('{n} pushups this run', {'n': run.reps}), style: AdvTokens.sm.copyWith(color: AdvTokens.rewardText)),
          if (won && _reward != null) ...[
            SizedBox(height: _t[2]),
            Pop(
              trigger: _reward,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // "+2" keeps its sign in front in Arabic too.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: StrokeText('+${_reward!.amount}', style: AdvTokens.lg, color: AdvTokens.goldTop),
                ),
                SizedBox(width: _t[1]),
                CoinIcon(gold: _reward!.gold, size: 30),
                SizedBox(width: _t[1]),
                StrokeText(tr(_reward!.gold ? 'Cinder Coins' : 'Silver coins'), style: AdvTokens.sm, color: AdvTokens.goldTop),
              ]),
            ),
          ],
          if (o.drops.isNotEmpty) ...[
            SizedBox(height: _t[3]),
            StrokeText(tr('Loot'), style: AdvTokens.lg, color: AdvTokens.goldTop),
            SizedBox(height: _t[2]),
            Wrap(spacing: _t[2], runSpacing: _t[2], alignment: WrapAlignment.center, children: [
              // The loot lands one piece at a time.
              for (final (i, d) in o.drops.indexed)
                FadeSlideIn(
                  index: i + 2,
                  step: const Duration(milliseconds: 180),
                  offset: 40,
                  child: GearIcon(d, size: AdvTokens.sizePickTile),
                ),
            ]),
            SizedBox(height: _t[1]),
            Text(tr('Added to your gear. Three of a kind merge into the next rarity.'),
                textAlign: TextAlign.center, style: AdvTokens.xs.copyWith(color: AdvTokens.textMuted)),
          ],
        ]);
      // These two stay on the road: the choice buttons and the chest sit in
      // the scene and the bottom bar, the way the original shows them.
      case OverlayKind.choice:
      case OverlayKind.chestClosed:
        return const SizedBox.shrink();
    }
  }
}
