import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../platform/capability_detector.dart';
import 'action_helpers.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    required this.detector,
    required this.controller,
    super.key,
  });

  final CapabilityDetector detector;
  final AppController controller;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, Object?> _status = const {};

  Future<void> _refresh() async {
    final result = await widget.controller.executeAction(
      createAction('diagnostics.status'),
      confirm: (action) => confirmAction(context, action),
    );
    if (!mounted) return;
    setState(() => _status = result.details);
    showActionResult(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = widget.detector.detect();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ListTile(
          leading: const Icon(Icons.computer),
          title: Text('แพลตฟอร์ม: ${widget.detector.platformName}'),
          subtitle: const Text('ตรวจจาก Flutter runtime'),
          trailing: FilledButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('อ่านสถานะจริง'),
          ),
        ),
        if (_status.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  for (final item in _status.entries)
                    if (item.key != 'success')
                      Chip(label: Text('${item.key}: ${item.value}')),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (final item in capabilities)
                ListTile(
                  leading: Icon(
                    item.available ? Icons.check_circle : Icons.cancel_outlined,
                    color: item.available ? Colors.green : Colors.orange,
                  ),
                  title: Text(item.capability.name),
                  subtitle: Text(item.reason),
                  trailing: Text(item.available ? 'พร้อม' : 'ไม่พร้อม'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
