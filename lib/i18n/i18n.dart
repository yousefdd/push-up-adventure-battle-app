import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ar.dart';
import 'world_ar.dart';

/// The app's two languages.
enum Lang { en, ar }

/// The language in use. English text is the key; Arabic comes from [ar]
/// (hand-written) and [worldAr] (generated with the adventure roster).
class I18n {
  static final lang = ValueNotifier<Lang>(Lang.en);
  static const _key = 'rr.lang';

  static bool get isAr => lang.value == Lang.ar;
  static TextDirection get direction => isAr ? TextDirection.rtl : TextDirection.ltr;

  /// The saved choice, or the phone's language the first time.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    lang.value = saved != null
        ? Lang.values.firstWhere((l) => l.name == saved, orElse: () => Lang.en)
        : PlatformDispatcher.instance.locale.languageCode == 'ar'
            ? Lang.ar
            : Lang.en;
  }

  static Future<void> set(Lang l) async {
    lang.value = l;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, l.name);
  }
}

/// [en] in the current language, with `{name}` slots filled from [args].
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = I18n.isAr ? (ar[en] ?? worldAr[en] ?? en) : en;
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// "1 day", "5 days"; in Arabic the counted noun follows the number's rules
/// (يوم واحد، يومان، ٣–١٠ أيام، ١١–٩٩ يومًا).
String trDays(int n) {
  if (!I18n.isAr) return n == 1 ? '1 day' : '$n days';
  if (n == 1) return 'يوم واحد';
  if (n == 2) return 'يومان';
  final r = n % 100;
  if (r >= 3 && r <= 10) return '$n أيام';
  if (r >= 11) return '$n يومًا';
  return '$n يوم';
}

/// A foe's name: elites carry a ★ after the name in both languages.
String trName(String name) => name.endsWith(' ★') ? '${tr(name.substring(0, name.length - 2))} ★' : tr(name);

const _ordinalsAr = [
  'الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس', 'السابع', 'الثامن', 'التاسع', 'العاشر', //
  'الحادي عشر', 'الثاني عشر', 'الثالث عشر', 'الرابع عشر', 'الخامس عشر',
];

/// "Chapter IV" → "الفصل الرابع".
String trChapter(int number, String roman) =>
    I18n.isAr && number <= _ordinalsAr.length ? 'الفصل ${_ordinalsAr[number - 1]}' : roman;
