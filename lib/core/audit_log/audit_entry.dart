class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.message,
    required this.success,
    required this.timestamp,
  });

  final String id;
  final String action;
  final String message;
  final bool success;
  final DateTime timestamp;

  Map<String, Object?> toJson() => {
    'id': id,
    'action': action,
    'message': message,
    'success': success,
    'timestamp': timestamp.toIso8601String(),
  };

  factory AuditEntry.fromJson(Map<String, Object?> json) => AuditEntry(
    id: json['id']! as String,
    action: json['action']! as String,
    message: json['message']! as String,
    success: json['success']! as bool,
    timestamp: DateTime.parse(json['timestamp']! as String),
  );
}
