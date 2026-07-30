import 'package:flutter/material.dart';

import '../screens/app_shell.dart';
import 'app_dependencies.dart';
import 'theme.dart';

class PhakphumAiAssistant extends StatelessWidget {
  const PhakphumAiAssistant({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phakphum AI System Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: AppShell(dependencies: dependencies),
    );
  }
}
