import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.forestGreen,
      brightness: Brightness.light,
      primary: AppColors.forestGreen,
      secondary: AppColors.accentGreen,
      surface: AppColors.white,
      error: AppColors.negativeRed,
    );

    return _baseTheme(colorScheme).copyWith(
      scaffoldBackgroundColor: AppColors.lightBackground,
      cardTheme: _cardTheme(
        AppColors.white,
        Colors.black.withValues(alpha: .08),
      ),
      dividerTheme: DividerThemeData(color: AppColors.lightGray),
      textTheme: _baseTheme(colorScheme).textTheme.apply(
        bodyColor: AppColors.darkGray,
        displayColor: AppColors.darkGray,
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accentGreen,
      brightness: Brightness.dark,
      primary: AppColors.accentGreen,
      secondary: AppColors.positiveGreen,
      surface: AppColors.darkCard,
      error: AppColors.negativeRed,
    );

    return _baseTheme(colorScheme).copyWith(
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardTheme: _cardTheme(AppColors.darkCard, Colors.transparent),
      dividerTheme: const DividerThemeData(color: AppColors.darkBorder),
      textTheme: _baseTheme(colorScheme).textTheme.apply(
        bodyColor: AppColors.white,
        displayColor: AppColors.white,
      ),
    );
  }

  static ThemeData _baseTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.forestGreen,
          foregroundColor: AppColors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  static CardThemeData _cardTheme(Color color, Color shadowColor) {
    return CardThemeData(
      color: color,
      elevation: shadowColor == Colors.transparent ? 0 : 10,
      shadowColor: shadowColor,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    );
  }
}
