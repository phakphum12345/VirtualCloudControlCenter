enum Capability {
  systemStatus,
  fileSearch,
  screenRecording,
  screenshot,
  appLaunch,
  appControl,
  settingsLaunch,
  volumeControl,
  contentFiltering,
  antiTheftCamera,
  antiTheftUpload,
}

class CapabilityStatus {
  const CapabilityStatus({
    required this.capability,
    required this.available,
    required this.reason,
  });

  final Capability capability;
  final bool available;
  final String reason;
}
