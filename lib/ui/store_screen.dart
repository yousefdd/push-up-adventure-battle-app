import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../online/ranked.dart';
import 'ads.dart';
import 'motion.dart';
import 'rank_widgets.dart';
import 'theme/rpg_theme.dart';

/// The store. Nothing is for sale yet: it shows both balances, what each
/// coin will buy, and how to earn them.
class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  /// What gold Cinder Coins will buy.
  static const rewards = [
    (Icons.diamond_outlined, 'Free Fire top-up cards', 'Diamonds for your Free Fire account'),
    (Icons.local_fire_department_outlined, 'PUBG Mobile top-up cards', 'UC for your PUBG Mobile account'),
    (Icons.phone_android, 'Mobile credit', 'Top up your phone line'),
  ];

  /// What silver coins will buy.
  static const silverRewards = [
    (Icons.checkroom_rounded, 'Hero outfits', 'New looks for your heroes'),
    (Icons.crop_square_rounded, 'Profile frames', 'A frame around your picture in races'),
    (Icons.inventory_2_rounded, 'In-game items', 'Gear and boosts for your adventure'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Rpg.bg,
        title: Text(tr('Store'),
            style: const TextStyle(
                fontFamily: Rpg.display, fontFamilyFallback: Rpg.arabicDisplay, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<PlayerStats>(
          valueListenable: Ranked.stats,
          builder: (context, s, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Row(children: [
                Expanded(child: _balance(true, s.gold)),
                const SizedBox(width: 10),
                Expanded(child: _balance(false, s.silver)),
              ]),
              const SizedBox(height: 16),
              _section(true),
              for (final (i, r) in rewards.indexed)
                FadeSlideIn(index: i + 1, child: _reward(r.$1, tr(r.$2), tr(r.$3), true)),
              const SizedBox(height: 14),
              _section(false),
              for (final (i, r) in silverRewards.indexed)
                FadeSlideIn(index: i + 4, child: _reward(r.$1, tr(r.$2), tr(r.$3), false)),
              const SizedBox(height: 18),
              _howToEarn(),
              const AdSlot(margin: EdgeInsets.only(top: 18)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balance(bool gold, int n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gold ? const [Color(0xFF3A1A0E), Color(0xFF1B1030)] : const [Color(0xFF26303F), Color(0xFF151827)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold ? const Color(0xFFE07A1F) : const Color(0xFF9AA8BE), width: 2),
      ),
      child: Column(children: [
        Bob(child: CoinIcon(gold: gold, size: 52)),
        const SizedBox(height: 6),
        Text('$n',
            style: TextStyle(
                fontFamily: Rpg.display,
                fontFamilyFallback: Rpg.arabicDisplay,
                fontSize: 34,
                height: 1.05,
                fontWeight: FontWeight.w800,
                color: gold ? const Color(0xFFFFD27A) : const Color(0xFFE8EEF6))),
        Text(tr(gold ? 'Cinder Coins' : 'Silver coins'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Rpg.ink2)),
      ]),
    );
  }

  /// "Cinder Coin rewards · Coming soon" or the silver one.
  Widget _section(bool gold) {
    final color = gold ? Rpg.gold : const Color(0xFFDDE5F0);
    return Pulse(
      amount: 0.015,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: Rpg.panel(
          fill: gold ? Rpg.goldSoft : const Color(0xFF1C2230),
          border: gold ? Rpg.goldEdge : const Color(0xFF7D8BA3),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            CoinIcon(gold: gold, size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(tr(gold ? 'Cinder Coin rewards' : 'Silver coin rewards'),
                    style: TextStyle(
                        fontFamily: Rpg.display,
                        fontFamilyFallback: Rpg.arabicDisplay,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
            ),
          ]),
          const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.hourglass_top_rounded, color: color, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(tr('Coming soon'),
                  style: TextStyle(
                      fontFamily: Rpg.display,
                      fontFamilyFallback: Rpg.arabicDisplay,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _reward(IconData icon, String name, String line, bool gold) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: Rpg.panel(),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Rpg.surface3, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Rpg.ink2, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: const TextStyle(
                      fontFamily: Rpg.display,
                      fontFamilyFallback: Rpg.arabicDisplay,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Rpg.ink)),
              Text(line, style: const TextStyle(fontSize: 13, color: Rpg.ink3)),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Rpg.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Rpg.border2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CoinIcon(gold: gold, size: 16, animate: false),
              const SizedBox(width: 4),
              const Icon(Icons.lock_outline, size: 14, color: Rpg.ink3),
              const SizedBox(width: 3),
              Text(tr('Soon'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Rpg.ink3)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _howToEarn() {
    Widget row(String text, String amount, bool gold, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: Rpg.ink))),
            // Signs and ranges read left to right in both languages.
            Text(amount, textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            const SizedBox(width: 4),
            CoinIcon(gold: gold, size: 18, animate: false),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Rpg.panel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('How to earn coins'),
            style: const TextStyle(
                fontFamily: Rpg.display,
                fontFamilyFallback: Rpg.arabicDisplay,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Rpg.ink)),
        const SizedBox(height: 6),
        Text(tr('Below Diamond'), style: const TextStyle(fontWeight: FontWeight.w800, color: Rpg.ink3)),
        row(tr('Win a ranked race'), '+3…6', false, Rpg.vigor),
        row(tr('Lose a ranked race'), '−2', false, Rpg.danger),
        row(tr('Clear adventure worlds 1–7'), '+2', false, Rpg.vigor),
        const SizedBox(height: 8),
        Text(tr('Diamond and above'), style: const TextStyle(fontWeight: FontWeight.w800, color: Rpg.ink3)),
        row(tr('Win a ranked race'), '+2…4', true, Rpg.vigor),
        row(tr('Lose a ranked race'), '−1', true, Rpg.danger),
        row(tr('Clear world 8 or higher, or Nightmare'), '+1', true, Rpg.vigor),
        const SizedBox(height: 6),
        Text(tr('Daily limits: 30 silver and 10 Cinder Coins from races. Stronger rivals pay more.'),
            style: const TextStyle(fontSize: 13, color: Rpg.ink3)),
      ]),
    );
  }
}
