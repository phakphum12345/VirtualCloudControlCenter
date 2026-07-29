import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/models/risk_level.dart';
import 'action_helpers.dart';

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  bool microphone = true;
  bool systemAudio = false;
  String quality = '1080p';
  int fps = 30;
  int countdown = 3;

  Future<void> _screenshot() async {
    final result = await widget.controller.executeAction(
      createAction('screenshot.take', risk: RiskLevel.confirmationRequired),
      confirm: (action) => confirmAction(context, action),
    );
    if (mounted) showActionResult(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ตั้งค่าการบันทึก',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  value: microphone,
                  onChanged: (value) => setState(() => microphone = value),
                  title: const Text('ไมโครโฟน'),
                ),
                SwitchListTile(
                  value: systemAudio,
                  onChanged: (value) => setState(() => systemAudio = value),
                  title: const Text('เสียงจากระบบ'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    DropdownMenu<String>(
                      label: const Text('ความละเอียด'),
                      initialSelection: quality,
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: '720p', label: '720p'),
                        DropdownMenuEntry(value: '1080p', label: '1080p'),
                        DropdownMenuEntry(value: '1440p', label: '1440p'),
                      ],
                      onSelected: (value) =>
                          setState(() => quality = value ?? quality),
                    ),
                    DropdownMenu<int>(
                      label: const Text('FPS'),
                      initialSelection: fps,
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: 24, label: '24'),
                        DropdownMenuEntry(value: 30, label: '30'),
                        DropdownMenuEntry(value: 60, label: '60'),
                      ],
                      onSelected: (value) => setState(() => fps = value ?? fps),
                    ),
                    DropdownMenu<int>(
                      label: const Text('นับถอยหลัง'),
                      initialSelection: countdown,
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: 0, label: 'ไม่ใช้'),
                        DropdownMenuEntry(value: 3, label: '3 วินาที'),
                        DropdownMenuEntry(value: 5, label: '5 วินาที'),
                      ],
                      onSelected: (value) =>
                          setState(() => countdown = value ?? countdown),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: null,
                      icon: Icon(Icons.fiber_manual_record),
                      label: Text('เริ่มบันทึก'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _screenshot,
                      icon: const Icon(Icons.screenshot),
                      label: const Text('จับภาพหลังยืนยัน'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'ยังไม่มี native recorder adapter จึงไม่เปิดปุ่มและไม่รายงานว่าบันทึกสำเร็จ',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
