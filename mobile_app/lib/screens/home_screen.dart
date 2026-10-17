import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';
import '../core/theme/radius.dart';
import '../core/theme/spacing.dart';
import '../core/theme/typography.dart';
import '../services/api_service.dart';
import '../services/telephony_bridge.dart';
import 'io_pending_requests_screen.dart';
import 'officer_request_screen.dart';
import 'role_dashboard_panel.dart';

/// Role-aware application shell with backend-backed dashboard data.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.apiService,
    required this.officerApiService,
    required this.role,
    required this.ioDeviceId,
    this.simSlotIndex = 0,
    this.telephonyBridge,
    this.onLogout,
  });

  final ApiService apiService;
  final ApiService officerApiService;
  final String role;
  final String ioDeviceId;
  final int simSlotIndex;
  final TelephonyBridge? telephonyBridge;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('IFSO Location Management'),
        actions: [
          if (onLogout != null)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Log Out',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Log Out'),
                    content: const Text(
                      'Are you sure you want to end your authenticated session? '
                      'You will need to re-authenticate to access operational workflows.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Log Out'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  onLogout!();
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space4,
          ),
          children: [
            RoleDashboardPanel(
              apiService: apiService,
              role: role,
            ),
            const SizedBox(height: AppSpacing.space4),

            // The role is resolved by /auth/me; UI visibility is not the security boundary.
            _buildRoleWorkflowSection(context, theme),
            if (role != 'ADMIN') const SizedBox(height: AppSpacing.space4),

            _buildForensicDisclaimer(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleWorkflowSection(BuildContext context, ThemeData theme) {
    if (role == 'ADMIN') {
      // The live, read-only administrative overview is rendered above.
      // Unsupported mutation capabilities are disclosed there, not simulated.
      return const SizedBox.shrink();
    }
    if (role != 'OFFICER' && role != 'IO') {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Unknown role. Access is denied.')));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Operational Workflows', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.space2),
        Row(
          children: [
            // Render only the workflow allowed by the backend-resolved role.
            if (role == 'OFFICER') Expanded(
              child: InkWell(
                borderRadius: AppRadius.borderMedium,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OfficerRequestScreen(
                        apiService: officerApiService,
                      ),
                    ),
                  );
                },
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.badge_outlined,
                          color: AppColors.primary,
                          size: 24,
                        ),
                        const SizedBox(height: AppSpacing.space2),
                        Text('Officer Module',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.space1),
                        Text(
                          'Request creation & secure link sharing.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.space3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space2,
                            vertical: AppSpacing.space1,
                          ),
                          decoration: const BoxDecoration(
                            color: AppColors.warningContainer,
                            borderRadius: AppRadius.borderSmall,
                          ),
                          child: Text(
                            'Create & Share',
                            style: AppTypography.technicalBold.copyWith(
                              fontSize: 11,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (role == 'IO') Expanded(
              child: InkWell(
                borderRadius: AppRadius.borderMedium,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => IoPendingRequestsScreen(
                        apiService: apiService,
                        ioDeviceId: ioDeviceId,
                        simSlotIndex: simSlotIndex,
                        telephonyBridge: telephonyBridge,
                      ),
                    ),
                  );
                },
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.phonelink_lock_outlined,
                          color: AppColors.secondary,
                          size: 24,
                        ),
                        const SizedBox(height: AppSpacing.space2),
                        Text('IO Execution', style: theme.textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.space1),
                        Text(
                          'Review pending requests and continue authorized execution.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.space3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space2,
                            vertical: AppSpacing.space1,
                          ),
                          decoration: const BoxDecoration(
                            color: AppColors.successContainer,
                            borderRadius: AppRadius.borderSmall,
                          ),
                          child: Text(
                            'Open Pending Queue',
                            style: AppTypography.technicalBold.copyWith(
                              fontSize: 11,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildForensicDisclaimer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppRadius.borderSmall,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_clock_outlined,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: Text(
              'EVIDENTIARY INTEGRITY: All queries require authorized authority. Target numbers are masked in UI and unencrypted coordinates are prohibited in application logs.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
