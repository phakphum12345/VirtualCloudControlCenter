import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/audit_log/audit_entry.dart';
import '../core/anti_theft/anti_theft_config.dart';

class StorageService {
  static const _auditKey = 'audit_log_v1';
  static const _antiTheftKey = 'anti_theft_config_v1';

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

  Future<AntiTheftConfig> loadAntiTheftConfig() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_antiTheftKey);
    if (value == null) return const AntiTheftConfig();
    return AntiTheftConfig.fromJson(
      Map<String, Object?>.from(jsonDecode(value) as Map),
    );
  }

  Future<void> saveAntiTheftConfig(AntiTheftConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_antiTheftKey, jsonEncode(config.toJson()));
  }
}
