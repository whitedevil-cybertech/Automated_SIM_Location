import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/location_request.dart';

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

  Uri _buildUri(String path) {
    final normalizedBaseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final normalizedPath = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$normalizedBaseUrl/$normalizedPath');
  }

  /// Returns the role resolved by the backend from the authenticated session.
  /// The client must not choose or infer its own authorization role.
  Future<Map<String, dynamic>> getCurrentPrincipal() async {
    final uri = _buildUri('/auth/me');
    final headers = <String, String>{'Accept': 'application/json'};
    final token = authToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ApiException.network(message: 'The server took too long to authenticate the session.');
    } on SocketException {
      throw const ApiException.network(message: 'Unable to connect to the authentication service.');
    } on http.ClientException {
      throw const ApiException.network(message: 'Unable to communicate with the authentication service.');
    }

    final body = _decodeResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        code: _extractErrorCode(body),
        message: _safeErrorMessage(response.statusCode, body),
      );
    }
    final data = body?['data'];
    if (body?['success'] != true || data is! Map ||
        data['principal_id'] is! String || data['role'] is! String) {
      throw const ApiException(
        statusCode: 500,
        code: 'INVALID_IDENTITY_RESPONSE',
        message: 'The server returned an invalid authenticated identity.',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  /// Creates a request using the authenticated officer identity.
  Future<LocationRequest> createLocationRequest({
    required String caseId,
    required String targetPhoneNumber,
    required String operatorCode,
    String? remarks,
  }) async {
    final body = await _postJson(
      '/requests',
      {
        'case_id': caseId.trim(),
        'target_phone_number': targetPhoneNumber.trim(),
        'operator_code': operatorCode.trim().toUpperCase(),
        if (remarks != null && remarks.trim().isNotEmpty)
          'remarks': remarks.trim(),
      },
      operation: 'create',
    );

    return _parseLocationRequest(body['data']);
  }

  /// Mints a one-time bearer link after an explicit officer action.
  Future<LocationRequest> mintShareLink({
    required String requestId,
  }) async {
    final body = await _postJson(
      '/requests/${Uri.encodeComponent(requestId)}/share-link',
      const <String, dynamic>{},
      operation: 'share-link',
    );

    return _parseLocationRequest(body['data']);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload, {
    String operation = 'execute',
  }) async {
    final uri = _buildUri(path);

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
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      final message = operation == 'create'
        ? 'No confirmation was received. The request may have been created. '
            'Verify its status before retrying to avoid duplicate submissions.'
        : operation == 'share-link'
            ? 'Share-link generation timed out. Check the request before '
                'trying again.'
            : 'The server took too long to respond.';

      throw ApiException.network(message: message);
    } on SocketException {
      throw ApiException.network(
        message: operation == 'create'
          ? 'Unable to connect to the server. Check your connection and '
              'server availability before retrying.'
          : 'Unable to connect to the server.',
      
      );
    } on http.ClientException {
      throw ApiException.network(
        message: operation == 'create'
          ? 'The request could not be sent. Check your connection and '
              'server availability.'
          : 'Unable to communicate with the server.',
      
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
          operation: operation,
        ),
      );
    }

    if (body == null || body['success'] != true) {
      throw ApiException(
        statusCode: response.statusCode,
        code: _extractErrorCode(body),
        message: _safeErrorMessage(
          response.statusCode,
          body,
          operation: operation,
        ),
      );
    }

    return body;
  }

  LocationRequest _parseLocationRequest(dynamic data) {
    if (data is! Map) {
      throw const ApiException(
        statusCode: 500,
        code: 'INVALID_RESPONSE',
        message: 'The server returned an invalid request response.',
      );
    }
    try {
      return LocationRequest.fromJson(Map<String, dynamic>.from(data));
    } on FormatException {
      throw const ApiException(
        statusCode: 500,
        code: 'INVALID_RESPONSE',
        message: 'The server returned invalid request data.',
      );
    } on TypeError {
      throw const ApiException(
        statusCode: 500,
        code: 'INVALID_RESPONSE',
        message: 'The server returned invalid request data.',
      );
    }
  }

  /// Retrieves requests that are awaiting IO review.
  Future<List<LocationRequest>> getPendingIoRequests() async {
    final uri = _buildUri('/requests/io/pending');
    final headers = <String, String>{'Accept': 'application/json'};

    final token = authToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: headers)
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
        message: _safeErrorMessage(response.statusCode, body),
      );
    }

    if (body == null || body['success'] != true || body['data'] is! List) {
      throw const ApiException(
        statusCode: 500,
        code: 'INVALID_RESPONSE',
        message: 'The pending-requests response has an invalid format.',
      );
    }

    try {
      return (body['data'] as List).map((item) {
        if (item is! Map) {
          throw const FormatException('Invalid request entry.');
        }
        return LocationRequest.fromJson(Map<String, dynamic>.from(item));
      }).toList(growable: false);
    } on FormatException {
      throw const ApiException(
        statusCode: 500,
        code: 'INVALID_RESPONSE',
        message: 'A pending request contains invalid data.',
      );
    } on TypeError {
      throw const ApiException(
        statusCode: 500,
        code: 'INVALID_RESPONSE',
        message: 'A pending request contains invalid data.',
      );
    }
  }

  Future<Map<String, dynamic>> executeLocationRequest({
    required String requestId,
    required String ioDeviceId,
    required int simSlotIndex,
  }) async {
    final uri = _buildUri(
      '/requests/${Uri.encodeComponent(requestId)}/execute',
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

  Future<Map<String, dynamic>> updateSendStatus({
    required String requestId,
    required bool success,
    String? deliveryStatus,
    String? errorMessage,
  }) async {
    final uri = _buildUri(
      '/requests/${Uri.encodeComponent(requestId)}/send-status',
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
              'success': success,
              if (deliveryStatus != null) 'delivery_status': deliveryStatus,
              if (errorMessage != null) 'error_message': errorMessage,
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

  Future<Map<String, dynamic>> submitResult({
    required String requestId,
    required String rawSmsContent,
    String? senderAddress,
    DateTime? receivedAt,
  }) async {
    final uri = _buildUri(
      '/requests/${Uri.encodeComponent(requestId)}/result',
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
              'raw_sms_content': rawSmsContent,
              if (senderAddress != null) 'sender_address': senderAddress,
              if (receivedAt != null)
                'received_at': receivedAt.toUtc().toIso8601String(),
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
    Map<String, dynamic>? body, {
    String operation = 'execute',
  }) {
    final error = body?['error'];

    // Extract the backend error code
    final backendCode =
      error is Map<String, dynamic> ? error['code'] : null;

    switch (backendCode) {
      case 'UNAUTHORIZED':
        return 'Your session is not authorized.';

      case 'FORBIDDEN':
        switch (operation) {
          case 'create':
            return 'You are not authorized to create location requests.';
          case 'share-link':
            return 'You are not authorized to generate this share link.';
          default:
            return 'You are not authorized to execute this request.';
        
        }

      case 'RESOURCE_NOT_FOUND':
      case 'NOT_FOUND':
        return operation == 'share-link'
          ? 'The request was not found. Verify the request before retrying.'
          : 'The requested resource could not be found.';

      case 'INVALID_STATE_TRANSITION':
        return 'The request is no longer awaiting IO review.';

      case 'VALIDATION_ERROR':
        if (_isOperatorInactive(body)) {
          return 'The selected operator is not approved or is currently inactive.';
        }

        return operation == 'create'
          ? 'The server rejected the request details. Check the case '
              'reference, phone number, operator, and remarks.'
          : 'The submitted data could not be validated.';

      case 'REQUEST_VALIDATION_FAILED':
        return operation == 'create'
          ? 'Some request fields were rejected. Check the case reference, '
              'phone number, operator, and remarks.'
          : 'The submitted request data is invalid.';

      case 'DATABASE_UNAVAILABLE':
      case 'SERVICE_UNAVAILABLE':
        return 'The service is temporarily unavailable.';

      case 'INTERNAL_SERVER_ERROR':
        return operation == 'create'
          ? 'The server encountered an error while processing the request. '
              'Verify whether the request was created before retrying.'
          : 'The server encountered an unexpected error.';

      default:
        break;
    
    }

    switch (statusCode) {
      case 400:
        return 'The server rejected the request. Check the submitted details.';

      case 401:
        return 'Your session is not authorized.';

      case 403:
        return operation == 'create'
          ? 'You are not authorized to create location requests.'
          : 'You are not authorized to perform this operation.';

      case 404:
        return 'The requested resource could not be found.';

      case 409:
        return 'The request is no longer awaiting IO review.';

      case 422:
        return operation == 'create'
          ? 'The submitted request details are invalid.'
          : 'The submitted data is invalid.';

      case 429:
        return 'Too many requests. Wait before trying again.';

      case 500:
        return operation == 'create'
          ? 'The server encountered an error. Verify the request status '
              'before retrying.'
          : 'The server encountered an unexpected error.';

      case 503:
        return 'The service is temporarily unavailable.';

      default:
        return operation == 'create'
          ? 'Unable to create the request. Check the request status before retrying.'
          : 'The operation could not be completed.';
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