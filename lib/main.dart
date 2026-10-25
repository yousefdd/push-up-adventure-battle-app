import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'engine/exercise.dart';
import 'i18n/i18n.dart';
import 'modes/online/lobby_screen.dart';
import 'modes/rpg/ui/adventure_home.dart';
import 'online/ranked.dart';
import 'profile/profile.dart';
import 'profile/account_screen.dart';
import 'profile/profile_screen.dart';
import 'online/supabase_config.dart';
import 'ui/ads.dart';
import 'ui/rank_widgets.dart';
import 'ui/store_screen.dart';
import 'ui/theme/rpg_theme.dart';
import 'ui/motion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only: the frame rotation handed to ML Kit assumes an upright phone.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (SupabaseConfig.isSet) {
    await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.key);
  }
  await I18n.load();
  runApp(const RepRaidApp());
}

class RepRaidApp extends StatelessWidget {
  const RepRaidApp({super.key});
  @override
  Widget build(BuildContext context) {
    // The whole app rebuilds when the language changes; Arabic reads right to left.
    return ValueListenableBuilder<Lang>(
      valueListenable: I18n.lang,
      builder: (context, lang, _) => MaterialApp(
        key: ValueKey(lang),
        title: 'Push Up Adventure Battle',
        theme: Rpg.theme(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => Directionality(textDirection: I18n.direction, child: child!),
        home: const HomeScreen(),
      ),
    );
  }
}

/// Home: Cinder, the pushup mode choice, and the button into a race.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ExerciseType _mode = ExerciseType.pushup;
  Profile? _me;

