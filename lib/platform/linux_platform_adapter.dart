import 'package:flutter/services.dart';

import '../core/actions/assistant_action.dart';
import 'action_result.dart';
import 'platform_adapter.dart';

class LinuxPlatformAdapter implements PlatformAdapter {
  const LinuxPlatformAdapter([
    this._channel = const MethodChannel('com.phakphum.aiassistant/linux'),
  ]);

  final MethodChannel _channel;

  @override
  String get platformName => 'linux';

  @override
  Future<ActionResult> execute(AssistantAction action) async {
    final method = switch (action.action) {
      'diagnostics.status' => 'getSystemStatus',
      'settings.open' => 'openSettings',
      _ => null,
    };
    if (method == null) {
      return _failure(action, 'คำสั่ง ${action.action} ยังไม่มี Linux adapter');
    }
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        method,
        action.parameters,
      );
      if (response == null) {
        return _failure(action, 'Linux adapter returned no result.');
      }
      final values = Map<String, Object?>.from(response);
      final success = values['success'] == true;
      final message =
          values.remove('message')?.toString() ??
          (success ? 'Linux action completed.' : 'Linux action failed.');
      return ActionResult(
        commandId: action.id,
        success: success,
        message: message,
        platform: platformName,
        details: values,
      );
    } on PlatformException catch (error) {
      return _failure(action, error.message ?? 'Linux platform call failed.');
    } on MissingPluginException {
      return _failure(action, 'Linux native adapter is not registered.');
    }
  }

  ActionResult _failure(AssistantAction action, String message) => ActionResult(
    commandId: action.id,
    success: false,
    message: message,
    platform: platformName,
    details: const {'reason': 'not_implemented'},
  );
}
