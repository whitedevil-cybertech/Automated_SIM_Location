import 'package:flutter/material.dart';

/// Centralized color palette defined by project Design.md.
/// Light-first neutral theme for forensic operational workflows.
abstract class AppColors {
  static const Color primary = Color(0xFF17324D);
  static const Color primaryContainer = Color(0xFFDCE8F2);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF0F2234);

  static const Color secondary = Color(0xFF52677A);
  static const Color onSecondary = Color(0xFFFFFFFF);

  static const Color surface = Color(0xFFF8FAFC);
  static const Color onSurface = Color(0xFF17212B);
  static const Color surfaceContainer = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF17212B);
  static const Color textSecondary = Color(0xFF52606D);
  static const Color border = Color(0xFFCBD5E1);

  // Semantic status colors
  static const Color success = Color(0xFF18794E);
  static const Color onSuccess = Color(0xFFFFFFFF);
  static const Color successContainer = Color(0xFFD1FADF);

  static const Color warning = Color(0xFF9A6700);
  static const Color onWarning = Color(0xFFFFFFFF);
  static const Color warningContainer = Color(0xFFFEF0C7);

  static const Color error = Color(0xFFB42318);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFEE4E2);

  static const Color info = Color(0xFF175CD3);
  static const Color onInfo = Color(0xFFFFFFFF);
  static const Color infoContainer = Color(0xFFD1E9FF);
}

/// Centralized Material 3 ColorScheme for light mode.
ColorScheme lightColorScheme = const ColorScheme(
  brightness: Brightness.light,
  primary: AppColors.primary,
  onPrimary: AppColors.onPrimary,
  primaryContainer: AppColors.primaryContainer,
  onPrimaryContainer: AppColors.onPrimaryContainer,
  secondary: AppColors.secondary,
  onSecondary: AppColors.onSecondary,
  error: AppColors.error,
  onError: AppColors.onError,
  errorContainer: AppColors.errorContainer,
  onErrorContainer: AppColors.error,
  surface: AppColors.surface,
  onSurface: AppColors.textPrimary,
  surfaceContainer: AppColors.surfaceContainer,
  outline: AppColors.border,
  outlineVariant: AppColors.border,
);
