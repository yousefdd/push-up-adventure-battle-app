import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'theme/rpg_theme.dart';

/// Where ads will go. Nothing is loaded yet: each slot is a marked, empty
/// space of a standard ad size, so the layout already leaves room for it.
/// When an ad network is added, fill these two widgets and nothing else.
class Ads {
  /// Turn every slot off (e.g. for a paid "no ads" option later).
  static bool enabled = true;
}

/// Standard ad sizes, in logical pixels.
enum AdSize {
  /// 320 × 50: a strip at the bottom of a screen.
  banner(320, 50),

  /// 300 × 250: a box between blocks of content.
  rectangle(300, 250);

  const AdSize(this.width, this.height);
  final double width, height;
}

/// An empty, labelled space of [size], centred in its row.
class AdSlot extends StatelessWidget {
  const AdSlot({super.key, this.size = AdSize.banner, this.margin = const EdgeInsets.symmetric(vertical: 8)});
  final AdSize size;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    if (!Ads.enabled) return const SizedBox.shrink();
    return Padding(
      padding: margin,
      child: Center(
        child: Semantics(
          label: tr('Ad space'),
          child: Container(
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              color: Rpg.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Rpg.border2, width: 1.5),
            ),
            child: Stack(children: [
              PositionedDirectional(
                top: 4,
                start: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Rpg.border2, borderRadius: BorderRadius.circular(4)),
                  child: Text(tr('AD'),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Rpg.ink3)),
                ),
              ),
              Center(
                child: Text(tr('Ad space'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Rpg.ink3)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The break after a match or a finished adventure run: a full screen with
/// room for one ad. It can be closed after a few seconds.
class AdBreak extends StatefulWidget {
  const AdBreak({super.key, this.seconds = 5});
  final int seconds;

  /// Shows the break over [navigator] (if ads are on) and waits for it to close.
  static Future<void> show(NavigatorState navigator) async {
    if (!Ads.enabled) return;
    await navigator.push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const AdBreak(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  State<AdBreak> createState() => _AdBreakState();
}

class _AdBreakState extends State<AdBreak> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left = (_left - 1).clamp(0, 99));
      if (_left == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canClose = _left == 0;
    return PopScope(
      canPop: canClose,
      child: Scaffold(
        backgroundColor: Rpg.bgDeep,
        body: SafeArea(
          child: Stack(children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Rpg.surface2,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Rpg.border2, width: 2),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Rpg.border2, borderRadius: BorderRadius.circular(6)),
                        child: Text(tr('AD'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Rpg.ink3)),
                      ),
                      const SizedBox(height: 10),
                      Text(tr('Ad space'),
                          style: const TextStyle(
                              fontFamily: Rpg.display,
                              fontFamilyFallback: Rpg.arabicDisplay,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Rpg.ink3)),
                    ]),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              top: 10,
              end: 10,
              child: Semantics(
                container: true,
                button: true,
                enabled: canClose,
                label: canClose ? tr('Close') : tr('Close in {n}', {'n': _left}),
                child: GestureDetector(
                  onTap: canClose ? () => Navigator.of(context).pop() : null,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Rpg.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: canClose ? Rpg.ink2 : Rpg.border2, width: 2),
                    ),
                    child: canClose
                        ? const Icon(Icons.close, color: Rpg.ink)
                        : Text('$_left',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Rpg.ink2)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
