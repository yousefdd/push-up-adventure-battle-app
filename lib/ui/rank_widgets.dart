import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../online/ranked.dart';
import 'motion.dart';
import 'theme/rpg_theme.dart';

/// A rank emblem: a faceted shield in the rank's metal, dressed more richly
/// the higher the rank, with a living effect of its own:
///   Bronze, Silver: a glint sweeps the metal.
///   Gold: glint and twinkling sparkles; wings.
///   Platinum: a breathing teal glow.
///   Diamond: a gem, and sparkles circling it.
///   Master: a crown and a violet aura.
///   Grandmaster: a spiked crown and embers orbiting it.
///   Champion: the last rank, kept a mystery. A void shield full of
///   stars with a watching eye, ghost-blue flames, a turning vortex and
///   runes circling it. Below Grandmaster the ladder shows only a shadow.
/// Chevrons at the bottom show the division (one for III, three for I).
class RankBadge extends StatefulWidget {
  const RankBadge(this.rank, {super.key, this.size = 56, this.animate = true});
  final Rank rank;
  final double size;
  final bool animate;

  @override
  State<RankBadge> createState() => _RankBadgeState();
}

class _RankBadgeState extends State<RankBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && Motion.on(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.rank.name,
      child: SizedBox(
        width: widget.size * 1.35,
        height: widget.size * 1.2,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _BadgePainter(widget.rank, _c.isAnimating ? _c.value : -1)),
        ),
      ),
    );
  }
}

const _voidMagenta = Color(0xFFD25BFF);

class _BadgePainter extends CustomPainter {
  _BadgePainter(this.rank, this.t);
  final Rank rank;

  /// 0..1 through the effect loop; negative when still.
  final double t;

