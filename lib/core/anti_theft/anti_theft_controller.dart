import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter/foundation.dart';

import '../../services/storage_service.dart';
import '../audit_log/audit_entry.dart';
import '../audit_log/audit_log_controller.dart';
import 'anti_theft_config.dart';
import 'anti_theft_evidence.dart';
import 'evidence_context.dart';
import 'evidence_vault.dart';
import 'google_drive_evidence_uploader.dart';

class AntiTheftController extends ChangeNotifier {
  static const _pinKdf = 'pbkdf2-sha256-210000';

  AntiTheftController(
    this._storage,
    this._auditLog, {
    EvidenceVault? vault,
    EvidenceContext? evidenceContext,
    GoogleDriveEvidenceUploader? uploader,
  }) : _vault = vault ?? EvidenceVault(),
       _evidenceContext = evidenceContext ?? EvidenceContext(),
       _uploader = uploader ?? GoogleDriveEvidenceUploader();

  final StorageService _storage;
  final AuditLogController _auditLog;
  final EvidenceVault _vault;
  final EvidenceContext _evidenceContext;
  final GoogleDriveEvidenceUploader _uploader;
  AntiTheftConfig _config = const AntiTheftConfig();
  List<AntiTheftEvidence> _evidence = const [];
  int _failedAttempts = 0;
  bool _captureRequested = false;
  bool _processing = false;
  String? _lastError;
  StreamSubscription<Object?>? _networkSubscription;

  AntiTheftConfig get config => _config;
  List<AntiTheftEvidence> get evidence => List.unmodifiable(_evidence);
  int get failedAttempts => _failedAttempts;
  bool get captureRequested => _captureRequested;
  bool get processing => _processing;
  String? get lastError => _lastError;
  String? get driveAccountEmail => _uploader.accountEmail;

  Future<void> initialize() async {
    _config = await _storage.loadAntiTheftConfig();
    _evidence = await _storage.loadAntiTheftEvidence();
    await _applyRetention();
    _networkSubscription = _evidenceContext.networkChanges.listen((_) {
      if (_uploader.connected) unawaited(retryQueuedUploads());
    });
    notifyListeners();
  }

