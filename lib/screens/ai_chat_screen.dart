import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/actions/assistant_action.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    await widget.controller.executeCommand(text, confirm: _confirm);
    if (mounted) setState(() {});
  }

  Future<bool> _confirm(AssistantAction action) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('ยืนยันการทำงาน'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('แผน: ${action.action}'),
                const SizedBox(height: 8),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(action.toJson()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('ยืนยัน'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final result = widget.controller.lastResult;
        final planned = widget.controller.plannedAction;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _textController,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'คำสั่งภาษาไทยหรืออังกฤษ',
                hintText: 'เช่น แสดงสถานะระบบ',
                suffixIcon: IconButton(
                  tooltip: 'ส่งคำสั่ง',
                  onPressed: widget.controller.isBusy ? null : _submit,
                  icon: const Icon(Icons.send),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('แสดงสถานะระบบ')),
                Chip(label: Text('เริ่มบันทึกหน้าจอพร้อมไมโครโฟน')),
                Chip(label: Text('เปิด Bluetooth')),
              ],
            ),
            if (widget.controller.isBusy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (planned != null) ...[
              const SizedBox(height: 24),
              Text('แผนล่าสุด', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    const JsonEncoder.withIndent(
                      '  ',
                    ).convert(planned.toJson()),
                  ),
                ),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Card(
                color: result.success
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(
                    result.success ? Icons.check_circle : Icons.info,
                  ),
                  title: Text(result.success ? 'สำเร็จ' : 'ไม่สำเร็จ'),
                  subtitle: Text(result.message),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
