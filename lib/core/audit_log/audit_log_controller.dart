import 'package:flutter/foundation.dart';

import '../../services/storage_service.dart';
import 'audit_entry.dart';

class AuditLogController extends ChangeNotifier {
  AuditLogController(this._storage);

  final StorageService _storage;
  final List<AuditEntry> _entries = [];

  List<AuditEntry> get entries => List.unmodifiable(_entries);

  Future<void> initialize() async {
    _entries
      ..clear()
      ..addAll(await _storage.loadAuditEntries());
    notifyListeners();
  }

  Future<void> add(AuditEntry entry) async {
    _entries.insert(0, entry);
    if (_entries.length > 200) _entries.removeLast();
    notifyListeners();
    await _storage.saveAuditEntries(_entries);
  }
}
