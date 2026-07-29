import 'package:flutter/services.dart';

import '../core/actions/assistant_action.dart';
import 'action_result.dart';
import 'platform_adapter.dart';

class AndroidPlatformAdapter implements PlatformAdapter {
  const AndroidPlatformAdapter([
    this._channel = const MethodChannel('com.phakphum.aiassistant/android'),
  ]);

  final MethodChannel _channel;

  @override
  String get platformName => 'android';

  @override
  Future<ActionResult> execute(AssistantAction action) async {
    final method = switch (action.action) {
      'diagnostics.status' => 'getSystemStatus',
      'settings.open' => 'openSettings',
      _ => null,
    };
    if (method == null) {
      return _failure(
        action,
        'คำสั่ง ${action.action} ยังไม่มี Android adapter',
        const {'reason': 'not_implemented'},
      );
    }
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        method,
        action.parameters,
      );
      if (response == null) {
        return _failure(action, 'Android adapter returned no result.');
      }
      final values = Map<String, Object?>.from(response);
      final success = values['success'] == true;
      final message =
          values.remove('message')?.toString() ??
          (success ? 'Android action completed.' : 'Android action failed.');
      return ActionResult(
        commandId: action.id,
        success: success,
        message: message,
        platform: platformName,
        details: values,
      );
    } on PlatformException catch (error) {
      return _failure(
        action,
        error.message ?? 'Android platform call failed.',
        {'code': error.code},
      );
    } on MissingPluginException {
      return _failure(
        action,
        'Android native adapter is not registered in this build.',
        const {'reason': 'adapter_unavailable'},
      );
    }
  }

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
