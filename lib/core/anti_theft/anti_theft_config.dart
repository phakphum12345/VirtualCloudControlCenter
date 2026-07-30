class AntiTheftConfig {
  const AntiTheftConfig({
    this.enabled = false,
    this.pinSalt = '',
    this.pinHash = '',
    this.pinKdf = 'sha256',
    this.failedAttemptThreshold = 3,
    this.recordingSeconds = 180,
    this.uploadOnWifiOnly = true,
    this.destination = AntiTheftDestination.localOnly,
    this.retentionDays = 30,
    this.maximumClips = 20,
  });

  final bool enabled;
  final String pinSalt;
  final String pinHash;
  final String pinKdf;
  final int failedAttemptThreshold;
  final int recordingSeconds;
  final bool uploadOnWifiOnly;
  final AntiTheftDestination destination;
  final int retentionDays;
  final int maximumClips;

  bool get hasPin => pinSalt.isNotEmpty && pinHash.isNotEmpty;

  AntiTheftConfig copyWith({
    bool? enabled,
    String? pinSalt,
    String? pinHash,
    String? pinKdf,
    int? failedAttemptThreshold,
    int? recordingSeconds,
    bool? uploadOnWifiOnly,
    AntiTheftDestination? destination,
    int? retentionDays,
    int? maximumClips,
  }) => AntiTheftConfig(
    enabled: enabled ?? this.enabled,
    pinSalt: pinSalt ?? this.pinSalt,
    pinHash: pinHash ?? this.pinHash,
    pinKdf: pinKdf ?? this.pinKdf,
    failedAttemptThreshold:
        failedAttemptThreshold ?? this.failedAttemptThreshold,
    recordingSeconds: recordingSeconds ?? this.recordingSeconds,
    uploadOnWifiOnly: uploadOnWifiOnly ?? this.uploadOnWifiOnly,
    destination: destination ?? this.destination,
    retentionDays: retentionDays ?? this.retentionDays,
    maximumClips: maximumClips ?? this.maximumClips,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'pinSalt': pinSalt,
    'pinHash': pinHash,
    'pinKdf': pinKdf,
    'failedAttemptThreshold': failedAttemptThreshold,
    'recordingSeconds': recordingSeconds,
    'uploadOnWifiOnly': uploadOnWifiOnly,
    'destination': destination.name,
    'retentionDays': retentionDays,
    'maximumClips': maximumClips,
  };

  factory AntiTheftConfig.fromJson(Map<String, Object?> json) {
    final destinationName = json['destination']?.toString();
    return AntiTheftConfig(
      enabled: json['enabled'] == true,
      pinSalt: json['pinSalt']?.toString() ?? '',
      pinHash: json['pinHash']?.toString() ?? '',
      pinKdf: json['pinKdf']?.toString() ?? 'sha256',
      failedAttemptThreshold:
          (json['failedAttemptThreshold'] as num?)?.toInt() ?? 3,
      recordingSeconds: (json['recordingSeconds'] as num?)?.toInt() ?? 180,
      uploadOnWifiOnly: json['uploadOnWifiOnly'] != false,
      destination: AntiTheftDestination.values.firstWhere(
        (value) => value.name == destinationName,
        orElse: () => AntiTheftDestination.localOnly,
      ),
      retentionDays: (json['retentionDays'] as num?)?.toInt() ?? 30,
      maximumClips: (json['maximumClips'] as num?)?.toInt() ?? 20,
    );
  }
}

enum AntiTheftDestination { localOnly, googleDrive }
