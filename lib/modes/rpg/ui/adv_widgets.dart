// The adventure's widget kit, one class per block in replica/design/components.md.
// Colours, sizes and type come from AdvTokens only.

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Hero;
import 'package:flutter/semantics.dart';

import '../../../ui/theme/adventure_tokens.dart';
import '../adventure_rules.dart';
import '../run_controller.dart';
import '../../../i18n/i18n.dart';
import '../../../ui/motion.dart';

const _t = AdvTokens.space;
const _outlineSide = BorderSide(color: AdvTokens.outline, width: AdvTokens.strokeOutline);

/// The painted adventure art lives in assets/art; anything else in assets/rpg.
String rpgAsset(String name) {
  if (name.endsWith('.jpg') || name.endsWith('.png')) return 'assets/rpg/$name';
  const art = ['foe_', 'hero_', 'pet_', 'gear_', 'bg_'];
  return art.any(name.startsWith) ? 'assets/art/$name.webp' : 'assets/rpg/$name.png';
}

/// Display text with a dark outline, the way every casual-game label reads.
class StrokeText extends StatelessWidget {
  const StrokeText(this.text,
      {super.key, this.style = AdvTokens.lg, this.color = AdvTokens.text, this.stroke, this.align});
  final String text;
  final TextStyle style;
  final Color color;
  final double? stroke;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) {
    final w = stroke ?? AdvTokens.strokeText;
    // The outline copy is decoration: screen readers hear the text once.
    return Stack(children: [
      ExcludeSemantics(
        child: Text(text,
            textAlign: align,
            style: style.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = w * 2
                  ..strokeJoin = StrokeJoin.round
                  ..color = AdvTokens.outline)),
      ),
      Text(text, textAlign: align, style: style.copyWith(color: color)),
    ]);
  }
}

// ------------------------------------------------------------ ActionButton

enum ActionVariant { go, strike, pick, orange, wait }

ActionVariant variantFor(RunMode m) => switch (m) {
      RunMode.walk || RunMode.card || RunMode.over => ActionVariant.go,
      RunMode.fight => ActionVariant.strike,
      RunMode.pick || RunMode.spin => ActionVariant.pick,
      RunMode.busy => ActionVariant.wait,
    };

class ActionButton extends StatefulWidget {
  const ActionButton({super.key, required this.variant, required this.label, required this.sub, this.onPressed});
  final ActionVariant variant;
  final String label, sub;
  final VoidCallback? onPressed;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _down = false;

  @override
  void didUpdateWidget(ActionButton old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label) {
      SemanticsService.announce(widget.label, TextDirection.ltr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.variant != ActionVariant.wait && widget.onPressed != null;
    final (top, bottom, ink) = switch (widget.variant) {
      ActionVariant.go => (AdvTokens.accentTop, AdvTokens.accent, AdvTokens.onAccent),
      ActionVariant.strike => (AdvTokens.dangerTop, AdvTokens.danger, AdvTokens.onDanger),
      ActionVariant.pick => (AdvTokens.goldTop, AdvTokens.gold, AdvTokens.onGold),
      ActionVariant.orange => (AdvTokens.orangeTop, AdvTokens.orange, AdvTokens.onAccent),
      ActionVariant.wait => (AdvTokens.waitTop, AdvTokens.waitBottom, AdvTokens.text.withOpacity(0.75)),
    };
    final drop = _down ? _t[1] / 2 : _t[1];
    return FractionallySizedBox(
      widthFactor: AdvTokens.sizeButtonWidth,
      child: Semantics(
        container: true,
        button: true,
        enabled: enabled,
        label: '${widget.label}, ${widget.sub}',
        excludeSemantics: true,
        child: FocusableActionDetector(
          enabled: enabled,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed?.call()),
          },
          child: Builder(builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              onTapDown: enabled ? (_) => setState(() => _down = true) : null,
              onTapCancel: () => setState(() => _down = false),
              onTapUp: enabled
                  ? (_) {
                      setState(() => _down = false);
                      widget.onPressed?.call();
                    }
                  : null,
              child: AnimatedContainer(
                duration: AdvTokens.hit ~/ 3,
                height: AdvTokens.sizeButton,
                margin: EdgeInsets.only(top: _t[1] - drop),
                decoration: BoxDecoration(
                  gradient:
                      LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
                  borderRadius: BorderRadius.circular(AdvTokens.radiusPill),
                  border:
                      Border.all(color: focused ? AdvTokens.focus : AdvTokens.outline, width: AdvTokens.strokeOutline),
                  boxShadow: [BoxShadow(color: AdvTokens.outline, offset: Offset(0, drop))],
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    widget.variant == ActionVariant.pick
                        ? Text(widget.label, style: AdvTokens.button.copyWith(color: ink))
                        : StrokeText(widget.label, style: AdvTokens.button, color: ink),
                    Text(widget.sub,
                        style: AdvTokens.xs
                            .copyWith(color: widget.variant == ActionVariant.pick ? ink : ink.withOpacity(0.9))),
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- Ribbon

class Ribbon extends StatelessWidget {
  const Ribbon(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: _t[5], vertical: _t[1]),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AdvTokens.goldTop, AdvTokens.gold]),
          borderRadius: BorderRadius.circular(AdvTokens.radiusCard),
          border: const Border.fromBorderSide(_outlineSide),
        ),
        child: StrokeText(title, style: AdvTokens.title.copyWith(fontSize: AdvTokens.lg.fontSize! * 1.3)),
      ),
    );
  }
}

// ---------------------------------------------------------------- LogCard

/// Body text where *name* is drawn in the keyword colour.
TextSpan richBody(String body, TextStyle style, {Color keyword = AdvTokens.keyword}) {
  final parts = body.split('*');
  return TextSpan(style: style, children: [
    for (var i = 0; i < parts.length; i++)
      TextSpan(text: parts[i], style: i.isOdd ? TextStyle(color: keyword, fontWeight: FontWeight.w900) : null),
  ]);
}

class LogCard extends StatelessWidget {
  const LogCard(this.entry, {super.key});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    // Foes are named in red, everything friendly in blue.
    final word = entry.kind == LogKind.fight ? AdvTokens.foeWord : AdvTokens.friendWord;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: _t[2]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.only(left: _t[1], bottom: _t[1] / 2),
            child: Text(entry.head, style: AdvTokens.sm.copyWith(color: AdvTokens.text, fontWeight: FontWeight.w900)),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(_t[3], _t[3], _t[3], _t[3]),
            decoration: BoxDecoration(
              color: AdvTokens.paper,
              borderRadius: BorderRadius.circular(AdvTokens.radiusCard / 2),
              border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeOutline),
              boxShadow: const [BoxShadow(color: AdvTokens.outline, offset: Offset(0, 3))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(richBody(entry.body, AdvTokens.sm.copyWith(color: AdvTokens.textOnCard), keyword: word)),
              if (entry.tag != null && entry.tag!.isNotEmpty) ...[
                SizedBox(height: _t[1]),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: _t[2], vertical: _t[1] / 2),
                  decoration: BoxDecoration(
                      color: AdvTokens.rewardBg, borderRadius: BorderRadius.circular(AdvTokens.radiusPill)),
                  child: Text(entry.tag!, style: AdvTokens.xs.copyWith(color: AdvTokens.rewardText)),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: _t[2], vertical: _t[1] / 2),
        decoration: BoxDecoration(
          color: AdvTokens.bandChip,
          borderRadius: BorderRadius.circular(AdvTokens.radiusPill),
          border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeText),
        ),
        child: child,
      );
}

