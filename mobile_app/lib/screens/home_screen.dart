import 'package:flutter/material.dart';

import '../core/constants/request_states.dart';
import '../core/theme/color_schemes.dart';
import '../core/theme/radius.dart';
import '../core/theme/spacing.dart';
import '../core/theme/typography.dart';
import '../services/api_service.dart';
import '../services/telephony_bridge.dart';
import 'io_pending_requests_screen.dart';
import 'officer_request_screen.dart';

/// Application Shell / Home Dashboard for Phase 1.
/// Establishes the visual hierarchy, layout tokens, and forensic status indicators.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.apiService,
    required this.officerApiService,
    required this.ioDeviceId,
    this.simSlotIndex = 0,
    this.telephonyBridge,
  });

  final ApiService apiService;
  final ApiService officerApiService;
  final String ioDeviceId;
  final int simSlotIndex;
  final TelephonyBridge? telephonyBridge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('IFSO Location Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Security Status',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Forensic integrity active: All events audited.',
                  ),
                ),
              );
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
            // Phase Banner
            _buildPhaseBanner(theme),
            const SizedBox(height: AppSpacing.space4),

            // System Information Card
            _buildSystemStatusCard(theme),
            const SizedBox(height: AppSpacing.space4),

            // Role Workflows (Phase 2 & Phase 3 placeholders)
            _buildRoleWorkflowSection(context, theme),
            const SizedBox(height: AppSpacing.space6),

            // Request Lifecycle State Tokens
            _buildLifecycleStateTokens(theme),
            const SizedBox(height: AppSpacing.space6),

            // Forensic Disclaimer
            _buildForensicDisclaimer(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: AppRadius.borderMedium,
        border: Border.all(color: AppColors.primary.withAlpha(50)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.foundation_outlined,
            color: AppColors.primary,
            size: 28,
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phase 1 — Foundation & Architecture',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  'Core backend, database, state machine, and design system established.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System Environment', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.space2),
            const Divider(),
            const SizedBox(height: AppSpacing.space2),
            _buildStatusRow(
              'Deployment Tier',
              'Internal MDM Managed',
              Icons.verified_user_outlined,
            ),
            const SizedBox(height: AppSpacing.space2),
            _buildStatusRow(
              'Backend API',
              'FastAPI /api/v1 (Ready)',
              Icons.cloud_done_outlined,
            ),
            const SizedBox(height: AppSpacing.space2),
            _buildStatusRow(
              'Audit Trail',
              'Tamper-Evident Write-Once',
              Icons.receipt_long_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.secondary),
        const SizedBox(width: AppSpacing.space2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTypography.technicalBold.copyWith(
            fontSize: 12,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleWorkflowSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Operational Workflows', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.space2),
        Row(
          children: [
            // Officer Module Card
            Expanded(
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
            const SizedBox(width: AppSpacing.space3),
            // IO Module Card
            Expanded(
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

  Widget _buildLifecycleStateTokens(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Request Lifecycle States', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Audited state machine transitions defined per architecture:',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.space3),
        Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: RequestState.values.map((state) {
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space3,
                vertical: AppSpacing.space2,
              ),
              decoration: BoxDecoration(
                color: state.containerColor,
                borderRadius: AppRadius.borderSmall,
                border: Border.all(color: state.color.withAlpha(80)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(state.icon, size: 14, color: state.color),
                  const SizedBox(width: AppSpacing.space1),
                  Text(
                    state.value,
                    style: AppTypography.technicalBold.copyWith(
                      fontSize: 11,
                      color: state.color,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
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
