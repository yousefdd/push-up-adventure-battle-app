import 'package:flutter/material.dart' hide Hero;

import '../../../i18n/i18n.dart';
import '../../../ui/motion.dart';
import '../../../ui/theme/adventure_tokens.dart';
import '../adventure_rules.dart';
import 'adv_widgets.dart';

const _t = AdvTokens.space;

/// Every creature of the adventure, world by world. The ones you have met
/// show their picture, name and line; the rest are dark silhouettes.
class BestiaryPanel extends StatelessWidget {
  const BestiaryPanel({super.key, required this.seen});

  /// Picture ids of the foes met so far (the save's `seen` list).
  final Set<String> seen;

  @override
  Widget build(BuildContext context) {
    final total = chapters.fold(0, (n, c) => n + c.foes.length + 1);
    final met = chapters.expand((c) => [...c.foes, c.boss]).where((f) => seen.contains(f.img)).length;
    return ListView(
      padding: EdgeInsets.fromLTRB(_t[4], _t[3], _t[4], _t[5]),
      children: [
        Row(children: [
          const Icon(Icons.menu_book, color: AdvTokens.goldTop, size: AdvTokens.sizeIcon * 0.8),
          SizedBox(width: _t[2]),
          Expanded(
            child: Text(tr('Creatures met: {n} of {total}', {'n': met, 'total': total}),
                style: AdvTokens.sm.copyWith(color: AdvTokens.text)),
          ),
        ]),
        SizedBox(height: _t[1]),
        ClipRRect(
          borderRadius: BorderRadius.circular(AdvTokens.radiusPill),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : met / total,
            minHeight: _t[2],
            color: AdvTokens.goldTop,
            backgroundColor: AdvTokens.surfaceDeep,
          ),
        ),
        SizedBox(height: _t[4]),
        for (final (wi, ch) in chapters.indexed) ...[
          FadeSlideIn(
            index: wi,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StrokeText('${trChapter(ch.number, ch.roman)} · ${tr(ch.name)}',
                  style: AdvTokens.sm, color: AdvTokens.goldTop),
              SizedBox(height: _t[2]),
              // Six to a row: a world's five foes and its boss side by side.
              LayoutBuilder(builder: (context, box) {
                final size = ((box.maxWidth - 5 * _t[2]) / 6).clamp(40.0, AdvTokens.sizeEventNext * 1.4);
                return Wrap(spacing: _t[2], runSpacing: _t[2], children: [
                  for (final f in [...ch.foes, ch.boss])
                    _Creature(foe: f, boss: f == ch.boss, met: seen.contains(f.img), world: ch, size: size),
                ]);
              }),
              SizedBox(height: _t[4]),
            ]),
          ),
        ],
      ],
    );
  }
}

class _Creature extends StatelessWidget {
  const _Creature({required this.foe, required this.boss, required this.met, required this.world, required this.size});

  final FoeKind foe;
  final bool boss, met;
  final ChapterDef world;
  final double size;

  @override
  Widget build(BuildContext context) {
    final art = Image.asset(rpgAsset(foe.img), width: size, height: size, filterQuality: FilterQuality.medium);
    return Pressable(
      onTap: met ? () => _details(context) : null,
      child: SizedBox(
        width: size,
        child: Column(children: [
          Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(_t[1]),
            decoration: BoxDecoration(
              color: AdvTokens.surfaceDeep,
              borderRadius: BorderRadius.circular(AdvTokens.radiusCard),
              border: Border.all(
                  color: boss && met ? AdvTokens.goldTop : AdvTokens.outline, width: AdvTokens.strokeOutline),
            ),
            child: met ? art : MysterySprite(foe.img, size: size * 0.8),
          ),
          SizedBox(height: _t[1] / 2),
          Text(met ? trName(foe.name) : '???',
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AdvTokens.micro.copyWith(color: met ? AdvTokens.text : AdvTokens.textMuted)),
        ]),
      ),
    );
  }

  void _details(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AdvTokens.surface,
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(_t[4]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Bob(child: Sprite(foe.img, size: AdvTokens.sizeSpriteBoss)),
            SizedBox(height: _t[2]),
            if (boss) Ribbon(tr('BOSS!')),
            StrokeText(trName(foe.name), style: AdvTokens.title),
            Text('${trChapter(world.number, world.roman)} · ${tr(world.name)}',
                style: AdvTokens.sm.copyWith(color: AdvTokens.textMuted)),
            SizedBox(height: _t[2]),
            AbilityTag(foe.ability),
            Text(tr(foe.ability.text),
                textAlign: TextAlign.center, style: AdvTokens.sm.copyWith(color: AdvTokens.text)),
            SizedBox(height: _t[2]),
            Text('“${tr(foe.quote)}”',
                textAlign: TextAlign.center, style: AdvTokens.base.copyWith(color: AdvTokens.rewardText)),
          ]),
        ),
      ),
    );
  }
}
