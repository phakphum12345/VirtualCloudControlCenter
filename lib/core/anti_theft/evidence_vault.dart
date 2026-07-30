import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class EvidenceVault {
  EvidenceVault([this._secureStorage = const FlutterSecureStorage()]);

  static const _keyName = 'anti_theft_evidence_key_v1';
  static const _magic = 'PAE1';
  final FlutterSecureStorage _secureStorage;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<String> encrypt(String sourcePath, String evidenceId) async {
    final directory = await _evidenceDirectory();
    final destination = File('${directory.path}/$evidenceId.pae');
    final input = File(sourcePath).openRead();
    final output = destination.openWrite();
    final key = await _key();
    output.add(utf8.encode(_magic));
    try {
      await for (final chunk in input) {
        final nonce = _randomBytes(12);
        final box = await _cipher.encrypt(chunk, secretKey: key, nonce: nonce);
        output.add(_uint32(chunk.length));
        output.add(nonce);
        output.add(box.mac.bytes);
        output.add(box.cipherText);
      }
      await output.flush();
      await output.close();
      await File(sourcePath).delete();
      return destination.path;
    } catch (_) {
      await output.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  Future<String> decryptToTemporary(String encryptedPath) async {
    final source = File(encryptedPath);
    final destination = File(
      '${(await getTemporaryDirectory()).path}/'
      '${source.uri.pathSegments.last.replaceAll('.pae', '')}.mp4',
    );
    final input = await source.open();
    final key = await _key();
    final output = destination.openWrite();
    try {
      final magic = await input.read(4);
      if (magic.length != 4 || utf8.decode(magic) != _magic) {
        throw const FormatException('รูปแบบหลักฐานไม่ถูกต้อง');
      }
      while (await input.position() < await input.length()) {
        final lengthBytes = await input.read(4);
        if (lengthBytes.length != 4) {
          throw const FormatException('หลักฐานเข้ารหัสไม่สมบูรณ์');
        }
        final length = ByteData.sublistView(
          Uint8List.fromList(lengthBytes),
        ).getUint32(0);
        final nonce = await input.read(12);
        final macBytes = await input.read(16);
        final cipherText = await input.read(length);
        if (nonce.length != 12 ||
            macBytes.length != 16 ||
            cipherText.length != length) {
          throw const FormatException('หลักฐานเข้ารหัสไม่สมบูรณ์');
        }
        final clear = await _cipher.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
          secretKey: key,
        );
        output.add(clear);
      }
      await input.close();
      await output.flush();
      await output.close();
      return destination.path;
    } catch (_) {
      await input.close();
      await output.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  Future<void> delete(String encryptedPath) async {
    final file = File(encryptedPath);
    if (await file.exists()) await file.delete();
  }

  Future<Directory> _evidenceDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/anti_theft_evidence');
    await directory.create(recursive: true);
    return directory;
  }

  Future<SecretKey> _key() async {
    var encoded = await _secureStorage.read(key: _keyName);
    if (encoded == null) {
      encoded = base64Encode(_randomBytes(32));
      await _secureStorage.write(key: _keyName, value: encoded);
    }
    return SecretKey(base64Decode(encoded));
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Uint8List _uint32(int value) {
    final data = ByteData(4)..setUint32(0, value);
    return data.buffer.asUint8List();
  }
}
