import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Small, reusable motion for the whole app. Every looping effect checks
/// [Motion.loops] so widget tests (and people who turn animations off in the
/// system settings) get still pictures and settled frames.
class Motion {
  /// Tests set this to false so pumpAndSettle can settle.
  static bool loops = true;

  static bool on(BuildContext context) => loops && !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
}

/// Fades and slides its child up into place once, after [index] × [step].
/// Lists use it for a staggered entrance.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.step = const Duration(milliseconds: 60),
    this.offset = 24,
  });

  final Widget child;
  final int index;
  final Duration step;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    Future.delayed(widget.step * widget.index, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Motion.on(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * widget.offset), child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Bounces its child whenever [trigger] changes (a new item worn, a level up).
class Pop extends StatelessWidget {
  const Pop({super.key, required this.trigger, required this.child, this.from = 0.6});

  final Object? trigger;
  final Widget child;
  final double from;

  @override
  Widget build(BuildContext context) {
    if (!Motion.on(context)) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: from, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (context, v, c) => Transform.scale(scale: v, child: c),
      child: child,
    );
  }
}

/// A gentle endless float, for idle characters and pets.
class Bob extends StatefulWidget {
  const Bob({super.key, required this.child, this.height = 6, this.period = const Duration(milliseconds: 1800)});

  final Widget child;
  final double height;
  final Duration period;

  @override
  State<Bob> createState() => _BobState();
}

class _BobState extends State<Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.on(context)) {
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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, math.sin(_c.value * 2 * math.pi) * widget.height), child: child),
      child: widget.child,
    );
  }
}

/// A slow breathing scale, for the one button that matters on a screen.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child, this.amount = 0.04, this.enabled = true});

  final Widget child;
  final double amount;
  final bool enabled;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.enabled && Motion.on(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) =>
          Transform.scale(scale: 1 + widget.amount * Curves.easeInOut.transform(_c.value), child: child),
      child: widget.child,
    );
  }
}

/// Turning rays of light behind a reward (merges, rare loot, level ups).
class RayBurst extends StatefulWidget {
  const RayBurst({super.key, required this.color, required this.size, this.child});

  final Color color;
  final double size;
  final Widget? child;

  @override
  State<RayBurst> createState() => _RayBurstState();
}

class _RayBurstState extends State<RayBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 8));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.on(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Transform.rotate(
            angle: _c.value * 2 * math.pi,
            child: CustomPaint(size: Size.square(widget.size), painter: _RaysPainter(widget.color)),
          ),
        ),
        if (widget.child != null) widget.child!,
      ]),
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final glow = Paint()
      ..shader = RadialGradient(colors: [color.withOpacity(0.55), color.withOpacity(0)])
          .createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, glow);
    final ray = Paint()..color = color.withOpacity(0.28);
    const n = 12;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a - 0.11), c.dy + r * math.sin(a - 0.11))
        ..lineTo(c.dx + r * math.cos(a + 0.11), c.dy + r * math.sin(a + 0.11))
        ..close();
      canvas.drawPath(path, ray);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.color != color;
}

/// Shrinks a little under the finger, so every tap feels pressed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.93 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A short shake every couple of seconds, for things that want to be tapped
/// (a closed chest on the road).
class Wiggle extends StatefulWidget {
  const Wiggle({super.key, required this.child, this.angle = 0.12});

  final Widget child;
  final double angle;

  @override
  State<Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<Wiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.on(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // Still for most of the cycle, then four quick swings that fade out.
        final v = _c.value;
        final a = v < 0.75 ? 0.0 : math.sin((v - 0.75) / 0.25 * 4 * math.pi) * (1 - (v - 0.75) / 0.25);
        return Transform.rotate(angle: a * widget.angle, alignment: Alignment.bottomCenter, child: child);
      },
      child: widget.child,
    );
  }
}
