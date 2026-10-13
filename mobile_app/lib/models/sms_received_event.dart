/// Event representing an incoming SMS message intercepted by the Android device.
class SmsReceivedEvent {
  const SmsReceivedEvent({
    required this.sender,
    required this.body,
    required this.timestamp,
    this.requestId,
  });

  final String sender;
  final String body;
  final DateTime timestamp;
  final String? requestId;

  factory SmsReceivedEvent.fromMap(Map<dynamic, dynamic> map) {
    final rawTs = map['timestamp'];
    final DateTime parsedTime;
    if (rawTs is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(rawTs, isUtc: true);
    } else if (rawTs is String) {
      parsedTime = DateTime.tryParse(rawTs) ?? DateTime.now().toUtc();
    } else {
      parsedTime = DateTime.now().toUtc();
    }

    return SmsReceivedEvent(
      sender: map['sender'] as String? ?? '',
      body: map['body'] as String? ?? '',
      timestamp: parsedTime,
      requestId: map['requestId'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'sender': sender,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        if (requestId != null) 'requestId': requestId,
      };
}