class Track extends StatelessWidget {
  const Track({super.key, required this.value, required this.color, this.height = AdvTokens.sizeBar, this.label});
  final double value;
  final Color color;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AdvTokens.surfaceDeep,
        borderRadius: BorderRadius.circular(AdvTokens.radiusPill),
        border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeText),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: AnimatedContainer(duration: AdvTokens.hit, color: color),
        ),
        if (label != null) Center(child: StrokeText(label!, style: AdvTokens.xs, stroke: AdvTokens.strokeText / 2)),
      ]),
    );
  }
}

class StatBar extends StatelessWidget {
  const StatBar(this.hero, {super.key});
  final Hero hero;

  @override
  Widget build(BuildContext context) {
    final h = hero;
    final pct = (100 * h.hp / h.max).round();
    return Semantics(
      label: tr('Level {lv}, HP {hp} of {max}, attack {atk}, defence {def}',
          {'lv': h.lv, 'hp': h.hp, 'max': h.max, 'atk': h.atk, 'def': h.def}),
      excludeSemantics: true,
      child: Container(
        height: AdvTokens.sizeStatBand,
        padding: EdgeInsets.symmetric(horizontal: _t[3]),
        decoration: const BoxDecoration(
          color: AdvTokens.band,
          border: Border(
            top: BorderSide(color: AdvTokens.bandTop, width: AdvTokens.strokeOutline * 2),
            bottom: _outlineSide,
          ),
        ),
        child: Row(children: [
          _Labeled(
              tr('EXP'),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _Pill(child: Text('${tr('Lv.')}${h.lv}', style: AdvTokens.xs.copyWith(color: AdvTokens.xp))),
                SizedBox(width: _t[1]),
                SizedBox(
                    width: AdvTokens.sizeEvent,
                    child: Track(value: h.xp / xpPerLevel, color: AdvTokens.xp, height: AdvTokens.sizeBarThin * 2)),
              ])),
          SizedBox(width: _t[2]),
          Expanded(
            child: _Labeled(
                tr('HP'),
                Row(children: [
                  const Icon(Icons.favorite, color: AdvTokens.hp, size: AdvTokens.sizeIcon * 0.8),
                  SizedBox(width: _t[1]),
                  Expanded(
                      child: Track(
                          value: h.hp / h.max,
                          color: AdvTokens.hp,
                          height: AdvTokens.sizeHpBar + _t[1],
                          label: '$pct%  ${h.hp}/${h.max}')),
                ])),
          ),
          SizedBox(width: _t[2]),
          _Labeled(
              tr('ATK'),
              _Pill(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.flash_on, color: AdvTokens.goldTop, size: AdvTokens.sizeIcon / 2),
                Text('${h.atk}', style: AdvTokens.xs.copyWith(color: AdvTokens.text)),
              ]))),
          SizedBox(width: _t[1]),
          _Labeled(
              tr('DEF'),
              _Pill(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.shield, color: AdvTokens.cardBorder, size: AdvTokens.sizeIcon / 2),
                Text('${h.def}', style: AdvTokens.xs.copyWith(color: AdvTokens.text)),
              ]))),
        ]),
      ),
    );
  }
}

/// A stat with its small caption above it, as in the original's stat band.
class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child);
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AdvTokens.micro.copyWith(color: AdvTokens.textMuted)),
          SizedBox(height: _t[1] / 2),
          child,
        ],
      );
}

// --------------------------------------------------------------- DayStrip

IconData nodeIcon(String node) => switch (node) {
      'story' => Icons.auto_stories,
      'skill' => Icons.auto_awesome,
      'wheel' => Icons.casino,
      'chest' => Icons.inventory_2,
      'choice' => Icons.call_split,
      _ => Icons.help,
    };

class EventIcon extends StatelessWidget {
  const EventIcon(this.node, {super.key, this.size = AdvTokens.sizeEvent, this.ring = false, this.chapter});
  final String node;

