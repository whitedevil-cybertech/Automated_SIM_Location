import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifso_mobile_app/models/sms_received_event.dart';
import 'package:ifso_mobile_app/services/telephony_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TelephonyBridge', () {
    late MethodChannel channel;
    late TelephonyBridge bridge;
    final List<MethodCall> log = [];

    setUp(() {
      log.clear();
      channel = const MethodChannel('gov.ifso.location_requests/telephony');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'checkSmsPermission':
            return true;
          case 'requestSmsPermission':
            return true;
          case 'sendSms':
            final args = methodCall.arguments as Map;
            if (args['destinationAddress'] == 'FAIL') {
              return {
                'success': false,
                'errorCode': 'RADIO_OFF',
                'errorMessage': 'Radio is off',
              };
            }
            return {
              'success': true,
              'deliveryStatus': 'SENT',
            };
          default:
            return null;
        }
      });

      bridge = TelephonyBridge(channel: channel);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      bridge.dispose();
    });

    test('checkSmsPermission invokes platform channel and returns boolean', () async {
      final hasPermission = await bridge.checkSmsPermission();
      expect(hasPermission, isTrue);
      expect(log.length, 1);
      expect(log.first.method, 'checkSmsPermission');
    });

    test('requestSmsPermission invokes platform channel and returns boolean', () async {
      final granted = await bridge.requestSmsPermission();
      expect(granted, isTrue);
      expect(log.length, 1);
      expect(log.first.method, 'requestSmsPermission');
    });

    test('sendSms dispatches arguments correctly and parses success', () async {
      final result = await bridge.sendSms(
        requestId: 'REQ-001',
        destinationAddress: '1512',
        message: 'LOC +919876543210',
        simSlotIndex: 0,
      );

      expect(result.success, isTrue);
      expect(result.deliveryStatus, 'SENT');
      expect(log.length, 1);
      expect(log.first.method, 'sendSms');
      final args = log.first.arguments as Map;
      expect(args['requestId'], 'REQ-001');
      expect(args['destinationAddress'], '1512');
      expect(args['message'], 'LOC +919876543210');
      expect(args['simSlotIndex'], 0);
    });

    test('sendSms parses platform failure outcome correctly', () async {
      final result = await bridge.sendSms(
        requestId: 'REQ-002',
        destinationAddress: 'FAIL',
        message: 'LOC +919876543210',
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'RADIO_OFF');
      expect(result.errorMessage, 'Radio is off');
    });

    test('sendSms validates required non-empty arguments before invoking channel', () async {
      final emptyAddress = await bridge.sendSms(
        requestId: 'REQ-003',
        destinationAddress: '   ',
        message: 'LOC',
      );
      expect(emptyAddress.success, isFalse);
      expect(emptyAddress.errorCode, 'INVALID_ARGUMENTS');

      final emptyMessage = await bridge.sendSms(
        requestId: 'REQ-004',
        destinationAddress: '1512',
        message: '',
      );
      expect(emptyMessage.success, isFalse);
      expect(emptyMessage.errorCode, 'INVALID_ARGUMENTS');
      expect(log, isEmpty);
    });

    test('onSmsReceived stream delivers incoming SMS from native broadcast', () async {
      final receivedEvents = <SmsReceivedEvent>[];
      final subscription = bridge.onSmsReceived.listen(receivedEvents.add);

      // Simulate native calling onSmsReceived
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'gov.ifso.location_requests/telephony',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onSmsReceived', {
            'sender': '1512',
            'body': 'Location: LAT:28.6139, LONG:77.2090',
            'timestamp': 1760000000000,
            'requestId': 'REQ-001',
          }),
        ),
        (_) {},
      );

      await pumpEventQueue();

      expect(receivedEvents.length, 1);
      expect(receivedEvents.first.sender, '1512');
      expect(receivedEvents.first.body, 'Location: LAT:28.6139, LONG:77.2090');
      expect(receivedEvents.first.requestId, 'REQ-001');

      await subscription.cancel();
    });

    test('isCorrelatedResponse validates expected sender and rejects unrelated messages', () {
      final matchingDirect = SmsReceivedEvent(
        sender: '1512',
        body: 'Location: LAT:28.6139, LONG:77.2090',
        timestamp: DateTime.now(),
      );
      expect(
        bridge.isCorrelatedResponse(
          event: matchingDirect,
          expectedSender: '1512',
        ),
        isTrue,
      );

      final matchingOperatorPrefix = SmsReceivedEvent(
        sender: 'VK-1512',
        body: 'Location: LAT:28.6139, LONG:77.2090',
        timestamp: DateTime.now(),
      );
      expect(
        bridge.isCorrelatedResponse(
          event: matchingOperatorPrefix,
          expectedSender: '1512',
        ),
        isTrue,
      );

      final unrelatedSpam = SmsReceivedEvent(
        sender: '+919999999999',
        body: 'Your account balance is 0',
        timestamp: DateTime.now(),
      );
      expect(
        bridge.isCorrelatedResponse(
          event: unrelatedSpam,
          expectedSender: '1512',
        ),
        isFalse,
      );

      final emptyBody = SmsReceivedEvent(
        sender: '1512',
        body: '',
        timestamp: DateTime.now(),
      );
      expect(
        bridge.isCorrelatedResponse(
          event: emptyBody,
          expectedSender: '1512',
        ),
        isFalse,
      );
    });
  });
}
