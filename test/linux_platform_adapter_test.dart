import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phakphum_ai_assistant/core/actions/assistant_action.dart';
import 'package:phakphum_ai_assistant/core/models/risk_level.dart';
import 'package:phakphum_ai_assistant/platform/linux_platform_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.phakphum.aiassistant/linux');
  const adapter = LinuxPlatformAdapter(channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses Linux native diagnostics result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getSystemStatus');
          return {
            'success': true,
            'message': 'Linux status read',
            'logicalProcessors': 8,
          };
        });
    final result = await adapter.execute(
      const AssistantAction(
        id: 'linux-status',
        action: 'diagnostics.status',
        parameters: {},
        risk: RiskLevel.safe,
      ),
    );
    expect(result.success, isTrue);
    expect(result.details['logicalProcessors'], 8);
  });
}
