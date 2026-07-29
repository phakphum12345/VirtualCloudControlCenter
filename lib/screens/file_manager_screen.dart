import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import 'action_helpers.dart';

class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  List<Map<String, Object?>> _files = const [];
  bool _loading = false;

  Future<void> _search() async {
    setState(() => _loading = true);
    final result = await widget.controller.executeAction(
      createAction('file.search_large'),
      confirm: (action) => confirmAction(context, action),
    );
    if (!mounted) return;
    final items = result.details['items'];
    setState(() {
      _loading = false;
      _files = items is List
          ? items
                .whereType<Map>()
                .map((item) => Map<String, Object?>.from(item))
                .toList()
          : const [];
    });
    showActionResult(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Expanded(child: Text('ค้นหาไฟล์ตั้งแต่ 10 MB ใน Downloads')),
            FilledButton.icon(
              onPressed: _loading ? null : _search,
              icon: const Icon(Icons.manage_search),
              label: const Text('ค้นหา'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _files.isEmpty)
          const Card(
            child: ListTile(
              title: Text('ยังไม่มีผลการค้นหา'),
              subtitle: Text('การค้นหาจะข้ามโฟลเดอร์ที่ Windows ไม่อนุญาต'),
            ),
          ),
        if (_files.isNotEmpty)
          Card(
            child: Column(
              children: [
                for (final file in _files)
                  ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(file['path']?.toString() ?? ''),
                    trailing: Text(_bytes(file['sizeBytes'])),
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