  StreamSubscription<AuthState>? _auth;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    Ranked.refresh();
    // The password reset link opens the app: ask for the new password.
    _auth = SupabaseConfig.client?.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery && mounted) showNewPasswordDialog(context);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final p = await ProfileStore.load();
    if (mounted) setState(() => _me = p);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _loadProfile(); // a race or an edit may have changed it
    Ranked.refresh();
  }

  /// Your picture, top right: opens the profile.
  Widget _profileButton() {
    return Semantics(
      container: true,
      button: true,
      label: tr('Your profile'),
      child: GestureDetector(
        onTap: () => _open(const ProfileScreen()),
        child: Avatar(photo: _me?.photo, size: 44),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: _staggered([
            Row(
              children: [
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('Push Up\nAdventure Battle', style: Rpg.title, maxLines: 2),
                  ),
                ),
                _langChip(),
                const SizedBox(width: 8),
                _streakChip(),
                const SizedBox(width: 10),
                _profileButton(),
              ],
            ),
            const SizedBox(height: 2),
            Text(tr('Only correct reps count'), style: Rpg.label),
            const SizedBox(height: 14),
            ValueListenableBuilder<PlayerStats>(
              valueListenable: Ranked.stats,
              builder: (context, s, _) => Row(children: [
                Expanded(child: RankCard(s, compact: true, onTap: () => _open(LobbyScreen(exercise: _mode)))),
                const SizedBox(width: 8),
                Column(children: [
                  CoinChip(gold: s.gold, silver: s.silver, onTap: () => _open(const StoreScreen())),
                  const SizedBox(height: 6),
                  _storeButton(),
                ]),
              ]),
            ),
            if (_isGuest) ...[
              const SizedBox(height: 8),
              _signInNudge(),
            ],
            const SizedBox(height: 14),
            _cinderCard(),
            const SizedBox(height: 22),
            Text(tr('Pushups strike'),
                style: const TextStyle(
                    fontFamily: Rpg.display,
                    fontFamilyFallback: Rpg.arabicDisplay,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Rpg.ink)),
            const SizedBox(height: 10),
            for (final t in ExerciseType.values) ...[
              _modeTile(ExerciseProfile.defaults[t]!),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            Pulse(
              amount: 0.025,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdventureHome(exercise: _mode))),
                child: Text(tr('Adventure')),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _open(LobbyScreen(exercise: _mode)),
              child: Text(tr('Online race')),
            ),
            const SizedBox(height: 14),
            Text(
              tr('Prop the phone in front of you, facing you, so your shoulders and hands are in frame.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Rpg.ink3, fontSize: 13),
            ),
            const AdSlot(margin: EdgeInsets.only(top: 16)),
          ]),
        ),
      ),
    );
  }

  /// A guest (anonymous) player: their rank lives only on this phone's account.
  bool get _isGuest {
    final c = SupabaseConfig.client;
    if (c == null) return false;
    final u = c.auth.currentUser;
    return u == null || u.isAnonymous;
  }

  /// "Sign in to keep your rank": opens the account screen.
  Widget _signInNudge() {
    return Semantics(
      container: true,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(const AccountScreen()),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: Rpg.panel(fill: Rpg.manaSoft, border: Rpg.mana.withOpacity(0.6)),
          child: Row(children: [
            const Icon(Icons.login_rounded, color: Rpg.mana, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Sign in with Google or email to keep your rank and coins'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Rpg.ink)),
            ),
            const Icon(Icons.chevron_right, color: Rpg.ink3),
          ]),
        ),
      ),
    );
  }

  /// The store, behind a small gift icon.
  Widget _storeButton() {
    return Semantics(
      container: true,
      button: true,
      label: tr('Store'),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(const StoreScreen()),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: Rpg.panel(fill: Rpg.goldSoft, border: Rpg.goldEdge),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.storefront_rounded, size: 18, color: Rpg.gold),
            const SizedBox(width: 6),
            Text(tr('Store'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Rpg.gold)),
          ]),
        ),
      ),
    );
  }

  /// EN / عربي: switches the whole app.
  Widget _langChip() {
    final next = I18n.isAr ? Lang.en : Lang.ar;
    return Semantics(
      container: true,
      button: true,
      label: I18n.isAr ? 'English' : 'العربية',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => I18n.set(next),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: Rpg.panel(border: Rpg.mana.withOpacity(0.6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.translate, size: 18, color: Rpg.mana),
            const SizedBox(width: 6),
            Text(I18n.isAr ? 'EN' : 'عربي',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Rpg.ink)),
          ]),
        ),
      ),
    );
  }

  /// Each block of the home screen arrives a beat after the one above it.
  List<Widget> _staggered(List<Widget> children) => [
        for (final (i, c) in children.indexed) c is SizedBox ? c : FadeSlideIn(index: i ~/ 2, child: c),
      ];

  Widget _streakChip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
      decoration: Rpg.panel(fill: Rpg.goldSoft, border: Rpg.goldEdge),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/rc/Streak_fire.png', width: 22, height: 22),
          const SizedBox(width: 4),
          const Text('0',
              style: TextStyle(
                  fontFamily: Rpg.display,
                  fontFamilyFallback: Rpg.arabicDisplay,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Rpg.gold)),
        ],
      ),
    );
  }

  Widget _cinderCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: Rpg.panel(),
      child: Row(
        children: [
          Bob(child: Image.asset('assets/rpg/flame_hero.png', width: 104, height: 104)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr('Cinder is ready to fight. One correct set today starts your streak.'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Rpg.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTile(ExerciseProfile p) {
    final selected = p.type == _mode;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _mode = p.type),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: Rpg.panel(
          fill: selected ? Rpg.brandSoft : Rpg.surface,
          border: selected ? Rpg.brand : Rpg.border,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(p.label),
                      style: const TextStyle(
                          fontFamily: Rpg.display,
                          fontFamilyFallback: Rpg.arabicDisplay,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Rpg.ink)),
                  Text(tr(p.blurb), style: const TextStyle(fontSize: 14, color: Rpg.ink2)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? Rpg.brand : Rpg.ink3,
            ),
          ],
        ),
      ),
    );
  }
}
