import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/exercise.dart';
import '../../engine/pose.dart';
import '../../engine/rep_engine.dart';
import '../../online/ranked.dart';
import '../../profile/profile.dart';
import '../../ui/motion.dart';
import '../../ui/rank_widgets.dart';
import '../../ui/pose_overlay.dart';
import '../../ui/theme/rpg_theme.dart';
import 'duel_controller.dart';
import 'duel_math.dart';
import 'duel_models.dart';
import 'pose_frame_source.dart';
import '../../i18n/i18n.dart';

/// The live race screen (1, 3 or 5 minutes), laid out like the source app's live duel:
/// full-screen camera with a skeleton, a frosted scoreboard on top (blue me,
/// red rival, TIME in the middle), a blue/red tug bar under it, and a depth
/// gauge on the right edge.
///
/// Owns the rep engine (verifies my reps), the duel controller (clock + win
/// decision), and a pose source (camera on device, or a fake in a demo). The
/// controller's clock is advanced from a real [Stopwatch] by a [Ticker].
class DuelScreen extends StatefulWidget {
  const DuelScreen({
    super.key,
    required this.bout,
    required this.poseSource,
    this.onBroadcast,
    this.opponentPulses,
    this.cameraBuilder,
    this.startAt,
    this.settle,
    this.onExit,
    this.onTaunt,
    this.opponentTaunts,
    this.onFinished,
  });

  /// Called once with the final result, when the result card comes up.
  final void Function(DuelResult result)? onFinished;

  /// Send a taunt to the rival (online: a realtime broadcast).
  final void Function(String text)? onTaunt;

  /// Taunts the rival throws at me; each shows as a bubble by their avatar.
  final Stream<String>? opponentTaunts;

  final DuelBout bout;
  final PoseFrameSource poseSource;

  /// Push my live pulse to the opponent (wire to DuelService.publishPulse).
  final void Function(LivePulse pulse)? onBroadcast;

  /// Opponent's live pulses (from DuelService, or a fake in a demo). Each one
  /// moves the rival counter and the tug bar.
  final Stream<LivePulse>? opponentPulses;

  /// Builds the full-screen live camera with [overlay] (the skeleton) laid
  /// out in the same frame coordinates, so joints sit on the body. Without
  /// it (demo / web) a still background is shown and the skeleton fills the
  /// screen.
  final Widget Function(Widget overlay)? cameraBuilder;

  /// When the countdown starts, on this phone's clock. Online both phones get
  /// the same instant from the server; offline it is "now".
  final DateTime? startAt;

  /// Asks the server for the final verdict once local time is up. While it
  /// runs the screen shows "Checking result…"; a null answer keeps the local
  /// result.
  final Future<DuelResult?> Function()? settle;

