import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phakphum_ai_assistant/app/app.dart';
import 'package:phakphum_ai_assistant/app/app_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders dashboard and emergency stop', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dependencies = await AppDependencies.create();

    await tester.pumpWidget(PhakphumAiAssistant(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(find.text('สวัสดีครับ มีอะไรให้ช่วยบนอุปกรณ์นี้?'), findsOneWidget);
    expect(find.text('หยุดฉุกเฉิน'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });
}
