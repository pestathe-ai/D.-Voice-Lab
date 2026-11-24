import 'package:flutter/material.dart';

/// Colori del marchio Dom Studio.
class Brand {
  static const blue = Color(0xFF1D3A8A);
  static const orange = Color(0xFFF28C38);
  static const paper = Color(0xFFFFF8F0);
  static const ink = Color(0xFF14213D);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    brightness: brightness,
  ).copyWith(
    primary: dark ? Brand.orange : Brand.blue,
    onPrimary: dark ? Brand.ink : Colors.white,
    secondary: Brand.orange,
    onSecondary: Brand.ink,
    surface: dark ? const Color(0xFF0D1018) : Brand.paper,
    onSurface: dark ? const Color(0xFFEDEBE6) : Brand.ink,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Sora',
    scaffoldBackgroundColor: scheme.surface,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Sora',
        fontWeight: FontWeight.w800,
        fontSize: 22,
        color: scheme.onSurface,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1A1F2B) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(16),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF181C27) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: Brand.orange,
      inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.18),
      thumbColor: Brand.orange,
      trackHeight: 3,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF151A24) : Brand.paper,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.orange),
  );
}