  /// Whose foes the icons show (defaults to the first world).
  final ChapterDef? chapter;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final isFoe = node.startsWith('foe:') || node == 'boss';
    final ch = chapter ?? chapters.first;
    final art = node == 'boss'
        ? ch.boss.img
        : isFoe
            ? ch.foes[int.parse(node.substring(4).replaceAll('+', ''))].img
            : null;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size / 10),
      decoration: BoxDecoration(
        color: node == 'boss' ? AdvTokens.hp : AdvTokens.card,
        shape: BoxShape.circle,
        border: Border.all(color: ring ? AdvTokens.goldTop : AdvTokens.outline, width: AdvTokens.strokeOutline),
      ),
      child: art != null
          ? Image.asset(rpgAsset(art), fit: BoxFit.contain, filterQuality: FilterQuality.medium)
          : Icon(nodeIcon(node), color: AdvTokens.cardHead, size: size * 0.55),
    );
  }
}

class DayStrip extends StatelessWidget {
  const DayStrip({super.key, required this.day, required this.upcoming, this.chapter});
  final int day;
  final ChapterDef? chapter;
  final List<String> upcoming;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Pill(child: StrokeText(tr('Day {n}', {'n': day}), style: AdvTokens.lg)),
      SizedBox(width: _t[2]),
      Expanded(
        child: Stack(alignment: Alignment.centerLeft, children: [
          Container(height: AdvTokens.sizeBarThin, color: AdvTokens.gold),
          // Narrow phones shrink the icons rather than cut the strip off.
          if (upcoming.isNotEmpty)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < upcoming.length; i++) ...[
                  if (i > 0) SizedBox(width: _t[2]),
                  EventIcon(upcoming[i],
                      chapter: chapter, size: i == 0 ? AdvTokens.sizeEventNext : AdvTokens.sizeEvent, ring: i == 0),
                ],
              ]),
            ),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------- FighterBar

class FighterBar extends StatelessWidget {
  const FighterBar({super.key, required this.value, required this.label, required this.foe, this.clock});
  final double value;
  final String label;
  final bool foe;

  /// 0..1: how close the foe is to its next attack.
  final double? clock;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AdvTokens.sizeFighter * 0.9,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Track(value: value, color: foe ? AdvTokens.hp : AdvTokens.accentTop),
        if (clock != null) ...[
          SizedBox(height: _t[1] / 2),
          Track(value: clock!, color: AdvTokens.xp, height: AdvTokens.sizeBarThin),
        ],
        StrokeText(label, style: AdvTokens.xs),
      ]),
    );
  }
}

// --------------------------------------------------------------- PickCard

class PickCard extends StatelessWidget {
  const PickCard({
    super.key,
    required this.option,
    required this.lit,
    required this.cycle,
    required this.onTap,
  });
  final PickOption option;
  final bool lit;

  /// 0..1 progress of the glow on this card.
  final double cycle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rarity = option.skill == null ? null : skills[option.skill]!.rarity;
    final tone = rarity == null ? AdvTokens.gold : rarityColor(rarity);
    return Semantics(
      container: true,
      button: true,
      selected: lit,
      label: '${option.title}. ${option.text}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          duration: AdvTokens.hit,
          scale: lit ? 1.04 : 1,
          child: Container(
            margin: EdgeInsets.only(bottom: _t[3]),
            padding: EdgeInsets.fromLTRB(_t[2], _t[2], _t[3], _t[2]),
            // Cream paper with a dark rim; the one a pushup takes glows gold,
            // the others sit under a light veil.
            foregroundDecoration: lit
                ? null
                : BoxDecoration(
                    color: AdvTokens.surfaceDeep.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(AdvTokens.radiusCard / 2),
                  ),
            decoration: BoxDecoration(
              color: AdvTokens.paper,
              borderRadius: BorderRadius.circular(AdvTokens.radiusCard / 2),
              border: Border.all(color: lit ? AdvTokens.goldTop : AdvTokens.outline, width: AdvTokens.strokeOutline),
              boxShadow: [
                const BoxShadow(color: AdvTokens.outline, offset: Offset(0, 3)),
                if (lit) BoxShadow(color: AdvTokens.gold.withOpacity(0.7), blurRadius: _t[4], spreadRadius: _t[1] / 2),
              ],
            ),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Square icon tile in the skill's rarity colour.
                Container(
                  width: AdvTokens.sizePickTile,
                  height: AdvTokens.sizePickTile,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(tone, AdvTokens.flash, 0.35)!, tone],
                    ),
                    borderRadius: BorderRadius.circular(AdvTokens.radiusCard / 2),
                    border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeOutline),
                  ),
                  child: Icon(skillIcon(option.skill),
                      color: AdvTokens.flash,
                      size: AdvTokens.sizeIcon,
                      shadows: const [Shadow(color: AdvTokens.outline, offset: Offset(0, 2))]),
                ),
                SizedBox(width: _t[3]),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (rarity != null) RarityTag(rarity),
                    Text(option.title,
                        style: AdvTokens.lg.copyWith(color: AdvTokens.textOnCard, fontWeight: FontWeight.w900)),
                    Text.rich(richBody(option.text, AdvTokens.xs.copyWith(color: AdvTokens.textOnCard),
                        keyword: AdvTokens.friendWord)),
                  ]),
                ),
              ]),
              if (lit) ...[
                SizedBox(height: _t[1]),
                Track(value: cycle, color: AdvTokens.gold, height: AdvTokens.sizeBarThin),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

IconData skillIcon(String? key) => switch (key) {
      'edge' => Icons.flash_on,
      'hide' => Icons.favorite,
      'guard' => Icons.shield,
      'eye' => Icons.visibility,
      'twin' => Icons.content_copy,
      'leech' => Icons.water_drop,
      'thorns' => Icons.grass,
      'spark' => Icons.bolt,
      'wind' => Icons.air,
      _ => Icons.alt_route,
    };

// ------------------------------------------------------------------ Wheel

class WheelView extends StatelessWidget {
  const WheelView({super.key, required this.index, this.result, this.spinning = true});
  final int index;
  final String? result;

  /// False while the wheel waits for the pushup that spins it.
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final n = wheel.length;
    // Stop with slice [index] under the pointer at the top.
    final end = 5 * 2 * math.pi + (2 * math.pi - (index + 0.5) * 2 * math.pi / n);
    const size = AdvTokens.sizeWheel;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: size,
        height: size * 1.12,
        child: Stack(alignment: Alignment.topCenter, children: [
          // A wooden stand the wheel turns on.
          const Positioned(
            bottom: 0,
            child: CustomPaint(size: Size(size * 0.7, size * 0.3), painter: _WheelStandPainter()),
          ),
          Positioned(
            top: size * 0.04,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: spinning ? end : 0),
              duration: AdvTokens.wheel,
              curve: const Cubic(.15, .85, .2, 1),
              builder: (_, a, __) => Transform.rotate(
                angle: a,
                child: CustomPaint(size: const Size.square(size * 0.94), painter: _WheelPainter()),
              ),
            ),
          ),
          Positioned(
            top: size * 0.04 + size * 0.47 - AdvTokens.sizeIcon / 2,
            child: Container(
              width: AdvTokens.sizeIcon,
              height: AdvTokens.sizeIcon,
              decoration: const BoxDecoration(
                gradient: RadialGradient(colors: [AdvTokens.goldTop, AdvTokens.gold]),
                shape: BoxShape.circle,
                border: Border.fromBorderSide(_outlineSide),
              ),
            ),
          ),
          // The red pin at the top that points at the prize.
          const Positioned(top: 0, child: CustomPaint(size: Size(30, 40), painter: _PinPainter())),
        ]),
      ),
      SizedBox(height: _t[2]),
      StrokeText(result ?? (spinning ? tr('Spinning…') : tr('A pushup spins it!')), style: AdvTokens.lg),
    ]);
  }
}

