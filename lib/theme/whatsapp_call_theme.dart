import 'package:flutter/material.dart';

/// WhatsApp-inspired palette for calls (dark surfaces, green accents).
abstract final class WhatsAppCallTheme {
  static const Color scaffold = Color(0xFF0B141A);
  static const Color surface = Color(0xFF111B21);
  static const Color bar = Color(0xFF1F2C34);
  static const Color accent = Color(0xFF00A884);
  static const Color accentMuted = Color(0xFF128C7E);
  static const Color onAccent = Color(0xFFE9EDEF);
  static const Color danger = Color(0xFFE53935);
  static const Color subtleText = Color(0xFF8696A0);
  static const Color strongText = Color(0xFFE9EDEF);

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
        backgroundColor: bar,
        foregroundColor: strongText,
        elevation: 0,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bar,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: subtleText),
        labelStyle: const TextStyle(color: subtleText),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
