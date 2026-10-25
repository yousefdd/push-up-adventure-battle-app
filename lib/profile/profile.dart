import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme/rpg_theme.dart';
import '../i18n/i18n.dart';

/// The player's profile: a name, a picture, and the race record. Kept on the
/// phone; the name and picture travel with each online duel so the rival
/// sees who they are racing.
class Profile {
  Profile({
    this.name = '',
    this.photo,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.pushups = 0,
    this.best = 0,
  });

  String name;

  /// A small JPEG (about 256 px), or null for the default picture.
  Uint8List? photo;

  int wins, losses, draws, pushups, best;

  int get races => wins + losses + draws;

  /// One level per 50 push-ups raced, starting at 1.
  int get level => 1 + pushups ~/ 50;

  String get displayName => name.trim().isEmpty ? tr('Player') : name.trim();

  /// Base64 for the server, which keeps it to 60 000 characters.
  String? get photoB64 {
    final p = photo;
    if (p == null) return null;
    final b = base64Encode(p);
    return b.length <= 60000 ? b : null;
  }

  /// Adds one finished race to the record.
  void record({required int mine, required int theirs}) {
    if (mine > theirs) {
      wins++;
    } else if (mine < theirs) {
      losses++;
    } else {
      draws++;
    }
    pushups += mine;
    if (mine > best) best = mine;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'photo': photo == null ? null : base64Encode(photo!),
        'wins': wins,
        'losses': losses,
        'draws': draws,
        'pushups': pushups,
        'best': best,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        name: j['name'] as String? ?? '',
        photo: j['photo'] == null ? null : base64Decode(j['photo'] as String),
        wins: j['wins'] as int? ?? 0,
        losses: j['losses'] as int? ?? 0,
        draws: j['draws'] as int? ?? 0,
        pushups: j['pushups'] as int? ?? 0,
        best: j['best'] as int? ?? 0,
      );
}

/// Loads and saves the profile under `rr.profile`.
class ProfileStore {
  static const key = 'rr.profile';
  static const _oldNameKey = 'player_name'; // the lobby's name field, before profiles

  static Future<Profile> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null) return Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return Profile(name: prefs.getString(_oldNameKey) ?? '');
    } catch (_) {
      return Profile();
    }
  }

  static Future<void> save(Profile p) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, jsonEncode(p.toJson()));
    } catch (_) {}
  }
}

/// Fits any picture into a profile photo: the middle square, scaled down
/// until it is under [limit] bytes (it travels with every online race).
/// Null if it can't be read.
Future<Uint8List?> fitPhoto(Uint8List bytes, {int limit = 44000}) async {
  try {
    final image = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
    final side = image.width < image.height ? image.width : image.height;
    final src = Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side.toDouble(), side.toDouble());
    // A small square original needs no work.
    if (bytes.length <= limit && image.width == image.height && side <= 256) return bytes;
    for (final size in [256, 192, 160, 128, 96, 72, 56]) {
      if (size > side && size != 56) continue;
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(image, src, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
          Paint()..filterQuality = FilterQuality.medium);
      final out = await (await rec.endRecording().toImage(size, size)).toByteData(format: ui.ImageByteFormat.png);
      if (out != null && out.lengthInBytes <= limit) return out.buffer.asUint8List();
    }
  } catch (_) {}
  return null;
}

/// A round picture: the player's photo, or the default one.
ImageProvider avatarImage(Uint8List? photo, {String fallback = 'assets/rc/Adrian.png'}) =>
    photo == null ? AssetImage(fallback) as ImageProvider : MemoryImage(photo);

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.photo, this.size = 54, this.ring = Rpg.mana, this.fallback = 'assets/rc/Adrian.png'});
  final Uint8List? photo;
  final double size;
  final Color ring;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Rpg.surface3,
        border: Border.all(color: ring, width: size > 80 ? 4 : 3),
        boxShadow: [BoxShadow(color: ring.withOpacity(0.4), blurRadius: size / 5)],
        image: DecorationImage(image: avatarImage(photo, fallback: fallback), fit: BoxFit.cover),
      ),
    );
  }
}
