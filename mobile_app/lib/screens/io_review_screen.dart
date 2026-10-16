import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Android telephony bridge for authorized SMS dispatch and response capture.
  final dynamic telephonyBridge;

  final String ioDeviceId;
  final int simSlotIndex;

  @override
  State<IoReviewScreen> createState() => _IoReviewScreenState();
}

class _IoReviewScreenState extends State<IoReviewScreen> {
  late RequestState _currentStatus;

  bool _isExecuting = false;
  bool _authorizationRecorded = false;
  bool _smsDispatchAccepted = false;
  bool _dispatchOutcomeUnknown = false;
  bool _executionOutcomeUnknown = false;
  bool _sendStatusSyncPending = false;
  bool? _pendingSendStatusSuccess;
  String? _pendingDeliveryStatus;
  String? _pendingSendError;
  StreamSubscription<dynamic>? _smsSubscription;
  String? _expectedSender;
  String? _rawResponse;
  String? _responseSender;
  DateTime? _responseReceivedAt;
  String? _responseHash;
  dynamic _earlySmsEvent;

  String? _errorMessage;
  String? _workflowMessage;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.request.status;
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    super.dispose();
  }

  bool get _canStartExecution =>
      mounted &&
      !_isExecuting &&
      !_authorizationRecorded &&
      !_smsDispatchAccepted &&
      !_dispatchOutcomeUnknown &&
      !_executionOutcomeUnknown &&
      _currentStatus == RequestState.pendingIoReview;

  Future<void> _confirmExecution() async {
    if (!_canStartExecution) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Execution Authorization'),
          content: const Text(
            'Confirm that this request has been reviewed and is '
            'authorized to proceed through the approved workflow.\n\n'
            'After confirmation, the app may send an SMS from this device only '
            'when approved operator configuration and required permissions exist.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _executeRequest();
  }

  Future<void> _executeRequest() async {
    if (!_canStartExecution) return;

    setState(() {
      _isExecuting = true;
      _errorMessage = null;
      _workflowMessage = 'Recording execution authorization...';
    });

    try {
      final bridge = widget.telephonyBridge;
      if (bridge != null) {
        final permissionGranted = await bridge.checkSmsPermission();
        if (!permissionGranted) {
          final granted = await bridge.requestSmsPermission();
          if (!granted) {
            throw const ApiException(
              statusCode: 403,
              code: 'SMS_PERMISSION_DENIED',
              message: 'SMS permissions were denied by the device or device policy.',
            );
          }
        }
      }

      final execution = await widget.apiService.executeLocationRequest(
        requestId: widget.request.requestId,
        ioDeviceId: widget.ioDeviceId,
        simSlotIndex: widget.simSlotIndex,
      );

      // The backend has accepted execution. From this point, never restart the
      // whole workflow from this screen; retries must not call the SMS bridge again.
      setState(() {
        _authorizationRecorded = true;
        _currentStatus = RequestState.executing;
        _workflowMessage = 'Authorization recorded. Validating approved dispatch instructions...';
      });

      if (bridge == null) {
        setState(() {
          _workflowMessage = 'Execution authorization recorded. No SMS was sent by this screen.';
        });
        return;
      }

      final data = execution['data'];
      if (data is! Map || data['dispatch_instructions'] is! Map) {
        throw const ApiException(
          statusCode: 500,
          code: 'INVALID_DISPATCH_INSTRUCTIONS',
          message: 'The server returned invalid dispatch instructions. Do not retry; reconcile the request status first.',
        );
      }
      final instructions = Map<String, dynamic>.from(data['dispatch_instructions'] as Map);
      final destination = instructions['service_number'] as String? ?? '';
      final message = instructions['sms_body'] as String? ?? '';
      final responseSender = instructions['response_sender'] as String? ?? '';
      if (destination.trim().isEmpty || message.trim().isEmpty || responseSender.trim().isEmpty) {
        throw const ApiException(
          statusCode: 500,
          code: 'INVALID_DISPATCH_INSTRUCTIONS',
          message: 'Approved operator configuration is incomplete. No SMS was sent; the authorized request requires review.',
        );
      }
      _expectedSender = responseSender;

      await _smsSubscription?.cancel();
      _smsSubscription = bridge.onSmsReceived.listen(_handleSmsEvent);

      setState(() {
        // A platform/channel exception can occur after Android accepted the SMS.
        // Treat the outcome as unknown until sendSms returns a definitive result.
        _dispatchOutcomeUnknown = true;
        _workflowMessage = 'Submitting the SMS to Android. Do not retry while the outcome is unknown...';
      });
      final sent = await bridge.sendSms(
        requestId: widget.request.requestId,
        destinationAddress: destination,
        message: message,
        simSlotIndex: widget.simSlotIndex,
      );

      setState(() {
        _dispatchOutcomeUnknown = false;
        _smsDispatchAccepted = sent.success;
        _currentStatus = sent.success
            ? RequestState.waitingResponse
            : RequestState.smsFailed;
        _sendStatusSyncPending = true;
        _pendingSendStatusSuccess = sent.success;
        _pendingDeliveryStatus = sent.deliveryStatus;
        _pendingSendError = sent.errorMessage ?? sent.errorCode;
        _workflowMessage = sent.success
            ? 'Android accepted the SMS for dispatch. This is not proof of carrier delivery or a location result.'
            : 'Android reported that the SMS was not sent. The failure will be recorded; do not restart this request from this screen.';
      });

      // Status synchronization is deliberately separate from SMS dispatch.
      // A synchronization failure must never cause the SMS to be sent again.
      await _synchronizeSendStatus();

      if (sent.success && !_sendStatusSyncPending) {
        final earlyEvent = _earlySmsEvent;
        _earlySmsEvent = null;
        if (earlyEvent != null && mounted) {
          await _handleSmsEvent(earlyEvent);
        }
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      final isTimeout = error.message.toLowerCase().contains('took too long') ||
          error.message.toLowerCase().contains('timed out');
      final uncertainServerOutcome = !_authorizationRecorded && isTimeout;
      setState(() {
        _isExecuting = false;
        if (_dispatchOutcomeUnknown) {
          _errorMessage =
              'SMS dispatch outcome is unknown. Do not retry or resend. Verify the device and request audit state before taking further action.';
          _workflowMessage = null;
        } else if (uncertainServerOutcome) {
          _executionOutcomeUnknown = true;
          _errorMessage =
              'The server outcome could not be confirmed. Do not retry execution until the request state has been verified.';
          _workflowMessage = null;
        } else {
          _errorMessage = _userFacingErrorMessage(error);
          _workflowMessage = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        if (_dispatchOutcomeUnknown) {
          _errorMessage =
              'SMS dispatch outcome is unknown. Do not retry or resend. Verify the device and request audit state before taking further action.';
          _workflowMessage = null;
        } else if (_authorizationRecorded) {
          _errorMessage =
              'Execution authorization was recorded, but dispatch could not be confirmed. Do not restart execution; reconcile the request state.';
          _workflowMessage = null;
        } else {
          _errorMessage =
              'The request could not be completed. Check configuration, permissions, and connection before retrying.';
          _workflowMessage = null;
        }
      });
    } finally {
      if (mounted && _isExecuting) {
        setState(() => _isExecuting = false);
      }
    }
  }

  Future<void> _synchronizeSendStatus() async {
    final success = _pendingSendStatusSuccess;
    if (success == null) return;
    final sendError = _pendingSendError;

    try {
      await widget.apiService.updateSendStatus(
        requestId: widget.request.requestId,
        success: success,
        deliveryStatus: _pendingDeliveryStatus,
        errorMessage: _pendingSendError,
      );
      if (!mounted) return;
      setState(() {
        _sendStatusSyncPending = false;
        _pendingSendStatusSuccess = null;
        _pendingDeliveryStatus = null;
        _pendingSendError = null;
        _errorMessage = null;
        if (success) {
          _workflowMessage =
              'SMS dispatch status was recorded. Waiting for the carrier response; delivery and location are not yet confirmed.';
        } else {
          _errorMessage = sendError ?? 'Android reported that the SMS was not sent.';
          _workflowMessage = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sendStatusSyncPending = true;
        _errorMessage = success
            ? 'Android accepted the SMS, but the backend could not confirm the dispatch status. Do not resend the SMS; use “Retry Status Sync”.'
            : 'Android reported an SMS failure, but the backend could not record it. Do not restart execution; use “Retry Status Sync”.';
        _workflowMessage = null;
      });
    }
  }

  Future<void> _retrySendStatusSync() async {
    if (!_sendStatusSyncPending || _isExecuting || !mounted) return;
    setState(() {
      _isExecuting = true;
      _errorMessage = null;
      _workflowMessage = 'Retrying status synchronization only. No SMS will be sent.';
    });
    try {
      await _synchronizeSendStatus();
      if (!_sendStatusSyncPending && _smsDispatchAccepted) {
        final earlyEvent = _earlySmsEvent;
        _earlySmsEvent = null;
        if (earlyEvent != null && mounted) {
          await _handleSmsEvent(earlyEvent);
        }
      }
    } finally {
      if (mounted) setState(() => _isExecuting = false);
    }
  }

  String _userFacingErrorMessage(ApiException error) {
    switch (error.code) {
      case 'UNAUTHORIZED':
        return 'Your session is not authorized.';
      case 'FORBIDDEN':
        return 'You are not authorized to execute this request.';
      case 'INVALID_STATE_TRANSITION':
        return 'The request is no longer awaiting IO review.';
      case 'SMS_PERMISSION_DENIED':
        return 'SMS permissions were denied by the device or device policy.';
      case 'VALIDATION_ERROR':
        if (error.message.contains('SMS configuration') ||
            error.message.contains('SMS destination') ||
            error.message.contains('SMS template') ||
            error.message.contains('response sender')) {
          return error.message;
        }
        return 'Operator is not approved or currently inactive.';
      case 'NETWORK_ERROR':
        return error.message.isNotEmpty
            ? error.message
            : 'Unable to communicate with the server.';
      default:
        final message = error.message.trim();
        return message.isEmpty
            ? 'Unable to record execution authorization.'
            : message;
    }
  }

  Future<void> _handleSmsEvent(dynamic event) async {
    final bridge = widget.telephonyBridge;
    if (bridge == null || _expectedSender == null || _expectedSender!.trim().isEmpty) {
      return;
    }
    if (!bridge.isCorrelatedResponse(
      event: event,
      expectedSender: _expectedSender!,
      expectedRequestId: widget.request.requestId,
    )) {
      return;
    }
    if (_sendStatusSyncPending) {
      if (_pendingSendStatusSuccess == true) _earlySmsEvent = event;
      return;
    }
    if (_currentStatus != RequestState.waitingResponse) {
      if (_currentStatus == RequestState.executing) _earlySmsEvent = event;
      return;
    }

    try {
      final response = await widget.apiService.submitResult(
        requestId: widget.request.requestId,
        rawSmsContent: event.body as String,
        senderAddress: event.sender as String,
        receivedAt: (event.timestamp as DateTime).toUtc(),
      );
      final responseData = response['data'];
      if (!mounted) return;
      setState(() {
        _rawResponse = event.body as String;
        _responseSender = event.sender as String;
        _responseReceivedAt = (event.timestamp as DateTime).toUtc();
        _responseHash = responseData is Map
            ? responseData['raw_hash_sha256'] as String?
            : null;
        _currentStatus = RequestState.completed;
        _workflowMessage = 'Response received and recorded. Review the raw response before sharing.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'SMS received, but the backend could not confirm that it was recorded. Preserve the message and retry submission.';
      });
    }
  }

  Future<void> _copyResponseForAuthorizedSharing() async {
    final response = _rawResponse;
    if (response == null || response.isEmpty) return;
    final report = 'IFSO Location Request Result\n'
        'Request ID: ${widget.request.requestId}\n'
        'Case ID: ${widget.request.caseId}\n'
        'Operator: ${widget.request.operatorCode}\n'
        'Received at: ${_responseReceivedAt?.toIso8601String() ?? "unknown"}\n'
        'Sender: ${_responseSender ?? "unknown"}\n'
        'SHA-256: ${_responseHash ?? "not returned by backend"}\n'
        'Raw SMS response (unparsed evidence):\n$response';
    final bridge = widget.telephonyBridge;
    if (bridge == null || !await bridge.shareText(report)) {
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) _showMessage('Share chooser unavailable. Result report copied; share only through an approved channel.');
      return;
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

  Widget _buildWorkflowStatus(ThemeData theme) {
    final message = _errorMessage ?? _workflowMessage;
    if ((message == null || message.isEmpty) && !_sendStatusSyncPending) {
      return const SizedBox.shrink();
    }
    final hasError = _errorMessage != null;
    return Card(
      key: const ValueKey('workflow-status-card'),
      color: hasError ? AppColors.errorContainer : AppColors.infoContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null && message.isNotEmpty)
              Row(
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
            if (_sendStatusSyncPending) ...[
              const SizedBox(height: AppSpacing.space2),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isExecuting ? null : _retrySendStatusSync,
                  icon: const Icon(Icons.sync),
                  label: const Text('Retry Status Sync'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final canExecute = _canStartExecution;

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
              if (_rawResponse != null) ...[
                const SizedBox(height: AppSpacing.space4),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Raw SMS Evidence', style: theme.textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.space2),
                        Text('Received: ${_responseReceivedAt?.toIso8601String() ?? "unknown"}'),
                        Text('Sender: ${_responseSender ?? "unknown"}'),
                        if (_responseHash != null)
                          SelectableText('SHA-256: $_responseHash', style: AppTypography.technical),
                        const Divider(),
                        SelectableText(_rawResponse!, style: AppTypography.technical),
                        const SizedBox(height: AppSpacing.space3),
                        OutlinedButton.icon(
                          onPressed: _copyResponseForAuthorizedSharing,
                          icon: const Icon(Icons.copy),
                          label: const Text('Share Result Report'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
                          _smsDispatchAccepted
                              ? Icons.check_circle_outline
                              : _dispatchOutcomeUnknown || _executionOutcomeUnknown
                                  ? Icons.help_outline
                                  : Icons.verified_user_outlined,
                        ),
                  label: Text(
                    _isExecuting
                        ? (_sendStatusSyncPending
                            ? 'Synchronizing Status...'
                            : 'Recording Authorization...')
                        : _smsDispatchAccepted
                            ? 'SMS Dispatch Accepted'
                            : _dispatchOutcomeUnknown || _executionOutcomeUnknown
                                ? 'Outcome Unknown — Verify Before Retry'
                                : _authorizationRecorded
                                    ? 'Authorization Recorded'
                                    : _currentStatus == RequestState.smsFailed
                                        ? 'SMS Dispatch Failed'
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
              _authorizationRecorded
                  ? 'Recorded'
                  : _executionOutcomeUnknown
                      ? 'Outcome unknown — verify before retry'
                      : _isExecuting
                          ? 'In progress'
                          : 'Not recorded',
            ),
            _detailRow(
              'SMS Dispatch Status',
              _dispatchOutcomeUnknown
                  ? 'Outcome unknown — do not resend'
                  : _smsDispatchAccepted
                      ? 'Accepted by Android; carrier delivery not confirmed'
                      : _currentStatus == RequestState.smsFailed
                          ? 'Failed'
                          : _authorizationRecorded
                              ? 'Not confirmed'
                              : 'Not started',
            ),
            _detailRow(
              'Carrier Response Status',
              _rawResponse != null
                  ? 'Received and recorded'
                  : _currentStatus == RequestState.waitingResponse
                      ? 'Waiting for carrier response'
                      : 'Not received',
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
              'It does not send carrier SMS commands without explicit authorization. '
              'Execution uses the authorized Android device/SIM and approved operator configuration. '
              'Raw carrier responses are preserved for review; no location is inferred when the carrier format is unknown.',
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