/// The picture on each slice of the wheel.
IconData wheelIcon(WheelSlice s) {
  if (s.skill) return Icons.question_mark;
  if (s.xp > 0) return Icons.diamond;
  if (s.label.startsWith('Heal')) return Icons.healing;
  if (s.label.startsWith('ATK')) return Icons.flash_on;
  return Icons.favorite;
}

class _WheelPainter extends CustomPainter {
  // Warm alternating slices, like painted wood.
  static const _fills = [
    Color(0xFFF6E3B4),
    Color(0xFFF0A23A),
    Color(0xFF7CC64E),
    Color(0xFFE9604E),
    Color(0xFFF6E3B4),
    Color(0xFF5FA8E8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rim = size.width * 0.07;
    final r = size.width / 2 - rim;
    final n = wheel.length, sweep = 2 * math.pi / n;
    final rect = Rect.fromCircle(center: c, radius: r);
    // Wooden rim with gold studs.
    canvas.drawCircle(c, size.width / 2, Paint()..color = AdvTokens.outline);
    canvas.drawCircle(c, size.width / 2 - 3, Paint()..color = const Color(0xFF8A5A34));
    canvas.drawCircle(c, size.width / 2 - rim * 0.55, Paint()..color = const Color(0xFFA8703F));
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final p = c + Offset(math.cos(a), math.sin(a)) * (size.width / 2 - rim * 0.5);
      canvas.drawCircle(p, rim * 0.22 + 1.5, Paint()..color = AdvTokens.outline);
      canvas.drawCircle(p, rim * 0.22, Paint()..color = AdvTokens.goldTop);
    }
    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * sweep;
      final fill = _fills[i % _fills.length];
      canvas.drawArc(rect, start, sweep, true, Paint()..color = fill);
      canvas.drawArc(
          rect,
          start,
          sweep,
          true,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = AdvTokens.strokeText
            ..color = const Color(0xFF6A4226));
      final mid = start + sweep / 2;
      final light = fill.computeLuminance() > 0.5;
      // The slice's picture, upright toward the rim, in a dark-rimmed badge.
      final icon = wheelIcon(wheel[i]);
      canvas.save();
      canvas.translate(c.dx + math.cos(mid) * r * 0.45, c.dy + math.sin(mid) * r * 0.45);
      canvas.rotate(mid + math.pi / 2);
      canvas.drawCircle(Offset.zero, r * 0.16, Paint()..color = AdvTokens.outline.withOpacity(0.85));
      final ip = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
              fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: r * 0.2, color: AdvTokens.flash),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      ip.paint(canvas, Offset(-ip.width / 2, -ip.height / 2));
      canvas.restore();
      canvas.save();
      canvas.translate(c.dx + math.cos(mid) * r * 0.76, c.dy + math.sin(mid) * r * 0.76);
      canvas.rotate(mid + math.pi / 2);
      final tp = TextPainter(
        text: TextSpan(
            text: tr(wheel[i].label),
            style: AdvTokens.xs
                .copyWith(color: light ? AdvTokens.textOnCard : AdvTokens.text, fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: r * 0.6);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AdvTokens.outline);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => false;
}

class _WheelStandPainter extends CustomPainter {
  const _WheelStandPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(s.width * 0.3, 0)
      ..lineTo(s.width * 0.7, 0)
      ..lineTo(s.width * 0.95, s.height * 0.8)
      ..lineTo(s.width * 0.05, s.height * 0.8)
      ..close();
    canvas.drawPath(path, Paint()..color = AdvTokens.outline);
    canvas.drawPath(path.shift(const Offset(0, -3)), Paint()..color = const Color(0xFF8A5A34));
    final base =
        RRect.fromRectAndRadius(Rect.fromLTWH(0, s.height * 0.72, s.width, s.height * 0.28), const Radius.circular(8));
    canvas.drawRRect(base, Paint()..color = AdvTokens.outline);
    canvas.drawRRect(base.deflate(3), Paint()..color = const Color(0xFF6A4226));
  }

