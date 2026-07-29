import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phakphum_ai_assistant/core/actions/assistant_action.dart';
import 'package:phakphum_ai_assistant/core/models/risk_level.dart';
import 'package:phakphum_ai_assistant/platform/android_platform_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.phakphum.aiassistant/android');
  const adapter = AndroidPlatformAdapter(channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses Android native diagnostics result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getSystemStatus');
          return {
            'success': true,
            'message': 'Android status read',
            'batteryPercent': 80,
          };
        });
    final result = await adapter.execute(
      const AssistantAction(
        id: 'android-status',
        action: 'diagnostics.status',
        parameters: {},
        risk: RiskLevel.safe,
      ),
    );
    expect(result.success, isTrue);
    expect(result.details['batteryPercent'], 80);
  });

  test('maps recording start to native MediaProjection method', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'startRecording');
          expect(call.arguments, containsPair('quality', '1080p'));
          return {
            'success': true,
            'message': 'Android recording service started.',
            'state': 'starting',
            'visibleIndicator': true,
          };
        });
    final result = await adapter.execute(
      const AssistantAction(
        id: 'android-record',
        action: 'screen_recording.start',
        parameters: {'quality': '1080p'},
        risk: RiskLevel.confirmationRequired,
      ),
    );
    expect(result.success, isTrue);
    expect(result.details['visibleIndicator'], isTrue);
  });
}
