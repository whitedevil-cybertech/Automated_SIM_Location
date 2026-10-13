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
    this.telephonyBridge,
    required this.ioDeviceId,
    this.simSlotIndex = 0,
  });

  final LocationRequest request;
  final ApiService apiService;

  /// Retained for compatibility with existing callers.
  ///
  /// This screen does not perform telephony operations.
  final dynamic telephonyBridge;

  final String ioDeviceId;
  final int simSlotIndex;

  @override
  State<IoReviewScreen> createState() => _IoReviewScreenState();
}

class _IoReviewScreenState extends State<IoReviewScreen> {
  late RequestState _currentStatus;

  bool _isExecuting = false;
  bool _executionSuccessful = false;

  String? _errorMessage;
  String? _workflowMessage;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.request.status;
  }

  Future<void> _confirmExecution() async {
    if (_isExecuting ||
        _executionSuccessful ||
        _currentStatus != RequestState.pendingIoReview) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Execution Authorization'),
          content: const Text(
            'Confirm that this request has been reviewed and is '
            'authorized to proceed through the approved workflow.\n\n'
            'This action records execution authorization. It does not '
            'send SMS messages or retrieve a device location.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Confirm'),
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
    if (_isExecuting || _executionSuccessful || !mounted) {
      return;
    }

    if (_currentStatus != RequestState.pendingIoReview) {
      return;
    }

    setState(() {
      _isExecuting = true;
      _errorMessage = null;
      _workflowMessage = 'Recording execution authorization...';
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
        _currentStatus = RequestState.executing;
        _workflowMessage = 'Execution authorization recorded. '
            'No SMS was sent by this screen.';
      });

      _showMessage(
        'Execution authorization recorded successfully.',
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      final message = _userFacingErrorMessage(error);

      setState(() {
        _isExecuting = false;
        _errorMessage = message;
        _workflowMessage = null;
      });

      // The inline workflow status card presents the error. Avoid showing
      // the same message a second time in a SnackBar.
    } catch (_) {
      if (!mounted) {
        return;
      }

      const message = 'Unable to record execution authorization. '
          'Check the service connection and try again.';

      setState(() {
        _isExecuting = false;
        _errorMessage = message;
        _workflowMessage = null;
      });

      // The inline workflow status card presents the error. Avoid showing
      // the same message a second time in a SnackBar.
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  String _userFacingErrorMessage(ApiException error) {
    // Prefer stable, user-facing text for known API error codes. Some
    // ApiService implementations expose a generic message for 422 responses,
    // so handle VALIDATION_ERROR by code rather than relying only on the
    // server message string.
    switch (error.code) {
      case 'UNAUTHORIZED':
        return 'Your session is not authorized.';
      case 'FORBIDDEN':
        return 'You are not authorized to execute this request.';
      case 'INVALID_STATE_TRANSITION':
        return 'The request is no longer awaiting IO review.';
      case 'VALIDATION_ERROR':
        return 'Operator is not approved or currently inactive.';
      default:
        final message = error.message.trim();

        // Fallback for API implementations that don't populate error.code.
        switch (message) {
          case 'Authentication required.':
          case 'Unauthorized':
            return 'Your session is not authorized.';
          case 'Insufficient permissions.':
            return 'You are not authorized to execute this request.';
          case 'Invalid request state.':
            return 'The request is no longer awaiting IO review.';
          default:
            return message.isEmpty
                ? 'Unable to record execution authorization.'
                : message;
        }
    }
  }

  Widget _buildWorkflowStatus(ThemeData theme) {
    final message = _errorMessage ?? _workflowMessage;

    if (message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasError = _errorMessage != null;

    return Card(
      key: const ValueKey('workflow-status-card'),
      color: hasError ? AppColors.errorContainer : AppColors.infoContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasError ? Icons.error_outline : Icons.info_outline,
              color: hasError ? AppColors.error : AppColors.info,
            ),
            const SizedBox(width: AppSpacing.space2),
            Expanded(
              child: Text(
                message,
                key: const ValueKey('workflow-status-message'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final canExecute = _currentStatus == RequestState.pendingIoReview &&
        !_isExecuting &&
        !_executionSuccessful;

    return Scaffold(
      appBar: AppBar(
        title: const Text('IO Request Review'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildReviewHeader(theme),
              const SizedBox(height: AppSpacing.space3),
              _buildWorkflowStatus(theme),
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
                              : Icons.verified_user_outlined,
                        ),
                  label: Text(
                    _isExecuting
                        ? 'Recording Authorization...'
                        : _executionSuccessful
                            ? 'Authorization Recorded'
                            : 'Authorize Execution',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewHeader(ThemeData theme) {
    final state = _currentStatus;

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
            SelectableText(
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
            _detailRow(
              'Authorization Status',
              _executionSuccessful
                  ? 'Recorded'
                  : _isExecuting
                      ? 'In progress'
                      : 'Not recorded',
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
              'This screen records execution authorization only. '
              'It does not send carrier SMS commands, retrieve '
              'locations, or collect carrier responses.',
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
      padding: const EdgeInsets.only(
        bottom: AppSpacing.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.space1),
          SelectableText(
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

    return '${utc.year}-${twoDigits(utc.month)}-'
        '${twoDigits(utc.day)} '
        '${twoDigits(utc.hour)}:${twoDigits(utc.minute)} UTC';
  }
}
