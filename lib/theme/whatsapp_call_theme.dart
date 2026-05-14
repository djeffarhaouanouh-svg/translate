import 'package:flutter/material.dart';

/// WhatsApp-inspired palette (dark chat surfaces + green accents).
abstract final class WhatsAppCallTheme {
  static const Color scaffold = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF141414);
  static const Color bar = Color(0xFF1C1C1C);
  static const Color waHeader = Color(0xFF008069);
  static const Color accent = Color(0xFF00A884);
  static const Color accentMuted = Color(0xFF128C7E);
  static const Color onAccent = Color(0xFFE9EDEF);
  static const Color danger = Color(0xFFE53935);
  static const Color subtleText = Color(0xFF8696A0);
  static const Color strongText = Color(0xFFE9EDEF);
  static const Color bubbleIncoming = Color(0xFF1F1F1F);

  static ThemeData material() {
    const base = ColorScheme.dark(
      primary: accent,
      onPrimary: onAccent,
      surface: surface,
      onSurface: strongText,
      error: danger,
      onError: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: base,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: strongText,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bar,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: subtleText),
        labelStyle: const TextStyle(color: subtleText),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF2A3942)),
    );
  }
}
