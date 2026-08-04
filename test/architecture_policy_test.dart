import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('architecture policy', () {
    test('banned integrations are absent', () {
      final files = <File>[];
      files.addAll(_dartFiles('lib'));
      files.add(File('pubspec.yaml'));

      const bannedPatterns = <String, String>{
        'laravel': 'Laravel is not approved.',
        'php artisan': 'PHP is not approved.',
        'googleapis/calendar': 'Calendar API is not approved.',
        'calendar/v3': 'Calendar API is not approved.',
        'firebase_core': 'Firebase is not approved.',
        'cloud_firestore': 'Firestore is not approved.',
      };

      final violations = <String>[];
      for (final file in files) {
        if (!file.existsSync()) {
          continue;
        }

        final content = file.readAsStringSync().toLowerCase();
        for (final entry in bannedPatterns.entries) {
          if (content.contains(entry.key)) {
            violations.add('${file.path}: ${entry.value}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: violations.join('\n'),
      );
    });

    test('Windows ICO build input exists', () {
      final icon = File(
        'windows/runner/resources/app_icon.ico',
      );
      expect(
        icon.existsSync(),
        isTrue,
        reason: 'Windows builds require app_icon.ico.',
      );
    });

    test('Flutter Web shell exists', () {
      final index = File('web/index.html');
      expect(index.existsSync(), isTrue);
    });
  });
}

Iterable<File> _dartFiles(String rootPath) sync* {
  final root = Directory(rootPath);
  if (!root.existsSync()) {
    return;
  }

  final entities = root.listSync(
    recursive: true,
    followLinks: false,
  );
  for (final entity in entities) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}
