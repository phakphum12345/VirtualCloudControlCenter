import '../core/actions/assistant_action.dart';

class ValidationResult {
  const ValidationResult(this.isValid, this.message);

  final bool isValid;
  final String message;
}

class CommandValidator {
  const CommandValidator();

  ValidationResult validate(AssistantAction action) {
    if (action.action == 'unknown') {
      return const ValidationResult(
        false,
        'ยังไม่เข้าใจคำสั่งนี้ กรุณาระบุสิ่งที่ต้องการให้ชัดเจนขึ้น',
      );
    }
    return const ValidationResult(true, 'Valid command.');
  }
}