  @override
  bool shouldRepaint(_WheelStandPainter old) => false;
}

class _PinPainter extends CustomPainter {
  const _PinPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(s.width / 2, s.height)
      ..quadraticBezierTo(0, s.height * 0.45, s.width * 0.1, s.height * 0.3)
      ..arcToPoint(Offset(s.width * 0.9, s.height * 0.3), radius: Radius.circular(s.width * 0.42))
      ..quadraticBezierTo(s.width, s.height * 0.45, s.width / 2, s.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AdvTokens.outline);
    canvas.drawPath(
        path.shift(const Offset(0, -2)).transform((Matrix4.identity()
              ..translate(s.width / 2, s.height / 2)
              ..scale(0.82)
              ..translate(-s.width / 2, -s.height / 2))
            .storage),
        Paint()..color = AdvTokens.hp);
    canvas.drawCircle(Offset(s.width / 2, s.height * 0.32), s.width * 0.14, Paint()..color = AdvTokens.flash);
  }

  @override
  bool shouldRepaint(_PinPainter old) => false;
}

// ----------------------------------------------------------------- Sprite

/// A creature drawn facing the viewer, turned a little toward the hero on
/// its left: a perspective turn where its far (right) side recedes, so the
/// two fighters look at each other.
class TurnToHero extends StatelessWidget {
  const TurnToHero({super.key, required this.child, this.on = true});
  final Widget child;
  final bool on;

  static const _angle = 0.42;

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    return Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0018)
        ..rotateY(_angle),
      child: child,
    );
  }
}

/// A creature not met yet: its dark silhouette with a pulsing question mark.
class MysterySprite extends StatelessWidget {
  const MysterySprite(this.asset, {super.key, required this.size, this.mark = true});
  final String asset;
  final double size;

  /// Draws the "?" over the silhouette (small chips may leave it off).
  final bool mark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        ColorFiltered(
          colorFilter: const ColorFilter.mode(AdvTokens.mystery, BlendMode.srcIn),
          child: Image.asset(rpgAsset(asset),
              width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
        ),
        if (mark)
          Pulse(
            amount: 0.12,
            child: StrokeText('?',
                style: AdvTokens.title.copyWith(fontSize: size * 0.42, height: 1),
                color: AdvTokens.goldTop,
                stroke: AdvTokens.strokeOutline),
          ),
      ]),
    );
  }
}

/// A short label of a foe's ability, shown under its name in a fight.
class AbilityTag extends StatelessWidget {
  const AbilityTag(this.ability, {super.key});
  final FoeAbility ability;

  @override
  Widget build(BuildContext context) {
    if (ability == FoeAbility.none) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(bottom: _t[1] / 2),
      padding: EdgeInsets.symmetric(horizontal: _t[1], vertical: 1),
      decoration: BoxDecoration(
        color: AdvTokens.surfaceDeep.withOpacity(0.8),
        borderRadius: BorderRadius.circular(AdvTokens.radiusPill),
        border: Border.all(color: AdvTokens.ability, width: AdvTokens.strokeText),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(abilityIcon(ability), size: AdvTokens.xs.fontSize! * 1.2, color: AdvTokens.ability),
        SizedBox(width: _t[1] / 2),
        Text(tr(ability.label), style: AdvTokens.xs.copyWith(color: AdvTokens.text)),
      ]),
    );
  }
}

IconData abilityIcon(FoeAbility a) => switch (a) {
      FoeAbility.regen => Icons.spa,
      FoeAbility.stoneSkin => Icons.shield,
      FoeAbility.frenzy => Icons.bolt,
      FoeAbility.drain => Icons.water_drop,
      FoeAbility.venom => Icons.coronavirus,
      FoeAbility.breath => Icons.local_fire_department,
      FoeAbility.hex => Icons.auto_fix_high,
      FoeAbility.evasive => Icons.air,
      FoeAbility.none => Icons.circle,
    };

class Sprite extends StatelessWidget {
  const Sprite(this.asset,
      {super.key, required this.size, this.flip = false, this.flash = 0, this.tint, this.tintAmount = 0});
  final String asset;
  final double size;
  final bool flip;

  /// 0..1: the whole body turns white when hit.
  final double flash;

  /// A colour washed over the body (poison, frenzy), [tintAmount] 0..1.
  final Color? tint;
  final double tintAmount;

