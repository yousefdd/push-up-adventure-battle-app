import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'run_controller.dart';

/// The local save: one JSON document under `rr.save` (replica/architecture.md).
class PrefsRunStore implements RunStore {
  static const key = 'rr.save';

  @override
  Future<Map<String, dynamic>?> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return null;
      final doc = jsonDecode(raw);
      return doc is Map<String, dynamic> && doc['version'] == 1 ? doc : null;
    } catch (_) {
      // A damaged save must never block the game: start fresh.
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> doc) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, jsonEncode(doc));
    } catch (_) {}
  }
}
