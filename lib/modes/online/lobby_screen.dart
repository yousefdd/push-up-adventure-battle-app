import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../engine/camera_pose_source.dart';
import '../../engine/web_pose_source.dart';
import '../../engine/exercise.dart';
import '../../online/supabase_config.dart';
import '../../online/ranked.dart';
import '../../profile/profile.dart';
import '../../ui/ads.dart';
import '../../ui/rank_widgets.dart';
import '../../ui/store_screen.dart';
import '../../profile/profile_screen.dart';
import '../../ui/theme/rpg_theme.dart';
import 'duel_models.dart';
import 'duel_screen.dart';
import 'duel_service.dart';
import 'pose_frame_source.dart';
import '../../i18n/i18n.dart';
import '../../ui/motion.dart';

/// Where an online duel starts: your profile on top, then create a duel and
/// share the code, or join a friend's code.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.exercise});

  /// The exercise picked on the home screen. A joining friend races the
  /// host's exercise, so both always do the same one.
  final ExerciseType exercise;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  Profile? _me;
  final _code = TextEditingController();
  DuelService? _service;

  DuelRow? _waiting; // my open invite, while the friend hasn't joined
  DuelInvite? _invite; // a friend's invite I am looking at before accepting
  int _secs = raceLengths.first; // the length I offer when I create a duel

  // Matchmaking: my open search, refreshed every few seconds until paired.
  DuelRow? _search;
  Timer? _searchTimer;
  (int, int) _crowd = (0, 0); // players searching, racing
  bool _started = false;
  StreamSubscription<DuelRow>? _watch;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (SupabaseConfig.isSet) {
      _service = DuelService(Supabase.instance.client);
    }
    _loadProfile();
    Ranked.refresh();
  }

  Future<void> _loadProfile() async {
    final p = await ProfileStore.load();
    if (mounted) setState(() => _me = p);
  }

  Future<void> _editProfile() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
    await _loadProfile();
  }

  /// Adds a finished race to the profile record.
  Future<void> _record(DuelResult r) async {
    final p = await ProfileStore.load();
    p.record(mine: r.myReps, theirs: r.opponentReps);
    await ProfileStore.save(p);
    if (mounted) setState(() => _me = p);
  }

  @override
  void dispose() {
    _watch?.cancel();
    _searchTimer?.cancel();
    final waiting = _waiting ?? _search;
    if (waiting != null && !waiting.isLive) _service?.cancel(waiting.id);
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(DuelService s) job) async {
    final service = _service;
    if (service == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // No camera, no race: only the camera can count a push-up.
    if (!await (kIsWeb ? WebPoseSource.check() : CameraPoseSource.check())) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('Allow the camera to race. Only the camera can count a push-up.');
        });
      }
      return;
    }
    try {
      await service.signIn();
      await service.syncClock();
      await job(service);
    } on PostgrestException catch (e) {
      _error = e.message;
    } on AuthException catch (e) {
      _error = tr('Could not sign in: {msg}', {'msg': e.message});
    } catch (_) {
      _error = tr('No connection to the duel server. Check your internet.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _create() => _run((s) async {
        final me = _me ?? await ProfileStore.load();
        final row = await s.create(widget.exercise, me.displayName, me.level, photo: me.photoB64, secs: _secs);
        setState(() => _waiting = row);
        _watch = s.watch(row.id).listen((r) {
          if (r.isLive && r.goAt != null) {
            _watch?.cancel();
            setState(() => _waiting = null);
            _startOnline(s, r);
          }
        });
      });

  /// Looks the code up first, so the guest sees who invited them and how
  /// long the race is before agreeing to it.
  Future<void> _join() => _run((s) async {
        final invite = await s.peek(_code.text);
        if (invite == null) {
          _error = tr('Code not found or already used.');
          return;
        }
        setState(() => _invite = invite);
      });

  Future<void> _accept(DuelInvite invite) => _run((s) async {
        final me = _me ?? await ProfileStore.load();
        final row = await s.join(invite.code, me.displayName, me.level, photo: me.photoB64, secs: invite.fightSecs);
        setState(() => _invite = null);
        _startOnline(s, row);
      });

  /// "Find an opponent": the server pairs me with anyone searching for the
  /// same exercise and length. The search is refreshed every 4 s; the race
  /// starts as soon as either side is paired.
  Future<void> _findOpponent() => _run((s) async {
        _started = false;
        await _searchStep(s, first: true);
        if (_started || _search == null) return;
        _watch = s.watch(_search!.id).listen((r) {
          if (r.isLive && r.goAt != null) _paired(s, r);
        });
        _searchTimer = Timer.periodic(const Duration(seconds: 4), (_) => _searchStep(s));
      });

  Future<void> _searchStep(DuelService s, {bool first = false}) async {
    if (_started) return;
    try {
      final me = _me ?? await ProfileStore.load();
      final row = await s.quickMatch(widget.exercise, me.displayName, me.level, photo: me.photoB64, secs: _secs);
      final crowd = await s.matchmakingStatus(widget.exercise);
      if (!mounted || _started) return;
      if (row.isLive && row.goAt != null) {
        _paired(s, row);
      } else {
        setState(() {
          _search = row;
          _crowd = crowd;
        });
      }
    } catch (_) {
      // A missed refresh is fine; the next one tries again. The first one
      // reports its error on the screen.
      if (first) rethrow;
    }
  }

  void _paired(DuelService s, DuelRow row) {
    if (_started) return;
    _started = true;
    _searchTimer?.cancel();
    _watch?.cancel();
    setState(() => _search = null);
    _startOnline(s, row);
  }

  Future<void> _stopSearch() async {
    _searchTimer?.cancel();
    await _watch?.cancel();
    final search = _search;
    setState(() => _search = null);
    if (search != null && !_started) await _service?.cancel(search.id);
  }

  Future<void> _cancel() async {
    final waiting = _waiting;
    await _watch?.cancel();
    setState(() => _waiting = null);
    if (waiting != null) await _service?.cancel(waiting.id);
  }

  void _startOnline(DuelService s, DuelRow row) {
    final bout = row.boutFor(s.myId);
    final countdownStart = s.toLocal(row.goAt!).subtract(Duration(seconds: row.leadSecs));
    _openRace(
      bout: bout,
      startAt: countdownStart,
      onBroadcast: (p) => s.reportReps(row.id, p.reps),
      opponentPulses: s.opponentPulses(bout),
      onTaunt: (t) => s.sendTaunt(bout, t),
      opponentTaunts: s.taunts(bout),
      settle: () => s.settle(bout, row.goAt!),
    );
  }

  void _openRace({
    required DuelBout bout,
    DateTime? startAt,
    void Function(LivePulse)? onBroadcast,
    Stream<LivePulse>? opponentPulses,
    Future<DuelResult?> Function()? settle,
    void Function(String)? onTaunt,
    Stream<String>? opponentTaunts,
  }) {
    // My own picture and level from the profile, whatever the server sent.
    final me = _me;
    if (me != null) {
      bout = DuelBout(
        boutId: bout.boutId,
        myId: bout.myId,
        opponentId: bout.opponentId,
        exercise: bout.exercise,
        window: bout.window,
        me: DuelPlayer(name: me.displayName, level: me.level, avatar: bout.me.avatar, photo: me.photo),
        opponent: bout.opponent,
      );
    }
    // On a phone the front camera and ML Kit count the reps; in a browser the
    // webcam and MediaPipe (web/rr_pose.js) do. With no camera nothing counts.
    final web = kIsWeb && WebPoseSource.available ? WebPoseSource() : null;
    final camera = kIsWeb ? null : CameraPoseSource();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DuelScreen(
        bout: bout,
        poseSource: camera ?? web ?? NoCameraSource(),
        cameraBuilder: camera != null
            ? (overlay) => camera.preview(overlay: overlay)
            : web != null
                ? (overlay) => web.preview(overlay: overlay)
                : null,
        startAt: startAt,
        onBroadcast: onBroadcast,
        opponentPulses: opponentPulses,
        onTaunt: onTaunt,
        onFinished: _record,
        opponentTaunts: opponentTaunts,
        settle: settle,
        onExit: () async {
          // Back to the lobby, then the ad break, then the new rank.
          final nav = Navigator.of(context);
          nav.pop();
          await AdBreak.show(nav);
          Ranked.refresh();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final label = ExerciseProfile.defaults[widget.exercise]!.label;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Rpg.bg,
        title: Text(tr('Duel'),
            style: const TextStyle(
                fontFamily: Rpg.display, fontFamilyFallback: Rpg.arabicDisplay, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _profileCard(),
            const SizedBox(height: 10),
            ValueListenableBuilder<PlayerStats>(
              valueListenable: Ranked.stats,
              builder: (context, s, _) => Row(children: [
                Expanded(child: RankCard(s, compact: true)),
                const SizedBox(width: 8),
                CoinChip(gold: s.gold, silver: s.silver, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StoreScreen()))),
              ]),
            ),
            const SizedBox(height: 14),
            Text(tr('{exercise} · most correct reps wins', {'exercise': tr(label)}), style: Rpg.label),
            const SizedBox(height: 16),
            if (_service == null) ...[
              // The race length is chosen here even before the server is set up.
              Text(tr('Race length'), style: Rpg.label),
              const SizedBox(height: 8),
              _lengthPicker(),
              const SizedBox(height: 16),
              _notSetUp(),
            ] else
              ..._online(),
            const AdSlot(margin: EdgeInsets.only(top: 22)),
          ],
        ),
      ),
    );
  }

  List<Widget> _online() {
    final waiting = _waiting;
    if (waiting != null) return [_inviteCard(waiting)];
    final invite = _invite;
    if (invite != null) return [_acceptCard(invite), ..._status()];
    final search = _search;
    if (search != null) return [_searchCard(search)];
    return [
      Text(tr('Race length'), style: Rpg.label),
      const SizedBox(height: 8),
      _lengthPicker(),
      const SizedBox(height: 12),
      Pulse(
        enabled: !_busy,
        amount: 0.03,
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _findOpponent,
          icon: const Icon(Icons.public),
          label: Text(tr('Find an opponent')),
        ),
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _tag(tr('RANKED'), Rpg.gold),
        const SizedBox(width: 8),
        Flexible(
          child: Text(tr('Wins raise your rank and pay coins; losses cost both.'),
              style: const TextStyle(color: Rpg.ink3, fontSize: 13)),
        ),
      ]),
      const SizedBox(height: 4),
      Text(tr('Races anyone online who picked the same length.'),
          textAlign: TextAlign.center, style: const TextStyle(color: Rpg.ink3, fontSize: 13)),
      const SizedBox(height: 18),
      Row(children: [
        Text(tr('Or race a friend'), style: Rpg.label),
        const SizedBox(width: 8),
        _tag(tr('FRIENDLY'), Rpg.mana),
      ]),
      const SizedBox(height: 4),
      Text(tr('Friendly races do not change ranks or coins.'), style: const TextStyle(color: Rpg.ink3, fontSize: 13)),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: _busy ? null : _create,
        child: Text(tr('Create duel')),
      ),
      const SizedBox(height: 22),
      Text(tr('Got a code from a friend?'), style: Rpg.label),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _field(_code, tr('CODE'), maxLength: 4, upper: true, center: true, big: true),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _busy ? null : _join,
            child: Text(tr('Join')),
          ),
        ],
      ),
      ..._status(),
    ];
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.7)),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: color)),
      );

  List<Widget> _status() => [
        if (_busy) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator(color: Rpg.gold)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: Rpg.danger, fontWeight: FontWeight.w700)),
        ],
      ];

  /// 1, 3 or 5 minutes: the host offers one, the friend agrees to it.
  Widget _lengthPicker() {
    return Row(children: [
      for (final secs in raceLengths)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              container: true,
              button: true,
              selected: secs == _secs,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _secs = secs),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: Rpg.panel(
                      border: secs == _secs ? Rpg.gold : Rpg.border, fill: secs == _secs ? Rpg.surface2 : null),
                  alignment: Alignment.center,
                  child: Text(raceLabel(secs),
                      style: TextStyle(
                          fontFamily: Rpg.display,
                          fontFamilyFallback: Rpg.arabicDisplay,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: secs == _secs ? Rpg.gold : Rpg.ink2)),
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  /// A friend's invite: their picture, the exercise and the race length,
  /// with Accept and Decline. Nothing starts until the guest agrees.
  Widget _acceptCard(DuelInvite invite) {
    final what = tr(ExerciseProfile.defaults[invite.exercise]!.label);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: Rpg.panel(border: Rpg.goldEdge),
      child: Column(children: [
        Avatar(photo: invite.hostPhoto, size: 72),
        const SizedBox(height: 10),
        Text('${invite.hostName} · ${tr('LV')} ${invite.hostLevel}',
            style: const TextStyle(
                fontFamily: Rpg.display,
                fontFamilyFallback: Rpg.arabicDisplay,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Rpg.ink)),
        const SizedBox(height: 4),
        Text(tr('invites you to a race'), style: const TextStyle(color: Rpg.ink2)),
        const SizedBox(height: 12),
        Text('${raceLabel(invite.fightSecs)} · $what',
            style: const TextStyle(
                fontFamily: Rpg.display,
                fontFamilyFallback: Rpg.arabicDisplay,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Rpg.gold)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => setState(() => _invite = null),
              child: Text(tr('Decline')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _busy ? null : () => _accept(invite),
              child: Text(tr('Accept')),
            ),
          ),
        ]),
      ]),
    );
  }

  /// Who you race as: your picture, name, level and record. Tap to edit.
  Widget _profileCard() {
    final me = _me;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _editProfile,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: Rpg.panel(border: Rpg.mana.withOpacity(0.5)),
        child: Row(children: [
          Avatar(photo: me?.photo, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me?.displayName ?? '…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: Rpg.display,
                      fontFamilyFallback: Rpg.arabicDisplay,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Rpg.ink)),
              Text(
                me == null
                    ? ''
                    : tr('LV {lv}  ·  {won} won  ·  {lost} lost', {'lv': me.level, 'won': me.wins, 'lost': me.losses}),
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1, color: Rpg.mana),
              ),
              if (me != null && me.photo == null)
                Text(tr('Tap to add your picture'), style: const TextStyle(fontSize: 13, color: Rpg.ink3)),
            ]),
          ),
          const Icon(Icons.edit, color: Rpg.ink2),
        ]),
      ),
    );
  }

  /// While matchmaking: who else is online, and Cancel.
  Widget _searchCard(DuelRow row) {
    final (searching, racing) = _crowd;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: Rpg.panel(border: Rpg.mana),
      child: Column(children: [
        const RayBurst(
          color: Rpg.mana,
          size: 110,
          child: SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 4, color: Rpg.mana)),
        ),
        const SizedBox(height: 14),
        Text(tr('Looking for an opponent…'),
            style: const TextStyle(
                fontFamily: Rpg.display,
                fontFamilyFallback: Rpg.arabicDisplay,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Rpg.ink)),
        const SizedBox(height: 4),
        Text(tr('{len} race', {'len': raceLabel(row.fightSecs)}),
            style: const TextStyle(color: Rpg.gold, fontSize: 16)),
        const SizedBox(height: 12),
        Text(tr('{s} searching · {r} racing now', {'s': searching, 'r': racing}),
            style: const TextStyle(color: Rpg.ink2)),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _stopSearch,
          child: Text(tr('Cancel'), style: const TextStyle(color: Rpg.danger)),
        ),
      ]),
    );
  }

  Widget _inviteCard(DuelRow row) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: Rpg.panel(border: Rpg.goldEdge),
      child: Column(
        children: [
          Text(tr('Send this code to your friend · {len} race', {'len': raceLabel(row.fightSecs)}), style: Rpg.label),
          const SizedBox(height: 8),
          SelectableText(
            row.code,
            style: const TextStyle(
              fontFamily: Rpg.display,
              fontFamilyFallback: Rpg.arabicDisplay,
              fontSize: 64,
              fontWeight: FontWeight.w800,
              letterSpacing: 10,
              color: Rpg.gold,
            ),
          ),
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: row.code)),
            icon: const Icon(Icons.copy, size: 18, color: Rpg.ink2),
            label: Text(tr('Copy'), style: const TextStyle(color: Rpg.ink2)),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Rpg.ink2)),
              const SizedBox(width: 10),
              Text(tr('Waiting for your friend to join…'), style: const TextStyle(color: Rpg.ink2)),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _cancel,
            child: Text(tr('Cancel'), style: const TextStyle(color: Rpg.danger)),
          ),
        ],
      ),
    );
  }

  Widget _notSetUp() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Rpg.panel(),
      child: Text(
        tr('Online duels are not set up in this build yet. Add your Supabase project to lib/online/supabase_config.dart (see README), then you can create a duel and send the code to a friend.'),
        style: const TextStyle(color: Rpg.ink2),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {int? maxLength, bool upper = false, bool center = false, bool big = false}) {
    return TextField(
      controller: c,
      maxLength: maxLength,
      textAlign: center ? TextAlign.center : TextAlign.start,
      textCapitalization: upper ? TextCapitalization.characters : TextCapitalization.words,
      inputFormatters: upper
          ? [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toUpperCase())),
            ]
          : null,
      style: TextStyle(
        fontFamily: big ? Rpg.display : Rpg.body,
        fontSize: big ? 26 : 17,
        fontWeight: FontWeight.w800,
        letterSpacing: big ? 6 : 0,
        color: Rpg.ink,
      ),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: Rpg.surface,
        hintStyle: const TextStyle(color: Rpg.ink3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Rpg.border, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Rpg.border, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Rpg.brand, width: 2),
        ),
      ),
    );
  }
}
