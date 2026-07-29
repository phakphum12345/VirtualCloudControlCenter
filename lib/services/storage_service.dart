import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/audit_log/audit_entry.dart';

class StorageService {
  static const _auditKey = 'audit_log_v1';

  Future<List<AuditEntry>> loadAuditEntries() async {
    final preferences = await SharedPreferences.getInstance();
    final values = preferences.getStringList(_auditKey) ?? const [];
    return values
        .map(
          (value) => AuditEntry.fromJson(
            Map<String, Object?>.from(jsonDecode(value) as Map),
          ),
        )
        .toList();
  }

  Future<void> saveAuditEntries(List<AuditEntry> entries) async {
    final preferences = await SharedPreferences.getInstance();
    final values = entries
        .take(200)
        .map((entry) => jsonEncode(entry.toJson()))
        .toList();
    await preferences.setStringList(_auditKey, values);
  }
}
