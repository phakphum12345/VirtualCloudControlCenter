import '../core/models/risk_level.dart';

class RiskClassifier {
  const RiskClassifier();

  RiskLevel classify(String action) {
    if (action.startsWith('restricted.')) return RiskLevel.restricted;
    if (const {
      'screen_recording.start',
      'screenshot.take',
      'application.close',
      'application.restart',
      'settings.volume',
      'device.restart',
      'device.shutdown',
      'file.move_many',
    }.contains(action)) {
      return RiskLevel.confirmationRequired;
    }
    return RiskLevel.safe;
  }
}
