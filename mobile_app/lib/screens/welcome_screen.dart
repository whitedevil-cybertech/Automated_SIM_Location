import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';
import '../core/theme/radius.dart';
import '../core/theme/spacing.dart';
import '../core/theme/typography.dart';

/// Welcome screen presented to first-time users of the IFSO Location Management application.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onLogin,
    required this.onSignUp,
  });

  final VoidCallback onLogin;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space6,
              vertical: AppSpacing.space8,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Department Shield & Seal Icon
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      size: 52,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space6),

                // Title
                Text(
                  'IFSO Location Management',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.space2),

                // Department Subheading
                Text(
                  'Special Cell • Delhi Police\nAutomated SIM Location Query System',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.space8),

                // Official Notice Card
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    side: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              size: 20,
                              color: AppColors.secondary,
                            ),
                            const SizedBox(width: AppSpacing.space2),
                            Text(
                              'Authorized Access Only',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.space2),
                        Text(
                          'This application is restricted to authorized IFSO personnel, Submitting Officers, and designated Investigating Officers (IO). All location dispatches and authorizations are cryptographically recorded in an immutable audit trail.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space8),

                // Primary Action: Log In
                FilledButton.icon(
                  onPressed: onLogin,
                  icon: const Icon(Icons.login),
                  label: const Text('Log In with Credentials'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space3),

                // Secondary Action: Sign Up / Request Provisioning
                OutlinedButton.icon(
                  onPressed: onSignUp,
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('New Officer Enrollment'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space6),

                // System Environment Footer
                Text(
                  'Environment: Production Boundary • MDM Enforced',
                  style: AppTypography.technical.copyWith(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
