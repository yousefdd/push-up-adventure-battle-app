import 'package:supabase_flutter/supabase_flutter.dart';

/// Your Supabase project, from Project Settings → API Keys.
///
/// Paste the two values between the quotes, or pass them at build time:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
///
/// Use the publishable key (sb_publishable_…) or, on older projects, the
/// "anon public" key: both are designed to ship inside apps. Never put the
/// secret / service_role key here: it bypasses every rule in schema.sql.
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://lnbhmstwdonkowpvcczy.supabase.co',
  );
  static const key = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_GVe_BwcPk02FVbDjfcN75Q_XLvO_7K1',
  );

  static bool get isSet => url.isNotEmpty && key.isNotEmpty;

  /// The client, or null when the server is not set up or not started yet
  /// (tests, or before Supabase.initialize).
  static SupabaseClient? get client {
    if (!isSet) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
