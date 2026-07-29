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
  bool microphone = false;
  bool systemAudio = false;
  String quality = '1080p';
  int fps = 30;
  int countdown = 3;
  bool recording = false;
  bool paused = false;
  bool starting = false;
  int countdownRemaining = 0;
  String? outputFile;
  final List<String> history = [];

  Future<void> _start() async {
    final action = createAction(
      'screen_recording.start',
      parameters: {
        'source': 'display',
        'microphone': microphone,
        'systemAudio': systemAudio,
        'quality': quality,
        'fps': fps,
        'countdownSeconds': countdown,
      },
      risk: RiskLevel.confirmationRequired,
    );
    if (!await confirmAction(context, action) || !mounted) return;
    setState(() {
      starting = true;
      countdownRemaining = countdown;
    });
    while (countdownRemaining > 0 && mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => countdownRemaining--);
    }
    if (!mounted) return;
    final result = await widget.controller.executeAction(
      action,
      confirm: (_) async => true,
    );
    if (!mounted) return;
    setState(() {
      starting = false;
      recording = result.success;
      paused = false;
      outputFile = result.details['outputFile']?.toString();
    });
    showActionResult(context, result);
  }

  Future<void> _control(String name) async {
    final result = await widget.controller.executeAction(
      createAction(name),
      confirm: (action) => confirmAction(context, action),
    );
    if (!mounted) return;
    setState(() {
      if (name == 'screen_recording.pause' && result.success) paused = true;
      if (name == 'screen_recording.resume' && result.success) paused = false;
      if (name == 'screen_recording.stop' && result.success) {
        recording = false;
        paused = false;
        outputFile = result.details['outputFile']?.toString() ?? outputFile;
        if (outputFile != null && !history.contains(outputFile)) {
          history.insert(0, outputFile!);
        }
      }
    });
    showActionResult(context, result);
  }

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
                if (recording || starting)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: Icon(
                        starting
                            ? Icons.timer_outlined
                            : paused
                            ? Icons.pause_circle
                            : Icons.fiber_manual_record,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        starting
                            ? 'เริ่มใน $countdownRemaining วินาที'
                            : paused
                            ? 'พักการบันทึก'
                            : 'กำลังบันทึกหน้าจอ',
                      ),
                      subtitle: outputFile == null ? null : Text(outputFile!),
                    ),
                  ),
                SwitchListTile(
                  value: microphone,
                  onChanged: recording || starting
                      ? null
                      : (value) => setState(() => microphone = value),
                  title: const Text('ไมโครโฟน'),
                  subtitle: const Text(
                    'Windows capture backend รุ่นนี้ยังไม่รองรับ',
                  ),
                ),
                SwitchListTile(
                  value: systemAudio,
                  onChanged: recording || starting
                      ? null
                      : (value) => setState(() => systemAudio = value),
                  title: const Text('เสียงจากระบบ'),
                  subtitle: const Text(
                    'Windows capture backend รุ่นนี้ยังไม่รองรับ',
                  ),
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
                      onPressed: recording || starting ? null : _start,
                      icon: Icon(Icons.fiber_manual_record),
                      label: Text('เริ่มบันทึก'),
                    ),
                    OutlinedButton.icon(
                      onPressed: !recording
                          ? null
                          : () => _control(
                              paused
                                  ? 'screen_recording.resume'
                                  : 'screen_recording.pause',
                            ),
                      icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                      label: Text(paused ? 'บันทึกต่อ' : 'พัก'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: !recording
                          ? null
                          : () => _control('screen_recording.stop'),
                      icon: const Icon(Icons.stop),
                      label: const Text('หยุดและบันทึกไฟล์'),
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
                  'รองรับวิดีโอเต็มจอแบบ H.264 MP4 เฉพาะ Windows; '
                  'หากเลือกเสียง ระบบจะปฏิเสธอย่างชัดเจน',
                ),
              ],
            ),
          ),
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('ประวัติไฟล์', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final file in history)
                  ListTile(
                    leading: const Icon(Icons.video_file_outlined),
                    title: Text(file),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