  @override
  Widget build(BuildContext context) {
    final painted = rpgAsset(asset).startsWith('assets/art/');
    final img = Image.asset(rpgAsset(asset),
        width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    // Painted sprites carry their own dark rim; other art gets four offset dark
    // copies. A soft ellipse is the ground shadow.
    final outline = painted
        ? const <Widget>[]
        : [
            for (final o in const [Offset(-1, 0), Offset(1, 0), Offset(0, -1), Offset(0, 1)])
              Transform.translate(
                offset: o * AdvTokens.strokeText,
                child:
                    ColorFiltered(colorFilter: const ColorFilter.mode(AdvTokens.outline, BlendMode.srcIn), child: img),
              ),
          ];
    return Transform.flip(
      flipX: flip,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: size * 0.2,
            right: size * 0.2,
            bottom: -_t[1],
            height: _t[3],
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: AdvTokens.outline.withOpacity(0.25),
                    borderRadius: BorderRadius.all(Radius.elliptical(size, _t[3])))),
          ),
          ...outline,
          img,
          // A flat colour silhouette over the picture: white for a hit, a
          // status colour for poison or frenzy.
          if (tint != null && tintAmount > 0)
            Opacity(
              opacity: tintAmount.clamp(0.0, 1.0),
              child: ColorFiltered(colorFilter: ColorFilter.mode(tint!, BlendMode.srcIn), child: img),
            ),
          if (flash > 0)
            Opacity(
              opacity: flash.clamp(0.0, 1.0),
              child: ColorFiltered(colorFilter: const ColorFilter.mode(AdvTokens.flash, BlendMode.srcIn), child: img),
            ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Modal

class EventModal extends StatelessWidget {
  const EventModal({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(colors: [
          AdvTokens.surfaceDeep.withOpacity(0.9),
          AdvTokens.surfaceDeep.withOpacity(0.97),
        ]),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(_t[4]),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AdvTokens.sizeMaxWidth - 80),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- Banner

class BannerText extends StatelessWidget {
  const BannerText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    // Swoops in from the left on a slant, overshoots, settles.
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      builder: (_, v, child) {
        final slide = Curves.easeOutCubic.transform(v);
        final pop = Curves.easeOutBack.transform(v);
        return Transform.translate(
          offset: Offset((1 - slide) * -AdvTokens.sizeSpriteBoss * 1.6, 0),
          child: Transform.rotate(
            angle: -0.08,
            child: Transform.scale(scale: 0.5 + 0.5 * pop, child: Opacity(opacity: slide, child: child)),
          ),
        );
      },
      child: StrokeText(text, style: AdvTokens.banner, color: AdvTokens.goldTop, stroke: AdvTokens.strokeOutline),
    );
  }
}

// -------------------------------------------------------------- RarityTag

Color rarityColor(Rarity r) => switch (r) {
      Rarity.common => AdvTokens.rareCommon,
      Rarity.uncommon => AdvTokens.rareUncommon,
      Rarity.rare => AdvTokens.rareRare,
      Rarity.epic => AdvTokens.rareEpic,
      Rarity.legendary => AdvTokens.rareLegend,
      Rarity.mythic => AdvTokens.rareMythic,
    };

class RarityTag extends StatelessWidget {
  const RarityTag(this.rarity, {super.key});
  final Rarity rarity;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: _t[2], vertical: 1),
        decoration: BoxDecoration(
          color: rarityColor(rarity),
          borderRadius: BorderRadius.circular(AdvTokens.radiusPill),
          border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeText / 2),
        ),
        child: Text(rarityName(rarity), style: AdvTokens.micro.copyWith(color: AdvTokens.outline)),
      );
}

// ------------------------------------------------------------ ChoiceButton

/// One side of a two-way choice: an orange button with its effect underneath,
/// lit while the glow is on it (a pushup takes the lit one).
class ChoiceButton extends StatelessWidget {
  const ChoiceButton({super.key, required this.option, required this.lit, required this.onTap});
  final PickOption option;
  final bool lit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: lit,
      label: '${option.title}: ${option.text}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          duration: AdvTokens.hit,
          scale: lit ? 1.05 : 0.95,
          child: Container(
            height: AdvTokens.sizeButton + _t[3],
            padding: EdgeInsets.symmetric(horizontal: _t[2], vertical: _t[1]),
            foregroundDecoration: lit
                ? null
                : BoxDecoration(
                    color: AdvTokens.surfaceDeep.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(AdvTokens.radiusTile)),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AdvTokens.orangeTop, AdvTokens.orange]),
              borderRadius: BorderRadius.circular(AdvTokens.radiusTile),
              border: Border.all(color: lit ? AdvTokens.goldTop : AdvTokens.outline, width: AdvTokens.strokeOutline),
              boxShadow: [
                BoxShadow(color: AdvTokens.outline, offset: Offset(0, _t[1])),
                if (lit) BoxShadow(color: AdvTokens.gold.withOpacity(0.8), blurRadius: _t[4]),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                StrokeText(option.title, style: AdvTokens.lg),
                SizedBox(height: _t[1] / 2),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: _t[2], vertical: 1),
                  decoration: BoxDecoration(
                      color: AdvTokens.rewardBg, borderRadius: BorderRadius.circular(AdvTokens.radiusPill)),
                  child: Text(option.text, style: AdvTokens.xs.copyWith(color: AdvTokens.rewardText)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Chest

/// RepRaid's own chest, drawn in code: wood, gold bands, a lock.
class ChestSprite extends StatelessWidget {
  const ChestSprite({super.key, this.size = AdvTokens.sizeChest});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size * 0.8), painter: _ChestPainter());
}

class _ChestPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AdvTokens.strokeOutline
      ..strokeJoin = StrokeJoin.round
      ..color = AdvTokens.outline;
    final body = RRect.fromLTRBR(w * .06, h * .42, w * .94, h * .96, Radius.circular(w * .06));
    final lid = RRect.fromLTRBAndCorners(w * .06, h * .1, w * .94, h * .46,
        topLeft: Radius.circular(w * .3), topRight: Radius.circular(w * .3));
    final gold = Paint()..color = AdvTokens.goldTop;
    canvas.drawRRect(body, Paint()..color = AdvTokens.keyword);
    canvas.drawRRect(lid, Paint()..color = AdvTokens.danger);
    for (final x in [.2, .8]) {
      canvas.drawRect(Rect.fromLTRB(w * (x - .06), h * .14, w * (x + .06), h * .96), gold);
    }
    canvas.drawRect(Rect.fromLTRB(w * .06, h * .4, w * .94, h * .5), gold);
    final lock = RRect.fromLTRBR(w * .4, h * .36, w * .6, h * .64, Radius.circular(w * .04));
    canvas.drawRRect(lock, gold);
    canvas.drawRRect(lock, line);
    canvas.drawRRect(body, line);
    canvas.drawRRect(lid, line);
  }

  @override
  bool shouldRepaint(_ChestPainter old) => false;
}

// ------------------------------------------------------------- EndBanner

