/// Approved telecom carrier dispatch parameters returned by backend to authorized IO device.
class DispatchInstructions {
  const DispatchInstructions({
    required this.serviceNumber,
    required this.smsBody,
    required this.operatorCode,
    this.simSlotIndex = 0,
  });

  final String serviceNumber;
  final String smsBody;
  final String operatorCode;
  final int simSlotIndex;

  factory DispatchInstructions.fromJson(Map<String, dynamic> json) {
    return DispatchInstructions(
      serviceNumber: json['service_number'] as String? ?? '',
      smsBody: json['sms_body'] as String? ?? '',
      operatorCode: json['operator_code'] as String? ?? '',
      simSlotIndex: json['sim_slot_index'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'service_number': serviceNumber,
        'sms_body': smsBody,
        'operator_code': operatorCode,
        'sim_slot_index': simSlotIndex,
      };
}
