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

Future<void> _openConfirmationDialog(WidgetTester tester) async {
  final executeButton = find.text('Execute Location Request');

  await tester.scrollUntilVisible(
    executeButton,
    500,
    scrollable: find.byType(Scrollable),
  );

  expect(executeButton, findsOneWidget);

  await tester.tap(executeButton);
  await tester.pumpAndSettle();

  expect(find.text('Confirm Location Request'), findsOneWidget);
  expect(find.text('Confirm Execution'), findsOneWidget);
  expect(find.text('Cancel'), findsOneWidget);
}

void main() {
  group('IoReviewScreen', () {
    testWidgets(
      'renders pending IO review request details',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => http.Response(
            jsonEncode({
              'success': true,
              'message': 'Execution authorized.',
              'data': {},
              'timestamp': '2026-10-01T10:40:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

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
           find.text('Execute Location Request'),
           500,
           scrollable: find.byType(Scrollable),
        );

        expect(find.text('Execute Location Request'), findsOneWidget);
      },
    );

    testWidgets(
      'displays created timestamp',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => http.Response(
            jsonEncode({
              'success': true,
              'data': {},
              'timestamp': '2026-10-01T10:40:00Z',
            }),
            200,
          ),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        expect(find.textContaining('Created'), findsOneWidget);
        expect(find.textContaining('2026'), findsWidgets);
      },
    );

    testWidgets(
      'opens explicit confirmation dialog before execution',
      (tester) async {
        var requestCount = 0;

        final apiService = _buildApiService(
          handler: (_) async {
            requestCount++;
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {},
                'timestamp': '2026-10-01T10:40:00Z',
              }),
              200,
            );
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
            'Executing this request will authorize the location workflow',
            ),
            findsOneWidget,
        );

        // Opening the dialog must not execute the request.
        expect(requestCount, 0);
      },
    );

    testWidgets(
      'canceling confirmation does not call API',
      (tester) async {
        var requestCount = 0;

        final apiService = _buildApiService(
          handler: (_) async {
            requestCount++;
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {},
                'timestamp': '2026-10-01T10:40:00Z',
              }),
              200,
            );
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

        expect(find.text('Confirm Location Request'), findsNothing);
        expect(requestCount, 0);
        expect(find.text('Execute Location Request'), findsOneWidget);
      },
    );

    testWidgets(
      'confirming execution calls correct API and shows success',
      (tester) async {
        http.Request? capturedRequest;

        final apiService = _buildApiService(
          handler: (request) async {
            capturedRequest = request;

            return http.Response(
              jsonEncode({
                'success': true,
                'message':
                    'Execution authorized and recorded. Backend did not dispatch SMS; Android device execution boundary remains enforced.',
                'data': {
                  'request_id': 'REQ-TEST-001',
                  'status': 'EXECUTING',
                  'executing_io_id': 'IO-001',
                  'io_device_id': 'TEST-DEVICE-001',
                  'sim_slot_index': 0,
                  'dispatched_at': '2026-10-01T10:40:00Z',
                },
                'timestamp': '2026-10-01T10:40:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          },
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Confirm Execution'));
        await tester.pumpAndSettle();

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

        expect(find.text('Execution Authorized'), findsOneWidget);
      },
    );

    testWidgets(
      'shows loading state while execution is in progress',
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

        await tester.tap(find.text('Confirm Execution'));
        await tester.pump();

        expect(find.text('Executing...'), findsOneWidget);
        expect(find.text('Execution Authorized'), findsNothing);

        responseCompleter.complete(
          http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'request_id': 'REQ-TEST-001',
                'status': 'EXECUTING',
              },
              'timestamp': '2026-10-01T10:40:00Z',
            }),
            200,
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Execution Authorized'), findsOneWidget);
        expect(find.text('Executing...'), findsNothing);
      },
    );

    testWidgets(
      'prevents duplicate execution while request is loading',
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

        await tester.tap(find.text('Confirm Execution'));
        await tester.pump();

        expect(requestCount, 1);
        expect(find.text('Executing...'), findsOneWidget);

        // The button is disabled while execution is active.
        final button = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Executing...'),
        );

        expect(button.onPressed, isNull);

        responseCompleter.complete(
          http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'request_id': 'REQ-TEST-001',
                'status': 'EXECUTING',
              },
              'timestamp': '2026-10-01T10:40:00Z',
            }),
            200,
          ),
        );

        await tester.pumpAndSettle();

        expect(requestCount, 1);
      },
    );

    testWidgets(
      'handles 401 unauthorized response',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'code': 'UNAUTHORIZED',
                'message': 'Authentication required.',
                'details': {},
              },
              'timestamp': '2026-10-01T10:40:00Z',
            }),
            401,
          ),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Confirm Execution'));
        await tester.pumpAndSettle();

        expect(
          find.text('Your session is not authorized.'),
          findsOneWidget,
        );

        expect(find.text('Execute Location Request'), findsOneWidget);
      },
    );

    testWidgets(
      'handles 403 forbidden response',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'code': 'FORBIDDEN',
                'message': 'Insufficient permissions.',
                'details': {},
              },
              'timestamp': '2026-10-01T10:40:00Z',
            }),
            403,
          ),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Confirm Execution'));
        await tester.pumpAndSettle();

        expect(
          find.text('You are not authorized to execute this request.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'handles invalid request state response',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'code': 'INVALID_STATE_TRANSITION',
                'message': 'Invalid request state.',
                'details': {},
              },
              'timestamp': '2026-10-01T10:40:00Z',
            }),
            409,
          ),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Confirm Execution'));
        await tester.pumpAndSettle();

        expect(
          find.text('The request is no longer awaiting IO review.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'handles inactive operator response',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'code': 'VALIDATION_ERROR',
                'message': 'Operator is not approved or currently inactive.',
                'details': {
                  'field': 'operator_code',
                  'operator_code': 'JIO',
                },
              },
              'timestamp': '2026-10-01T10:40:00Z',
            }),
            422,
          ),
        );

        await tester.pumpWidget(
          _buildTestApp(
            request: _buildRequest(),
            apiService: apiService,
          ),
        );

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Confirm Execution'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'The selected operator is not approved or is currently inactive.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'handles network failure',
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

        await _openConfirmationDialog(tester);

        await tester.tap(find.text('Confirm Execution'));
        await tester.pumpAndSettle();

        expect(
          find.text('Unable to connect to the server.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'does not allow execution when request is not pending IO review',
      (tester) async {
        final apiService = _buildApiService(
          handler: (_) async => http.Response(
            jsonEncode({
              'success': true,
              'data': {},
              'timestamp': '2026-10-01T10:40:00Z',
            }),
            200,
          ),
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
        await tester.scrollUntilVisible(
            find.text('Execute Location Request'),
            500,
            scrollable: find.byType(Scrollable),
        );

        expect(find.text('Execute Location Request'), findsOneWidget);

        final button = tester.widget<ElevatedButton>(
           find.widgetWithText(
           ElevatedButton,
           'Execute Location Request',
           ),
        );

        expect(button.onPressed, isNull);
      },
    );
  });
}