  final VoidCallback? onExit;

  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> with SingleTickerProviderStateMixin {
  late final RepEngine _engine;
  late final DuelController _duel;
  late final Ticker _ticker;
  late final DateTime _startAt;
  bool _settling = false;

  PoseFrame? _frame; // latest pose, for the skeleton
  RepState _rep = const RepState(RepPhase.arming, null, 0, 0);
  int _declared = 0; // raw rep attempts, for the anti-cheat declared count

  // End of race: the rope holds, pauses, then glides to the winner before the
  // result card comes up, as in the source app.
  DateTime? _finishedAt;
  bool _pulled = false;
  bool _reported = false;
  bool _noCamera = false;

  // Taunts and the every-5-reps callout.
  String? _theirTaunt, _myTaunt;
  bool _tray = false;
  int? _callout;

  @override
  void initState() {
    super.initState();
    final profile = ExerciseProfile.defaults[widget.bout.exercise]!;

    _engine = RepEngine(profile, onRep: _onRep);
    _duel = DuelController(
      widget.bout,
      onBroadcast: widget.onBroadcast,
      onPhaseChanged: (_) => setState(() {}),
    );

    widget.poseSource.frames.listen(_onFrame);
    widget.opponentTaunts?.listen((t) => _flash(t, mine: false));
    widget.opponentPulses?.listen((p) {
      _duel.onOpponentPulse(p);
      setState(() {});
    });
    _ticker = createTicker(_onTick);

    _begin();
  }

  Future<void> _begin() async {
    _startAt = widget.startAt ?? DateTime.now();
    _duel.start();
    _ticker.start();
    try {
      await widget.poseSource.start();
    } catch (_) {
      // Refused or missing: the race goes on, but no rep can count.
      if (mounted) setState(() => _noCamera = true);
    }
  }

  void _onTick(Duration _) {
    // Seconds since the shared start instant; negative while both phones are
    // still opening the screen, which shows as a longer countdown.
    final elapsed = DateTime.now().difference(_startAt).inMicroseconds / 1e6;
    _duel.advanceTo(elapsed);
    if (_duel.phase == DuelPhase.finished && _finishedAt == null) {
      _finishedAt = DateTime.now();
      widget.poseSource.stop();
      _askServer();
    }
    if (_finishedAt != null && DateTime.now().difference(_finishedAt!).inMilliseconds >= DuelMath.finalPullBeatMs) {
      _pulled = true;
      _ticker.stop();
    }
    setState(() {});
  }

  Future<void> _askServer() async {
    final settle = widget.settle;
    if (settle == null || _settling) return;
    _settling = true;
    setState(() {});
    final verdict = await settle();
    if (!mounted) return;
    if (verdict != null) _duel.settle(verdict);
    setState(() => _settling = false);
  }

  void _onFrame(PoseFrame frame) {
    // The engine always tracks the body so the skeleton and gauge work while
    // lining up; only reps during the race reach the score.
    _frame = frame;
    _rep = _engine.update(frame);
    if (_duel.phase == DuelPhase.fighting) {
      _duel.onMyRep(verifiedReps: _rep.reps, declaredReps: _declared);
    }
  }

  void _onRep(RepEvent ev) {
    // Every attempt, accepted or not, counts toward "declared" so the server
    // can see counted << declared when someone games the camera.
    _declared += 1;
    if (ev.accepted) {
      _duel.onMyRep(verifiedReps: ev.totalReps, declaredReps: _declared);
      final n = _duel.phase == DuelPhase.fighting ? DuelMath.streakCallout(_duel.myReps) : null;
      if (n != null) {
        _callout = n;
        Future.delayed(const Duration(milliseconds: 1100), () {
          if (mounted && _callout == n) setState(() => _callout = null);
        });
      }
    }
  }

  /// Shows a taunt bubble for a few seconds (mine by my avatar, theirs by theirs).
  void _flash(String text, {required bool mine}) {
    if (!mounted) return;
    setState(() => mine ? _myTaunt = text : _theirTaunt = text);
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      setState(() {
        if (mine && _myTaunt == text) _myTaunt = null;
        if (!mine && _theirTaunt == text) _theirTaunt = null;
      });
    });
  }

  void _sendTaunt(String text) {
    _tray = false;
    widget.onTaunt?.call(text);
    _flash(text, mine: true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.poseSource.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.ltr, child: _build(context));
  }

  Widget _build(BuildContext context) {
    final over = _duel.phase == DuelPhase.finished;
    if (over && _pulled && !_settling && !_reported && _duel.result != null) {
      _reported = true;
      final r = _duel.result!;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onFinished?.call(r));
    }
    return Scaffold(
      backgroundColor: Rpg.bgDeep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.cameraBuilder != null)
            widget.cameraBuilder!(_skeleton())
          else ...[
            Image.asset('assets/rpg/cinder_training_sanctum.jpg', fit: BoxFit.cover),
            _skeleton(),
          ],
          if (_noCamera) _noCameraNote(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
              child: Column(
                children: [
                  _topRow(),
                  const SizedBox(height: 10),
                  _scoreboard(),
                  if (_tray) _tauntTray(),
                  Expanded(
                    child: Stack(children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: FractionallySizedBox(heightFactor: 0.72, child: _depthGauge()),
                      ),
                      if (_callout != null) Align(alignment: const Alignment(0, -0.55), child: _calloutPop(_callout!)),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          if (_duel.phase == DuelPhase.countdown) _countdownOverlay(),
          if (over && _pulled) _settling ? _checkingOverlay() : _resultOverlay(),
        ],
      ),
    );
  }

  /// Shown over the race when the camera can't be used.
  Widget _noCameraNote() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.all(18),
        decoration: Rpg.panel(),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_outlined, color: Rpg.danger, size: 40),
          const SizedBox(height: 8),
          Text(tr('No camera, no reps'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: Rpg.display,
                  fontFamilyFallback: Rpg.arabicDisplay,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Rpg.ink)),
          const SizedBox(height: 4),
          Text(tr('Only the camera can count a push-up. Allow it in your settings and race again.'),
              textAlign: TextAlign.center, style: const TextStyle(color: Rpg.ink2)),
        ]),
      ),
    );
  }

  Widget _skeleton() => CustomPaint(painter: SkeletonPainter(_frame, _rep.depthProgress));

  Widget _topRow() {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: Rpg.bgDeep.withOpacity(0.85),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: widget.onExit,
                child: const SizedBox(width: 40, height: 40, child: Icon(Icons.close, color: Colors.white)),
              ),
            ),
          ),
          const Text(
            'REPRAID',
            style: TextStyle(
              fontFamily: Rpg.body,
              fontFamilyFallback: Rpg.arabic,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: 3,
              color: Rpg.danger,
            ),
          ),
        ],
      ),
    );
  }

  /// Frosted card: me (blue) — TIME — rival (red), and the rope beneath.
  Widget _scoreboard() {
    final b = widget.bout;
    final secs = _duel.secondsLeft;
    final hot = secs <= 10 && _duel.phase == DuelPhase.fighting;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
          color: Rpg.bgDeep.withOpacity(0.45),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _player(b.me, Rpg.mana, bubble: _myTaunt, onTap: () => setState(() => _tray = !_tray)),
                  Expanded(child: _score(_duel.result?.myReps ?? _duel.myReps, Rpg.mana)),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('TIME'),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2, color: Rpg.ink2)),
                        Text(
                          secs >= 60 ? '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}' : '$secs',
                          style: TextStyle(
                            fontFamily: Rpg.body,
                            fontFamilyFallback: Rpg.arabic,
                            fontSize: hot ? 22 : 28,
                            fontWeight: FontWeight.w900,
                            color: hot ? Rpg.danger : Colors.white,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _score(_duel.result?.opponentReps ?? _duel.opponentReps, Rpg.danger)),
                  _player(b.opponent, Rpg.danger, bubble: _theirTaunt),
                ],
              ),
              const SizedBox(height: 12),
              _tugBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _player(DuelPlayer p, Color color, {String? bubble, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Rpg.surface,
                  border: Border.all(color: color, width: 3),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.45), blurRadius: 10)],
                  image: DecorationImage(image: avatarImage(p.photo, fallback: p.avatar), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 4),
              // Long names shrink to fit rather than lose their end.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(p.name,
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white)),
              ),
              Text('${tr('LV')}  ${p.level}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.5, color: color)),
            ],
          ),
          if (bubble != null)
            Positioned(
              top: -6,
              left: color == Rpg.danger ? null : 40,
              right: color == Rpg.danger ? 40 : null,
              child: _bubble(bubble),
            ),
        ]),
      ),
    );
  }

  /// A white speech bubble, the way the rival's taunt shows in the video.
  Widget _bubble(String text) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (_, v, c) => Transform.scale(scale: v, child: c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Text(tr(text),
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Rpg.bgDeep)),
      ),
    );
  }

  /// Taunts to throw: tap your own avatar to open, tap one to send.
  Widget _tauntTray() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (final t in taunts)
            ActionChip(
              label: Text(tr(t), style: const TextStyle(fontWeight: FontWeight.w800, color: Rpg.bgDeep)),
              backgroundColor: Colors.white,
              side: BorderSide.none,
              onPressed: () => setState(() => _sendTaunt(t)),
            ),
        ],
      ),
    );
  }

  /// Big score that pops (scale + fade) every time it changes.
  Widget _score(int value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: Tween(begin: 1.35, end: 1.0).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Text(
            '$value',
            key: ValueKey(value),
            style: TextStyle(
              fontFamily: Rpg.body,
              fontFamilyFallback: Rpg.arabic,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  /// The rope: blue from the left, red from the right, a white knot at the
  /// split. The split follows the lead (not the share of reps), and after the
  /// bell it is pulled across to the winner.
  double get _ropeShare {
    final me = _duel.myReps, them = _duel.opponentReps;
    final end = _finishedAt;
    if (end == null) return DuelMath.tugShare(me, them);
    final ms = DateTime.now().difference(end).inMilliseconds - DuelMath.finalPullHoldMs - DuelMath.finalPullPauseMs;
    return DuelMath.pullShare(me, them, ms / DuelMath.finalPullGlideMs);
  }

  Widget _tugBar() {
    final share = _ropeShare;
    return SizedBox(
      height: 16,
      child: LayoutBuilder(builder: (context, c) {
        return TweenAnimationBuilder<double>(
          tween: Tween(end: share),
          duration: Duration(milliseconds: _finishedAt == null ? 300 : 60),
          curve: Curves.easeOut,
          builder: (context, s, _) {
            final split = c.maxWidth * s;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(color: Rpg.danger, borderRadius: BorderRadius.circular(6)),
                ),
                Container(
                  width: split,
                  decoration: BoxDecoration(color: Rpg.mana, borderRadius: BorderRadius.circular(6)),
                ),
                Positioned(
                  left: (split - 2).clamp(0.0, c.maxWidth - 4),
                  top: -3,
                  bottom: -3,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  /// "DEPTH" over a tall gauge; the white mark is where a rep starts to count.
  Widget _depthGauge() {
    return Column(children: [
      Text(tr('DEPTH'),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Colors.white70)),
      const SizedBox(height: 6),
      Expanded(child: DepthMeter(progress: _rep.depthProgress)),
    ]);
  }

  Widget _calloutPop(int n) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(n),
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (_, v, c) => Transform.scale(scale: v, child: c),
      child: Text(
        '$n 🔥',
        style: const TextStyle(
          fontFamily: Rpg.display,
          fontFamilyFallback: Rpg.arabicDisplay,
          fontSize: 64,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          shadows: [Shadow(color: Rpg.mana, blurRadius: 18)],
        ),
      ),
    );
  }

  Widget _countdownOverlay() {
    final n = _duel.countdownLeft;
    return Container(
      color: Rpg.bgDeep.withOpacity(0.55),
      alignment: Alignment.center,
      child: Text(
        n > 0 ? '$n' : tr('GO!'),
        style: const TextStyle(
            fontFamily: Rpg.display,
            fontFamilyFallback: Rpg.arabicDisplay,
            fontSize: 140,
            fontWeight: FontWeight.w800,
            color: Rpg.gold),
      ),
    );
  }

  Widget _checkingOverlay() {
    return Container(
      color: Rpg.bgDeep.withOpacity(0.8),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Rpg.gold),
          const SizedBox(height: 16),
          Text(tr('Checking result…'),
              style: const TextStyle(
                  fontFamily: Rpg.display,
                  fontFamilyFallback: Rpg.arabicDisplay,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Rpg.ink)),
        ],
      ),
    );
  }

  /// The result card from the video: "YOU WIN", both avatars around the
  /// score, one line on how the rope went, what was saved, and Done.
  Widget _resultOverlay() {
    final r = _duel.result!;
    final b = widget.bout;
    final (head, line, headColor) = switch (r.outcome) {
      DuelOutcome.win => (tr('YOU WIN'), tr('You pulled the rope.'), Rpg.mana),
      DuelOutcome.loss => (tr('YOU LOSE'), tr('They pulled harder this time.'), Rpg.danger),
      DuelOutcome.draw => (tr('DEAD LEVEL'), tr('Dead level. Again?'), Rpg.ink2),
    };
    final saved = r.myReps == 1
        ? tr('1 push-up added to your streak and records.')
        : tr('{n} push-ups added to your streak and records.', {'n': r.myReps});
    return Container(
      color: Rpg.bgDeep.withOpacity(0.35),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B1446), Color(0xFF0E0A26)],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Rpg.mana.withOpacity(0.45), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 30)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(head, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 3, color: headColor)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _resultSide(b.me, Rpg.mana, you: true, glow: r.outcome == DuelOutcome.win),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${r.myReps} – ${r.opponentReps}',
                        style: const TextStyle(
                          fontFamily: Rpg.body,
                          fontFamilyFallback: Rpg.arabic,
                          fontSize: 46,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                _resultSide(b.opponent, Rpg.danger, glow: r.outcome == DuelOutcome.loss),
              ],
            ),
            const SizedBox(height: 18),
            Text(line, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 10),
            Text(saved,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Rpg.ink2)),
            if (r.rank != null) ...[
              const SizedBox(height: 14),
              _rankResult(r.rank!),
            ] else if (widget.settle != null && !r.ranked) ...[
              const SizedBox(height: 10),
              Text(tr('Friendly race: ranks and coins are unchanged.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Rpg.ink3)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: const Color(0xFF07051A),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: widget.onExit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(tr('Done'),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('REPRAID',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 3, color: Rpg.ink3)),
          ],
        ),
      ),
    );
  }

  /// What the race did to my rank: the new badge, rating ± and embers ±,
  /// with a banner when I moved up or down a division.
  Widget _rankResult(RankChange c) {
    final rank = c.newRank;
    final up = c.delta >= 0;
    final banner = c.promoted ? tr('RANK UP!') : c.demoted ? tr('Rank down') : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF07051A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: rank.tier.light.withOpacity(0.7), width: 1.5),
      ),
      child: Column(children: [
        if (banner != null) ...[
          Pop(
            trigger: banner,
            child: Text(banner,
                style: TextStyle(
                    fontFamily: Rpg.display,
                    fontFamilyFallback: Rpg.arabicDisplay,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: c.promoted ? rank.tier.light : Rpg.danger)),
          ),
          const SizedBox(height: 6),
        ],
        Row(children: [
          RankBadge(rank, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rank.name,
                  style: TextStyle(
                      fontFamily: Rpg.display,
                      fontFamilyFallback: Rpg.arabicDisplay,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: rank.tier.light)),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, k, __) => Text(
                  '${(c.before + c.delta * k).round()}  (${up ? '+' : '−'}${c.delta.abs()})',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontWeight: FontWeight.w800, color: up ? Rpg.vigor : Rpg.danger),
                ),
              ),
            ]),
          ),
          for (final (gold, n) in [(true, c.gold), (false, c.silver)])
            if (n != 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${n > 0 ? '+' : '−'}${n.abs()}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          fontFamily: Rpg.display,
                          fontFamilyFallback: Rpg.arabicDisplay,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: n < 0 ? Rpg.danger : gold ? const Color(0xFFFFD27A) : const Color(0xFFE8EEF6))),
                  const SizedBox(width: 4),
                  CoinIcon(gold: gold, size: 26),
                ]),
              ),
        ]),
      ]),
    );
  }

  Widget _resultSide(DuelPlayer p, Color ring, {bool you = false, bool glow = false}) {
    return SizedBox(
      width: 96,
      child: Column(children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Rpg.surface,
            border: Border.all(color: glow ? ring : Rpg.border2, width: 3),
            boxShadow: glow ? [BoxShadow(color: ring.withOpacity(0.6), blurRadius: 14)] : null,
            image: DecorationImage(image: avatarImage(p.photo, fallback: p.avatar), fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(p.name,
              maxLines: 1,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: you ? Colors.white : Rpg.ink2)),
        ),
        if (you) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: Rpg.surface3, borderRadius: BorderRadius.circular(999)),
            child: Text(tr('YOU'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2, color: Rpg.ink2)),
          ),
        ],
      ]),
    );
  }
}
