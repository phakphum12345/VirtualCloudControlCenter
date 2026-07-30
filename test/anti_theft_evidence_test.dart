import 'package:flutter_test/flutter_test.dart';
import 'package:phakphum_ai_assistant/core/anti_theft/anti_theft_config.dart';
import 'package:phakphum_ai_assistant/core/anti_theft/anti_theft_evidence.dart';

void main() {
  test('anti-theft config persists retention and upload settings', () {
    final source = const AntiTheftConfig().copyWith(
      enabled: true,
      retentionDays: 14,
      maximumClips: 8,
      destination: AntiTheftDestination.googleDrive,
    );

    final restored = AntiTheftConfig.fromJson(source.toJson());

    expect(restored.enabled, isTrue);
    expect(restored.retentionDays, 14);
    expect(restored.maximumClips, 8);
    expect(restored.destination, AntiTheftDestination.googleDrive);
  });

  test('evidence metadata round-trips upload state', () {
    final source = AntiTheftEvidence(
      id: 'evidence_1',
      createdAt: DateTime.utc(2026, 7, 30),
      durationSeconds: 30,
      encryptedPath: '/evidence/evidence_1.pae',
      encryptedBytes: 4096,
      networkType: 'wifi',
      deviceSummary: 'Android test',
      uploadState: EvidenceUploadState.uploaded,
      driveFileId: 'drive-file',
    );

    final restored = AntiTheftEvidence.fromJson(source.toJson());

    expect(restored.id, source.id);
    expect(restored.uploadState, EvidenceUploadState.uploaded);
    expect(restored.driveFileId, 'drive-file');
    expect(restored.createdAt, source.createdAt);
  });
}