  Future<void> initializeDrive() async {
    try {
      await _uploader.initialize();
      _lastError = null;
      await retryQueuedUploads();
    } catch (error) {
      _lastError = 'Google Drive ยังไม่พร้อม: $error';
    }
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw const FormatException('PIN ต้องเป็นตัวเลข 6–12 หลัก');
    }
    final salt = base64Encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    _config = _config.copyWith(
      pinSalt: salt,
      pinHash: await _hashPin(pin, salt, _pinKdf),
      pinKdf: _pinKdf,
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
    int? retentionDays,
    int? maximumClips,
  }) async {
    if (enabled == true && !_config.hasPin) {
      throw StateError('กรุณาตั้ง PIN เจ้าของก่อนเปิดใช้งาน');
    }
    if (destination == AntiTheftDestination.googleDrive &&
        !_uploader.connected) {
      throw StateError('กรุณาเชื่อม Google Drive ก่อนเลือกเป็นปลายทาง');
    }
    _config = _config.copyWith(
      enabled: enabled,
      failedAttemptThreshold: failedAttemptThreshold?.clamp(1, 10),
      recordingSeconds: recordingSeconds?.clamp(30, 180),
      uploadOnWifiOnly: uploadOnWifiOnly,
      destination: destination,
      retentionDays: retentionDays?.clamp(1, 365),
      maximumClips: maximumClips?.clamp(1, 100),
    );
    await _save('อัปเดตการตั้งค่าโหมดป้องกันการขโมย');
    await _applyRetention();
  }

  Future<AntiTheftAttemptResult> verifyPin(String pin) async {
    if (!_config.hasPin) {
      return const AntiTheftAttemptResult(
        accepted: false,
        triggerRequested: false,
        message: 'ยังไม่ได้ตั้ง PIN เจ้าของ',
      );
    }
    if (await _hashPin(pin, _config.pinSalt, _config.pinKdf) ==
        _config.pinHash) {
      _failedAttempts = 0;
      notifyListeners();
      return const AntiTheftAttemptResult(
        accepted: true,
        triggerRequested: false,
        message: 'PIN ถูกต้อง',
      );
    }
    _failedAttempts++;
    final attemptNumber = _failedAttempts;
    final trigger =
        _config.enabled && _failedAttempts >= _config.failedAttemptThreshold;
    if (trigger) {
      _captureRequested = true;
      _failedAttempts = 0;
    }
    await _auditLog.add(
      AuditEntry(
        id: 'anti_theft_${DateTime.now().microsecondsSinceEpoch}',
        action: trigger
            ? 'anti_theft.trigger_requested'
            : 'anti_theft.pin_failed',
        message: trigger
            ? 'PIN ผิดถึงเกณฑ์ รอเปิดกล้องพร้อม permission และ indicator'
            : 'PIN ไม่ถูกต้อง ครั้งที่ $attemptNumber',
        success: false,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
    return AntiTheftAttemptResult(
      accepted: false,
      triggerRequested: trigger,
      message: trigger
          ? 'ถึงเกณฑ์แล้ว กำลังขอเปิดกล้องเพื่อบันทึกหลักฐาน'
          : 'PIN ไม่ถูกต้อง',
    );
  }

  void acknowledgeCaptureRequest() {
    _captureRequested = false;
    notifyListeners();
  }

  Future<AntiTheftEvidence> completeCapture(
    String sourcePath,
    int durationSeconds,
  ) async {
    _processing = true;
    _lastError = null;
    notifyListeners();
    final now = DateTime.now();
    final id = 'evidence_${now.toUtc().microsecondsSinceEpoch}';
    try {
      final encryptedPath = await _vault.encrypt(sourcePath, id);
      final file = File(encryptedPath);
      final evidence = AntiTheftEvidence(
        id: id,
        createdAt: now,
        durationSeconds: durationSeconds,
        encryptedPath: encryptedPath,
        encryptedBytes: await file.length(),
        networkType: await _evidenceContext.networkType(),
        deviceSummary: await _evidenceContext.deviceSummary(),
        uploadState: _config.destination == AntiTheftDestination.googleDrive
            ? EvidenceUploadState.queued
            : EvidenceUploadState.local,
      );
      _evidence = [evidence, ..._evidence];
      await _storage.saveAntiTheftEvidence(_evidence);
      await _audit(
        'anti_theft.evidence_saved',
        'บันทึกหลักฐานเข้ารหัส ${evidence.id} แล้ว',
        true,
      );
      await _applyRetention();
      if (evidence.uploadState == EvidenceUploadState.queued) {
        await uploadEvidence(evidence.id);
      }
      return _findEvidence(id);
    } catch (error) {
      _lastError = error.toString();
      await _audit(
        'anti_theft.evidence_failed',
        'บันทึกหลักฐานไม่สำเร็จ: $error',
        false,
      );
      rethrow;
    } finally {
      _processing = false;
      notifyListeners();
    }
  }

  Future<String> connectGoogleDrive() async {
    final email = await _uploader.connect();
    _config = _config.copyWith(destination: AntiTheftDestination.googleDrive);
    await _save('เชื่อม Google Drive สำหรับหลักฐานแล้ว');
    await retryQueuedUploads();
    return email;
  }

  Future<void> disconnectGoogleDrive() async {
    await _uploader.disconnect();
    _config = _config.copyWith(destination: AntiTheftDestination.localOnly);
    await _save('ยกเลิกการเชื่อม Google Drive');
  }

  Future<void> uploadEvidence(String id) async {
    final evidence = _findEvidence(id);
    if (!_uploader.connected) {
      await _replaceEvidence(
        evidence.copyWith(
          uploadState: EvidenceUploadState.queued,
          lastError: 'รอเชื่อม Google Drive',
        ),
      );
      return;
    }
    if (_config.uploadOnWifiOnly &&
        !((await _evidenceContext.networkType()).split(',').contains('wifi'))) {
      await _replaceEvidence(
        evidence.copyWith(
          uploadState: EvidenceUploadState.queued,
          lastError: 'รอเครือข่าย Wi-Fi',
        ),
      );
      return;
    }
    await _replaceEvidence(
      evidence.copyWith(
        uploadState: EvidenceUploadState.uploading,
        clearError: true,
      ),
    );
    try {
      final fileId = await _uploader.upload(evidence);
      await _replaceEvidence(
        evidence.copyWith(
          uploadState: EvidenceUploadState.uploaded,
          driveFileId: fileId,
          clearError: true,
        ),
      );
      await _audit(
        'anti_theft.uploaded',
        'อัปโหลดหลักฐาน ${evidence.id} ไป Google Drive แล้ว',
        true,
      );
    } catch (error) {
      await _replaceEvidence(
        evidence.copyWith(
          uploadState: EvidenceUploadState.failed,
          lastError: error.toString(),
        ),
      );
      await _audit(
        'anti_theft.upload_failed',
        'อัปโหลดหลักฐาน ${evidence.id} ไม่สำเร็จ: $error',
        false,
      );
    }
  }

  Future<void> retryQueuedUploads() async {
    if (!_uploader.connected) return;
    final queued = _evidence
        .where(
          (value) =>
              value.uploadState == EvidenceUploadState.queued ||
              value.uploadState == EvidenceUploadState.failed,
        )
        .map((value) => value.id)
        .toList();
    for (final id in queued) {
      await uploadEvidence(id);
    }
  }

  Future<String> decryptForExport(String id) =>
      _vault.decryptToTemporary(_findEvidence(id).encryptedPath);

  Future<void> deleteEvidence(String id) async {
    final evidence = _findEvidence(id);
    await _vault.delete(evidence.encryptedPath);
    _evidence = _evidence.where((value) => value.id != id).toList();
    await _storage.saveAntiTheftEvidence(_evidence);
    await _audit(
      'anti_theft.evidence_deleted',
      'ลบหลักฐานในเครื่อง ${evidence.id} แล้ว',
      true,
    );
    notifyListeners();
  }

  Future<String> _hashPin(String pin, String salt, String kdf) async {
    if (kdf == _pinKdf) {
      final algorithm = cryptography.Pbkdf2(
        macAlgorithm: cryptography.Hmac.sha256(),
        iterations: 210000,
        bits: 256,
      );
      final key = await algorithm.deriveKeyFromPassword(
        password: pin,
        nonce: base64Decode(salt),
      );
      return base64Encode(await key.extractBytes());
    }
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

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

  Future<void> _replaceEvidence(AntiTheftEvidence replacement) async {
    _evidence = [
      for (final value in _evidence)
        if (value.id == replacement.id) replacement else value,
    ];
    await _storage.saveAntiTheftEvidence(_evidence);
    notifyListeners();
  }

  AntiTheftEvidence _findEvidence(String id) =>
      _evidence.firstWhere((value) => value.id == id);

  Future<void> _applyRetention() async {
    final cutoff = DateTime.now().subtract(
      Duration(days: _config.retentionDays),
    );
    final sorted = [..._evidence]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final retained = <AntiTheftEvidence>[];
    final removed = <AntiTheftEvidence>[];
    for (final value in sorted) {
      if (value.createdAt.isBefore(cutoff) ||
          retained.length >= _config.maximumClips) {
        removed.add(value);
      } else {
        retained.add(value);
      }
    }
    for (final value in removed) {
      await _vault.delete(value.encryptedPath);
    }
    if (removed.isNotEmpty) {
      _evidence = retained;
      await _storage.saveAntiTheftEvidence(_evidence);
      await _audit(
        'anti_theft.retention',
        'ลบหลักฐานตามนโยบาย ${removed.length} รายการ',
        true,
      );
    }
  }

  Future<void> _audit(String action, String message, bool success) async {
    await _auditLog.add(
      AuditEntry(
        id: 'anti_theft_${DateTime.now().microsecondsSinceEpoch}',
        action: action,
        message: message,
        success: success,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    super.dispose();
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
