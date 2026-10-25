// S14–S16: the adventure's home, with three tabs at the bottom like the
// original: Gear (equip and merge), Adventure (pick a world and a tier),
// Heroes (pick a class).

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Hero;

import '../../../engine/camera_pose_source.dart';
import '../../../engine/exercise.dart';
import '../../../ui/theme/adventure_tokens.dart';
import '../adventure_rules.dart';
import '../run_controller.dart';
import '../run_store.dart';
import 'adv_widgets.dart';
import 'armory_panel.dart';
import 'bestiary_panel.dart';
import 'fx.dart';
import 'run_screen.dart';
import '../../../i18n/i18n.dart';
import '../../../ui/motion.dart';
import '../../../ui/ads.dart';

const _t = AdvTokens.space;

class AdventureHome extends StatefulWidget {
  const AdventureHome({super.key, this.exercise = ExerciseType.pushup, RunStore? store})
      : store = store ?? const _DefaultStore();
  final ExerciseType exercise;
  final RunStore store;

  @override
  State<AdventureHome> createState() => _AdventureHomeState();
}

class _DefaultStore implements RunStore {
  const _DefaultStore();
  @override
  Future<Map<String, dynamic>?> load() => PrefsRunStore().load();
  @override
  Future<void> save(Map<String, dynamic> doc) => PrefsRunStore().save(doc);
}

class _AdventureHomeState extends State<AdventureHome> {
  Map<String, dynamic> _save = {'version': 1};
  bool _loading = true;
  PageController? _pages;
  int _page = 0;
  int _tab = 1; // 0 gear, 1 adventure, 2 heroes
  Tier _tier = Tier.normal;
  late Armory _armory = Armory();

  int get _unlocked => (_save['unlocked'] as int? ?? 1).clamp(1, chapters.length);
  String get _class => heroClassById(_save['class'] as String?).id;

