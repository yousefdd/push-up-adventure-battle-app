// ignore_for_file: avoid_renaming_method_parameters
// Battle effects: the slash on every strike, each class's special, the
// pixel burst when a foe falls. All drawn in code, chunky like the sprites.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/theme/adventure_tokens.dart';

/// Where the foe stands in the scene, as a fraction of its size.
const foeSpot = Offset(0.75, 0.64);

/// Where the hero stands.
const heroSpot = Offset(0.29, 0.64);

/// The colour a class's attacks glow in.
Color classColor(String classId) => switch (classId) {
      'knight' => AdvTokens.rareRare,
      'ranger' => AdvTokens.rareUncommon,
      'monk' => AdvTokens.goldTop,
      _ => AdvTokens.hp,
    };

/// Plays [painter] from 0 to 1 once over [duration], then calls [onDone].
class OneShot extends StatefulWidget {
  const OneShot({super.key, required this.duration, required this.painter, this.onDone});
  final Duration duration;
  final CustomPainter Function(double t) painter;
  final VoidCallback? onDone;

  @override
  State<OneShot> createState() => _OneShotState();
}

class _OneShotState extends State<OneShot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone?.call();
    })
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: widget.painter(_c.value), size: Size.infinite),
        ),
      );
}

Paint _pixelStroke(Color c, double w) => Paint()
  ..color = c
  ..strokeWidth = w
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.square;

/// A blade arc across the foe: sweeps in, then fades.
class SlashPainter extends CustomPainter {
  SlashPainter(this.t, this.color, {this.crit = false, this.angle = -0.6});
  final double t, angle;
  final Color color;
  final bool crit;

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width * foeSpot.dx, s.height * foeSpot.dy);
    final r = s.height * (crit ? 0.3 : 0.22);
    final sweep = math.pi * 0.9 * Curves.easeOut.transform(math.min(1, t * 1.6));
    final fade = (1 - t).clamp(0.0, 1.0);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
        rect, angle - math.pi / 2, sweep, false, _pixelStroke(AdvTokens.outline.withOpacity(fade), crit ? 14 : 10));
    canvas.drawArc(rect, angle - math.pi / 2, sweep, false, _pixelStroke(color.withOpacity(fade), crit ? 9 : 6));
    canvas.drawArc(
        rect, angle - math.pi / 2, sweep, false, _pixelStroke(AdvTokens.flash.withOpacity(fade), crit ? 3 : 2));
    if (crit && t < 0.5) {
      // A star burst at the point of impact.
      final p = Paint()..color = AdvTokens.goldTop.withOpacity(1 - t * 2);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final d = r * (0.4 + t);
        canvas.drawRect(Rect.fromCenter(center: c + Offset(math.cos(a), math.sin(a)) * d, width: 8, height: 8), p);
      }
    }
  }

  @override
  bool shouldRepaint(SlashPainter o) => o.t != t;
}

/// The class special, drawn over the whole scene.
class SpecialPainter extends CustomPainter {
  SpecialPainter(this.t, this.classId);
  final double t;
  final String classId;