/// End of run: a hanging banner with the days survived and the best run.
class EndBanner extends StatelessWidget {
  const EndBanner(
      {super.key,
      required this.won,
      required this.title,
      required this.survived,
      required this.best,
      this.note,
      this.chapterLabel = 'Chapter I · Sunlit Meadow'});
  final String chapterLabel;
  final bool won;
  final String title;
  final int survived, best;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final (top, bottom) = won ? (AdvTokens.goldTop, AdvTokens.gold) : (AdvTokens.defeatTop, AdvTokens.defeat);
    final ink = won ? AdvTokens.onGold : AdvTokens.text;
    const rodY = 46.0;
    final bannerTop = rodY + _t[2];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // A banner hung from a rod; a lost run has arrows stuck in it.
      Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Padding(
          padding: EdgeInsets.only(top: bannerTop),
          child: _banner(top, bottom, ink),
        ),
        if (!won)
          const Positioned(
              top: 0, child: CustomPaint(size: Size(AdvTokens.sizeWheel, rodY + 26), painter: _ArrowsPainter())),
        Positioned(
          top: rodY,
          child: CustomPaint(
              size: Size(AdvTokens.sizeWheel + _t[6], 18),
              painter: _RodPainter(won ? AdvTokens.gold : AdvTokens.defeat)),
        ),
        Positioned(
          top: bannerTop + _t[1],
          child: StrokeText(title, style: AdvTokens.banner, stroke: AdvTokens.strokeOutline),
        ),
      ]),
      if (note != null) ...[
        SizedBox(height: _t[3]),
        Text(note!, textAlign: TextAlign.center, style: AdvTokens.sm.copyWith(color: AdvTokens.text)),
      ],
    ]);
  }

  Widget _banner(Color top, Color bottom, Color ink) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ClipPath(
        clipper: _BannerTail(),
        child: Container(
          width: AdvTokens.sizeWheel,
          padding: EdgeInsets.fromLTRB(_t[4], _t[6] + _t[5], _t[4], _t[6] + _t[3]),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
            border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeOutline),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(chapterLabel, style: AdvTokens.xs.copyWith(color: ink)),
            SizedBox(height: _t[2]),
            Text(tr('Days survived'), style: AdvTokens.sm.copyWith(color: ink)),
            StrokeText(trDays(survived), style: AdvTokens.title),
            SizedBox(height: _t[1]),
            Text(tr('Longest journey: {n}d', {'n': best}), style: AdvTokens.sm.copyWith(color: ink)),
          ]),
        ),
      ),
    ]);
  }
}

/// The rod a result banner hangs from, with round knobs at both ends.
class _RodPainter extends CustomPainter {
  const _RodPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final h = s.height;
    final bar = RRect.fromRectAndRadius(Rect.fromLTWH(h / 2, h * 0.2, s.width - h, h * 0.6), Radius.circular(h));
    canvas.drawRRect(bar, Paint()..color = AdvTokens.outline);
    canvas.drawRRect(bar.deflate(2.5), Paint()..color = Color.lerp(color, AdvTokens.flash, 0.25)!);
    for (final x in [h / 2, s.width - h / 2]) {
      canvas.drawCircle(Offset(x, h / 2), h / 2, Paint()..color = AdvTokens.outline);
      canvas.drawCircle(Offset(x, h / 2), h / 2 - 2.5, Paint()..color = AdvTokens.textMuted);
    }
  }

  @override
  bool shouldRepaint(_RodPainter o) => o.color != color;
}

/// Four arrows stuck in the top of a lost run's banner.
class _ArrowsPainter extends CustomPainter {
  const _ArrowsPainter();
  @override
  void paint(Canvas canvas, Size s) {
    const shaft = Color(0xFF5B4A7A), feather = Color(0xFFA98CFF);
    final tips = [
      (0.3, -0.7),
      (0.44, -0.25),
      (0.57, 0.2),
      (0.7, 0.65),
    ];
    for (final (x, lean) in tips) {
      final tip = Offset(s.width * x, s.height);
      final tail = tip + Offset(lean * s.height, -s.height * 0.95);
      canvas.drawLine(tail, tip, _stroke(AdvTokens.outline, 7));
      canvas.drawLine(tail, tip, _stroke(shaft, 4));
      final dir = (tip - tail) / (tip - tail).distance;
      final side = Offset(-dir.dy, dir.dx);
      for (final k in [0.0, 0.12]) {
        final base = tail + dir * (k * s.height);
        final f = Path()
          ..moveTo(base.dx, base.dy)
          ..lineTo((base + side * 9 + dir * 14).dx, (base + side * 9 + dir * 14).dy)
          ..lineTo((base + dir * 18).dx, (base + dir * 18).dy)
          ..lineTo((base - side * 9 + dir * 14).dx, (base - side * 9 + dir * 14).dy)
          ..close();
        canvas.drawPath(f, Paint()..color = AdvTokens.outline);
        canvas.drawPath(f.shift(Offset.zero), Paint()..color = feather.withOpacity(0.9));
      }
    }
  }

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  @override
  bool shouldRepaint(_ArrowsPainter o) => false;
}

class _BannerTail extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width / 2, s.height - AdvTokens.space[5])
    ..lineTo(0, s.height)
    ..close();
  @override
  bool shouldReclip(_BannerTail old) => false;
}

// ------------------------------------------------------------ ScenePalette

