import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ifso_mobile_app/core/constants/request_states.dart';
import 'package:ifso_mobile_app/core/theme/app_theme.dart';
import 'package:ifso_mobile_app/models/location_request.dart';
import 'package:ifso_mobile_app/screens/io_review_screen.dart';
import 'package:ifso_mobile_app/services/api_service.dart';

LocationRequest _buildPendingRequest() {
  return LocationRequest(
    requestId: 'REQ-PHASE3-001',
    caseId: 'FIR-2026-DEL-101',
    targetPhoneMasked: '+91 XXXXXXX210',
    operatorCode: 'JIO',
    status: RequestState.pendingIoReview,
    createdAt: DateTime.parse('2026-10-08T08:00:00Z'),
    updatedAt: DateTime.parse('2026-10-08T08:05:00Z'),
    submittingOfficerId: 'OFFICER-001',
    executingIoId: null,
    remarks: 'Phase 3 authorization test request',
  );
}

ApiService _buildApiService({
  required Future<http.Response> Function(http.Request) handler,
}) {
  return ApiService(
    baseUrl: 'http://testserver/api/v1',
    authToken: 'dev-io-token',
    client: MockClient(handler),
  );
}

http.Response _successResponse() {
  return http.Response(
    jsonEncode({
      'success': true,
      'message': 'Execution authorization recorded.',
      'data': {
        'request_id': 'REQ-PHASE3-001',
        'status': 'EXECUTING',
        'io_device_id': 'MDM-TEST-DEVICE',
        'sim_slot_index': 0,
      },
      'timestamp': '2026-10-08T08:10:00Z',
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _errorResponse({
  required String code,
  required String message,
  required int statusCode,
}) {
  return http.Response(
    jsonEncode({
      'success': false,
      'error': {
        'code': code,
        'message': message,
        'details': <String, dynamic>{},
      },
      'timestamp': '2026-10-08T08:10:00Z',
    }),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Future<void> _openConfirmationDialog(WidgetTester tester) async {
  final authorizeButton = find.text('Authorize Execution');

  await tester.scrollUntilVisible(
    authorizeButton,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();

  expect(authorizeButton, findsOneWidget);

  await tester.tap(authorizeButton);
  await tester.pumpAndSettle();

  expect(find.text('Confirm Execution Authorization'), findsOneWidget);
  expect(find.text('Confirm'), findsOneWidget);
  expect(find.text('Cancel'), findsOneWidget);
}

Future<void> _confirmAuthorization(WidgetTester tester) async {
  await _openConfirmationDialog(tester);

  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();

  await tester.ensureVisible(
    find.byKey(const ValueKey('workflow-status-message')),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 Authorization Workflow', () {
    late MethodChannel telephonyChannel;
    late List<MethodCall> nativeCalls;

    setUp(() {
      nativeCalls = [];

      telephonyChannel = const MethodChannel(
        'gov.ifso.location_requests/telephony',
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        telephonyChannel,
        (MethodCall call) async {
          nativeCalls.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        telephonyChannel,
        null,
      );
    });

    testWidgets(
      'renders a pending request and authorization-only notice',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _successResponse(),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: IoReviewScreen(
              request: _buildPendingRequest(),
              apiService: apiService,
              ioDeviceId: 'MDM-TEST-DEVICE',
              simSlotIndex: 0,
            ),
          ),
        );

        expect(find.text('IO Request Review'), findsOneWidget);
        expect(find.text('REQ-PHASE3-001'), findsOneWidget);
        expect(
          find.text(RequestState.pendingIoReview.label),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Authorize Execution'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.text('Authorize Execution'), findsOneWidget);

        expect(
          find.textContaining(
            'It does not send carrier SMS commands',
          ),
          findsOneWidget,
        );

        expect(nativeCalls, isEmpty);
      },
    );

    testWidgets(
      'records authorization after explicit confirmation',
      (tester) async {
        final requestedPaths = <String>[];
        http.Request? capturedRequest;

        final apiService = _buildApiService(
          handler: (request) async {
            requestedPaths.add(request.url.path);
            capturedRequest = request;
            return _successResponse();
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: IoReviewScreen(
              request: _buildPendingRequest(),
              apiService: apiService,
              ioDeviceId: 'MDM-TEST-DEVICE',
              simSlotIndex: 0,
            ),
          ),
        );

        await _openConfirmationDialog(tester);

        // Merely opening the confirmation dialog must not call the API.
        expect(requestedPaths, isEmpty);

        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();

        expect(
          requestedPaths,
          contains('/api/v1/requests/REQ-PHASE3-001/execute'),
        );

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.method, 'POST');

        expect(
          capturedRequest!.headers['authorization'],
          'Bearer dev-io-token',
        );

        expect(
          jsonDecode(capturedRequest!.body),
          {
            'io_device_id': 'MDM-TEST-DEVICE',
            'sim_slot_index': 0,
          },
        );

        expect(
          find.text('Authorization Recorded'),
          findsOneWidget,
        );

        expect(
          find.textContaining(
            'No SMS was sent by this screen.',
          ),
          findsOneWidget,
        );

        // The authorization screen must not invoke native telephony.
        expect(nativeCalls, isEmpty);
      },
    );

    testWidgets(
      'cancelling authorization does not call the API',
      (tester) async {
        var requestCount = 0;

        final apiService = _buildApiService(
          handler: (_) async {
            requestCount++;
            return _successResponse();
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: IoReviewScreen(
              request: _buildPendingRequest(),
              apiService: apiService,
              ioDeviceId: 'MDM-TEST-DEVICE',
              simSlotIndex: 0,
            ),
          ),
        );

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(requestCount, 0);
        expect(
          find.text('Confirm Execution Authorization'),
          findsNothing,
        );
        expect(find.text('Authorize Execution'), findsOneWidget);
        expect(nativeCalls, isEmpty);
      },
    );

    testWidgets(
      'shows a loading state while authorization is pending',
      (tester) async {
        final responseCompleter = Completer<http.Response>();

        final apiService = _buildApiService(
          handler: (_) => responseCompleter.future,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: IoReviewScreen(
              request: _buildPendingRequest(),
              apiService: apiService,
              ioDeviceId: 'MDM-TEST-DEVICE',
              simSlotIndex: 0,
            ),
          ),
        );

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Confirm'));
        await tester.pump();

        expect(
          find.text('Recording Authorization...'),
          findsOneWidget,
        );
        expect(find.text('Authorization Recorded'), findsNothing);
        expect(nativeCalls, isEmpty);

        responseCompleter.complete(_successResponse());

        await tester.pumpAndSettle();

        expect(
          find.text('Authorization Recorded'),
          findsOneWidget,
        );
        expect(
          find.text('Recording Authorization...'),
          findsNothing,
        );
        expect(nativeCalls, isEmpty);
      },
    );

    testWidgets(
      'prevents duplicate submissions while authorization is pending',
      (tester) async {
        final responseCompleter = Completer<http.Response>();
        var requestCount = 0;

        final apiService = _buildApiService(
          handler: (_) {
            requestCount++;
            return responseCompleter.future;
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: IoReviewScreen(
              request: _buildPendingRequest(),
              apiService: apiService,
              ioDeviceId: 'MDM-TEST-DEVICE',
              simSlotIndex: 0,
            ),
          ),
        );

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Confirm'));
        await tester.pump();

        expect(requestCount, 1);

        final button = tester.widget<ElevatedButton>(
          find.widgetWithText(
            ElevatedButton,
            'Recording Authorization...',
          ),
        );

        expect(button.onPressed, isNull);
        expect(nativeCalls, isEmpty);

        responseCompleter.complete(_successResponse());

        await tester.pumpAndSettle();

        expect(requestCount, 1);
      },
    );

    testWidgets(
      'displays an authorization error for a forbidden response',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _errorResponse(
            code: 'FORBIDDEN',
            message: 'Insufficient permissions.',
            statusCode: 403,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: IoReviewScreen(
              request: _buildPendingRequest(),
              apiService: apiService,
              ioDeviceId: 'MDM-TEST-DEVICE',
              simSlotIndex: 0,
            ),
          ),
        );

        await _confirmAuthorization(tester);

        expect(
          find.text(
            'You are not authorized to execute this request.',
          ),
          findsOneWidget,
        );

        expect(find.text('Authorize Execution'), findsOneWidget);
        expect(nativeCalls, isEmpty);
      },
    );

    testWidgets(
      'displays an error when the request state is invalid',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _errorResponse(
            code: 'INVALID_STATE_TRANSITION',
            message: 'Invalid request state.',
            statusCode: 409,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: IoReviewScreen(
              request: _buildPendingRequest(),
              apiService: apiService,
              ioDeviceId: 'MDM-TEST-DEVICE',
              simSlotIndex: 0,
            ),
          ),
        );

        await _confirmAuthorization(tester);

        expect(
          find.text(
            'The request is no longer awaiting IO review.',
          ),
          findsOneWidget,
        );

        expect(nativeCalls, isEmpty);
      },
    );

    testWidgets(
      'disables authorization for a request outside pending IO review',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _successResponse(),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: IoReviewScreen(
              request: LocationRequest(
                requestId: 'REQ-PHASE3-001',
                caseId: 'FIR-2026-DEL-101',
                targetPhoneMasked: '+91 XXXXXXX210',
                operatorCode: 'JIO',
                status: RequestState.executing,
                createdAt: DateTime.parse('2026-10-08T08:00:00Z'),
                updatedAt: DateTime.parse('2026-10-08T08:05:00Z'),
                submittingOfficerId: 'OFFICER-001',
                executingIoId: 'IO-001',
                remarks: 'Already authorized',
              ),
              apiService: apiService,
              ioDeviceId: 'MDM-TEST-DEVICE',
              simSlotIndex: 0,
            ),
          ),
        );

        expect(
          find.text(RequestState.executing.label),
          findsOneWidget,
        );

        final buttonFinder = find.ancestor(
          of: find.text('Authorize Execution'),
          matching: find.byType(ElevatedButton),
        );

        expect(buttonFinder, findsOneWidget);

        final button = tester.widget<ElevatedButton>(buttonFinder);
        expect(button.onPressed, isNull);

        expect(button.onPressed, isNull);
        expect(nativeCalls, isEmpty);
      },
    );
  });
}
