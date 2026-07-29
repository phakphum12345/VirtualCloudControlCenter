import 'package:flutter_test/flutter_test.dart';
import 'package:phakphum_ai_assistant/core/actions/assistant_action.dart';
import 'package:phakphum_ai_assistant/core/models/risk_level.dart';
import 'package:phakphum_ai_assistant/platform/platform_adapter.dart';

void main() {
  const adapter = SharedPlatformAdapter('test');

  test('reports shared diagnostics as successful', () async {
    final result = await adapter.execute(
      const AssistantAction(
        id: 'status',
        action: 'diagnostics.status',
        parameters: {},
        risk: RiskLevel.safe,
      ),
    );
    expect(result.success, isTrue);
  });

  test('never claims unimplemented native action succeeded', () async {
    final result = await adapter.execute(
      const AssistantAction(
        id: 'record',
        action: 'screen_recording.start',
        parameters: {},
        risk: RiskLevel.confirmationRequired,
      ),
    );
    expect(result.success, isFalse);
    expect(result.details['reason'], 'not_implemented');
  });
}