  RankTier get tier => rank.tier;
  bool at(RankTier r) => tier.index >= r.index;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / 1.2;
    final c = Offset(size.width / 2, size.height * 0.57);
    final k = t < 0 ? 0.0 : t;
    final wave = 0.5 + 0.5 * math.sin(k * math.pi * 2);
    final outline = Paint()
      ..color = const Color(0xFF120B1F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.07
      ..strokeJoin = StrokeJoin.round;

    // ---- effects behind the shield
    if (tier == RankTier.champion) {
      // A vortex: three arcs turning at different speeds over a dark glow.
      final v = c.translate(0, -s * 0.04);
      canvas.drawCircle(
          v,
          s * 0.62,
          Paint()
            ..color = _voidMagenta.withOpacity(0.28 + 0.2 * wave)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.18));
      for (final (r, speed, w) in [(0.66, 1.0, 0.05), (0.56, -1.5, 0.035), (0.74, 0.6, 0.025)]) {
        canvas.save();
        canvas.translate(v.dx, v.dy);
        canvas.rotate(k * math.pi * 2 * speed);
        final rect = Rect.fromCircle(center: Offset.zero, radius: s * r);
        canvas.drawArc(
            rect,
            0,
            math.pi * 1.3,
            false,
            Paint()
              ..shader = SweepGradient(
                colors: [Colors.transparent, tier.light, _voidMagenta, Colors.transparent],
                stops: const [0, 0.25, 0.5, 0.65],
              ).createShader(rect)
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * w
              ..strokeCap = StrokeCap.round);
        canvas.restore();
      }
    }
    if (at(RankTier.platinum)) {
      final glow = tier == RankTier.platinum || tier == RankTier.diamond ? tier.light : tier.light;
      canvas.drawCircle(
          c.translate(0, -s * 0.02),
          s * (0.5 + 0.06 * wave),
          Paint()
            ..color = glow.withOpacity(tier == RankTier.platinum ? 0.25 + 0.3 * wave : 0.22 + 0.18 * wave)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.14));
    }
    if (tier == RankTier.champion) {
      // Ghost-blue flames.
      for (final (dx, h, ph) in [(-0.22, 0.5, 0.0), (0.0, 0.68, 0.33), (0.22, 0.52, 0.66)]) {
        final flick = 0.85 + 0.15 * math.sin((k + ph) * math.pi * 6);
        final x = c.dx + dx * s;
        final top = c.dy - s * (0.3 + h * flick);
        canvas.drawPath(
            Path()
              ..moveTo(x - s * 0.16, c.dy - s * 0.1)
              ..quadraticBezierTo(x - s * 0.2, top + s * 0.18, x, top)
              ..quadraticBezierTo(x + s * 0.2, top + s * 0.18, x + s * 0.16, c.dy - s * 0.1)
              ..close(),
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xFF3B1A8C), _voidMagenta, Color(0xFF9BF6FF)],
              ).createShader(Rect.fromLTRB(x - s * 0.2, top, x + s * 0.2, c.dy)));
      }
    }

    // ---- wings (Gold and up)
    if (at(RankTier.gold)) {
      final flap = 0.04 * math.sin(k * math.pi * 4);
      for (final side in [-1.0, 1.0]) {
        final w = Path()
          ..moveTo(c.dx + side * s * 0.28, c.dy - s * 0.22)
          ..quadraticBezierTo(
              c.dx + side * s * 0.62, c.dy - s * (0.42 + flap), c.dx + side * s * 0.66, c.dy - s * (0.05 + flap))
          ..quadraticBezierTo(c.dx + side * s * 0.52, c.dy - s * 0.02, c.dx + side * s * 0.58, c.dy + s * 0.14)
          ..quadraticBezierTo(c.dx + side * s * 0.42, c.dy + s * 0.12, c.dx + side * s * 0.3, c.dy + s * 0.2)
          ..close();
        canvas.drawPath(w, Paint()..color = tier.dark);
        canvas.drawPath(w, outline);
      }
    }

    // ---- the shield
    final shield = Path()
      ..moveTo(c.dx, c.dy - s * 0.48)
      ..lineTo(c.dx + s * 0.36, c.dy - s * 0.34)
      ..lineTo(c.dx + s * 0.34, c.dy + s * 0.12)
      ..quadraticBezierTo(c.dx + s * 0.3, c.dy + s * 0.34, c.dx, c.dy + s * 0.5)
      ..quadraticBezierTo(c.dx - s * 0.3, c.dy + s * 0.34, c.dx - s * 0.34, c.dy + s * 0.12)
      ..lineTo(c.dx - s * 0.36, c.dy - s * 0.34)
      ..close();
    final box = shield.getBounds();
    canvas.drawPath(
        shield,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tier == RankTier.champion
                ? const [Color(0xFF3A1C7A), Color(0xFF160A36), Color(0xFF05030F)]
                : [tier.light, Color.lerp(tier.light, tier.dark, 0.55)!, tier.dark],
          ).createShader(box));
    if (tier == RankTier.champion) {
      // Stars drifting inside the shield.
      canvas.save();
      canvas.clipPath(shield);
      for (var i = 0; i < 9; i++) {
        final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin((k * 3 + i * 0.37) * math.pi * 2));
        final p = Offset(box.left + box.width * ((i * 0.618 + k * 0.08) % 1), box.top + box.height * ((i * 0.291) % 1));
        canvas.drawCircle(p, s * (i.isEven ? 0.018 : 0.011), Paint()..color = Colors.white.withOpacity(tw * 0.85));
      }
      canvas.restore();
    }
    canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - s * 0.48)
          ..lineTo(c.dx, c.dy + s * 0.5)
          ..quadraticBezierTo(c.dx - s * 0.3, c.dy + s * 0.34, c.dx - s * 0.34, c.dy + s * 0.12)
          ..lineTo(c.dx - s * 0.36, c.dy - s * 0.34)
          ..close(),
        Paint()..color = Colors.white.withOpacity(0.18));
    // A glint sweeping across the metal (every rank).
    if (t >= 0 && k < 0.3) {
      canvas.save();
      canvas.clipPath(shield);
      final x = box.left - s * 0.3 + (k / 0.3) * (box.width + s * 0.6);
      canvas.drawPath(
          Path()
            ..moveTo(x, box.top)
            ..lineTo(x + s * 0.14, box.top)
            ..lineTo(x - s * 0.16, box.bottom)
            ..lineTo(x - s * 0.3, box.bottom)
            ..close(),
          Paint()..color = Colors.white.withOpacity(0.45));
      canvas.restore();
    }
    canvas.drawPath(shield, outline);

    // ---- emblem: a star, or a gem from Diamond up
    final e = Paint()..color = Colors.white.withOpacity(0.92);
    if (tier == RankTier.champion) {
      // A watching eye that blinks now and then.
      final open = k > 0.86 && k < 0.92 ? (1 - math.sin((k - 0.86) / 0.06 * math.pi)).clamp(0.05, 1.0) : 1.0;
      final ec = c.translate(0, -s * 0.04);
      final eye = Path()
        ..moveTo(ec.dx - s * 0.2, ec.dy)
        ..quadraticBezierTo(ec.dx, ec.dy - s * 0.2 * open, ec.dx + s * 0.2, ec.dy)
        ..quadraticBezierTo(ec.dx, ec.dy + s * 0.2 * open, ec.dx - s * 0.2, ec.dy)
        ..close();
      canvas.drawPath(
          eye,
          Paint()
            ..color = tier.light.withOpacity(0.5)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.06));
      canvas.drawPath(eye, Paint()..color = const Color(0xFFDDFBFF));
      canvas.save();
      canvas.clipPath(eye);
      canvas.drawCircle(ec, s * 0.085, Paint()..color = _voidMagenta);
      canvas.drawOval(
          Rect.fromCenter(center: ec, width: s * 0.035, height: s * 0.13), Paint()..color = const Color(0xFF05030F));
      canvas.restore();
    } else if (at(RankTier.diamond)) {
      final g = Path()
        ..moveTo(c.dx, c.dy - s * 0.24)
        ..lineTo(c.dx + s * 0.16, c.dy - s * 0.06)
        ..lineTo(c.dx, c.dy + s * 0.2)
        ..lineTo(c.dx - s * 0.16, c.dy - s * 0.06)
        ..close();
      canvas.drawPath(g, e);
      canvas.drawPath(
          g,
          Paint()
            ..color = tier.dark
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.03);
    } else {
      canvas.drawPath(_star(c.translate(0, -s * 0.03), s * 0.17, s * 0.075), e);
    }

    // ---- division chevrons
    final chevrons = 4 - rank.division;
    for (var i = 0; i < chevrons; i++) {
      final y = c.dy + s * (0.24 + i * 0.075) - (chevrons - 1) * s * 0.03;
      canvas.drawPath(
          Path()
            ..moveTo(c.dx - s * 0.12, y)
            ..lineTo(c.dx, y + s * 0.05)
            ..lineTo(c.dx + s * 0.12, y),
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.04
            ..strokeCap = StrokeCap.round);
    }

    // ---- crown (Master and up; spiked from Grandmaster)
    if (at(RankTier.master)) {
      final y = c.dy - s * 0.5;
      final spiky = at(RankTier.grandmaster);
      final h = spiky ? 0.24 : 0.16;
      final cr = Path()
        ..moveTo(c.dx - s * 0.22, y + s * 0.02)
        ..lineTo(c.dx - s * 0.25, y - s * h)
        ..lineTo(c.dx - s * 0.12, y - s * 0.06)
        ..lineTo(c.dx, y - s * (h + 0.06))
        ..lineTo(c.dx + s * 0.12, y - s * 0.06)
        ..lineTo(c.dx + s * 0.25, y - s * h)
        ..lineTo(c.dx + s * 0.22, y + s * 0.02)
        ..close();
      canvas.drawPath(
          cr,
          Paint()
            ..color = tier == RankTier.champion
                ? const Color(0xFF9BF6FF)
                : spiky
                    ? const Color(0xFFFFE17A)
                    : const Color(0xFFFFD25A));
      canvas.drawPath(cr, outline..strokeWidth = s * 0.045);
      canvas.drawCircle(Offset(c.dx, y - s * 0.02), s * 0.035, Paint()..color = tier.dark);
    }

    // ---- effects in front
    if (t >= 0) {
      if (tier == RankTier.champion) {
        // Runes circling on a tilted orbit, fading behind the shield.
        for (var i = 0; i < 4; i++) {
          final ang = k * math.pi * 2 + i * math.pi / 2;
          final front = math.sin(ang);
          final p = c + Offset(math.cos(ang) * s * 0.6, front * s * 0.18 + s * 0.02);
          final r = s * (0.045 + 0.015 * front);
          final rune = Path()
            ..moveTo(p.dx, p.dy - r * 1.4)
            ..lineTo(p.dx + r, p.dy)
            ..lineTo(p.dx, p.dy + r * 1.4)
            ..lineTo(p.dx - r, p.dy)
            ..close();
          final col = i.isEven ? tier.light : _voidMagenta;
          canvas.drawPath(
              rune,
              Paint()
                ..color = col.withOpacity(0.5)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.04));
          canvas.drawPath(rune, Paint()..color = col.withOpacity(0.55 + 0.45 * (front + 1) / 2));
        }
      }
      if (tier == RankTier.gold) {
        // Twinkling sparkles.
        for (var i = 0; i < 4; i++) {
          final ph = (k * 2 + i / 4) % 1;
          final a = math.sin(ph * math.pi);
          final p = c + Offset(math.cos(i * 1.9) * s * 0.5, math.sin(i * 2.3) * s * 0.42 - s * 0.05);
          canvas.drawPath(_star(p, s * 0.07 * a, s * 0.02 * a), Paint()..color = Colors.white.withOpacity(a));
        }
      }
      if (tier == RankTier.diamond) {
        // Sparkles circling the gem.
        for (var i = 0; i < 3; i++) {
          final ang = k * math.pi * 2 + i * math.pi * 2 / 3;
          final p = c + Offset(math.cos(ang) * s * 0.5, math.sin(ang) * s * 0.28 - s * 0.05);
          canvas.drawPath(_star(p, s * 0.07, s * 0.022), Paint()..color = Colors.white.withOpacity(0.9));
        }
      }
      if (tier == RankTier.master) {
        canvas.drawCircle(
            c,
            s * (0.56 + 0.05 * wave),
            Paint()
              ..color = tier.light.withOpacity(0.35 * (1 - wave) + 0.1)
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * 0.04);
      }
      if (tier == RankTier.grandmaster) {
        // Embers orbiting.
        for (var i = 0; i < 5; i++) {
          final ang = -k * math.pi * 2 + i * math.pi * 2 / 5;
          final p = c + Offset(math.cos(ang) * s * 0.56, math.sin(ang) * s * 0.36);
          canvas.drawCircle(p, s * 0.04, Paint()..color = const Color(0xFFFF7A3D));
          canvas.drawCircle(
              p,
              s * 0.07,
              Paint()
                ..color = const Color(0xFFFF7A3D).withOpacity(0.3)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.04));
        }
      }
    }
  }

  static Path _star(Offset c, double r1, double r2) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? r1 : r2;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(_BadgePainter old) => old.rank != rank || old.t != t;
}

