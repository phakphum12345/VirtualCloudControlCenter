import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import 'anti_theft_camera_panel.dart';
import 'app_shell.dart';

class OwnerLockGate extends StatefulWidget {
  const OwnerLockGate({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<OwnerLockGate> createState() => _OwnerLockGateState();
}

class _OwnerLockGateState extends State<OwnerLockGate> {
  final _pin = TextEditingController();
  bool _unlocked = false;
  bool _cameraVisible = false;
  bool _checking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.dependencies.antiTheftController.config.enabled) {
      unawaited(widget.dependencies.antiTheftController.initializeDrive());
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await widget.dependencies.antiTheftController.verifyPin(
      _pin.text,
    );
    _pin.clear();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _unlocked = result.accepted;
      _cameraVisible = result.triggerRequested;
      _message = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.dependencies.antiTheftController;
    if (!controller.config.enabled || _unlocked) {
      return AppShell(dependencies: widget.dependencies);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('ยืนยันเจ้าของอุปกรณ์')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.phonelink_lock, size: 64),
          const SizedBox(height: 16),
          Text(
            'แอปถูกล็อกด้วย Owner-enabled Anti-Theft Mode',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'กรอก PIN เจ้าของเพื่อเข้าแอป หน้านี้ไม่แทนหน้าจอล็อกของระบบ '
            'และไม่ปิดกั้น Power หรือ Emergency call',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _verify(),
            decoration: const InputDecoration(
              labelText: 'PIN เจ้าของ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _checking ? null : _verify,
            icon: const Icon(Icons.lock_open),
            label: Text(_checking ? 'กำลังตรวจสอบ' : 'ปลดล็อก'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, textAlign: TextAlign.center),
          ],
          if (_cameraVisible) ...[
            const SizedBox(height: 16),
            AntiTheftCameraPanel(
              controller: controller,
              recordingSeconds: controller.config.recordingSeconds,
              onClosed: () {
                if (mounted) setState(() => _cameraVisible = false);
              },
            ),
          ],
        ],
      ),
    );
  }
}
