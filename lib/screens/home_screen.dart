import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../app/routes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.dependencies,
    required this.onNavigate,
    super.key,
  });

  final AppDependencies dependencies;
  final ValueChanged<AppSection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final capabilities = dependencies.capabilityDetector.detect();
    final available = capabilities.where((item) => item.available).length;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'สวัสดีครับ มีอะไรให้ช่วยบนอุปกรณ์นี้?',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'ระบบจะแจ้งแผน ขออนุญาตเมื่อจำเป็น และรายงานผลจริงจาก platform adapter เท่านั้น',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Card(
          child: InkWell(
            onTap: () => onNavigate(AppSection.assistant),
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 32),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'พิมพ์คำสั่งภาษาไทยหรืออังกฤษ',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  Icon(Icons.arrow_forward),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 600
                ? constraints.maxWidth
                : (constraints.maxWidth - 16) / 2;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _StatusCard(
                  width: width,
                  title: 'แพลตฟอร์ม',
                  value: dependencies.capabilityDetector.platformName,
                  icon: Icons.devices,
                ),
                _StatusCard(
                  width: width,
                  title: 'ความสามารถที่พร้อม',
                  value: '$available / ${capabilities.length}',
                  icon: Icons.fact_check_outlined,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text('ทางลัด', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              [
                    _Shortcut(
                      'บันทึกหน้าจอ',
                      Icons.videocam,
                      AppSection.recorder,
                    ),
                    _Shortcut('จัดการแอป', Icons.apps, AppSection.applications),
                    _Shortcut('จัดการไฟล์', Icons.folder, AppSection.files),
                    _Shortcut(
                      'ตรวจระบบ',
                      Icons.monitor_heart,
                      AppSection.diagnostics,
                    ),
                  ]
                  .map(
                    (item) => ActionChip(
                      avatar: Icon(item.icon),
                      label: Text(item.label),
                      onPressed: () => onNavigate(item.section),
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
  });

  final double width;
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 30),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(title), Text(value)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.icon, this.section);
  final String label;
  final IconData icon;
  final AppSection section;
}
