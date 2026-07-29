import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phakphum_ai_assistant/core/actions/assistant_action.dart';
import 'package:phakphum_ai_assistant/core/models/risk_level.dart';
import 'package:phakphum_ai_assistant/platform/windows_platform_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.phakphum.aiassistant/windows');
  const adapter = WindowsPlatformAdapter(channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses confirmed native success result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getSystemStatus');
          return {
            'success': true,
            'message': 'status read',
            'memoryLoadPercent': 42,
          };
        });

    final result = await adapter.execute(
      const AssistantAction(
        id: 'status',
        action: 'diagnostics.status',
        parameters: {},
        risk: RiskLevel.safe,
      ),
    );

    expect(result.success, isTrue);
    expect(result.platform, 'windows');
    expect(result.details['memoryLoadPercent'], 42);
  });

  test('returns honest failure for missing native method', () async {
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
