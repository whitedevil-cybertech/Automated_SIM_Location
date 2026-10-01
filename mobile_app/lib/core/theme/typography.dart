import 'package:flutter/material.dart';
import 'color_schemes.dart';

/// Centralized Typography hierarchy per Design.md.
/// Uses Inter for UI elements and monospace for technical forensic tokens.
abstract class AppTypography {
  static const String primaryFontFamily = 'Inter';
  static const List<String> primaryFontFallback = [
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'sans-serif',
  ];

  static const List<String> monoFontFallback = [
    'JetBrains Mono',
    'Courier New',
    'monospace',
  ];

  /// Technical style for Request IDs, hashes, timestamps, and raw evidence.
  static const TextStyle technical = TextStyle(
    fontFamilyFallback: monoFontFallback,
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    color: AppColors.textPrimary,
  );

  /// Technical bold for badges and status codes.
  static const TextStyle technicalBold = TextStyle(
    fontFamilyFallback: monoFontFallback,
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: AppColors.textPrimary,
  );

  /// Material 3 TextTheme configuration.
  static TextTheme textTheme = const TextTheme(
    // Display: 28-32 px, weight 600-700
    displayLarge: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 32.0,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: AppColors.textPrimary,
    ),
    displayMedium: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 28.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: AppColors.textPrimary,
    ),

    // Headings
    headlineLarge: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 24.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: AppColors.textPrimary,
    ),
    headlineMedium: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 20.0,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    headlineSmall: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 18.0,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),

    // Titles
    titleLarge: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 18.0,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    titleMedium: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 16.0,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    titleSmall: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 14.0,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),

    // Body
    bodyLarge: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 16.0,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: AppColors.textPrimary,
    ),
    bodyMedium: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 14.0,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: AppColors.textPrimary,
    ),
    bodySmall: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 12.0,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: AppColors.textSecondary,
    ),

    // Labels & Buttons
    labelLarge: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 14.0,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: AppColors.textPrimary,
    ),
    labelMedium: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 13.0,
      fontWeight: FontWeight.w500,
      color: AppColors.textSecondary,
    ),
    labelSmall: TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallback,
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
      color: AppColors.textSecondary,
    ),
  );
}
