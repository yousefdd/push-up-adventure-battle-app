// The Gear tab: the hero with six slots, what the worn gear adds, and the
// bag. Three identical pieces merge into one of the next rarity.

import 'package:flutter/material.dart' hide Hero;

import '../../../ui/theme/adventure_tokens.dart';
import '../adventure_rules.dart';
import 'adv_widgets.dart';
import '../../../i18n/i18n.dart';
import '../../../ui/motion.dart';

const _t = AdvTokens.space;

String slotName(Slot s) => switch (s) {
      Slot.weapon => tr('Weapon'),
      Slot.armor => tr('Armor'),
      Slot.helmet => tr('Helmet'),
      Slot.boots => tr('Boots'),
      Slot.ring => tr('Ring'),
      Slot.amulet => tr('Amulet'),
    };

class ArmoryPanel extends StatelessWidget {
  const ArmoryPanel({super.key, required this.armory, required this.heroClass, required this.onChanged});
  final Armory armory;
  final HeroClass heroClass;

  /// Called after any change, so the screen can save.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    // Every piece is its own tile; identical pieces sit side by side so a
    // pair is easy to spot and drag together.
    final bag = [...armory.items]..sort((a, b) {
        final s = a.slot.index.compareTo(b.slot.index);
        if (s != 0) return s;
        final k = a.kind.compareTo(b.kind);
        return k != 0 ? k : b.rarity.index.compareTo(a.rarity.index);
      });
    return ListView(
      padding: EdgeInsets.fromLTRB(_t[4], _t[3], _t[4], _t[5]),
      children: [
        _paperDoll(context),
        SizedBox(height: _t[3]),
        _stats(),
        SizedBox(height: _t[4]),
        Row(children: [
          Expanded(child: StrokeText('${tr('Bag')}  ${armory.items.length}', style: AdvTokens.lg)),
          _smallButton(
              tr('Equip best'),
              Icons.auto_fix_high,
              armory.items.isEmpty
                  ? null
                  : () {
                      armory.equipBest();
                      onChanged();
                    }),
        ]),
        SizedBox(height: _t[2]),
        if (bag.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: _t[5]),
            child: Text(
                tr('No gear yet. Every run drops some: longer runs, cleared worlds and harder tiers drop more.'),
                textAlign: TextAlign.center,
                style: AdvTokens.sm.copyWith(color: AdvTokens.textMuted)),
          )
        else
          Wrap(spacing: _t[2], runSpacing: _t[2], children: [
            for (final (i, item) in bag.indexed)
              FadeSlideIn(
                key: ValueKey(item.id),
                index: i,
                step: const Duration(milliseconds: 25),
                child: _BagTile(
                  item: item,
                  armory: armory,
                  onTap: () => _details(context, item),
                  onMerged: (up) {
                    onChanged();
                    _celebrate(context, [up]);
                  },
                ),
              ),
          ]),
        SizedBox(height: _t[3]),
        Row(children: [
          const Icon(Icons.pan_tool_alt, size: AdvTokens.sizeIcon * 0.6, color: AdvTokens.goldTop),
          SizedBox(width: _t[2]),
          Expanded(
            child: Text(
                tr('Hold a piece and drop it on an identical one (same piece, same rarity) to merge them into the next rarity: Common → Uncommon → Rare → Epic → Legendary → Mythic. Drop a piece on the hero to wear it.'),
                style: AdvTokens.xs.copyWith(color: AdvTokens.textMuted)),
          ),
        ]),
      ],
    );
  }

  Widget _paperDoll(BuildContext context) {
    Widget slot(Slot s) {
      final item = armory.worn(s);
      return DragTarget<GearItem>(
        onWillAcceptWithDetails: (d) => d.data.slot == s && !armory.isWorn(d.data),
        onAcceptWithDetails: (d) {
          armory.equip(d.data);
          onChanged();
        },
        builder: (context, ok, no) => AnimatedScale(
          scale: ok.isNotEmpty ? 1.15 : 1,
          duration: const Duration(milliseconds: 150),
          child: GestureDetector(
            onTap: item == null ? null : () => _details(context, item),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              item == null
                  ? Container(
                      width: AdvTokens.sizeEventNext * 1.2,
                      height: AdvTokens.sizeEventNext * 1.2,
                      decoration: BoxDecoration(
                        color: AdvTokens.surfaceDeep,
                        borderRadius: BorderRadius.circular(AdvTokens.radiusCard),
                        border: Border.all(color: AdvTokens.surface, width: AdvTokens.strokeOutline),
                      ),
                      child: const Icon(Icons.add, color: AdvTokens.surface, size: AdvTokens.sizeIcon),
                    )
                  : Pop(trigger: item.id, child: GearIcon(item, size: AdvTokens.sizeEventNext * 1.2)),
              SizedBox(height: _t[1] / 2),
              Text(slotName(s),
                  style: AdvTokens.xs.copyWith(color: ok.isNotEmpty ? AdvTokens.goldTop : AdvTokens.textMuted)),
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(_t[3]),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AdvTokens.surface, AdvTokens.surfaceDeep],
        ),
        borderRadius: BorderRadius.circular(AdvTokens.radiusPanel),
        border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeOutline),
      ),
      child: Row(children: [
        Column(children: [
          slot(Slot.weapon),
          SizedBox(height: _t[2]),
          slot(Slot.armor),
          SizedBox(height: _t[2]),
          slot(Slot.helmet)
        ]),
        Expanded(
          child: Column(children: [
            Bob(child: Sprite(heroClass.sprite, size: AdvTokens.sizeSpriteBoss)),
            StrokeText(tr(heroClass.name), style: AdvTokens.lg),
          ]),
        ),
        Column(children: [
          slot(Slot.boots),
          SizedBox(height: _t[2]),
          slot(Slot.ring),
          SizedBox(height: _t[2]),
          slot(Slot.amulet)
        ]),
      ]),
    );
  }

  Widget _stats() {
    final b = armory.bonus;
    final lines = b.lines;
    return Container(
      padding: EdgeInsets.all(_t[3]),
      decoration: BoxDecoration(
        color: AdvTokens.card,
        borderRadius: BorderRadius.circular(AdvTokens.radiusCard),
        border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeText),
      ),
      child: lines.isEmpty
          ? Text(tr('Wear gear to start every run stronger.'),
              style: AdvTokens.sm.copyWith(color: AdvTokens.textOnCard))
          : Wrap(spacing: _t[3], runSpacing: _t[1], children: [
              for (final l in lines) Text(l, style: AdvTokens.sm.copyWith(color: AdvTokens.textOnCard)),
            ]),
    );
  }

  Widget _smallButton(String label, IconData icon, VoidCallback? onTap) {
    final on = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: _t[2], vertical: _t[1]),
        decoration: BoxDecoration(
          color: on ? AdvTokens.gold : AdvTokens.surface,
          borderRadius: BorderRadius.circular(AdvTokens.radiusPill),
          border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeText),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: AdvTokens.sizeIcon * 0.6, color: on ? AdvTokens.onGold : AdvTokens.textMuted),
          SizedBox(width: _t[1]),
          Text(label, style: AdvTokens.xs.copyWith(color: on ? AdvTokens.onGold : AdvTokens.textMuted)),
        ]),
      ),
    );
  }

  Future<void> _celebrate(BuildContext context, List<GearItem> made) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: AdvTokens.surface,
          child: Padding(
            padding: EdgeInsets.all(_t[4]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Ribbon(tr('Merged!')),
              SizedBox(height: _t[3]),
              Wrap(spacing: _t[2], runSpacing: _t[2], alignment: WrapAlignment.center, children: [
                for (final m in made)
                  RayBurst(
                    color: rarityColor(m.rarity),
                    size: AdvTokens.sizeEventNext * 2.2,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.3, end: 1),
                      duration: AdvTokens.walk,
                      curve: Curves.elasticOut,
                      builder: (_, v, c) =>
                          Transform.rotate(angle: (1 - v) * 0.6, child: Transform.scale(scale: v, child: c)),
                      child: GearIcon(m, size: AdvTokens.sizeEventNext * 1.3),
                    ),
                  ),
              ]),
              SizedBox(height: _t[2]),
              Text(made.length == 1 ? made.first.name : tr('{n} pieces upgraded', {'n': made.length}),
                  style: AdvTokens.sm.copyWith(color: AdvTokens.text)),
              SizedBox(height: _t[3]),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Nice'))),
            ]),
          ),
        ),
      );

  Future<void> _details(BuildContext context, GearItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AdvTokens.surface,
      builder: (sheet) => StatefulBuilder(builder: (sheet, setSheet) {
        final pairs = armory.twins(item).length - 1;
        final worn = armory.isWorn(item);
        final next = item.rarity.next;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(_t[4]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RayBurst(
                  color: rarityColor(item.rarity),
                  size: AdvTokens.sizeLoot * 1.6,
                  child: Pop(trigger: item.id, child: GearIcon(item, size: AdvTokens.sizeLoot))),
              SizedBox(height: _t[2]),
              StrokeText(item.name, style: AdvTokens.title, color: rarityColor(item.rarity)),
              Text(tr('{slot} · {n} more like it', {'slot': slotName(item.slot), 'n': pairs}),
                  style: AdvTokens.sm.copyWith(color: AdvTokens.textMuted)),
              SizedBox(height: _t[2]),
              Wrap(spacing: _t[3], children: [
                for (final l in item.bonus.lines) Text(l, style: AdvTokens.base.copyWith(color: AdvTokens.rewardText)),
              ]),
              if (next != null) ...[
                SizedBox(height: _t[2]),
                Text(
                    '${tr('Drag onto an identical piece →')} ${GearItem(0, item.kind, next).name}: ${GearItem(0, item.kind, next).bonus.lines.join(' · ')}',
                    textAlign: TextAlign.center,
                    style: AdvTokens.xs.copyWith(color: AdvTokens.textMuted)),
              ],
              SizedBox(height: _t[4]),
              Row(children: [
                Expanded(
                  child: ActionButton(
                    variant: worn ? ActionVariant.wait : ActionVariant.go,
                    label: worn ? tr('Worn') : tr('Equip'),
                    sub: slotName(item.slot),
                    onPressed: worn
                        ? null
                        : () {
                            armory.equip(item);
                            onChanged();
                            Navigator.pop(sheet);
                          },
                  ),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
  }
}

/// One piece in the bag. Hold it to drag; drop it on an identical piece to
/// merge the two, or on the hero's matching slot to wear it. While a piece
/// hovers over this one, the tile grows and glows gold if they would merge.
class _BagTile extends StatelessWidget {
  const _BagTile({required this.item, required this.armory, required this.onTap, required this.onMerged});

  final GearItem item;
  final Armory armory;
  final VoidCallback onTap;
  final void Function(GearItem up) onMerged;

  static const double _size = AdvTokens.sizeEventNext * 1.2;

  @override
  Widget build(BuildContext context) {
    final hasPair = armory.canMerge(item);
    Widget tile({bool glow = false, bool deny = false}) => AnimatedScale(
          scale: glow ? 1.14 : 1,
          duration: const Duration(milliseconds: 140),
          child: Stack(clipBehavior: Clip.none, children: [
            GearIcon(item, size: _size, worn: armory.isWorn(item)),
            if (glow)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AdvTokens.radiusCard),
                    border: Border.all(color: AdvTokens.goldTop, width: AdvTokens.strokeOutline * 1.5),
                    boxShadow: [BoxShadow(color: AdvTokens.goldTop.withOpacity(0.7), blurRadius: _size / 4)],
                  ),
                  child: const Center(child: Icon(Icons.add_circle, color: AdvTokens.goldTop, size: _size / 2.6)),
                ),
              ),
            if (deny)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AdvTokens.outline.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(AdvTokens.radiusCard),
                  ),
                ),
              ),
            // A small link badge: this piece has a twin to merge with.
            if (hasPair && !glow)
              Positioned(
                right: -_size / 12,
                top: -_size / 12,
                child: Pulse(
                  amount: 0.15,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: AdvTokens.goldTop, shape: BoxShape.circle),
                    child: const Icon(Icons.merge_type, size: _size / 4.5, color: AdvTokens.onGold),
                  ),
                ),
              ),
          ]),
        );

    return DragTarget<GearItem>(
      onWillAcceptWithDetails: (d) => d.data.id != item.id && d.data.twin(item) && item.rarity.next != null,
      onAcceptWithDetails: (d) {
        final up = armory.mergeInto(d.data, item);
        if (up != null) onMerged(up);
      },
      builder: (context, ok, no) => LongPressDraggable<GearItem>(
        data: item,
        delay: const Duration(milliseconds: 160),
        feedback: Material(
          color: Colors.transparent,
          child: Transform.scale(scale: 1.18, child: GearIcon(item, size: _size)),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile()),
        child: Pressable(onTap: onTap, child: tile(glow: ok.isNotEmpty, deny: no.isNotEmpty)),
      ),
    );
  }
}
