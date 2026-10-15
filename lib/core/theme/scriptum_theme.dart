import 'package:flutter/material.dart';

class ScriptumTheme {
  ScriptumTheme._();

  // Core Surface Colors
  static const Color obsidianBg = Color(0xFF090B10);
  static const Color slateSurface = Color(0xFF121620);

  // Brand Accents (From Scriptum Icon)
  static const Color cyanGlow = Color(0xFF38BDF8);
  static const Color goldAccent = Color(0xFFF59E0B);
  static const Color dangerRed = Color(0xFFEF4444);

  // Curated Stylus Ink Palette
  static const List<Color> inkColors = [
    Color(0xFFFFFFFF), // Pure White (for dark-mode notes)
    Color(0xFF0F172A), // Deep Charcoal Ink (for standard white PDFs)
    Color(0xFF38BDF8), // Scriptum Cyan
    Color(0xFFF59E0B), // Amber Gold
    Color(0xFFEF4444), // Crimson Correction Red
    Color(0xFF10B981), // Emerald Green
    Color(0xFFA855F7), // Royal Purple
  ];

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: obsidianBg,
      colorScheme: const ColorScheme.dark(
        primary: cyanGlow,
        secondary: goldAccent,
        surface: slateSurface,
      ),
      splashFactory: InkSparkle.splashFactory,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.85),
          highlightColor: cyanGlow.withValues(alpha: 0.15),
        ),
      ),
    );
  }
}