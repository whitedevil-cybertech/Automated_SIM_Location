import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ifso_mobile_app/core/constants/request_states.dart';
import 'package:ifso_mobile_app/core/theme/app_theme.dart';
import 'package:ifso_mobile_app/models/location_request.dart';
import 'package:ifso_mobile_app/screens/io_review_screen.dart';
import 'package:ifso_mobile_app/services/api_service.dart';

LocationRequest _buildRequest({
  RequestState status = RequestState.pendingIoReview,
}) {
  return LocationRequest(
    requestId: 'REQ-TEST-001',
    caseId: 'CASE-TEST-001',
    targetPhoneMasked: '+91 XXXXXXX123',
    operatorCode: 'JIO',
    status: status,
    createdAt: DateTime.parse('2026-10-01T10:30:00Z'),
    updatedAt: DateTime.parse('2026-10-01T10:35:00Z'),
    submittingOfficerId: 'OFFICER-001',
    executingIoId: null,
    remarks: 'Test location request',
  );
}

Widget _buildTestApp({
  required LocationRequest request,
  required ApiService apiService,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: IoReviewScreen(
      request: request,
      apiService: apiService,
      ioDeviceId: 'TEST-DEVICE-001',
      simSlotIndex: 0,
    ),
  );
}

ApiService _buildApiService({
  required Future<http.Response> Function(http.Request) handler,
}) {
  return ApiService(
    baseUrl: 'https://test.example/api/v1',
    authToken: 'test-bearer-token',
    client: MockClient(handler),
  );
}

