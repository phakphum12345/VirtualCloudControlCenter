enum EvidenceUploadState { local, queued, uploading, uploaded, failed }

class AntiTheftEvidence {
  const AntiTheftEvidence({
    required this.id,
    required this.createdAt,
    required this.durationSeconds,
    required this.encryptedPath,
    required this.encryptedBytes,
    required this.networkType,
    required this.deviceSummary,
    this.uploadState = EvidenceUploadState.local,
    this.driveFileId,
    this.lastError,
  });

  final String id;
  final DateTime createdAt;
  final int durationSeconds;
  final String encryptedPath;
  final int encryptedBytes;
  final String networkType;
  final String deviceSummary;
  final EvidenceUploadState uploadState;
  final String? driveFileId;
  final String? lastError;

  AntiTheftEvidence copyWith({
    EvidenceUploadState? uploadState,
    String? driveFileId,
    String? lastError,
    bool clearError = false,
  }) => AntiTheftEvidence(
    id: id,
    createdAt: createdAt,
    durationSeconds: durationSeconds,
    encryptedPath: encryptedPath,
    encryptedBytes: encryptedBytes,
    networkType: networkType,
    deviceSummary: deviceSummary,
    uploadState: uploadState ?? this.uploadState,
    driveFileId: driveFileId ?? this.driveFileId,
    lastError: clearError ? null : lastError ?? this.lastError,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'durationSeconds': durationSeconds,
    'encryptedPath': encryptedPath,
    'encryptedBytes': encryptedBytes,
    'networkType': networkType,
    'deviceSummary': deviceSummary,
    'uploadState': uploadState.name,
    'driveFileId': driveFileId,
    'lastError': lastError,
  };

  factory AntiTheftEvidence.fromJson(Map<String, Object?> json) {
    return AntiTheftEvidence(
      id: json['id']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      encryptedPath: json['encryptedPath']?.toString() ?? '',
      encryptedBytes: (json['encryptedBytes'] as num?)?.toInt() ?? 0,
      networkType: json['networkType']?.toString() ?? 'unknown',
      deviceSummary: json['deviceSummary']?.toString() ?? 'unknown',
      uploadState: EvidenceUploadState.values.firstWhere(
        (value) => value.name == json['uploadState']?.toString(),
        orElse: () => EvidenceUploadState.local,
      ),
      driveFileId: json['driveFileId']?.toString(),
      lastError: json['lastError']?.toString(),
    );
  }
}
