import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../services/storage_service.dart';
import '../audit_log/audit_entry.dart';
import '../audit_log/audit_log_controller.dart';
import 'anti_theft_config.dart';

class AntiTheftController extends ChangeNotifier {
  AntiTheftController(this._storage, this._auditLog);

  final StorageService _storage;
  final AuditLogController _auditLog;
  AntiTheftConfig _config = const AntiTheftConfig();
  int _failedAttempts = 0;

  AntiTheftConfig get config => _config;
  int get failedAttempts => _failedAttempts;

  Future<void> initialize() async {
    _config = await _storage.loadAntiTheftConfig();
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw const FormatException('PIN ต้องเป็นตัวเลข 6–12 หลัก');
    }
    final salt =
        '${DateTime.now().microsecondsSinceEpoch}:${identityHashCode(this)}';
    _config = _config.copyWith(
      pinSalt: salt,
      pinHash: _hash(pin, salt),
      enabled: false,
    );
    _failedAttempts = 0;
    await _save('ตั้ง PIN เจ้าของแล้ว ต้องเปิดโหมดป้องกันอีกครั้ง');
  }

  Future<void> update({
    bool? enabled,
    int? failedAttemptThreshold,
    int? recordingSeconds,
    bool? uploadOnWifiOnly,
    AntiTheftDestination? destination,
  }) async {
    if (enabled == true && !_config.hasPin) {
      throw StateError('กรุณาตั้ง PIN เจ้าของก่อนเปิดใช้งาน');
    }
    if (destination == AntiTheftDestination.googleDrive) {
      throw StateError(
        'Google Drive ยังไม่ได้เชื่อมต่อ จึงยังเลือกเป็นปลายทางไม่ได้',
      );
    }
    _config = _config.copyWith(
      enabled: enabled,
      failedAttemptThreshold: failedAttemptThreshold?.clamp(1, 10),
      recordingSeconds: recordingSeconds?.clamp(30, 180),
      uploadOnWifiOnly: uploadOnWifiOnly,
      destination: destination,
    );
    await _save('อัปเดตการตั้งค่าโหมดป้องกันการขโมย');
  }

  Future<AntiTheftAttemptResult> verifyPin(String pin) async {
    if (!_config.hasPin) {
      return const AntiTheftAttemptResult(
        accepted: false,
        triggerRequested: false,
        message: 'ยังไม่ได้ตั้ง PIN เจ้าของ',
      );
    }
    if (_hash(pin, _config.pinSalt) == _config.pinHash) {
      _failedAttempts = 0;
      notifyListeners();
      return const AntiTheftAttemptResult(
        accepted: true,
        triggerRequested: false,
        message: 'PIN ถูกต้อง',
      );
    }
    _failedAttempts++;
    final trigger =
        _config.enabled && _failedAttempts >= _config.failedAttemptThreshold;
    await _auditLog.add(
      AuditEntry(
        id: 'anti_theft_${DateTime.now().microsecondsSinceEpoch}',
        action: trigger
            ? 'anti_theft.trigger_requested'
            : 'anti_theft.pin_failed',
        message: trigger
            ? 'PIN ผิดถึงเกณฑ์ แต่ยังไม่เริ่มกล้อง: native camera adapter ยังไม่พร้อม'
            : 'PIN ไม่ถูกต้อง ครั้งที่ $_failedAttempts',
        success: false,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
    return AntiTheftAttemptResult(
      accepted: false,
      triggerRequested: trigger,
      message: trigger
          ? 'ถึงเกณฑ์แจ้งเตือนแล้ว แต่กล้องยังไม่ถูกเปิด'
          : 'PIN ไม่ถูกต้อง',
    );
  }

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> _save(String message) async {
    await _storage.saveAntiTheftConfig(_config);
    await _auditLog.add(
      AuditEntry(
        id: 'anti_theft_${DateTime.now().microsecondsSinceEpoch}',
        action: 'anti_theft.settings',
        message: message,
        success: true,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }
}

class AntiTheftAttemptResult {
  const AntiTheftAttemptResult({
    required this.accepted,
    required this.triggerRequested,
    required this.message,
  });

  final bool accepted;
  final bool triggerRequested;
  final String message;
}
