import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n/i18n.dart';
import '../online/ranked.dart';
import '../online/supabase_config.dart';
import '../ui/theme/rpg_theme.dart';

/// Sign in, so the rank and coins follow you to a new phone.
///
/// Everyone starts as a guest (an anonymous account). "Save my progress"
/// turns that same account into a real one, with Google or with an email and
/// password, so nothing is lost. "I already have an account" signs in to
/// another one instead.
///
/// Server setup (Supabase dashboard → Authentication):
/// - Providers → Email on, and Google on with its OAuth client.
/// - Settings → "Allow manual linking" on (guest → Google).
/// - URL Configuration → add com.repraid.app://login-callback.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

enum _Mode { save, signIn }

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.save;
  bool _busy = false, _hide = true;
  String? _error, _note;
  StreamSubscription<AuthState>? _auth;

  static const _redirect = 'com.repraid.app://login-callback';

  SupabaseClient? get _client => SupabaseConfig.client;
  User? get _user => _client?.auth.currentUser;
  bool get _guest => _user == null || (_user!.isAnonymous);

  @override
  void initState() {
    super.initState();
    // Google sign-in finishes in the browser and comes back here.
    _auth = _client?.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      setState(() {});
      Ranked.refresh();
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(SupabaseClient c) job) async {
    final c = _client;
    if (c == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      await job(c);
      await Ranked.refresh();
    } on AuthException catch (e) {
      _error = _explain(e.message);
    } catch (_) {
      _error = tr('No connection to the server. Check your internet.');
    }
    if (mounted) setState(() => _busy = false);
  }

  String _explain(String m) {
    final s = m.toLowerCase();
    if (s.contains('invalid login')) return tr('Wrong email or password.');
    if (s.contains('already') && s.contains('registered')) return tr('That email already has an account. Sign in instead.');
    if (s.contains('password') && s.contains('6')) return tr('The password needs at least 6 characters.');
    if (s.contains('provider') && s.contains('not enabled')) return tr('This sign-in method is not switched on yet.');
    if (s.contains('manual linking')) return tr('This sign-in method is not switched on yet.');
    return m;
  }

  bool _validEmail(String e) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e.trim());

  Future<void> _google() => _run((c) async {
        const redirect = kIsWeb ? null : _redirect;
        if (_guest && _user != null) {
          // Keeps the guest's rank and coins on the same account.
          await c.auth.linkIdentity(OAuthProvider.google, redirectTo: redirect);
        } else {
          await c.auth.signInWithOAuth(OAuthProvider.google, redirectTo: redirect);
        }
      });

  Future<void> _submitEmail() async {
    final email = _email.text.trim(), password = _password.text;
    if (!_validEmail(email)) {
      setState(() => _error = tr('Enter a valid email.'));
      return;
    }
    if (password.length < 6) {
      setState(() => _error = tr('The password needs at least 6 characters.'));
      return;
    }
    await _run((c) async {
      if (_mode == _Mode.signIn) {
        await c.auth.signInWithPassword(email: email, password: password);
        return;
      }
      if (c.auth.currentUser == null) await c.auth.signInAnonymously();
      // The guest account becomes an email account: same id, same rank.
      await c.auth.updateUser(UserAttributes(email: email, password: password), emailRedirectTo: kIsWeb ? null : _redirect);
      _note = tr('Check your inbox: open the link we sent to confirm your email.');
    });
  }

  /// Sends a reset link to the email in the field.
  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!_validEmail(email)) {
      setState(() => _error = tr('Enter your email above, then tap Forgot password.'));
      return;
    }
    await _run((c) async {
      await c.auth.resetPasswordForEmail(email, redirectTo: kIsWeb ? null : _redirect);
      _note = tr('We sent a link to reset your password. Open it on this phone.');
    });
  }

  Future<void> _signOut() => _run((c) async {
        await c.auth.signOut();
        await c.auth.signInAnonymously();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Rpg.bg,
        title: Text(tr('Account'),
            style: const TextStyle(
                fontFamily: Rpg.display, fontFamilyFallback: Rpg.arabicDisplay, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: _client == null
            ? Center(child: Text(tr('No connection to the server. Check your internet.')))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: _guest ? _guestView() : _signedInView(),
              ),
      ),
    );
  }

  List<Widget> _signedInView() {
    final u = _user!;
    final google = u.appMetadata['provider'] == 'google' ||
        (u.identities ?? const []).any((i) => i.provider == 'google');
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: Rpg.panel(border: Rpg.vigor.withOpacity(0.6)),
        child: Row(children: [
          Icon(google ? Icons.g_mobiledata_rounded : Icons.mail_outline, color: Rpg.vigor, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Signed in'), style: const TextStyle(fontWeight: FontWeight.w800, color: Rpg.vigor)),
              Text(u.email ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Rpg.ink)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Text(tr('Your rank and coins are saved to this account.'), style: Rpg.label),
      const SizedBox(height: 20),
      OutlinedButton(onPressed: _busy ? null : _signOut, child: Text(tr('Sign out'))),
      ..._status(),
    ];
  }

  List<Widget> _guestView() {
    final save = _mode == _Mode.save;
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: Rpg.panel(fill: Rpg.goldSoft, border: Rpg.goldEdge),
        child: Row(children: [
          const Icon(Icons.shield_outlined, color: Rpg.gold, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tr('You are playing as a guest. Sign in so your rank and coins are never lost.'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: Rpg.ink)),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      _googleButton(),
      const SizedBox(height: 18),
      Row(children: [
        const Expanded(child: Divider(color: Rpg.border2)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(tr('or with email'), style: const TextStyle(color: Rpg.ink3, fontWeight: FontWeight.w700)),
        ),
        const Expanded(child: Divider(color: Rpg.border2)),
      ]),
      const SizedBox(height: 14),
      _tabs(),
      const SizedBox(height: 14),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textDirection: TextDirection.ltr,
        decoration: _input(tr('Email'), Icons.mail_outline),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _password,
        obscureText: _hide,
        autofillHints: [save ? AutofillHints.newPassword : AutofillHints.password],
        textDirection: TextDirection.ltr,
        decoration: _input(tr('Password'), Icons.lock_outline).copyWith(
          suffixIcon: IconButton(
            tooltip: tr(_hide ? 'Show password' : 'Hide password'),
            icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Rpg.ink3),
            onPressed: () => setState(() => _hide = !_hide),
          ),
        ),
        onSubmitted: (_) => _submitEmail(),
      ),
      const SizedBox(height: 14),
      ElevatedButton(
        onPressed: _busy ? null : _submitEmail,
        child: Text(tr(save ? 'Create account' : 'Sign in')),
      ),
      if (!save) ...[
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: _busy ? null : _forgot,
            child: Text(tr('Forgot password?'), style: const TextStyle(fontWeight: FontWeight.w800, color: Rpg.mana)),
          ),
        ),
        Text(tr('Signing in to another account leaves this guest\'s rank behind.'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Rpg.ink3)),
      ],
      ..._status(),
    ];
  }

  Widget _googleButton() {
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy ? null : _google,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF1F3F4)),
                child: const Text('G',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF4285F4))),
              ),
              const SizedBox(width: 10),
              Text(tr('Continue with Google'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1F1F1F))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tabs() {
    Widget tab(_Mode m, String label) {
      final on = _mode == m;
      return Expanded(
        child: Semantics(
          container: true,
          button: true,
          selected: on,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() {
              _mode = m;
              _error = null;
              _note = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? Rpg.surface3 : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, color: on ? Rpg.ink : Rpg.ink3)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: Rpg.panel(),
      child: Row(children: [
        tab(_Mode.save, tr('Save my progress')),
        tab(_Mode.signIn, tr('I already have an account')),
      ]),
    );
  }

  InputDecoration _input(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Rpg.ink3),
        filled: true,
        fillColor: Rpg.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Rpg.border, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Rpg.mana, width: 2),
        ),
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
        if (_note != null) ...[
          const SizedBox(height: 14),
          Text(_note!, style: const TextStyle(color: Rpg.vigor, fontWeight: FontWeight.w700)),
        ],
      ];
}

/// After the reset link opens the app: choose a new password.
Future<void> showNewPasswordDialog(BuildContext context) async {
  final c = SupabaseConfig.client;
  if (c == null) return;
  final field = TextEditingController();
  String? error;
  var busy = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: Rpg.surface,
        title: Text(tr('Choose a new password'),
            style: const TextStyle(fontFamily: Rpg.display, fontFamilyFallback: Rpg.arabicDisplay, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: field,
            obscureText: true,
            autofocus: true,
            textDirection: TextDirection.ltr,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(hintText: tr('New password')),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Rpg.danger, fontWeight: FontWeight.w700)),
          ],
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.of(context).pop(), child: Text(tr('Cancel'))),
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    if (field.text.length < 6) {
                      setState(() => error = tr('The password needs at least 6 characters.'));
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      await c.auth.updateUser(UserAttributes(password: field.text));
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (_) {
                      setState(() {
                        busy = false;
                        error = tr('No connection to the server. Check your internet.');
                      });
                    }
                  },
            child: Text(tr('Save')),
          ),
        ],
      ),
    ),
  );
  field.dispose();
}
