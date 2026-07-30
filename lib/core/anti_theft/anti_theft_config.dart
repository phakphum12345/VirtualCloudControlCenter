class AntiTheftConfig {
  const AntiTheftConfig({
    this.enabled = false,
    this.pinSalt = '',
    this.pinHash = '',
    this.failedAttemptThreshold = 3,
    this.recordingSeconds = 180,
    this.uploadOnWifiOnly = true,
    this.destination = AntiTheftDestination.localOnly,
  });

  final bool enabled;
  final String pinSalt;
  final String pinHash;
  final int failedAttemptThreshold;
  final int recordingSeconds;
  final bool uploadOnWifiOnly;
  final AntiTheftDestination destination;

  bool get hasPin => pinSalt.isNotEmpty && pinHash.isNotEmpty;

  AntiTheftConfig copyWith({
    bool? enabled,
    String? pinSalt,
    String? pinHash,
    int? failedAttemptThreshold,
    int? recordingSeconds,
    bool? uploadOnWifiOnly,
    AntiTheftDestination? destination,
  }) => AntiTheftConfig(
    enabled: enabled ?? this.enabled,
    pinSalt: pinSalt ?? this.pinSalt,
    pinHash: pinHash ?? this.pinHash,
    failedAttemptThreshold:
        failedAttemptThreshold ?? this.failedAttemptThreshold,
    recordingSeconds: recordingSeconds ?? this.recordingSeconds,
    uploadOnWifiOnly: uploadOnWifiOnly ?? this.uploadOnWifiOnly,
    destination: destination ?? this.destination,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'pinSalt': pinSalt,
    'pinHash': pinHash,
    'failedAttemptThreshold': failedAttemptThreshold,
    'recordingSeconds': recordingSeconds,
    'uploadOnWifiOnly': uploadOnWifiOnly,
    'destination': destination.name,
  };

  factory AntiTheftConfig.fromJson(Map<String, Object?> json) {
    final destinationName = json['destination']?.toString();
    return AntiTheftConfig(
      enabled: json['enabled'] == true,
      pinSalt: json['pinSalt']?.toString() ?? '',
      pinHash: json['pinHash']?.toString() ?? '',
      failedAttemptThreshold:
          (json['failedAttemptThreshold'] as num?)?.toInt() ?? 3,
      recordingSeconds: (json['recordingSeconds'] as num?)?.toInt() ?? 180,
      uploadOnWifiOnly: json['uploadOnWifiOnly'] != false,
      destination: AntiTheftDestination.values.firstWhere(
        (value) => value.name == destinationName,
        orElse: () => AntiTheftDestination.localOnly,
      ),
    );
  }
}

enum AntiTheftDestination { localOnly, googleDrive }
