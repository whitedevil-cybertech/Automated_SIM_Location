import 'package:flutter/material.dart';

import '../core/constants/request_states.dart';
import '../core/theme/color_schemes.dart';
import '../core/theme/radius.dart';
import '../core/theme/spacing.dart';
import '../core/theme/typography.dart';
import '../models/location_request.dart';
import '../services/api_service.dart';

class IoReviewScreen extends StatefulWidget {
  const IoReviewScreen({
    super.key,
    required this.request,
    required this.apiService,
    required this.ioDeviceId,
    this.simSlotIndex = 0,
  });

  final LocationRequest request;
  final ApiService apiService;
  final String ioDeviceId;
  final int simSlotIndex;

  @override
  State<IoReviewScreen> createState() => _IoReviewScreenState();
}

class _IoReviewScreenState extends State<IoReviewScreen> {
  bool _isExecuting = false;
  bool _executionSuccessful = false;

  Future<void> _confirmExecution() async {
    if (_isExecuting ||
        _executionSuccessful ||
        widget.request.status != RequestState.pendingIoReview) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Location Request'),
          content: const Text(
            'Executing this request will authorize the location workflow '
            'to proceed through the authorized IO device and SIM.\n\n'
            'The backend records the execution authorization. '
            'SMS transmission is performed by the authorized Android device, '
            'not by the backend.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm Execution'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _executeRequest();
  }

  Future<void> _executeRequest() async {
    setState(() {
      _isExecuting = true;
    });

    try {
      await widget.apiService.executeLocationRequest(
        requestId: widget.request.requestId,
        ioDeviceId: widget.ioDeviceId,
        simSlotIndex: widget.simSlotIndex,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isExecuting = false;
        _executionSuccessful = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location request execution authorized successfully.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isExecuting = false;
      });

      _showError(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isExecuting = false;
      });

      _showError(
        'Unable to execute the location request. Check the network connection '
        'and try again.',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final canExecute =
        request.status == RequestState.pendingIoReview &&
        !_isExecuting &&
        !_executionSuccessful;

    return Scaffold(
      appBar: AppBar(
        title: const Text('IO Request Review'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space4),
          children: [
            _buildReviewHeader(theme),
            const SizedBox(height: AppSpacing.space4),
            _buildRequestDetails(theme),
            const SizedBox(height: AppSpacing.space4),
            _buildExecutionInformation(theme),
            const SizedBox(height: AppSpacing.space6),
            _buildExecutionBoundaryNotice(theme),
            const SizedBox(height: AppSpacing.space6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canExecute ? _confirmExecution : null,
                icon: _isExecuting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Icon(
                        _executionSuccessful
                            ? Icons.check_circle_outline
                            : Icons.send_outlined,
                      ),
                label: Text(
                  _isExecuting
                      ? 'Executing...'
                      : _executionSuccessful
                          ? 'Execution Authorized'
                          : 'Execute Location Request',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewHeader(ThemeData theme) {
    final state = widget.request.status;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LOCATION REQUEST',
              style: AppTypography.technicalBold.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              widget.request.requestId,
              style: AppTypography.technicalBold.copyWith(
                fontSize: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space3,
                vertical: AppSpacing.space2,
              ),
              decoration: BoxDecoration(
                color: state.containerColor,
                borderRadius: AppRadius.borderSmall,
                border: Border.all(
                  color: state.color.withAlpha(80),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    state.icon,
                    size: 17,
                    color: state.color,
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  Text(
                    state.label,
                    style: AppTypography.technicalBold.copyWith(
                      color: state.color,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestDetails(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request Details',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.space3),
            _detailRow(
              'Target Number',
              widget.request.targetPhoneMasked,
              technical: true,
            ),
            _detailRow(
              'SIM / Operator',
              widget.request.operatorCode,
            ),
            _detailRow(
              'Case ID',
              widget.request.caseId,
              technical: true,
            ),
            _detailRow(
              'Created',
              _formatDateTime(widget.request.createdAt),
              technical: true,
            ),
            if (widget.request.remarks != null &&
                widget.request.remarks!.trim().isNotEmpty)
              _detailRow(
                'Remarks',
                widget.request.remarks!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionInformation(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Execution Context',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.space3),
            _detailRow(
              'IO Device',
              widget.ioDeviceId,
              technical: true,
            ),
            _detailRow(
              'SIM Slot',
              widget.simSlotIndex.toString(),
              technical: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionBoundaryNotice(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: AppColors.infoContainer,
        borderRadius: AppRadius.borderMedium,
        border: Border.all(
          color: AppColors.info.withAlpha(70),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.phonelink_lock_outlined,
            color: AppColors.info,
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              'Execution authorization is recorded by the backend. '
              'The actual SMS workflow remains on the authorized Android '
              'device and SIM.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    bool technical = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            value,
            style: technical
                ? AppTypography.technical
                : Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final utc = value.toUtc();

    String twoDigits(int number) => number.toString().padLeft(2, '0');

    return '${utc.year}-${twoDigits(utc.month)}-${twoDigits(utc.day)} '
        '${twoDigits(utc.hour)}:${twoDigits(utc.minute)} UTC';
  }
}