/// A coin: the gold Cinder Coin (a molten disc with Cinder's flame at its
/// heart) or the silver coin (cool steel with a silver flame). A glint
/// sweeps across now and then.
class CoinIcon extends StatefulWidget {
  const CoinIcon({super.key, this.gold = true, this.size = 24, this.animate = true});
  final bool gold;
  final double size;
  final bool animate;

  @override
  State<CoinIcon> createState() => _CoinIconState();
}

class _CoinIconState extends State<CoinIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && Motion.on(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr(widget.gold ? 'Cinder Coins' : 'Silver coins'),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _CoinPainter(widget.gold, _c.isAnimating ? _c.value : -1)),
        ),
      ),
    );
  }
}

class _CoinPainter extends CustomPainter {
  _CoinPainter(this.gold, this.t);
  final bool gold;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final rim = gold ? const [Color(0xFFFFB347), Color(0xFFC2410C)] : const [Color(0xFFE8EEF6), Color(0xFF6B7A90)];
    final face = gold
        ? const [Color(0xFFFFF3B0), Color(0xFFFFC94A), Color(0xFFE07A1F)]
        : const [Color(0xFFFFFFFF), Color(0xFFCFD8E6), Color(0xFF8592A8)];
    final flame = gold
        ? const [Color(0xFFB91C1C), Color(0xFFF2764D), Color(0xFFFFE17A)]
        : const [Color(0xFF4A5A75), Color(0xFF8EA3C2), Color(0xFFF4F8FF)];
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = (gold ? const Color(0xFFFF8A3D) : const Color(0xFFB8C7DD)).withOpacity(0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25));
    canvas.drawCircle(
        c, r * 0.94, Paint()..shader = RadialGradient(colors: rim).createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(
        c,
        r * 0.76,
        Paint()
          ..shader = RadialGradient(center: const Alignment(-0.3, -0.4), colors: face, stops: const [0, 0.55, 1])
              .createShader(Rect.fromCircle(center: c, radius: r * 0.76)));
    canvas.drawCircle(
        c,
        r * 0.76,
        Paint()
          ..color = (gold ? const Color(0xFF8A2A06) : const Color(0xFF3E4A5E)).withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.07);
    final f = Path()
      ..moveTo(c.dx, c.dy + r * 0.5)
      ..cubicTo(c.dx - r * 0.42, c.dy + r * 0.48, c.dx - r * 0.42, c.dy + r * 0.02, c.dx - r * 0.12, c.dy - r * 0.18)
      ..cubicTo(c.dx - r * 0.12, c.dy - r * 0.02, c.dx - r * 0.02, c.dy + r * 0.06, c.dx + r * 0.02, c.dy)
      ..cubicTo(c.dx, c.dy - r * 0.26, c.dx + r * 0.1, c.dy - r * 0.42, c.dx + r * 0.04, c.dy - r * 0.56)
      ..cubicTo(c.dx + r * 0.36, c.dy - r * 0.36, c.dx + r * 0.42, c.dy, c.dx + r * 0.36, c.dy + r * 0.2)
      ..cubicTo(c.dx + r * 0.32, c.dy + r * 0.42, c.dx + r * 0.18, c.dy + r * 0.5, c.dx, c.dy + r * 0.5)
      ..close();
    canvas.drawPath(
        f,
        Paint()
          ..shader = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: flame)
              .createShader(Rect.fromCircle(center: c, radius: r * 0.56)));
    canvas.drawOval(Rect.fromCenter(center: c.translate(0, r * 0.24), width: r * 0.26, height: r * 0.34),
        Paint()..color = Colors.white.withOpacity(0.85));
    if (t >= 0 && t < 0.35) {
      final k = t / 0.35;
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.94)));
      final x = -r + k * r * 4;
      canvas.drawPath(
          Path()
            ..moveTo(x, 0)
            ..lineTo(x + r * 0.35, 0)
            ..lineTo(x - r * 0.65, size.height)
            ..lineTo(x - r, size.height)
            ..close(),
          Paint()..color = Colors.white.withOpacity(0.45));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CoinPainter old) => old.t != t || old.gold != gold;
}

