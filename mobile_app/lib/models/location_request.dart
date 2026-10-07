import '../core/constants/request_states.dart';

class LocationRequest {
  const LocationRequest({
    required this.requestId,
    required this.caseId,
    required this.targetPhoneMasked,
    required this.operatorCode,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.submittingOfficerId,
    this.executingIoId,
    this.remarks,
  });

  final String requestId;
  final String caseId;
  final String targetPhoneMasked;
  final String operatorCode;
  final RequestState status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? submittingOfficerId;
  final String? executingIoId;
  final String? remarks;

  factory LocationRequest.fromJson(Map<String, dynamic> json) {
    return LocationRequest(
      requestId: json['request_id'] as String,
      caseId: json['case_id'] as String,
      targetPhoneMasked: json['target_phone_masked'] as String,
      operatorCode: json['operator_code'] as String,
      status: RequestState.fromString(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      submittingOfficerId: json['submitting_officer_id'] as String?,
      executingIoId: json['executing_io_id'] as String?,
      remarks: json['remarks'] as String?,
    );
  }
}