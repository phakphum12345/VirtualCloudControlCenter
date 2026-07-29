import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai_engine/ai_service.dart';
import '../core/actions/assistant_action.dart';
import '../core/audit_log/audit_entry.dart';
import '../core/audit_log/audit_log_controller.dart';
import '../core/emergency_stop/emergency_stop_controller.dart';
import '../core/models/risk_level.dart';
import '../core/permissions/permission_policy.dart';
import '../platform/action_result.dart';
import '../platform/platform_controller.dart';

typedef ConfirmationCallback = Future<bool> Function(AssistantAction action);

class AppController extends ChangeNotifier {
  AppController(
    this._aiService,
    this._permissionPolicy,
    this._platformController, {
    required this.auditLog,
    required this.emergencyStop,
  });

  final AiService _aiService;
  final PermissionPolicy _permissionPolicy;
  final PlatformController _platformController;
  final AuditLogController auditLog;
  final EmergencyStopController emergencyStop;

  bool _isBusy = false;
  AssistantAction? _plannedAction;
  ActionResult? _lastResult;

  bool get isBusy => _isBusy;
  AssistantAction? get plannedAction => _plannedAction;
  ActionResult? get lastResult => _lastResult;

  Future<ActionResult> executeCommand(
    String input, {
    required ConfirmationCallback confirm,
  }) {
    final prepared = _aiService.prepare(input);
    return _execute(
      prepared.action,
      confirm: confirm,
      validationMessage: prepared.validation.isValid
          ? null
          : prepared.validation.message,
    );
  }

  Future<ActionResult> executeAction(
    AssistantAction action, {
    required ConfirmationCallback confirm,
  }) => _execute(action, confirm: confirm);

  Future<ActionResult> _execute(
    AssistantAction action, {
    required ConfirmationCallback confirm,
    String? validationMessage,
  }) async {
    if (_isBusy) {
      return _localFailure('', 'มีคำสั่งอื่นกำลังทำงานอยู่');
    }
    if (emergencyStop.isStopped) {
      return _localFailure('', 'ระบบถูกหยุดฉุกเฉิน กรุณาเปิดใช้งานใหม่');
    }

    _isBusy = true;
    final operationGeneration = emergencyStop.generation;
    notifyListeners();

    try {
      _plannedAction = action;
      notifyListeners();

      if (validationMessage != null) {
        return await _finish(
          action,
          _localFailure(action.id, validationMessage),
        );
      }

      final permission = _permissionPolicy.evaluate(action);
      if (!permission.allowed) {
        return await _finish(
          action,
          _localFailure(action.id, permission.reason),
        );
      }

      if (permission.requiresConfirmation && !await confirm(action)) {
        return await _finish(
          action,
          _localFailure(action.id, 'ผู้ใช้ยกเลิกคำสั่ง'),
        );
      }

      if (emergencyStop.wasCancelled(operationGeneration)) {
        return await _finish(
          action,
          _localFailure(action.id, 'คำสั่งถูกยกเลิกโดย Emergency Stop'),
        );
      }

      final result = await _platformController.execute(action);
      return await _finish(action, result);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void triggerEmergencyStop() {
    emergencyStop.stop();
    _lastResult = _localFailure('', 'หยุดการทำงานทั้งหมดแล้ว');
    unawaited(_stopNativeOperations());
    notifyListeners();
  }

  void resumeOperations() {
    emergencyStop.reset();
    _lastResult = null;
    notifyListeners();
  }

  Future<ActionResult> _finish(
    AssistantAction action,
    ActionResult result,
  ) async {
    _lastResult = result;
    await auditLog.add(
      AuditEntry(
        id: result.commandId,
        action: action.action,
        message: result.message,
        success: result.success,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
    return result;
  }

  Future<void> _stopNativeOperations() async {
    final action = AssistantAction(
      id: 'emergency_${DateTime.now().microsecondsSinceEpoch}',
      action: 'screen_recording.stop',
      parameters: const {},
      risk: RiskLevel.safe,
    );
    final result = await _platformController.execute(action);
    await auditLog.add(
      AuditEntry(
        id: action.id,
        action: 'emergency_stop',
        message: result.success
            ? 'Emergency Stop terminated native recording.'
            : 'Emergency Stop active; no native recording was terminated.',
        success: true,
        timestamp: DateTime.now(),
      ),
    );
  }

  ActionResult _localFailure(String commandId, String message) => ActionResult(
    commandId: commandId,
    success: false,
    message: message,
    platform: 'shared',
  );
}