  /// Creatures met in any run; the rest show as mysteries.
  Set<String> get _seen => {...(_save['seen'] as List? ?? const []).map((e) => '$e')};
  Map<String, dynamic>? get _run => _save['run'] == null ? null : Map<String, dynamic>.from(_save['run'] as Map);
  ChapterDef get _chapter => chapters[_page];
  bool get _open => _chapter.number <= _unlocked && RunController.tierOpen(_save, _chapter, _tier);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final s = await widget.store.load() ?? {'version': 1};
    if (!mounted) return;
    setState(() {
      _save = Map<String, dynamic>.from(s);
      _armory = Armory.fromJson(_save['gear']);
      _loading = false;
      final run = _run;
      _page = run != null ? RunController.chapterOf(run['chapter']).number - 1 : _unlocked - 1;
      _pages?.dispose();
      _pages = PageController(viewportFraction: 0.86, initialPage: _page);
      _tier = _bestOpenTier(_chapter);
    });
  }

  Tier _bestOpenTier(ChapterDef c) =>
      Tier.values.lastWhere((t) => RunController.tierOpen(_save, c, t) && !_cleared(c, t), orElse: () => Tier.normal);

  bool _cleared(ChapterDef c, Tier t) => RunController.tierCleared(_save, c, t);

  Future<void> _store() async {
    _save['gear'] = _armory.toJson();
    await widget.store.save(_save);
    if (mounted) setState(() {});
  }

  Future<void> _pickClass(String id) async {
    setState(() => _save['class'] = id);
    await widget.store.save(_save);
  }

  Future<void> _go({required bool resume}) async {
    final run = resume && _run != null
        ? RunController.resume(_run!, store: widget.store, save: _save)
        : RunController.start(store: widget.store, save: _save, chapter: _chapter, heroClass: _class, tier: _tier);
    final camera = kIsWeb ? null : CameraPoseSource();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RunScreen(
        run: run,
        exercise: widget.exercise,
        poseSource: camera,
        cameraBuilder: camera == null ? null : (overlay) => camera.preview(overlay: overlay),
      ),
    ));
    run.dispose();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdvTokens.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AdvTokens.sizeMaxWidth),
            child: Column(children: [
              Padding(
                padding: EdgeInsets.fromLTRB(_t[3], _t[3], _t[4], 0),
                child: Row(children: [
                  IconButton(
                    tooltip: tr('Back'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: AdvTokens.text),
                  ),
                  Expanded(
                      child: StrokeText(tr(['Gear', 'Adventure', 'Heroes', 'Bestiary'][_tab]), style: AdvTokens.title)),
                  if (!_loading)
                    StrokeText(I18n.isAr ? '$_unlocked من ${chapters.length}' : '$_unlocked/${chapters.length}',
                        style: AdvTokens.lg, color: AdvTokens.goldTop),
                ]),
              ),
              Expanded(
                child: _loading
                    ? const SizedBox.shrink()
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_tab),
                          child: switch (_tab) {
                            0 => ArmoryPanel(armory: _armory, heroClass: heroClassById(_class), onChanged: _store),
                            2 => _heroes(),
                            3 => BestiaryPanel(seen: _seen),
                            _ => _adventure(),
                          },
                        ),
                      ),
              ),
              _tabs(),
            ]),
          ),
        ),
      ),
    );
  }

  /// Bottom tabs with a raised centre, the way the original lays them out.
  Widget _tabs() {
    Widget tab(int i, IconData icon, String label) {
      final on = _tab == i;
      return Expanded(
        child: Semantics(
          container: true,
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tab = i),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: _t[2]),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedScale(
                  duration: AdvTokens.hit,
                  scale: on ? 1.25 : 1,
                  child: Icon(icon, color: on ? AdvTokens.goldTop : AdvTokens.textMuted, size: AdvTokens.sizeIcon),
                ),
                StrokeText(label, style: AdvTokens.xs, color: on ? AdvTokens.goldTop : AdvTokens.textMuted),
              ]),
            ),
          ),
        ),
      );
    }

    final mergeable = _armory.items.any(_armory.canMerge);
    return Container(
      decoration: const BoxDecoration(
        color: AdvTokens.surface,
        border: Border(top: BorderSide(color: AdvTokens.outline, width: AdvTokens.strokeOutline)),
      ),
      child: Row(children: [
        Expanded(
          child: Stack(alignment: Alignment.topCenter, children: [
            Row(children: [tab(0, Icons.shield, tr('Gear'))]),
            if (mergeable)
              Positioned(
                top: _t[1],
                right: _t[5],
                child: Container(
                  width: _t[3],
                  height: _t[3],
                  decoration: const BoxDecoration(color: AdvTokens.hp, shape: BoxShape.circle),
                ),
              ),
          ]),
        ),
        tab(1, Icons.explore, tr('Adventure')),
        tab(2, Icons.person, tr('Heroes')),
        tab(3, Icons.menu_book, tr('Bestiary')),
      ]),
    );
  }

  // ------------------------------------------------------------ adventure

  Widget _adventure() {
    final run = _run;
    final runChapter = run == null ? null : RunController.chapterOf(run['chapter']);
    final worldOpen = _chapter.number <= _unlocked;
    return ListView(
      padding: EdgeInsets.symmetric(vertical: _t[3]),
      children: [
        if (_pages != null)
          SizedBox(
            height: AdvTokens.sizeScene * 1.1,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
              ),
              child: PageView.builder(
                controller: _pages,
                itemCount: chapters.length,
                onPageChanged: (i) => setState(() {
                  _page = i;
                  _tier = _bestOpenTier(chapters[i]);
                }),
                // Cards beside the centre shrink and dim a little as they slide.
                itemBuilder: (_, i) => AnimatedBuilder(
                  animation: _pages!,
                  builder: (context, child) {
                    final p = _pages!.hasClients && _pages!.position.haveDimensions
                        ? (_pages!.page ?? _page.toDouble())
                        : _page.toDouble();
                    final d = (p - i).abs().clamp(0.0, 1.0);
                    return Opacity(opacity: 1 - 0.35 * d, child: Transform.scale(scale: 1 - 0.08 * d, child: child));
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: _t[1]),
                    child: _worldCard(chapters[i]),
                  ),
                ),
              ),
            ),
          ),
        SizedBox(height: _t[1]),
        _dots(),
        SizedBox(height: _t[2]),
        if (worldOpen) _tierPicker(),
        SizedBox(height: _t[3]),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _t[4]),
          child: Column(children: [
            if (run != null && runChapter == _chapter) ...[
              ActionButton(
                variant: ActionVariant.go,
                label: tr('Continue'),
                sub: '${tr('Day {n}', {'n': run['day']})} · ${tr('Lv.')}${(run['hero'] as Map)['lv']}',
                onPressed: () => _go(resume: true),
              ),
              SizedBox(height: _t[2]),
              TextButton(
                onPressed: () => _go(resume: false),
                child: Text(tr('Start a new run'), style: AdvTokens.sm.copyWith(color: AdvTokens.textMuted)),
              ),
            ] else
              Pulse(
                enabled: _open,
                child: ActionButton(
                  variant: _open ? ActionVariant.pick : ActionVariant.wait,
                  label: _open ? tr('Start') : tr('Locked'),
                  sub: !worldOpen
                      ? tr('Clear {world} first', {'world': tr(chapters[_chapter.number - 2].name)})
                      : _open
                          ? tr('30 days · {tier}', {'tier': tr(_tier.label)})
                          : tr('Beat all {n} worlds first', {'n': chapters.length}),
                  onPressed: !_open ? null : () => _go(resume: false),
                ),
              ),
            SizedBox(height: _t[4]),
            _howTo(),
            const AdSlot(margin: EdgeInsets.only(top: 16)),
          ]),
        ),
      ],
    );
  }

  /// A world: its pixel landscape, its boss towering on the right, the hero
  /// on the left, and the name and best run over the sky.
  Widget _worldCard(ChapterDef c) {
    final open = c.number <= _unlocked;
    final best = RunController.bestIn(_save, c);
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight, w = box.maxWidth;
      // Like the road in a run: painted scenery on top with the world's name
      // over it, a wide road where the hero and the boss stand, grass below.
      final strip = h * 0.46, road = h * 0.3;
      final feet = h - strip - road * 0.78;
      final ground = Color(c.ground);
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AdvTokens.radiusPanel),
          border: Border.all(
              color: _cleared(c, Tier.normal) ? AdvTokens.goldTop : AdvTokens.outline, width: AdvTokens.strokeOutline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          Positioned(
            left: 0,
            right: 0,
            top: strip + road - 2,
            bottom: 0,
            child: ColoredBox(color: Color.lerp(ground, AdvTokens.flash, 0.12)!),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: strip - 2,
            height: road,
            child: CustomPaint(painter: RoadPainter(Color.lerp(ground, AdvTokens.road, 0.78)!, 0)),
          ),
          for (final layer in [c.far, c.near])
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: strip,
              child: Image.asset(rpgAsset(layer),
                  fit: BoxFit.cover, alignment: Alignment.bottomCenter, filterQuality: FilterQuality.medium),
            ),
          Positioned(
            top: _t[3],
            left: _t[3],
            right: _t[3],
            child: Column(children: [
              StrokeText(trChapter(c.number, c.roman), style: AdvTokens.sm, color: AdvTokens.goldTop),
              StrokeText(tr(c.name), style: AdvTokens.title, stroke: AdvTokens.strokeOutline, align: TextAlign.center),
              SizedBox(height: _t[1]),
              StrokeText(tr('Longest survived: {days}', {'days': trDays(best)}), style: AdvTokens.sm),
              SizedBox(height: _t[1]),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final t in Tier.values)
                  Icon(Icons.star,
                      size: AdvTokens.sizeIcon * 0.8,
                      color: _cleared(c, t) ? AdvTokens.goldTop : AdvTokens.surfaceDeep.withOpacity(0.6)),
              ]),
            ]),
          ),
          Positioned(
            left: w * 0.12,
            bottom: feet,
            child: Bob(
                height: 4,
                child: Pop(
                    trigger: _class, child: Sprite(heroClassById(_class).sprite, size: AdvTokens.sizeFighter * 1.15))),
          ),
          Positioned(
            right: w * 0.08,
            bottom: feet,
            child: Bob(
                height: 7,
                period: const Duration(milliseconds: 2300),
                child: _seen.contains(c.boss.img)
                    ? TurnToHero(on: c.boss.front, child: Sprite(c.boss.img, size: AdvTokens.sizeFighterBoss * 1.15))
                    : MysterySprite(c.boss.img, size: AdvTokens.sizeFighterBoss * 1.15)),
          ),
          Positioned(
            left: _t[3],
            right: _t[3],
            bottom: _t[2],
            child: Row(children: [
              for (final f in c.foes) Padding(padding: EdgeInsets.only(right: _t[1] / 2), child: _foeChip(f)),
              const Spacer(),
              Flexible(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: StrokeText(_seen.contains(c.boss.img) ? tr(c.boss.name) : '???', style: AdvTokens.xs),
                ),
              ),
            ]),
          ),
          if (!open)
            Container(
              color: AdvTokens.locked.withOpacity(0.75),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock, color: AdvTokens.text, size: AdvTokens.sizeEventNext),
                SizedBox(height: _t[2]),
                StrokeText(tr(c.name), style: AdvTokens.lg),
                SizedBox(height: _t[1]),
                Text(tr('Clear {world} to open', {'world': tr(chapters[c.number - 2].name)}),
                    style: AdvTokens.sm.copyWith(color: AdvTokens.textMuted)),
              ]),
            ),
        ]),
      );
    });
  }

  Widget _foeChip(FoeKind f) {
    return Container(
      width: AdvTokens.sizeEvent * 0.8,
      height: AdvTokens.sizeEvent * 0.8,
      padding: EdgeInsets.all(_t[1] / 2),
      decoration: BoxDecoration(
        color: AdvTokens.surfaceDeep.withOpacity(0.7),
        shape: BoxShape.circle,
        border: Border.all(color: AdvTokens.outline, width: AdvTokens.strokeText),
      ),
      child: _seen.contains(f.img)
          ? Image.asset(rpgAsset(f.img), semanticLabel: tr(f.name), filterQuality: FilterQuality.medium)
          : MysterySprite(f.img, size: AdvTokens.sizeEvent * 0.8, mark: false),
    );
  }

  /// Normal, Hard, Nightmare: each opens when the one before is cleared.
  Widget _tierPicker() {
    // Narrow phones shrink the chips rather than cut one off.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final t in Tier.values)
          Builder(builder: (context) {
            final open = RunController.tierOpen(_save, _chapter, t);
            final on = t == _tier;
            final col = switch (t) {
              Tier.normal => AdvTokens.accent,
              Tier.nightmare => AdvTokens.danger,
            };
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: _t[1]),
              child: Semantics(
                container: true,
                button: true,
                selected: on,
                enabled: open,
                label: '${tr(t.label)}${open ? '' : ', ${tr('locked')}'}',
                child: GestureDetector(
                  onTap: open ? () => setState(() => _tier = t) : null,
                  child: AnimatedContainer(
                    duration: AdvTokens.hit,
                    padding: EdgeInsets.symmetric(horizontal: _t[3], vertical: _t[1]),
                    decoration: BoxDecoration(
                      color: on ? col : AdvTokens.surface,
                      borderRadius: BorderRadius.circular(AdvTokens.radiusPill),
                      border:
                          Border.all(color: on ? AdvTokens.goldTop : AdvTokens.outline, width: AdvTokens.strokeText),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!open) const Icon(Icons.lock, size: AdvTokens.sizeIcon * 0.55, color: AdvTokens.textMuted),
                      for (var i = 0; i < t.stars; i++)
                        Icon(Icons.star,
                            size: AdvTokens.sizeIcon * 0.55, color: open ? AdvTokens.goldTop : AdvTokens.textMuted),
                      SizedBox(width: _t[1]),
                      StrokeText(tr(t.label), style: AdvTokens.xs, color: open ? AdvTokens.text : AdvTokens.textMuted),
                    ]),
                  ),
                ),
              ),
            );
          }),
      ]),
    );
  }

  void _turn(int by) => _pages?.animateToPage((_page + by).clamp(0, chapters.length - 1),
      duration: AdvTokens.walk, curve: Curves.easeOut);

  Widget _dots() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(
        tooltip: tr('Previous world'),
        onPressed: _page > 0 ? () => _turn(-1) : null,
        icon: const Icon(Icons.chevron_left, color: AdvTokens.text),
      ),
      for (var i = 0; i < chapters.length; i++)
        AnimatedContainer(
          duration: AdvTokens.hit,
          margin: EdgeInsets.symmetric(horizontal: _t[1] / 2),
          width: i == _page ? _t[4] : _t[2],
          height: _t[2],
          decoration: BoxDecoration(
            color: i + 1 > _unlocked
                ? AdvTokens.surface
                : i == _page
                    ? AdvTokens.goldTop
                    : AdvTokens.textMuted,
            borderRadius: BorderRadius.circular(AdvTokens.radiusPill),
          ),
        ),
      IconButton(
        tooltip: tr('Next world'),
        onPressed: _page < chapters.length - 1 ? () => _turn(1) : null,
        icon: const Icon(Icons.chevron_right, color: AdvTokens.text),
      ),
    ]);
  }

  Widget _howTo() {
    final rows = [
      (Icons.directions_walk, 'On the road, one pushup is one day. In a fight, every pushup is a strike.'),
      (Icons.bolt, 'Strikes charge your special. When it says READY, the next pushup unleashes it.'),
      (Icons.warning_amber, 'Bosses wind up heavy blows: three quick pushups stagger them.'),
      (Icons.shield, 'Every run drops gear. Merge three of a kind into the next rarity.'),
      (Icons.pan_tool, 'No hands needed: prop the phone up so your shoulders and hands are in frame.'),
    ];
    return Column(children: [
      for (final (icon, text) in rows)
        Padding(
          padding: EdgeInsets.only(bottom: _t[2]),
          child: Row(children: [
            Icon(icon, color: AdvTokens.goldTop, size: AdvTokens.sizeIcon * 0.8),
            SizedBox(width: _t[3]),
            Expanded(child: Text(tr(text), style: AdvTokens.sm.copyWith(color: AdvTokens.textMuted))),
          ]),
        ),
    ]);
  }

  // --------------------------------------------------------------- heroes

  Widget _heroes() {
    return ListView(
      padding: EdgeInsets.fromLTRB(_t[4], _t[3], _t[4], _t[5]),
      children: [
        for (final (i, c) in heroClasses.indexed) ...[
          FadeSlideIn(
              index: i,
              child: Semantics(
                container: true,
                button: true,
                selected: c.id == _class,
                label:
                    '${tr(c.name)}. ${tr(c.perk)}: ${tr(c.perkText)}. ${tr('Special')}: ${tr(c.special)}, ${tr(c.specialText)}',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => _pickClass(c.id),
                  child: AnimatedContainer(
                    duration: AdvTokens.hit,
                    padding: EdgeInsets.all(_t[3]),
                    decoration: BoxDecoration(
                      color: c.id == _class ? AdvTokens.card : AdvTokens.surface,
                      borderRadius: BorderRadius.circular(AdvTokens.radiusTile),
                      border: Border.all(
                          color: c.id == _class ? AdvTokens.goldTop : AdvTokens.outline,
                          width: AdvTokens.strokeOutline),
                    ),
                    child: Row(children: [
                      Pop(trigger: c.id == _class, child: Sprite(c.sprite, size: AdvTokens.sizeLoot)),
                      SizedBox(width: _t[3]),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          StrokeText(tr(c.name), style: AdvTokens.title),
                          Text('${tr(c.perk)}: ${tr(c.perkText)}',
                              style: AdvTokens.sm
                                  .copyWith(color: c.id == _class ? AdvTokens.textOnCard : AdvTokens.textMuted)),
                          SizedBox(height: _t[1]),
                          Text('${tr('Special')} · ${tr(c.special)}',
                              style: AdvTokens.sm
                                  .copyWith(color: c.id == _class ? AdvTokens.keyword : AdvTokens.specialTop)),
                          Text(tr(c.specialText),
                              style: AdvTokens.xs
                                  .copyWith(color: c.id == _class ? AdvTokens.textOnCardMuted : AdvTokens.textMuted)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              )),
          SizedBox(height: _t[3]),
        ],
      ],
    );
  }
}
