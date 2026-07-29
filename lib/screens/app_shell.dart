import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../app/routes.dart';
import 'ai_chat_screen.dart';
import 'app_manager_screen.dart';
import 'diagnostics_screen.dart';
import 'file_manager_screen.dart';
import 'home_screen.dart';
import 'permission_center_screen.dart';
import 'privacy_screen.dart';
import 'recorder_screen.dart';
import 'system_settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _section = AppSection.home;

  void _select(AppSection value) {
    setState(() => _section = value);
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: Text(_section.label),
        actions: [
          AnimatedBuilder(
            animation: widget.dependencies.appController.emergencyStop,
            builder: (context, _) {
              final stopped =
                  widget.dependencies.appController.emergencyStop.isStopped;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: stopped
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.error,
                  ),
                  onPressed: stopped
                      ? widget.dependencies.appController.resumeOperations
                      : widget.dependencies.appController.triggerEmergencyStop,
                  icon: Icon(stopped ? Icons.play_arrow : Icons.stop_circle),
                  label: Text(stopped ? 'เปิดระบบอีกครั้ง' : 'หยุดฉุกเฉิน'),
                ),
              );
            },
          ),
        ],
      ),
      drawer: wide ? null : Drawer(child: _NavigationList(onSelect: _select)),
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 250,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: _NavigationList(selected: _section, onSelect: _select),
              ),
            ),
          Expanded(child: _currentScreen()),
        ],
      ),
    );
  }

  Widget _currentScreen() => switch (_section) {
    AppSection.home => HomeScreen(
      dependencies: widget.dependencies,
      onNavigate: _select,
    ),
    AppSection.assistant => AiChatScreen(
      controller: widget.dependencies.appController,
    ),
    AppSection.recorder => RecorderScreen(
      controller: widget.dependencies.appController,
    ),
    AppSection.applications => AppManagerScreen(
      controller: widget.dependencies.appController,
    ),
    AppSection.files => FileManagerScreen(
      controller: widget.dependencies.appController,
    ),
    AppSection.settings => SystemSettingsScreen(
      controller: widget.dependencies.appController,
    ),
    AppSection.diagnostics => DiagnosticsScreen(
      detector: widget.dependencies.capabilityDetector,
      controller: widget.dependencies.appController,
    ),
    AppSection.permissions => PermissionCenterScreen(
      detector: widget.dependencies.capabilityDetector,
      auditLog: widget.dependencies.appController.auditLog,
    ),
    AppSection.privacy => const PrivacyScreen(),
  };
}

class _NavigationList extends StatelessWidget {
  const _NavigationList({
    required this.onSelect,
    this.selected = AppSection.home,
  });

  final AppSection selected;
  final ValueChanged<AppSection> onSelect;

  static const icons = {
    AppSection.home: Icons.dashboard_outlined,
    AppSection.assistant: Icons.auto_awesome_outlined,
    AppSection.recorder: Icons.videocam_outlined,
    AppSection.applications: Icons.apps,
    AppSection.files: Icons.folder_outlined,
    AppSection.settings: Icons.settings_outlined,
    AppSection.diagnostics: Icons.monitor_heart_outlined,
    AppSection.permissions: Icons.shield_outlined,
    AppSection.privacy: Icons.visibility_off_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          const ListTile(
            leading: CircleAvatar(child: Icon(Icons.smart_toy_outlined)),
            title: Text('Phakphum AI'),
            subtitle: Text('System Assistant'),
          ),
          const Divider(),
          for (final section in AppSection.values)
            ListTile(
              selected: section == selected,
              leading: Icon(icons[section]),
              title: Text(section.label),
              onTap: () => onSelect(section),
            ),
        ],
      ),
    );
  }
}
