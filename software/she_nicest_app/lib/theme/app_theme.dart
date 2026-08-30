import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF15252B);
  static const mist = Color(0xFFE9ECE9);
  static const lake = Color(0xFF85B5A7);
  static const moon = Color(0xFFE5EA82);
  static const quiet = Color(0xFF9BA8A6);
  static const textPrimary = Color(0xFFF1F4F1);
  static const textSecondary = Color(0xFFC7CFCC);
  static const textTertiary = Color(0xFF9EACA8);
  static const dusk = Color(0xFFD6AF76);
  static const cardBg = Color(0xFF1B3138);
  static const dockBg = Color(0xFF273A40);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.lake,
    brightness: Brightness.dark,
    surface: AppColors.ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: AppColors.moon,
      secondary: AppColors.lake,
      surface: AppColors.ink,
    ),
    scaffoldBackgroundColor: AppColors.ink,
    fontFamily: 'sans-serif',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 34, height: 1.2, fontWeight: FontWeight.w500),
      headlineSmall: TextStyle(fontSize: 24, height: 1.3, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 17, height: 1.55),
      bodyMedium: TextStyle(fontSize: 15, height: 1.5),
    ).apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.moon,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.09),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      hintStyle: const TextStyle(color: AppColors.quiet),
    ),
  );
}
