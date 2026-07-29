class ActionResult {
  const ActionResult({
    required this.commandId,
    required this.success,
    required this.message,
    required this.platform,
    this.details = const {},
  });

  final String commandId;
  final bool success;
  final String message;
  final String platform;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => {
    'commandId': commandId,
    'success': success,
    'message': message,
    'platform': platform,
    'details': details,
  };
}
