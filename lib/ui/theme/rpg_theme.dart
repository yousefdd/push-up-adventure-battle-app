import 'package:flutter/material.dart';

/// The "Obsidian Violet" palette, value for value, as defined in the source
/// app's theme (its default dark skin). Names follow the source's own
/// `Palette(bgDeep, bg, surface, …)` fields so the mapping stays obvious.
class Rpg {
  static const Color bgDeep = Color(0xFF05030E);
  static const Color bg = Color(0xFF0D0A1B);
  static const Color surface = Color(0xFF181327);
  static const Color surface2 = Color(0xFF120E20);
  static const Color surface3 = Color(0xFF231C39);
  static const Color border = Color(0xFF2A2342);
  static const Color border2 = Color(0xFF3A3155);
  static const Color ink = Color(0xFFF1ECDF);
  static const Color ink2 = Color(0xFFA99FC4);
  static const Color ink3 = Color(0xFF8B82A8);
  static const Color brand = Color(0xFFF2764D);
  static const Color brandEdge = Color(0xFFB8431F);
  static const Color brandSoft = Color(0xFF2A1D2A);
  static const Color onBrand = Color(0xFFFFFFFF);
  static const Color gold = Color(0xFFFFC94A);
  static const Color goldEdge = Color(0xFFC9881A);
  static const Color goldSoft = Color(0xFF2E2413);
  static const Color vigor = Color(0xFF5FD08C);
  static const Color vigorSoft = Color(0xFF15271E);
  static const Color mana = Color(0xFF6BA8FF);
  static const Color manaSoft = Color(0xFF141F30);
  static const Color arcane = Color(0xFFA98CFF);
  static const Color arcaneSoft = Color(0xFF1F1934);
  static const Color danger = Color(0xFFFF5C7A);

  /// Display face (Baloo 2) and body face (Nunito), both shipped by the source.
  static const String display = 'Baloo2';
  static const String body = 'Nunito';

  /// Arabic glyphs, when the language is Arabic (the Latin faces have none).
  /// Every style names its fallback: the web renderer has no system fonts and
  /// would otherwise fetch one from the network.
  static const List<String> arabic = ['Tajawal'];
  static const List<String> arabicDisplay = ['Lalezar', 'Tajawal'];

  static ThemeData theme() {
    // The app's own fonts everywhere, including the Material defaults
    // (otherwise Roboto, which is not bundled).
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: body,
      fontFamilyFallback: arabic,
    );
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      // Screens zoom and fade in rather than sliding flat.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
      }),
      colorScheme: base.colorScheme.copyWith(
        primary: brand,
        onPrimary: onBrand,
        secondary: gold,
        surface: surface,
        onSurface: ink,
        error: danger,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: body,
        fontFamilyFallback: arabic,
        bodyColor: ink,
        displayColor: ink,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: onBrand,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: brandEdge, width: 2),
          ),
          textStyle: const TextStyle(
            fontFamily: display,
            fontFamilyFallback: arabicDisplay,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  /// Standard raised panel: surface fill with a soft violet border.
  static BoxDecoration panel({Color? border, Color? fill}) => BoxDecoration(
        color: fill ?? surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border ?? Rpg.border, width: 2),
      );

  static const TextStyle title = TextStyle(
    fontFamily: display,
    fontFamilyFallback: arabicDisplay,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: ink,
    height: 1.05,
  );

  static const TextStyle bigNumber = TextStyle(
    fontFamily: display,
    fontFamilyFallback: arabicDisplay,
    fontSize: 68,
    fontWeight: FontWeight.w800,
    height: 1.0,
  );

  static const TextStyle label = TextStyle(
    fontFamily: body,
    fontFamilyFallback: arabic,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: ink2,
  );
}
