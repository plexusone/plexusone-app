import 'package:flutter/material.dart';

/// Terminal-style color theme
class TerminalTheme {
  // Background colors
  static const Color background = Color(0xFF1A1A1A);
  static const Color surface = Color(0xFF252525);
  static const Color surfaceLight = Color(0xFF333333);

  // Foreground colors
  static const Color foreground = Color(0xFFE0E0E0);
  static const Color foregroundDim = Color(0xFF888888);

  // Accent colors
  static const Color primary = Color(0xFF4A9980);
  static const Color primaryLight = Color(0xFF6BC4A6);

  // Status colors
  static const Color green = Color(0xFF4CAF50);
  static const Color red = Color(0xFFE53935);
  static const Color yellow = Color(0xFFFFC107);
  static const Color blue = Color(0xFF2196F3);
  static const Color orange = Color(0xFFFF9800);

  // ANSI-like colors
  static const Color ansiBlack = Color(0xFF000000);
  static const Color ansiRed = Color(0xFFCD3131);
  static const Color ansiGreen = Color(0xFF0DBC79);
  static const Color ansiYellow = Color(0xFFE5E510);
  static const Color ansiBlue = Color(0xFF2472C8);
  static const Color ansiMagenta = Color(0xFFBC3FBC);
  static const Color ansiCyan = Color(0xFF11A8CD);
  static const Color ansiWhite = Color(0xFFE5E5E5);

  /// Get the app's dark theme
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: primaryLight,
        surface: surface,
        error: red,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      iconTheme: const IconThemeData(
        color: foreground,
      ),
    );
  }
}
