import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.isNetworkError = false,
  });

  const ApiException.network({
    required this.message,
  })  : statusCode = 0,
        code = 'NETWORK_ERROR',
        isNetworkError = true;

  final int statusCode;
  final String code;
  final String message;
  final bool isNetworkError;

  @override
  String toString() => message;
}

class ApiService {
  ApiService({
    required this.baseUrl,
    http.Client? client,
    this.authToken,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String? authToken;
  final http.Client _client;

  Future<Map<String, dynamic>> executeLocationRequest({
    required String requestId,
    required String ioDeviceId,
    required int simSlotIndex,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/requests/$requestId/execute',
    );

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final token = authToken;

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;

    try {
      response = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode({
              'io_device_id': ioDeviceId,
              'sim_slot_index': simSlotIndex,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ApiException.network(
        message: 'The server took too long to respond.',
      );
    } on SocketException {
      throw const ApiException.network(
        message: 'Unable to connect to the server.',
      );
    } on http.ClientException {
      throw const ApiException.network(
        message: 'Unable to communicate with the server.',
      );
    }

    final body = _decodeResponse(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        code: _extractErrorCode(body),
        message: _safeErrorMessage(
          response.statusCode,
          body,
        ),
      );
    }

    if (body == null) {
      throw const ApiException(
        statusCode: 500,
        code: 'INVALID_RESPONSE',
        message: 'The server returned an invalid response.',
      );
    }

    if (body['success'] != true) {
      throw ApiException(
        statusCode: response.statusCode,
        code: _extractErrorCode(body),
        message: _safeErrorMessage(
          response.statusCode,
          body,
        ),
      );
    }

    return body;
  }

  Map<String, dynamic>? _decodeResponse(String responseBody) {
    if (responseBody.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(responseBody);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      return null;
    }

    return null;
  }

  String _extractErrorCode(Map<String, dynamic>? body) {
    final error = body?['error'];

    if (error is Map<String, dynamic>) {
      final code = error['code'];

      if (code is String && code.isNotEmpty) {
        return code;
      }
    }

    return 'HTTP_ERROR';
  }

  String _safeErrorMessage(
    int statusCode,
    Map<String, dynamic>? body,
  ) {
    final error = body?['error'];

    final backendCode = error is Map<String, dynamic>
        ? error['code']
        : null;

    switch (backendCode) {
      case 'UNAUTHORIZED':
        return 'Your session is not authorized.';

      case 'FORBIDDEN':
        return 'You are not authorized to execute this request.';

      case 'RESOURCE_NOT_FOUND':
      case 'NOT_FOUND':
        return 'The location request could not be found.';

      case 'INVALID_STATE_TRANSITION':
        return 'The request is no longer awaiting IO review.';

      case 'VALIDATION_ERROR':
        if (_isOperatorInactive(body)) {
          return 'The selected operator is not approved or is currently inactive.';
        }

        return 'The request could not be validated.';

      case 'REQUEST_VALIDATION_FAILED':
        return 'The submitted execution request is invalid.';

      case 'DATABASE_UNAVAILABLE':
      case 'SERVICE_UNAVAILABLE':
        return 'The service is temporarily unavailable.';

      case 'INTERNAL_SERVER_ERROR':
        return 'The server encountered an unexpected error.';

      default:
        break;
    }

    switch (statusCode) {
      case 401:
        return 'Your session is not authorized.';

      case 403:
        return 'You are not authorized to execute this request.';

      case 404:
        return 'The location request could not be found.';

      case 409:
        return 'The request is no longer awaiting IO review.';

      case 422:
        return 'The execution request is invalid.';

      case 503:
        return 'The service is temporarily unavailable.';

      default:
        return 'The location request could not be executed.';
    }
  }

  bool _isOperatorInactive(Map<String, dynamic>? body) {
    final error = body?['error'];

    if (error is! Map<String, dynamic>) {
      return false;
    }

    if (error['code'] != 'VALIDATION_ERROR') {
      return false;
    }

    final details = error['details'];

    if (details is! Map<String, dynamic>) {
      return false;
    }

    return details['field'] == 'operator_code';
  }

  void dispose() {
    _client.close();
  }
}