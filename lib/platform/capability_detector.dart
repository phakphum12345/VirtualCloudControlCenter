import 'package:flutter/foundation.dart';

import '../core/capabilities/capability.dart';

class CapabilityDetector {
  const CapabilityDetector();

  String get platformName {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  List<CapabilityStatus> detect() {
    final windows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    return [
      CapabilityStatus(
        capability: Capability.systemStatus,
        available: true,
        reason: windows
            ? 'Windows memory, disk, CPU, and process APIs are connected.'
            : 'Basic platform identity is available.',
      ),
      CapabilityStatus(
        capability: Capability.fileSearch,
        available: windows,
        reason: windows
            ? 'Windows large-file search is available.'
            : 'A native file adapter has not been installed.',
      ),
      const CapabilityStatus(
        capability: Capability.screenRecording,
        available: false,
        reason: 'A native recorder adapter has not been installed.',
      ),
      CapabilityStatus(
        capability: Capability.screenshot,
        available: windows,
        reason: windows
            ? 'Visible Windows desktop screenshots are available.'
            : 'A native capture adapter has not been installed.',
      ),
      CapabilityStatus(
        capability: Capability.appLaunch,
        available: windows,
        reason: windows
            ? 'Allowlisted Windows applications can be opened.'
            : 'A native application adapter has not been installed.',
      ),
      CapabilityStatus(
        capability: Capability.appControl,
        available: windows,
        reason: windows
            ? 'Windows processes can be inspected and confirmed before closing.'
            : 'A native process adapter has not been installed.',
      ),
      CapabilityStatus(
        capability: Capability.settingsLaunch,
        available: windows,
        reason: windows
            ? 'Allowlisted Windows Settings pages can be opened.'
            : 'A native settings adapter has not been installed.',
      ),
      CapabilityStatus(
        capability: Capability.volumeControl,
        available: windows,
        reason: windows
            ? 'Windows default output volume control is available.'
            : 'A native audio adapter has not been installed.',
      ),
      const CapabilityStatus(
        capability: Capability.contentFiltering,
        available: false,
        reason: 'Content filtering is planned for a later phase.',
      ),
    ];
  }
}
