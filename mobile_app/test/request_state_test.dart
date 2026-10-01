import 'package:flutter_test/flutter_test.dart';
import 'package:ifso_mobile_app/core/constants/request_states.dart';
import 'package:ifso_mobile_app/core/theme/color_schemes.dart';

void main() {
  group('RequestState Enum Verification', () {
    test('All 8 architecture lifecycle states are defined', () {
      final values = RequestState.values.map((s) => s.value).toSet();
      expect(values, {
        'CREATED',
        'PENDING_IO_REVIEW',
        'EXECUTING',
        'WAITING_RESPONSE',
        'COMPLETED',
        'SMS_FAILED',
        'TIMEOUT',
        'RESPONSE_INVALID',
      });
    });

    test('fromString parses correctly with case insensitivity', () {
      expect(RequestState.fromString('created'), RequestState.created);
      expect(RequestState.fromString('PENDING_IO_REVIEW'), RequestState.pendingIoReview);
      expect(RequestState.fromString('executing'), RequestState.executing);
      expect(RequestState.fromString('COMPLETED'), RequestState.completed);
      expect(RequestState.fromString('UNKNOWN_STATE'), RequestState.created);
    });

    test('Terminal states are accurately identified', () {
      expect(RequestState.created.isTerminal, isFalse);
      expect(RequestState.pendingIoReview.isTerminal, isFalse);
      expect(RequestState.executing.isTerminal, isFalse);
      expect(RequestState.waitingResponse.isTerminal, isFalse);

      expect(RequestState.completed.isTerminal, isTrue);
      expect(RequestState.smsFailed.isTerminal, isTrue);
      expect(RequestState.timeout.isTerminal, isTrue);
      expect(RequestState.responseInvalid.isTerminal, isTrue);
    });

    test('Accessible labels and colors are properly assigned', () {
      expect(RequestState.completed.label, 'Completed');
      expect(RequestState.completed.color, AppColors.success);

      expect(RequestState.smsFailed.label, 'SMS Failed');
      expect(RequestState.smsFailed.color, AppColors.error);

      expect(RequestState.pendingIoReview.color, AppColors.warning);
      expect(RequestState.created.color, AppColors.info);
    });
  });
}
