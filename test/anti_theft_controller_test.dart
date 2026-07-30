import 'package:flutter_test/flutter_test.dart';
import 'package:phakphum_ai_assistant/core/anti_theft/anti_theft_controller.dart';
import 'package:phakphum_ai_assistant/core/audit_log/audit_log_controller.dart';
import 'package:phakphum_ai_assistant/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('requires an owner PIN before enabling', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    final audit = AuditLogController(storage);
    await audit.initialize();
    final controller = AntiTheftController(storage, audit);
    await controller.initialize();

    expect(() => controller.update(enabled: true), throwsA(isA<StateError>()));
  });

  test(
    'stores no plaintext PIN and triggers only at configured threshold',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final audit = AuditLogController(storage);
      await audit.initialize();
      final controller = AntiTheftController(storage, audit);
      await controller.initialize();

      await controller.setPin('123456');
      await controller.update(enabled: true, failedAttemptThreshold: 2);

      final first = await controller.verifyPin('000000');
      final second = await controller.verifyPin('111111');

      expect(first.triggerRequested, isFalse);
      expect(second.triggerRequested, isTrue);
      expect(controller.captureRequested, isTrue);
      expect(controller.config.pinHash, isNot('123456'));
      expect(audit.entries.first.message, contains('รอเปิดกล้อง'));
    },
  );

  test('correct PIN resets failed-attempt count', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    final audit = AuditLogController(storage);
    await audit.initialize();
    final controller = AntiTheftController(storage, audit);
    await controller.initialize();
    await controller.setPin('654321');
    await controller.update(enabled: true);

    await controller.verifyPin('000000');
    final accepted = await controller.verifyPin('654321');

    expect(accepted.accepted, isTrue);
    expect(controller.failedAttempts, 0);
  });
}
