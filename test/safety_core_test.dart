import 'package:flutter_test/flutter_test.dart';
import 'package:phakphum_ai_assistant/core/actions/assistant_action.dart';
import 'package:phakphum_ai_assistant/core/emergency_stop/emergency_stop_controller.dart';
import 'package:phakphum_ai_assistant/core/models/risk_level.dart';
import 'package:phakphum_ai_assistant/core/permissions/permission_policy.dart';

void main() {
  group('PermissionPolicy', () {
    const policy = PermissionPolicy();

    test('safe actions do not require confirmation', () {
      final decision = policy.evaluate(
        const AssistantAction(
          id: 'safe',
          action: 'diagnostics.status',
          parameters: {},
          risk: RiskLevel.safe,
        ),
      );
      expect(decision.allowed, isTrue);
      expect(decision.requiresConfirmation, isFalse);
    });

    test('important actions require confirmation', () {
      final decision = policy.evaluate(
        const AssistantAction(
          id: 'confirm',
          action: 'screen_recording.start',
          parameters: {},
          risk: RiskLevel.confirmationRequired,
        ),
      );
      expect(decision.allowed, isTrue);
      expect(decision.requiresConfirmation, isTrue);
    });

    test('restricted actions are blocked', () {
      final decision = policy.evaluate(
        const AssistantAction(
          id: 'blocked',
          action: 'restricted.security_bypass',
          parameters: {},
          risk: RiskLevel.restricted,
        ),
      );
      expect(decision.allowed, isFalse);
    });
  });

  test('emergency stop invalidates active operation generation', () {
    final controller = EmergencyStopController();
    final generation = controller.generation;

    controller.stop();

    expect(controller.isStopped, isTrue);
    expect(controller.wasCancelled(generation), isTrue);
  });
}
