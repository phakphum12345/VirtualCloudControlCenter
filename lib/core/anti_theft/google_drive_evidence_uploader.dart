import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'anti_theft_evidence.dart';

class GoogleDriveEvidenceUploader {
  static const scopes = <String>[drive.DriveApi.driveFileScope];
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  final GoogleSignIn _signIn = GoogleSignIn.instance;
  GoogleSignInAccount? _account;
  bool _initialized = false;

  String? get accountEmail => _account?.email;
  bool get connected => _account != null;

  Future<void> initialize() async {
    if (_initialized) return;
    await _signIn.initialize(
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
    _initialized = true;
    final result = _signIn.attemptLightweightAuthentication();
    if (result != null) {
      _account = await result;
    }
  }

  Future<String> connect() async {
    await initialize();
    if (!_signIn.supportsAuthenticate()) {
      throw StateError('แพลตฟอร์มนี้ไม่รองรับ Google Sign-In แบบปุ่มในแอป');
    }
    _account = await _signIn.authenticate(scopeHint: scopes);
    await _account!.authorizationClient.authorizeScopes(scopes);
    return _account!.email;
  }

  Future<void> disconnect() async {
    await initialize();
    await _signIn.disconnect();
    _account = null;
  }

  Future<String> upload(AntiTheftEvidence evidence) async {
    await initialize();
    final account = _account;
    if (account == null) {
      throw StateError('กรุณาเชื่อม Google Drive ก่อนอัปโหลด');
    }
    final authorization = await account.authorizationClient
        .authorizationForScopes(scopes);
    if (authorization == null) {
      throw StateError('สิทธิ์ Google Drive หมดอายุ กรุณาเชื่อมใหม่');
    }
    final client = authorization.authClient(scopes: scopes);
    try {
      final api = drive.DriveApi(client);
      final source = File(evidence.encryptedPath);
      final result = await api.files.create(
        drive.File(
          name: '${evidence.id}.pae',
          description:
              'Encrypted anti-theft evidence. '
              'Created ${evidence.createdAt.toUtc().toIso8601String()}.',
          properties: {'evidenceId': evidence.id, 'format': 'PAE1'},
        ),
        uploadMedia: drive.Media(source.openRead(), await source.length()),
        $fields: 'id',
      );
      if (result.id == null) {
        throw StateError('Google Drive ไม่คืนรหัสไฟล์หลังอัปโหลด');
      }
      return result.id!;
    } finally {
      client.close();
    }
  }
}
