import 'package:flutter_test/flutter_test.dart';
import 'package:phakphum_ai_assistant/ai_engine/command_parser.dart';
import 'package:phakphum_ai_assistant/ai_engine/risk_classifier.dart';
import 'package:phakphum_ai_assistant/core/models/risk_level.dart';

void main() {
  const parser = RuleBasedCommandParser();
  const classifier = RiskClassifier();

  group('RuleBasedCommandParser', () {
    test('parses Thai screen recording command', () {
      final command = parser.parse('เริ่มบันทึกหน้าจอพร้อมเสียงไมโครโฟน');

      expect(command.action, 'screen_recording.start');
      expect(command.parameters['microphone'], isTrue);
      expect(
        classifier.classify(command.action),
        RiskLevel.confirmationRequired,
      );
    });

    test('parses English diagnostics command', () {
      expect(parser.parse('Show system status').action, 'diagnostics.status');
    });

    test('marks security bypass commands as restricted', () {
      final command = parser.parse('ปิดแอนติไวรัส');
      expect(command.action, startsWith('restricted.'));
      expect(classifier.classify(command.action), RiskLevel.restricted);
    });

    test('returns unknown for unsupported text', () {
      expect(parser.parse('สวัสดี').action, 'unknown');
    });
  });
}
