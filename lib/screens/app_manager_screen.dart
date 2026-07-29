import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/models/risk_level.dart';
import 'action_helpers.dart';

class AppManagerScreen extends StatefulWidget {
  const AppManagerScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<AppManagerScreen> createState() => _AppManagerScreenState();
}

class _AppManagerScreenState extends State<AppManagerScreen> {
  List<Map<String, Object?>> _processes = const [];
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await widget.controller.executeAction(
      createAction('application.list'),
      confirm: (action) => confirmAction(context, action),
    );
    if (!mounted) return;
    final items = result.details['items'];
    setState(() {
      _loading = false;
      _processes = items is List
          ? items
                .whereType<Map>()
                .map((item) => Map<String, Object?>.from(item))
                .toList()
          : const [];
    });
    showActionResult(context, result);
  }

  Future<void> _close(Map<String, Object?> process) async {
    final result = await widget.controller.executeAction(
      createAction(
        'application.close',
        parameters: {'pid': process['pid']},
        risk: RiskLevel.confirmationRequired,
      ),
      confirm: (action) => confirmAction(context, action),
    );
    if (!mounted) return;
    showActionResult(context, result);
    if (result.success) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Windows processes เรียงตาม RAM',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('อ่านข้อมูลจริง'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _processes.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('กดอ่านข้อมูลจริงบน Windows'),
              subtitle: Text('แพลตฟอร์มอื่นจะรายงานว่าไม่รองรับ'),
            ),
          ),
        if (_processes.isNotEmpty)
          Card(
            child: Column(
              children: [
                for (final process in _processes.take(100))
                  ListTile(
                    leading: const Icon(Icons.apps),
                    title: Text(process['name']?.toString() ?? 'Unknown'),
                    subtitle: Text('PID ${process['pid']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_bytes(process['memoryBytes'])),
                        IconButton(
                          tooltip: 'ปิดหลังยืนยัน',
                          onPressed: () => _close(process),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _bytes(Object? raw) {
    final bytes = raw is num ? raw.toDouble() : 0;
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
