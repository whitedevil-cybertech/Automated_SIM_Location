/// Result of an Android device SMS transmission attempt.
class SmsSendResult {
  const SmsSendResult({
    required this.success,
    this.deliveryStatus,
    this.errorCode,
    this.errorMessage,
  });

  final bool success;
  final String? deliveryStatus;
  final String? errorCode;
  final String? errorMessage;

  factory SmsSendResult.success({String deliveryStatus = 'SENT'}) =>
      SmsSendResult(
        success: true,
        deliveryStatus: deliveryStatus,
      );

  factory SmsSendResult.failure({
    required String errorMessage,
    String? errorCode,
  }) =>
      SmsSendResult(
        success: false,
        errorMessage: errorMessage,
        errorCode: errorCode,
      );

  factory SmsSendResult.fromMap(Map<dynamic, dynamic> map) {
    final success = map['success'] as bool? ?? false;
    return SmsSendResult(
      success: success,
      deliveryStatus: map['deliveryStatus'] as String?,
      errorCode: map['errorCode'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}
