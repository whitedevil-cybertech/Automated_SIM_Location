import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifso_mobile_app/core/theme/app_theme.dart';
import 'package:ifso_mobile_app/core/theme/color_schemes.dart';
import 'package:ifso_mobile_app/core/theme/radius.dart';
import 'package:ifso_mobile_app/core/theme/spacing.dart';

void main() {
  group('Design Tokens Verification', () {
    test('Colors match project specifications in Design.md', () {
      expect(AppColors.primary, const Color(0xFF17324D));
      expect(AppColors.primaryContainer, const Color(0xFFDCE8F2));
      expect(AppColors.surface, const Color(0xFFF8FAFC));
      expect(AppColors.textPrimary, const Color(0xFF17212B));
      expect(AppColors.textSecondary, const Color(0xFF52606D));
      expect(AppColors.border, const Color(0xFFCBD5E1));

      // Semantic status colors
      expect(AppColors.success, const Color(0xFF18794E));
      expect(AppColors.warning, const Color(0xFF9A6700));
      expect(AppColors.error, const Color(0xFFB42318));
      expect(AppColors.info, const Color(0xFF175CD3));
    });

    test('Spacing tokens adhere to 8-point system', () {
      expect(AppSpacing.space1, 4.0);
      expect(AppSpacing.space2, 8.0);
      expect(AppSpacing.space3, 12.0);
      expect(AppSpacing.space4, 16.0);
      expect(AppSpacing.space5, 20.0);
      expect(AppSpacing.space6, 24.0);
      expect(AppSpacing.space8, 32.0);
      expect(AppSpacing.space10, 40.0);
    });

    test('Shape radius tokens match operational guidelines', () {
      expect(AppRadius.small, 6.0);
      expect(AppRadius.medium, 10.0);
      expect(AppRadius.large, 16.0);
    });

    test('ThemeData is configured with Material 3 enabled', () {
      final theme = AppTheme.lightTheme;
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.scaffoldBackgroundColor, AppColors.surface);
    });
  });
}
