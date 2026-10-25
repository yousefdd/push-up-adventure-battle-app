import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ui/theme/rpg_theme.dart';
import '../online/ranked.dart';
import '../ui/rank_widgets.dart';
import 'account_screen.dart';
import 'profile.dart';
import '../i18n/i18n.dart';

/// Your profile: the picture and name your rival sees, and your race record.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _p;
  final _name = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    ProfileStore.load().then((p) {
      if (!mounted) return;
      setState(() => _p = p);
      _name.text = p.name;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = _p;
    if (p == null) return;
    p.name = _name.text.trim();
    await ProfileStore.save(p);
  }

  Future<void> _pick(ImageSource source) async {
    try {
      // Picked at a modest size; fitPhoto squares it and shrinks it to fit.
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null) return;
      final bytes = await fitPhoto(await file.readAsBytes());
      if (bytes == null) {
        setState(() => _error = tr('That picture could not be read. Try another one.'));
        return;
      }
      setState(() {
        _p!.photo = bytes;
        _error = null;
      });
      await _save();
    } catch (_) {
      setState(() => _error = tr('Could not open your pictures. Check the app\'s photo permission.'));
    }
  }

  Future<void> _choose() async {
    if (kIsWeb) return _pick(ImageSource.gallery);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Rpg.surface,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera, color: Rpg.ink),
            title: Text(tr('Take a photo'), style: const TextStyle(color: Rpg.ink)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Rpg.ink),
            title: Text(tr('Choose from gallery'), style: const TextStyle(color: Rpg.ink)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          if (_p?.photo != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Rpg.danger),
              title: Text(tr('Remove picture'), style: const TextStyle(color: Rpg.danger)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _p!.photo = null);
                _save();
              },
            ),
        ]),
      ),
    );
    if (source != null) await _pick(source);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return PopScope(
      onPopInvokedWithResult: (_, __) => _save(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Rpg.bg,
          title: Text(tr('Profile'),
              style: const TextStyle(
                  fontFamily: Rpg.display, fontFamilyFallback: Rpg.arabicDisplay, fontWeight: FontWeight.w800)),
        ),
        body: p == null
            ? const Center(child: CircularProgressIndicator(color: Rpg.gold))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _choose,
                      child: Stack(clipBehavior: Clip.none, children: [
                        Avatar(photo: p.photo, size: 132),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(color: Rpg.mana, shape: BoxShape.circle),
                            child: const Icon(Icons.photo_camera, color: Colors.white, size: 20),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _choose,
                      child: Text(p.photo == null ? tr('Add a picture') : tr('Change picture')),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Rpg.danger, fontWeight: FontWeight.w700)),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _name,
                    maxLength: 20,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Rpg.ink, fontSize: 18, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      labelText: tr('Your name'),
                      counterText: '',
                      filled: true,
                      fillColor: Rpg.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onChanged: (_) => _save(),
                  ),
                  const SizedBox(height: 6),
                  Text(tr('Your rival sees this picture and name during the race.'),
                      style: const TextStyle(color: Rpg.ink3, fontSize: 13)),
                  const SizedBox(height: 24),
                  Row(children: [
                    _stat(tr('LV'), '${p.level}', Rpg.mana),
                    _stat(tr('Races'), '${p.races}', Rpg.ink),
                    _stat(tr('Best'), '${p.best}', Rpg.gold),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _stat(tr('Won'), '${p.wins}', Rpg.vigor),
                    _stat(tr('Lost'), '${p.losses}', Rpg.danger),
                    _stat(tr('Push-ups'), '${p.pushups}', Rpg.ink),
                  ]),
                  const SizedBox(height: 24),
                  Text(tr('Ranked'), style: Rpg.label),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<PlayerStats>(
                    valueListenable: Ranked.stats,
                    builder: (context, s, _) => Column(children: [
                      RankCard(s),
                      const SizedBox(height: 10),
                      RankLadder(current: s.rank.tier),
                      const SizedBox(height: 10),
                      Row(children: [
                        _stat(tr('Rating'), '${s.rating}', s.rank.tier.light),
                        _stat(tr('Peak'), '${s.peak}', Rpg.gold),
                        _stat(tr('Cinder Coins'), '${s.gold}', const Color(0xFFFFD27A)),
                        _stat(tr('Silver coins'), '${s.silver}', const Color(0xFFDDE5F0)),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        _stat(tr('Won'), '${s.wins}', Rpg.vigor),
                        _stat(tr('Lost'), '${s.losses}', Rpg.danger),
                        _stat(tr('Draws'), '${s.draws}', Rpg.ink2),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
                    icon: const Icon(Icons.account_circle_outlined),
                    label: Text(tr('Account and sign-in')),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: Rpg.panel(),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontFamily: Rpg.body,
                  fontFamilyFallback: Rpg.arabic,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: color)),
          Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Rpg.ink2)),
        ]),
      ),
    );
  }
}
