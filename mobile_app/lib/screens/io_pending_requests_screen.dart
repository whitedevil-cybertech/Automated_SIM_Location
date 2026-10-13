import 'package:flutter/material.dart';

import '../core/constants/request_states.dart';
import '../core/theme/color_schemes.dart';
import '../core/theme/radius.dart';
import '../core/theme/spacing.dart';
import '../models/location_request.dart';
import '../services/api_service.dart';
import '../services/telephony_bridge.dart';
import 'io_review_screen.dart';

class IoPendingRequestsScreen extends StatefulWidget {
  const IoPendingRequestsScreen({
    super.key,
    required this.apiService,
    required this.ioDeviceId,
    this.simSlotIndex = 0,
    this.telephonyBridge,
  });

  final ApiService apiService;
  final String ioDeviceId;
  final int simSlotIndex;
  final TelephonyBridge? telephonyBridge;

  @override
  State<IoPendingRequestsScreen> createState() =>
      _IoPendingRequestsScreenState();
}

class _IoPendingRequestsScreenState extends State<IoPendingRequestsScreen> {
  List<LocationRequest> _requests = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests({bool showLoadingIndicator = true}) async {
    if (showLoadingIndicator && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final requests = await widget.apiService.getPendingIoRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _errorMessage = null;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to load pending requests. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openRequest(LocationRequest request) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => IoReviewScreen(
          request: request,
          apiService: widget.apiService,
          ioDeviceId: widget.ioDeviceId,
          simSlotIndex: widget.simSlotIndex,
          telephonyBridge: widget.telephonyBridge,
        ),
      ),
    );

    if (mounted) {
      await _loadRequests(showLoadingIndicator: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending IO Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh requests',
            onPressed: _isLoading ? null : () => _loadRequests(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading && _requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _requests.isEmpty) {
      return _buildErrorState(theme);
    }

    if (_requests.isEmpty) {
      return _buildEmptyState(theme);
    }

    return RefreshIndicator(
      onRefresh: () => _loadRequests(showLoadingIndicator: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.space4),
        children: [
          _buildQueueSummary(theme),
          const SizedBox(height: AppSpacing.space3),
          for (final request in _requests)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space3),
              child: _buildRequestCard(request, theme),
            ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space2),
              child: Text(
                'Refresh failed: $_errorMessage',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQueueSummary(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Row(
          children: [
            const Icon(
              Icons.pending_actions_outlined,
              color: AppColors.primary,
              size: 30,
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Awaiting IO Review',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.space1),
                  Text(
                    '${_requests.length} pending '
                    '${_requests.length == 1 ? 'request' : 'requests'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(LocationRequest request, ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: AppRadius.borderMedium,
        onTap: () => _openRequest(request),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.requestId,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  _buildStatusBadge(request.status),
                ],
              ),
              const SizedBox(height: AppSpacing.space3),
              _buildDetailRow(Icons.folder_outlined, 'Case ID', request.caseId),
              const SizedBox(height: AppSpacing.space2),
              _buildDetailRow(
                Icons.phone_android_outlined,
                'Target',
                request.targetPhoneMasked,
              ),
              const SizedBox(height: AppSpacing.space2),
              _buildDetailRow(
                Icons.sim_card_outlined,
                'Operator',
                request.operatorCode,
              ),
              const SizedBox(height: AppSpacing.space2),
              _buildDetailRow(
                Icons.schedule_outlined,
                'Created',
                _formatDate(request.createdAt),
              ),
              const SizedBox(height: AppSpacing.space3),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _openRequest(request),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Review Request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(RequestState status) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space2,
        vertical: AppSpacing.space1,
      ),
      decoration: BoxDecoration(
        color: status.containerColor,
        borderRadius: AppRadius.borderSmall,
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.space2),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () => _loadRequests(showLoadingIndicator: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.space6),
        children: [
          const SizedBox(height: 90),
          Icon(
            Icons.inbox_outlined,
            size: 68,
            color: AppColors.textSecondary.withAlpha(150),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            'No Pending Requests',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Requests awaiting IO review will appear here after a valid '
            'request link is accessed.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.space4),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _loadRequests(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 56, color: AppColors.error),
            const SizedBox(height: AppSpacing.space3),
            Text(
              'Unable to Load Requests',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.space4),
            FilledButton.icon(
              onPressed: () => _loadRequests(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}