  @override
  void paint(Canvas canvas, Size s) {
    final foe = Offset(s.width * foeSpot.dx, s.height * foeSpot.dy);
    final col = classColor(classId);
    final fade = t < 0.75 ? 1.0 : (1 - t) / 0.25;
    // A flash of the class colour over the scene.
    canvas.drawRect(Offset.zero & s, Paint()..color = col.withOpacity(0.25 * (1 - t)));
    switch (classId) {
      case 'knight': // shockwave rings from the shield
        for (var i = 0; i < 3; i++) {
          final k = (t * 1.4 - i * 0.18).clamp(0.0, 1.0);
          if (k <= 0) continue;
          final r = s.height * 0.5 * k;
          canvas.drawCircle(foe, r, _pixelStroke(AdvTokens.outline.withOpacity((1 - k) * fade), 12));
          canvas.drawCircle(foe, r, _pixelStroke(col.withOpacity((1 - k) * fade), 7));
          canvas.drawCircle(foe, r, _pixelStroke(AdvTokens.flash.withOpacity((1 - k) * fade), 2));
        }
      case 'ranger': // a rain of arrows onto the foe
        final rnd = math.Random(7);
        for (var i = 0; i < 14; i++) {
          final start = rnd.nextDouble() * 0.5;
          final k = ((t - start) / 0.35).clamp(0.0, 1.0);
          if (k <= 0 || k >= 1) continue;
          final x = foe.dx + (rnd.nextDouble() - 0.5) * s.width * 0.3;
          final tip = Offset(x - (1 - k) * 40, foe.dy - s.height * 0.1 + (rnd.nextDouble() - 0.5) * 30) +
              Offset(0, -(1 - k) * s.height * 0.7);
          final tail = tip + const Offset(-14, -30);
          canvas.drawLine(tail, tip, _pixelStroke(AdvTokens.outline, 6));
          canvas.drawLine(tail, tip, _pixelStroke(const Color(0xFF8A5A2A), 3));
          canvas.drawRect(Rect.fromCenter(center: tip, width: 7, height: 7), Paint()..color = AdvTokens.flash);
          canvas.drawRect(Rect.fromCenter(center: tail, width: 6, height: 6), Paint()..color = col);
        }
      case 'monk': // golden rays
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6 + t * 1.2;
          final len = s.height * (0.15 + 0.5 * Curves.easeOut.transform(t));
          final p = foe + Offset(math.cos(a), math.sin(a)) * len;
          canvas.drawLine(foe, p, _pixelStroke(col.withOpacity(0.8 * fade), 8));
          canvas.drawLine(foe, p, _pixelStroke(AdvTokens.flash.withOpacity(0.7 * fade), 3));
        }
        canvas.drawCircle(foe, s.height * 0.12 * (1 + t), Paint()..color = AdvTokens.flash.withOpacity(0.6 * fade));
      default: // berserker: three red slashes
        for (var i = 0; i < 3; i++) {
          final k = ((t - i * 0.15) * 2.2).clamp(0.0, 1.0);
          if (k <= 0) continue;
          final y = foe.dy - s.height * 0.2 + i * s.height * 0.2;
          final a = Offset(foe.dx - s.width * 0.22, y - 40);
          final b = Offset(foe.dx + s.width * 0.22, y + 40);
          final end = Offset.lerp(a, b, Curves.easeOut.transform(k))!;
          canvas.drawLine(a, end, _pixelStroke(AdvTokens.outline.withOpacity(fade), 14));
          canvas.drawLine(a, end, _pixelStroke(col.withOpacity(fade), 8));
          canvas.drawLine(a, end, _pixelStroke(AdvTokens.flash.withOpacity(fade), 2));
        }
        // red vignette at the edges
        canvas.drawRect(
          Offset.zero & s,
          Paint()
            ..shader = RadialGradient(colors: [Colors.transparent, col.withOpacity(0.35 * fade)], stops: const [0.6, 1])
                .createShader(Offset.zero & s),
        );
    }
  }

  @override
  bool shouldRepaint(SpecialPainter o) => o.t != t;
}

/// Pixel shards flying out of a fallen foe.
class BurstPainter extends CustomPainter {
  BurstPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width * foeSpot.dx, s.height * (foeSpot.dy - 0.05));
    final rnd = math.Random(3);
    for (var i = 0; i < 22; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final v = 60 + rnd.nextDouble() * 120;
      final p = c + Offset(math.cos(a), math.sin(a)) * v * t + Offset(0, 160 * t * t);
      final size = 10 * (1 - t) + 2;
      canvas.drawRect(Rect.fromCenter(center: p, width: size, height: size),
          Paint()..color = (i.isEven ? color : AdvTokens.flash).withOpacity(1 - t));
    }
  }

  @override
  bool shouldRepaint(BurstPainter o) => o.t != t;
}

/// A ball of energy thrown from one fighter to the other, with a trail and a
/// splash where it lands.
class ProjectilePainter extends CustomPainter {
  ProjectilePainter(this.t, this.color, {this.fromFoe = true, this.size = 14});
  final double t, size;
  final Color color;
  final bool fromFoe;

  @override
  void paint(Canvas canvas, Size s) {
    final foe = Offset(s.width * foeSpot.dx, s.height * (foeSpot.dy - 0.05));
    final hero = Offset(s.width * heroSpot.dx, s.height * (heroSpot.dy - 0.05));
    final a = fromFoe ? foe : hero, b = fromFoe ? hero : foe;
    if (t < 0.7) {
      final k = Curves.easeIn.transform(t / 0.7);
      for (var i = 4; i >= 0; i--) {
        final kk = (k - i * 0.05).clamp(0.0, 1.0);
        final p = Offset.lerp(a, b, kk)! - Offset(0, math.sin(kk * math.pi) * s.height * 0.12);
        final r = size * (1 - i * 0.16);
        canvas.drawCircle(p, r + 3, Paint()..color = AdvTokens.outline.withOpacity(i == 0 ? 1 : 0.2));
        canvas.drawCircle(p, r, Paint()..color = color.withOpacity(i == 0 ? 1 : 0.45));
        if (i == 0) canvas.drawCircle(p, r * 0.45, Paint()..color = AdvTokens.flash);
      }
    } else {
      final k = (t - 0.7) / 0.3;
      canvas.drawCircle(b, size * (1 + 3 * k), _pixelStroke(color.withOpacity(1 - k), 8 * (1 - k) + 1));
      canvas.drawCircle(b, size * 2 * (1 - k), Paint()..color = color.withOpacity(0.5 * (1 - k)));
    }
  }