/// One pill with both balances: gold Cinder Coins and silver coins.
class CoinChip extends StatelessWidget {
  const CoinChip({super.key, required this.gold, required this.silver, this.onTap, this.big = false});
  final int gold, silver;
  final VoidCallback? onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    Widget part(bool isGold, int n) => Row(mainAxisSize: MainAxisSize.min, children: [
          CoinIcon(gold: isGold, size: big ? 28 : 20),
          const SizedBox(width: 3),
          Text('$n',
              style: TextStyle(
                  fontFamily: Rpg.display,
                  fontFamilyFallback: Rpg.arabicDisplay,
                  fontWeight: FontWeight.w800,
                  fontSize: big ? 20 : 15,
                  color: isGold ? const Color(0xFFFFD27A) : const Color(0xFFDDE5F0))),
        ]);
    final chip = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 3, 10, 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF3A1A0E), Color(0xFF231022)]),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE07A1F), width: 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        part(true, gold),
        const SizedBox(width: 8),
        part(false, silver),
      ]),
    );
    if (onTap == null) return chip;
    return Semantics(
      container: true,
      button: true,
      label: '${tr('Cinder Coins')} $gold, ${tr('Silver coins')} $silver',
      child: InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap, child: chip),
    );
  }
}

/// My rank at a glance: badge, rank name, rating and the bar to the next
/// division. Used on the home screen, in the lobby and on the profile.
class RankCard extends StatelessWidget {
  const RankCard(this.stats, {super.key, this.onTap, this.compact = false});
  final PlayerStats stats;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rank = stats.rank;
    final t = rank.tier;
    final next = rank.next;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [Color.lerp(Rpg.surface, t.dark, 0.35)!, Rpg.surface],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.light.withOpacity(0.7), width: 2),
      ),
      child: Row(children: [
        RankBadge(rank, size: compact ? 42 : 54),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(rank.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: Rpg.display,
                        fontFamilyFallback: Rpg.arabicDisplay,
                        fontSize: compact ? 19 : 22,
                        fontWeight: FontWeight.w800,
                        color: t.light)),
              ),
              const SizedBox(width: 8),
              Text('${stats.rating}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Rpg.ink2)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: rank.progress(stats.rating),
                minHeight: 8,
                backgroundColor: Rpg.surface2,
                color: t.light,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              next == null
                  ? tr('Top rank')
                  : tr('{n} to {rank}', {'n': next - stats.rating, 'rank': Rank.of(next).name}),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Rpg.ink3),
            ),
          ]),
        ),
      ]),
    );
    if (onTap == null) return card;
    return Semantics(
      container: true,
      button: true,
      label: '${rank.name}, ${stats.rating}',
      child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: card),
    );
  }
}

