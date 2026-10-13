import 'dart:async';
import 'package:flutter/services.dart';

import '../models/sms_received_event.dart';
import '../models/sms_send_result.dart';

/// Platform bridge connecting Flutter to the native Android telephony subsystem.
///
/// Dispatches SMS through Android's native [SmsManager] and intercepts incoming
/// telecom carrier replies using a broadcast receiver.
class TelephonyBridge {
  TelephonyBridge({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('gov.ifso.location_requests/telephony') {
    _channel.setMethodCallHandler(_handlePlatformMethodCall);
  }

  final MethodChannel _channel;
  final StreamController<SmsReceivedEvent> _smsReceivedController =
      StreamController<SmsReceivedEvent>.broadcast();

  /// Stream of raw incoming SMS messages intercepted by the Android device.
  Stream<SmsReceivedEvent> get onSmsReceived => _smsReceivedController.stream;

  /// Internal platform method handler listening for incoming SMS broadcasts.
  Future<dynamic> _handlePlatformMethodCall(MethodCall call) async {
    if (call.method == 'onSmsReceived') {
      final arguments = call.arguments;
      if (arguments is Map) {
        final event = SmsReceivedEvent.fromMap(Map<dynamic, dynamic>.from(arguments));
        _smsReceivedController.add(event);
      }
    }
    return null;
  }

  /// Check whether the dangerous android.permission.SEND_SMS and RECEIVE_SMS are granted.
  Future<bool> checkSmsPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkSmsPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Request SMS permissions from the user/MDM policy.
  Future<bool> requestSmsPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestSmsPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Dispatch an SMS query from the authorized IO device SIM via SmsManager.
  Future<SmsSendResult> sendSms({
    required String requestId,
    required String destinationAddress,
    required String message,
    int simSlotIndex = 0,
  }) async {
    if (destinationAddress.trim().isEmpty || message.trim().isEmpty) {
      return SmsSendResult.failure(
        errorMessage: 'Destination address and SMS message content are required.',
        errorCode: 'INVALID_ARGUMENTS',
      );
    }

    try {
      final result = await _channel.invokeMethod<dynamic>(
        'sendSms',
        <String, dynamic>{
          'requestId': requestId,
          'destinationAddress': destinationAddress.trim(),
          'message': message,
          'simSlotIndex': simSlotIndex,
        },
      );

      if (result is Map) {
        return SmsSendResult.fromMap(result);
      }

      return SmsSendResult.success();
    } on PlatformException catch (e) {
      return SmsSendResult.failure(
        errorMessage: e.message ?? 'Platform error dispatching SMS.',
        errorCode: e.code,
      );
    } catch (e) {
      return SmsSendResult.failure(
        errorMessage: 'Unexpected error sending SMS: $e',
        errorCode: 'UNEXPECTED_ERROR',
      );
    }
  }

  /// Validate and correlate an incoming SMS event against active request/operator context.
  ///
  /// Prevents blindly accepting unrelated SMS messages (personal messages, spam, etc.).
  bool isCorrelatedResponse({
    required SmsReceivedEvent event,
    required String expectedSender,
    String? expectedRequestId,
  }) {
    if (event.body.trim().isEmpty) {
      return false;
    }

    // Normalize sender representations (e.g. "1512" vs "VK-1512" or "+911512")
    final cleanSender = event.sender.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    final cleanExpected = expectedSender.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();

    final matchesSender = cleanSender == cleanExpected ||
        cleanSender.endsWith(cleanExpected) ||
        cleanExpected.endsWith(cleanSender);

    if (!matchesSender) {
      return false;
    }

    // If an explicit request ID correlation was attached by receiver, verify match
    if (expectedRequestId != null &&
        event.requestId != null &&
        event.requestId != expectedRequestId) {
      return false;
    }

    return true;
  }

  /// Inject synthetic SMS event for automated integration and unit testing.
  void simulateIncomingSmsForTesting(SmsReceivedEvent event) {
    _smsReceivedController.add(event);
  }

  void dispose() {
    _smsReceivedController.close();
  }
}