  @override
  bool shouldRepaint(ProjectilePainter o) => o.t != t;
}

/// Particles rising around a fighter: green for healing, grey for stone skin,
/// purple for a hex.
class AuraPainter extends CustomPainter {
  AuraPainter(this.t, this.color, {this.onFoe = true, this.rising = true});
  final double t;
  final Color color;
  final bool onFoe, rising;

  @override
  void paint(Canvas canvas, Size s) {
    final spot = onFoe ? foeSpot : heroSpot;
    final c = Offset(s.width * spot.dx, s.height * (spot.dy + 0.12));
    final rnd = math.Random(5);
    for (var i = 0; i < 16; i++) {
      final start = rnd.nextDouble() * 0.4;
      final k = ((t - start) / 0.6).clamp(0.0, 1.0);
      if (k <= 0 || k >= 1) continue;
      final x = c.dx + (rnd.nextDouble() - 0.5) * s.width * 0.18;
      final y = rising ? c.dy - k * s.height * 0.35 : c.dy - s.height * 0.35 + k * s.height * 0.35;
      final r = 4 + 4 * (1 - k);
      final p = Offset(x + math.sin(k * 6 + i) * 6, y);
      canvas.drawRect(Rect.fromCenter(center: p, width: r * 2 + 3, height: r * 2 + 3),
          Paint()..color = AdvTokens.outline.withOpacity(0.6 * (1 - k)));
      canvas.drawRect(
          Rect.fromCenter(center: p, width: r * 2, height: r * 2), Paint()..color = color.withOpacity(1 - k));
    }
    // A ring on the ground.
    final ring = Rect.fromCenter(center: c, width: s.width * 0.24 * (0.6 + 0.4 * t), height: s.height * 0.06);
    canvas.drawOval(ring, _pixelStroke(color.withOpacity(0.7 * (1 - t)), 4));
  }

  @override
  bool shouldRepaint(AuraPainter o) => o.t != t;
}

/// Puffs of dust kicked up behind running feet.
class DustPainter extends CustomPainter {
  DustPainter(this.t, this.at, {this.toLeft = true});
  final double t;
  final Offset at;
  final bool toLeft;

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width * at.dx, s.height * at.dy);
    for (var i = 0; i < 4; i++) {
      final k = (t * 1.2 - i * 0.08).clamp(0.0, 1.0);
      if (k <= 0 || k >= 1) continue;
      final p = c + Offset((toLeft ? -1 : 1) * (10 + k * 34 + i * 8), -k * 14 - i * 3);
      canvas.drawCircle(p, 6 + 6 * k, Paint()..color = AdvTokens.flash.withOpacity(0.7 * (1 - k)));
    }
    // Speed lines.
    if (t < 0.6) {
      final k = t / 0.6;
      for (var i = 0; i < 3; i++) {
        final y = c.dy - 8 - i * 9;
        final x0 = c.dx + (toLeft ? -1 : 1) * (14 + k * 10);
        canvas.drawLine(Offset(x0, y), Offset(x0 + (toLeft ? -1 : 1) * (22 - i * 4), y),
            _pixelStroke(AdvTokens.flash.withOpacity(0.8 * (1 - k)), 3));
      }
    }
  }

  @override
  bool shouldRepaint(DustPainter o) => o.t != t;
}

/// The road the fighters stand on: flat sand in the world's colour, with
/// darker patches that slide past as the hero walks.
class RoadPainter extends CustomPainter {
  RoadPainter(this.color, this.scroll);
  final Color color;
  final double scroll;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = color);
    // A soft shadow under the scenery strip.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, 10),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.25), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, 0, s.width, 10)),
    );
    final patch = Paint()..color = Color.lerp(color, Colors.black, 0.09)!;
    const tile = 300.0;
    final rnd = math.Random(4);
    final spots = [
      for (var i = 0; i < 7; i++) (rnd.nextDouble() * tile, 0.12 + rnd.nextDouble() * 0.8, 30 + rnd.nextDouble() * 50),
    ];
    final off = scroll % tile;
    for (var k = -1; k <= (s.width / tile).ceil(); k++) {
      for (final (x, y, w) in spots) {
        final cx = k * tile + x - off;
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, s.height * y), width: w, height: w * 0.32), patch);
      }
    }
  }

  @override
  bool shouldRepaint(RoadPainter o) => o.scroll != scroll || o.color != color;
}