/// Each chapter's sky, ground and the tint laid over the road backdrop.
({Color sky, Color low, Color ground, Color tint}) scenePalette(String chapterId) => switch (chapterId) {
      'forest' => (
          sky: AdvTokens.sceneForestSky,
          low: AdvTokens.sceneForestLow,
          ground: AdvTokens.sceneForestGround,
          tint: AdvTokens.sceneForestTint
        ),
      'frost' => (
          sky: AdvTokens.sceneFrostSky,
          low: AdvTokens.sceneFrostLow,
          ground: AdvTokens.sceneFrostGround,
          tint: AdvTokens.sceneFrostTint
        ),
      'ember' => (
          sky: AdvTokens.sceneEmberSky,
          low: AdvTokens.sceneEmberLow,
          ground: AdvTokens.sceneEmberGround,
          tint: AdvTokens.sceneEmberTint
        ),
      'ruins' => (
          sky: AdvTokens.sceneRuinsSky,
          low: AdvTokens.sceneRuinsLow,
          ground: AdvTokens.sceneRuinsGround,
          tint: AdvTokens.sceneRuinsTint
        ),
      'storm' => (
          sky: AdvTokens.sceneStormSky,
          low: AdvTokens.sceneStormLow,
          ground: AdvTokens.sceneStormGround,
          tint: AdvTokens.sceneStormTint
        ),
      'shadow' => (
          sky: AdvTokens.sceneShadowSky,
          low: AdvTokens.sceneShadowLow,
          ground: AdvTokens.sceneShadowGround,
          tint: AdvTokens.sceneShadowTint
        ),
      'astral' => (
          sky: AdvTokens.sceneAstralSky,
          low: AdvTokens.sceneAstralLow,
          ground: AdvTokens.sceneAstralGround,
          tint: AdvTokens.sceneAstralTint
        ),
      _ => (
          sky: AdvTokens.sceneMeadowSky,
          low: AdvTokens.sceneMeadowLow,
          ground: AdvTokens.sceneMeadowGround,
          tint: AdvTokens.sceneMeadowTint
        ),
    };

// ---------------------------------------------------------------- GearIcon

/// A gear piece: its pixel icon on a tile framed in its rarity colour.
/// A gear piece in its rarity frame, alive in proportion to its rarity:
/// Uncommon floats, Rare and up glow in a slow pulse, Epic and up catch a
/// sweep of light, Legendary and Mythic sparkle, and Mythic's frame turns.
class GearIcon extends StatefulWidget {
  const GearIcon(this.item, {super.key, this.size = AdvTokens.sizePickTile, this.worn = false, this.count});
  final GearItem item;
  final double size;
  final bool worn;

  /// How many identical pieces there are, shown in the corner when > 1.
  final int? count;

  @override
  State<GearIcon> createState() => _GearIconState();
}

class _GearIconState extends State<GearIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  int get _tier => widget.item.rarity.index;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tier > 0 && Motion.on(context)) {
      if (!_t.isAnimating) _t.repeat();
    } else {
      _t.stop();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item, size = widget.size, worn = widget.worn, count = widget.count;
    final c = rarityColor(item.rarity);
    final tier = _tier;
    final art = Image.asset(rpgAsset(item.type.img), filterQuality: FilterQuality.medium, semanticLabel: item.name);
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final v = _t.value;
        final wave = math.sin(v * 2 * math.pi);
        final pulse = 0.5 + 0.5 * wave;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdvTokens.radiusCard),
            boxShadow: tier >= Rarity.rare.index
                ? [BoxShadow(color: c.withOpacity(0.25 + 0.35 * pulse), blurRadius: size / 8 + size / 10 * pulse)]
                : null,
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            // Frame: a turning ring of colour for Mythic, a plain one below.
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AdvTokens.radiusCard),
                child: Stack(fit: StackFit.expand, children: [
                  if (tier >= Rarity.mythic.index)
                    Transform.rotate(
                      angle: v * 2 * math.pi,
                      child: Transform.scale(
                        scale: 1.5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: SweepGradient(colors: [c, AdvTokens.goldTop, AdvTokens.special, c]),
                          ),
                        ),
                      ),
                    )
                  else
                    ColoredBox(color: worn ? AdvTokens.goldTop : c),
                  Padding(
                    padding: const EdgeInsets.all(AdvTokens.strokeOutline),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AdvTokens.radiusCard - AdvTokens.strokeOutline),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [c.withOpacity(0.55), AdvTokens.surfaceDeep],
                        ),
                      ),
                    ),
                  ),
                  // The art, floating gently from Uncommon up.
                  Padding(
                    padding: EdgeInsets.all(size / 10),
                    child: Transform.translate(
                      offset: Offset(0, tier >= 1 ? wave * size * 0.035 : 0),
                      child: art,
                    ),
                  ),
                  // A sweep of light across Epic and up.
                  if (tier >= Rarity.epic.index)
                    Transform.translate(
                      offset: Offset((v * 2.4 - 1.2) * size, 0),
                      child: Transform.rotate(
                        angle: 0.5,
                        child: Center(
                          child: Container(
                            width: size * 0.22,
                            height: size * 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                Colors.white.withOpacity(0),
                                Colors.white.withOpacity(0.45),
                                Colors.white.withOpacity(0),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            // Sparkles on Legendary and Mythic.
            if (tier >= Rarity.legendary.index)
              for (final (dx, dy, phase) in const [(0.08, 0.1, 0.0), (0.78, 0.18, 0.33), (0.62, 0.74, 0.66)])
                Positioned(
                  left: size * dx,
                  top: size * dy,
                  child: Opacity(
                    opacity: (math.sin((v + phase) * 2 * math.pi) * 0.5 + 0.5).clamp(0.0, 1.0),
                    child: Icon(Icons.auto_awesome, size: size / 6, color: AdvTokens.goldTop),
                  ),
                ),
            if (worn)
              Positioned(
                left: -size / 12,
                top: -size / 12,
                child: Icon(Icons.check_circle, color: AdvTokens.goldTop, size: size / 3.2),
              ),
            if ((count ?? 1) > 1)
              Positioned(
                right: -size / 14,
                bottom: -size / 14,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: _t1, vertical: 0),
                  decoration: BoxDecoration(
                      color: AdvTokens.surfaceDeep, borderRadius: BorderRadius.circular(AdvTokens.radiusPill)),
                  child: Text('×$count', style: AdvTokens.xs.copyWith(color: AdvTokens.text)),
                ),
              ),
          ]),
        );
      },
    );
  }
}

final double _t1 = _t[1];
