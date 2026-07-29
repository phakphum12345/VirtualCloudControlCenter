import 'package:flutter/services.dart';

import '../core/actions/assistant_action.dart';
import 'action_result.dart';
import 'platform_adapter.dart';

class WindowsPlatformAdapter implements PlatformAdapter {
  const WindowsPlatformAdapter([
    this._channel = const MethodChannel('com.phakphum.aiassistant/windows'),
  ]);

  final MethodChannel _channel;

  @override
  String get platformName => 'windows';

  @override
  Future<ActionResult> execute(AssistantAction action) async {
    final method = switch (action.action) {
      'diagnostics.status' => 'getSystemStatus',
      'settings.open' => 'openSettings',
      'settings.volume' => 'setVolume',
      'application.open' => 'openApplication',
      'application.list' => 'listProcesses',
      'application.close' => 'closeApplication',
      'file.search_large' => 'findLargeFiles',
      'screenshot.take' => 'takeScreenshot',
      _ => null,
    };
    if (method == null) {
      return _failure(
        action,
        'คำสั่ง ${action.action} ยังไม่มี Windows adapter',
        const {'reason': 'not_implemented'},
      );
    }

    try {
      final response = await _channel.invokeMethod<Object?>(
        method,
        action.parameters,
      );
      if (response is List) {
        return ActionResult(
          commandId: action.id,
          success: true,
          message: _listMessage(action.action, response.length),
          platform: platformName,
          details: {'items': response},
        );
      }
      if (response is Map) {
        final values = Map<String, Object?>.from(response);
        final success = values['success'] == true;
        return ActionResult(
          commandId: action.id,
          success: success,
          message:
              values['message'] as String? ??
              (success
                  ? 'Windows action completed.'
                  : 'Windows action failed.'),
          platform: platformName,
          details: values..remove('message'),
        );
      }
      return _failure(action, 'Windows adapter returned an invalid result.');
    } on PlatformException catch (error) {
      return _failure(
        action,
        error.message ?? 'Windows platform call failed.',
        {'code': error.code},
      );
    } on MissingPluginException {
      return _failure(
        action,
        'Windows native adapter is not registered in this build.',
        const {'reason': 'adapter_unavailable'},
      );
    }
  }

  String _listMessage(String action, int count) => switch (action) {
    'application.list' => 'พบ $count processes',
    'file.search_large' => 'พบไฟล์ขนาดใหญ่ $count รายการ',
    _ => 'พบ $count รายการ',
  };

  ActionResult _failure(
    AssistantAction action,
    String message, [
    Map<String, Object?> details = const {},
  ]) => ActionResult(
    commandId: action.id,
    success: false,
    message: message,
    platform: platformName,
    details: details,
  );
}
