import 'package:flutter/material.dart';
import '../theme/color_schemes.dart';

/// Request lifecycle states matching project architecture.
/// Status is strictly communicated with both icon/label and color per WCAG 2.2 AA.
enum RequestState {
  created('CREATED'),
  pendingIoReview('PENDING_IO_REVIEW'),
  executing('EXECUTING'),
  waitingResponse('WAITING_RESPONSE'),
  completed('COMPLETED'),
  smsFailed('SMS_FAILED'),
  timeout('TIMEOUT'),
  responseInvalid('RESPONSE_INVALID');

  final String value;
  const RequestState(this.value);

  static RequestState fromString(String raw) {
    return RequestState.values.firstWhere(
      (s) => s.value == raw.toUpperCase().trim(),
      orElse: () => RequestState.created,
    );
  }

  String get label {
    switch (this) {
      case RequestState.created:
        return 'Created';
      case RequestState.pendingIoReview:
        return 'Pending IO Review';
      case RequestState.executing:
        return 'Executing';
      case RequestState.waitingResponse:
        return 'Waiting Response';
      case RequestState.completed:
        return 'Completed';
      case RequestState.smsFailed:
        return 'SMS Failed';
      case RequestState.timeout:
        return 'Timeout';
      case RequestState.responseInvalid:
        return 'Response Invalid';
    }
  }

  Color get color {
    switch (this) {
      case RequestState.created:
        return AppColors.info;
      case RequestState.pendingIoReview:
      case RequestState.executing:
      case RequestState.waitingResponse:
        return AppColors.warning;
      case RequestState.completed:
        return AppColors.success;
      case RequestState.smsFailed:
      case RequestState.timeout:
      case RequestState.responseInvalid:
        return AppColors.error;
    }
  }

  Color get containerColor {
    switch (this) {
      case RequestState.created:
        return AppColors.infoContainer;
      case RequestState.pendingIoReview:
      case RequestState.executing:
      case RequestState.waitingResponse:
        return AppColors.warningContainer;
      case RequestState.completed:
        return AppColors.successContainer;
      case RequestState.smsFailed:
      case RequestState.timeout:
      case RequestState.responseInvalid:
        return AppColors.errorContainer;
    }
  }

  IconData get icon {
    switch (this) {
      case RequestState.created:
        return Icons.note_add_outlined;
      case RequestState.pendingIoReview:
        return Icons.pending_actions_outlined;
      case RequestState.executing:
        return Icons.send_outlined;
      case RequestState.waitingResponse:
        return Icons.hourglass_top_outlined;
      case RequestState.completed:
        return Icons.check_circle_outline;
      case RequestState.smsFailed:
        return Icons.sms_failed_outlined;
      case RequestState.timeout:
        return Icons.timer_off_outlined;
      case RequestState.responseInvalid:
        return Icons.error_outline;
    }
  }

  bool get isTerminal {
    return this == RequestState.completed ||
        this == RequestState.smsFailed ||
        this == RequestState.timeout ||
        this == RequestState.responseInvalid;
  }
}
