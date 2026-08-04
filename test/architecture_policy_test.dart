import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('architecture policy', () {
    test(
      'production source does not introduce banned backend integrations',
      () {
        final files = <File>[
          ..._dartFiles('lib'),
          File('pubspec.yaml'),
        ].where((file) => file.existsSync());

        const bannedPatterns = <String, String>{
          'laravel':
              'Laravel is outside the approved Flutter-only architecture.',
          'php artisan': 'PHP/Laravel commands are not allowed.',
          'googleapis/calendar': 'Google Calendar API is not approved.',
          'calendar/v3': 'Google Calendar API is not approved.',
          'firebase_core': 'Firebase requires explicit architecture approval.',
          'cloud_firestore': 'Firestore requires explicit architecture approval.',
        };

        final violations = <String>[];
        for (final file in files) {
          final content = file.readAsStringSync().toLowerCase();
          for (final entry in bannedPatterns.entries) {
            if (content.contains(entry.key)) {
              violations.add('${file.path}: ${entry.value}');
            }
          }
        }

        expect(violations, isEmpty, reason: violations.join('\n'));
      },
    );

    test('Windows ICO build input exists', () {
      expect(
        File('windows/runner/resources/app_icon.ico').existsSync(),
        isTrue,
        reason: 'Windows builds require app_icon.ico.',
      );
    });

    test('Flutter Web shell exists', () {
      expect(File('web/index.html').existsSync(), isTrue);
    });
  });
}

Iterable<File> _dartFiles(String rootPath) sync* {
  final root = Directory(rootPath);
  if (!root.existsSync()) return;

  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}
