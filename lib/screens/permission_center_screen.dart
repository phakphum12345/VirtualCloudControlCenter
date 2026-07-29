import 'package:flutter/material.dart';

import '../core/audit_log/audit_log_controller.dart';
import '../platform/capability_detector.dart';

class PermissionCenterScreen extends StatelessWidget {
  const PermissionCenterScreen({
    required this.detector,
    required this.auditLog,
    super.key,
  });

  final CapabilityDetector detector;
  final AuditLogController auditLog;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auditLog,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Safety & Permission Center',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'คำสั่งสำคัญต้องยืนยัน คำสั่งต้องห้ามจะถูกบล็อก และทุกผลลัพธ์ถูกบันทึกไว้ในเครื่อง',
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                for (final item in detector.detect())
                  ListTile(
                    leading: Icon(
                      item.available ? Icons.verified_user : Icons.lock_outline,
                    ),
                    title: Text(item.capability.name),
                    subtitle: Text(item.reason),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('กิจกรรมล่าสุด', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (auditLog.entries.isEmpty)
            const Card(child: ListTile(title: Text('ยังไม่มีกิจกรรม')))
          else
            Card(
              child: Column(
                children: [
                  for (final entry in auditLog.entries.take(20))
                    ListTile(
                      leading: Icon(
                        entry.success ? Icons.check_circle : Icons.info_outline,
                      ),
                      title: Text(entry.action),
                      subtitle: Text(entry.message),
                      trailing: Text(
                        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                        '${entry.timestamp.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