/// All eight ranks in a row, lowest to highest: for the profile. The last
/// one stays a shadow until you reach Grandmaster.
class RankLadder extends StatelessWidget {
  const RankLadder({super.key, required this.current});
  final RankTier current;

  bool _hidden(RankTier t) => t == RankTier.champion && current.index < RankTier.grandmaster.index;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final t in RankTier.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Opacity(
                opacity: t.index <= current.index || _hidden(t) ? 1 : 0.45,
                child: Column(children: [
                  if (_hidden(t))
                    const _MysteryBadge(size: 46)
                  else
                    RankBadge(Rank(t, 1, t.start, null), size: 46, animate: t == current),
                  const SizedBox(height: 2),
                  Text(_hidden(t) ? '???' : tr(t.label),
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, color: t == current ? t.light : Rpg.ink3)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// The last rank before it is in sight: a shadow of the emblem and a
/// question mark breathing in its middle.
class _MysteryBadge extends StatelessWidget {
  const _MysteryBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '???',
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: size * 0.9,
          height: size * 0.9,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x66D25BFF), blurRadius: 18, spreadRadius: 2)],
          ),
        ),
        ColorFiltered(
          colorFilter: const ColorFilter.mode(Color(0xFF34205C), BlendMode.srcIn),
          child: RankBadge(Rank.of(RankTier.champion.start), size: size, animate: false),
        ),
        Pulse(
          amount: 0.12,
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.12),
            child: Text('?',
                style: TextStyle(
                    fontFamily: Rpg.display,
                    fontSize: size * 0.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFD25BFF),
                    shadows: const [Shadow(color: Color(0xFF8FF6FF), blurRadius: 10)])),
          ),
        ),
      ]),
    );
  }
}
