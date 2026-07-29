import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/models/risk_level.dart';
import 'action_helpers.dart';

class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  double _volume = 30;

  Future<void> _run(String page) async {
    final result = await widget.controller.executeAction(
      createAction('settings.open', parameters: {'page': page}),
      confirm: (action) => confirmAction(context, action),
    );
    if (mounted) showActionResult(context, result);
  }

  Future<void> _setVolume() async {
    final result = await widget.controller.executeAction(
      createAction(
        'settings.volume',
        parameters: {'percent': _volume.round()},
        risk: RiskLevel.confirmationRequired,
      ),
      confirm: (action) => confirmAction(context, action),
    );
    if (mounted) showActionResult(context, result);
  }

  @override
  Widget build(BuildContext context) {
    const pages = {
      'bluetooth': 'Bluetooth',
      'wifi': 'Wi-Fi',
      'microphone': 'ไมโครโฟน',
      'camera': 'กล้อง',
      'display': 'จอภาพ',
      'storage': 'พื้นที่จัดเก็บ',
      'battery': 'แบตเตอรี่',
      'notifications': 'การแจ้งเตือน',
      'sound': 'เสียง',
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Windows Settings allowlist',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final page in pages.entries)
              ActionChip(
                avatar: const Icon(Icons.open_in_new),
                label: Text(page.value),
                onPressed: () => _run(page.key),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text('ระดับเสียง ${_volume.round()}%'),
        Slider(
          value: _volume,
          divisions: 20,
          label: '${_volume.round()}%',
          onChanged: (value) => setState(() => _volume = value),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _setVolume,
            child: const Text('ยืนยันและเปลี่ยนระดับเสียง'),
          ),
        ),
      ],
    );
  }
}