http.Response _successResponse({
  String message = 'Execution authorization recorded.',
}) {
  return http.Response(
    jsonEncode({
      'success': true,
      'message': message,
      'data': {
        'request_id': 'REQ-TEST-001',
        'status': 'EXECUTING',
        'io_device_id': 'TEST-DEVICE-001',
        'sim_slot_index': 0,
      },
      'timestamp': '2026-10-01T10:40:00Z',
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
      'timestamp': '2026-10-01T10:40:00Z',
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

  // Do not call ensureVisible() here.
  // The workflow status widget may not exist when the request fails.
}

void main() {
  group('IoReviewScreen', () {
    testWidgets(
      'renders pending IO review request details',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _successResponse(),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        expect(find.text('IO Request Review'), findsOneWidget);
        expect(find.text('LOCATION REQUEST'), findsOneWidget);
        expect(find.text('REQ-TEST-001'), findsOneWidget);
        expect(find.text('+91 XXXXXXX123'), findsOneWidget);
        expect(find.text('JIO'), findsOneWidget);
        expect(find.text('CASE-TEST-001'), findsOneWidget);
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
        expect(find.text('Request Details'), findsOneWidget);
        expect(find.text('Execution Context'), findsOneWidget);
        expect(
          find.textContaining(
            'Execution uses the authorized Android device/SIM and approved operator configuration.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'displays the created timestamp',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _successResponse(),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        expect(find.text('Created'), findsOneWidget);
        expect(find.textContaining('2026'), findsWidgets);
        expect(find.textContaining('UTC'), findsOneWidget);
      },
    );

    testWidgets(
      'opens confirmation before calling the API',
      (tester) async {
        var requestCount = 0;

        final apiService = _buildApiService(
          handler: (_) async {
            requestCount++;
            return _successResponse();
          },
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _openConfirmationDialog(tester);

        expect(
          find.textContaining(
            'Confirm that this request has been reviewed and is',
          ),
          findsOneWidget,
        );

        expect(
          find.textContaining(
            'After confirmation, the app may send an SMS from this device only',
          ),
          findsOneWidget,
        );

        // Opening the dialog must not submit the request.
        expect(requestCount, 0);
      },
    );

    testWidgets(
      'cancelling confirmation does not call the API',
      (tester) async {
        var requestCount = 0;

        final apiService = _buildApiService(
          handler: (_) async {
            requestCount++;
            return _successResponse();
          },
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(
          find.text('Confirm Execution Authorization'),
          findsNothing,
        );
        expect(requestCount, 0);
        expect(find.text('Authorize Execution'), findsOneWidget);
      },
    );

    testWidgets(
      'confirmation submits the expected authorization API request',
      (tester) async {
        http.Request? capturedRequest;

        final apiService = _buildApiService(
          handler: (request) async {
            capturedRequest = request;
            return _successResponse();
          },
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _confirmAuthorization(tester);

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.method, 'POST');
        expect(
          capturedRequest!.url.toString(),
          'https://test.example/api/v1/requests/REQ-TEST-001/execute',
        );

        expect(
          capturedRequest!.headers['authorization'],
          'Bearer test-bearer-token',
        );

        expect(
          capturedRequest!.headers['content-type'],
          contains('application/json'),
        );

        expect(
          jsonDecode(capturedRequest!.body),
          {
            'io_device_id': 'TEST-DEVICE-001',
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
      },
    );

    testWidgets(
      'shows loading state while authorization is being recorded',
      (tester) async {
        final responseCompleter = Completer<http.Response>();

        final apiService = _buildApiService(
          handler: (_) => responseCompleter.future,
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
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
      },
    );

    testWidgets(
      'prevents duplicate submissions while the request is loading',
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
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Confirm'));
        await tester.pump();

        expect(requestCount, 1);
        expect(
          find.text('Recording Authorization...'),
          findsOneWidget,
        );


        final button = tester.widget<ElevatedButton>(
          find.widgetWithText(
            ElevatedButton,
            'Recording Authorization...',
          ),
        );

        expect(button.onPressed, isNull);

        responseCompleter.complete(_successResponse());

        await tester.pumpAndSettle();

        expect(requestCount, 1);
      },
    );

    testWidgets(
      'displays an error for an unauthorized session',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _errorResponse(
            code: 'UNAUTHORIZED',
            message: 'Authentication required.',
            statusCode: 401,
          ),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _confirmAuthorization(tester);

        expect(
          find.descendant(
            of: find.byKey(const ValueKey('workflow-status-card')),
            matching: find.text('Your session is not authorized.'),
          ),
          findsOneWidget,
        );
        expect(find.text('Authorize Execution'), findsOneWidget);
      },
    );

    testWidgets(
      'displays an error when the user lacks permission',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _errorResponse(
            code: 'FORBIDDEN',
            message: 'Insufficient permissions.',
            statusCode: 403,
          ),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _confirmAuthorization(tester);

        expect(
          find.text(
            'You are not authorized to execute this request.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'displays an error for an invalid request state',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _errorResponse(
            code: 'INVALID_STATE_TRANSITION',
            message: 'Invalid request state.',
            statusCode: 409,
          ),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _confirmAuthorization(tester);

        expect(
          find.text(
            'The request is no longer awaiting IO review.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'displays an error for an inactive operator',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _errorResponse(
            code: 'VALIDATION_ERROR',
            message: 'Operator is not approved or currently inactive.',
            statusCode: 422,
          ),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _confirmAuthorization(tester);

        expect(
          find.text(
            'Operator is not approved or currently inactive.'
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'handles network failures',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async {
            throw const SocketException('Network unavailable');
          },
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _confirmAuthorization(tester);

        expect(
          find.text('Unable to connect to the server.'),
          findsOneWidget,
        );

        expect(find.text('Authorize Execution'), findsOneWidget);
      },
    );

    testWidgets(
      'disables authorization when the request is not pending IO review',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => _successResponse(),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(
              status: RequestState.executing,
            ),
            apiService: apiService,
          ),
        );

        expect(
          find.text(RequestState.executing.label),
          findsOneWidget,
        );


        expect(find.text('Authorize Execution'), findsOneWidget);

        final buttonFinder = find.ancestor(
          of: find.text('Authorize Execution'),
          matching: find.byType(ElevatedButton),
        );

        expect(buttonFinder, findsOneWidget);

        final button = tester.widget<ElevatedButton>(buttonFinder);
        expect(button.onPressed, isNull);

        expect(button.onPressed, isNull);
      },
    );
  });
}