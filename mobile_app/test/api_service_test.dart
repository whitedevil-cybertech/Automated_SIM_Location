import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ifso_mobile_app/services/api_service.dart';

void main() {
  group('ApiService.executeLocationRequest', () {
    test('sends correct endpoint, headers, and request body', () async {
      late http.Request capturedRequest;

      final client = MockClient((request) async {
        capturedRequest = request;

        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Execution authorized and recorded.',
            'data': {
              'request_id': 'REQ-TEST-001',
              'status': 'EXECUTING',
            },
          }),
          200,
          headers: {
            'content-type': 'application/json',
          },
        );
      });

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        authToken: 'test-bearer-token',
        client: client,
      );

      final response = await apiService.executeLocationRequest(
        requestId: 'REQ-TEST-001',
        ioDeviceId: 'TEST-DEVICE-001',
        simSlotIndex: 0,
      );

      expect(
        capturedRequest.url.toString(),
        'http://127.0.0.1:8000/api/v1/requests/REQ-TEST-001/execute',
      );

      expect(capturedRequest.method, 'POST');

      expect(
        capturedRequest.headers['authorization'],
        'Bearer test-bearer-token',
      );

      expect(
        capturedRequest.headers['content-type'],
        contains('application/json'),
      );

      expect(
        jsonDecode(capturedRequest.body),
        {
          'io_device_id': 'TEST-DEVICE-001',
          'sim_slot_index': 0,
        },
      );

      expect(response['success'], true);
    });

    test('accepts a successful execution response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Execution authorized and recorded.',
            'data': {
              'request_id': 'REQ-TEST-002',
              'status': 'EXECUTING',
            },
          }),
          200,
          headers: {
            'content-type': 'application/json',
          },
        );
      });

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        authToken: 'test-token',
        client: client,
      );

      final response = await apiService.executeLocationRequest(
        requestId: 'REQ-TEST-002',
        ioDeviceId: 'DEVICE-002',
        simSlotIndex: 0,
      );

      expect(response['success'], true);
      expect(
        (response['data'] as Map<String, dynamic>)['status'],
        'EXECUTING',
      );
    });

    test('handles 401 unauthorized response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'UNAUTHORIZED',
              'message': 'Authentication credentials were not provided.',
              'details': {},
            },
          }),
          401,
        );
      });

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        authToken: 'invalid-token',
        client: client,
      );

      expect(
        () => apiService.executeLocationRequest(
          requestId: 'REQ-401',
          ioDeviceId: 'DEVICE-401',
          simSlotIndex: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                401,
              )
              .having(
                (error) => error.code,
                'code',
                'UNAUTHORIZED',
              )
              .having(
                (error) => error.message,
                'message',
                'Your session is not authorized.',
              ),
        ),
      );
    });

    test('handles 403 forbidden response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'FORBIDDEN',
              'message': 'Caller is not authorized for this operation.',
              'details': {},
            },
          }),
          403,
        );
      });

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        authToken: 'officer-token',
        client: client,
      );

      expect(
        () => apiService.executeLocationRequest(
          requestId: 'REQ-403',
          ioDeviceId: 'DEVICE-403',
          simSlotIndex: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                403,
              )
              .having(
                (error) => error.code,
                'code',
                'FORBIDDEN',
              )
              .having(
                (error) => error.message,
                'message',
                'You are not authorized to execute this request.',
              ),
        ),
      );
    });

    test('handles invalid request state with 409 response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'INVALID_STATE_TRANSITION',
              'message':
                  "Invalid request transition from 'EXECUTING' to 'EXECUTING'.",
              'details': {
                'current_state': 'EXECUTING',
                'target_state': 'EXECUTING',
              },
            },
          }),
          409,
        );
      });

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        authToken: 'io-token',
        client: client,
      );

      expect(
        () => apiService.executeLocationRequest(
          requestId: 'REQ-409',
          ioDeviceId: 'DEVICE-409',
          simSlotIndex: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                409,
              )
              .having(
                (error) => error.code,
                'code',
                'INVALID_STATE_TRANSITION',
              )
              .having(
                (error) => error.message,
                'message',
                'The request is no longer awaiting IO review.',
              ),
        ),
      );
    });

    test('handles inactive operator validation error', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'VALIDATION_ERROR',
              'message':
                  'Operator is not approved or currently inactive.',
              'details': {
                'operator_code': 'JIO',
                'field': 'operator_code',
              },
            },
          }),
          422,
        );
      });

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        authToken: 'io-token',
        client: client,
      );

      expect(
        () => apiService.executeLocationRequest(
          requestId: 'REQ-INACTIVE',
          ioDeviceId: 'DEVICE-INACTIVE',
          simSlotIndex: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                422,
              )
              .having(
                (error) => error.code,
                'code',
                'VALIDATION_ERROR',
              )
              .having(
                (error) => error.message,
                'message',
                'The selected operator is not approved or is currently inactive.',
              ),
        ),
      );
    });

    test('handles generic 422 validation error', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'REQUEST_VALIDATION_FAILED',
              'message':
                  'The submitted request body or parameters failed validation.',
              'details': {},
            },
          }),
          422,
        );
      });

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        authToken: 'io-token',
        client: client,
      );

      expect(
        () => apiService.executeLocationRequest(
          requestId: 'REQ-422',
          ioDeviceId: 'DEVICE-422',
          simSlotIndex: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                422,
              )
              .having(
                (error) => error.code,
                'code',
                'REQUEST_VALIDATION_FAILED',
              ),
        ),
      );
    });

    test('handles 503 service unavailable response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'SERVICE_UNAVAILABLE',
              'message': 'The service is temporarily unavailable.',
              'details': {},
            },
          }),
          503,
        );
      });

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        authToken: 'io-token',
        client: client,
      );

      expect(
        () => apiService.executeLocationRequest(
          requestId: 'REQ-503',
          ioDeviceId: 'DEVICE-503',
          simSlotIndex: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                503,
              )
              .having(
                (error) => error.code,
                'code',
                'SERVICE_UNAVAILABLE',
              ),
        ),
      );
    });

    test('handles unexpected server error', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'INTERNAL_SERVER_ERROR',
              'message': 'An unexpected server error occurred.',
              'details': {},
            },
          }),
          500,
        );
      });

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        authToken: 'io-token',
        client: client,
      );

      expect(
        () => apiService.executeLocationRequest(
          requestId: 'REQ-500',
          ioDeviceId: 'DEVICE-500',
          simSlotIndex: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                500,
              )
              .having(
                (error) => error.code,
                'code',
                'INTERNAL_SERVER_ERROR',
              ),
        ),
      );
    });

    test('handles network failure', () async {
      final client = MockClient((request) async {
        throw const SocketException('Connection refused');
      });

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8000/api/v1',
        authToken: 'io-token',
        client: client,
      );

      expect(
        () => apiService.executeLocationRequest(
          requestId: 'REQ-NETWORK',
          ioDeviceId: 'DEVICE-NETWORK',
          simSlotIndex: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (error) => error.isNetworkError,
                'isNetworkError',
                true,
              )
              .having(
                (error) => error.code,
                'code',
                'NETWORK_ERROR',
              )
              .having(
                (error) => error.message,
                'message',
                'Unable to connect to the server.',
              ),
        ),
      );
    });
  });
}