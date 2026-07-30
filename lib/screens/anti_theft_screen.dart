import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/anti_theft/anti_theft_controller.dart';
import '../core/anti_theft/anti_theft_evidence.dart';
import 'anti_theft_camera_panel.dart';

class AntiTheftScreen extends StatefulWidget {
  const AntiTheftScreen({required this.controller, super.key});

  final AntiTheftController controller;

  @override
  State<AntiTheftScreen> createState() => _AntiTheftScreenState();
}

class _AntiTheftScreenState extends State<AntiTheftScreen> {
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();
  final _testPin = TextEditingController();
  bool _cameraVisible = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initializeDrive());
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirmPin.dispose();
    _testPin.dispose();
    super.dispose();
  }

  Future<void> _setPin() async {
    if (_pin.text != _confirmPin.text) {
      _message('PIN ทั้งสองช่องไม่ตรงกัน');
      return;
    }
    try {
      await widget.controller.setPin(_pin.text);
      _pin.clear();
      _confirmPin.clear();
      _message('ตั้ง PIN แล้ว กรุณาเปิดสวิตช์เมื่อพร้อม');
    } on FormatException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _update({bool? enabled}) async {
    try {
      await widget.controller.update(enabled: enabled);
    } on StateError catch (error) {
      _message(error.message);
    }
  }

  Future<void> _testAttempt() async {
    final result = await widget.controller.verifyPin(_testPin.text);
    _testPin.clear();
    if (result.triggerRequested && mounted) {
      setState(() => _cameraVisible = true);
    }
    _message(result.message);
  }

  Future<void> _connectDrive() async {
    try {
      final email = await widget.controller.connectGoogleDrive();
      _message('เชื่อม Google Drive ด้วย $email แล้ว');
    } catch (error) {
      _message('เชื่อม Google Drive ไม่สำเร็จ: $error');
    }
  }

  Future<void> _export(String id) async {
    String? path;
    try {
      path = await widget.controller.decryptForExport(id);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Anti-theft evidence $id'),
      );
    } catch (error) {
      _message('เปิดหลักฐานไม่สำเร็จ: $error');
    } finally {
      if (path != null) {
        final temporary = File(path);
        if (await temporary.exists()) await temporary.delete();
      }
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบหลักฐานในเครื่อง'),
        content: const Text(
          'การลบนี้ย้อนกลับไม่ได้ และไม่ลบสำเนาที่อัปโหลดไป Google Drive แล้ว',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.deleteEvidence(id);
  }

  void _message(Object? value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value?.toString() ?? 'เกิดข้อผิดพลาด')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final config = widget.controller.config;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'โหมดป้องกันการขโมย',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'เจ้าของต้องเปิดใช้งานเอง ระบบจะไม่ปิดกั้นปุ่ม Power, '
              'การล็อกหน้าจอ หรือการโทรฉุกเฉิน และจะไม่แอบเปิดกล้อง',
            ),
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('สถานะกล้องและ Google Drive'),
                subtitle: Text(
                  'กล้องพร้อมทำงานเมื่อแอปอยู่ด้านหน้าและผู้ใช้ให้สิทธิ์ '
                  '${widget.controller.driveAccountEmail == null ? 'Google Drive ยังไม่เชื่อม' : 'Drive: ${widget.controller.driveAccountEmail}'}',
                ),
              ),
            ),
            if (_cameraVisible)
              AntiTheftCameraPanel(
                controller: widget.controller,
                recordingSeconds: config.recordingSeconds,
                onClosed: () {
                  if (mounted) setState(() => _cameraVisible = false);
                },
              ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    value: config.enabled,
                    onChanged: (value) => _update(enabled: value),
                    title: const Text('เปิดโหมดป้องกันการขโมย'),
                    subtitle: Text(
                      config.hasPin
                          ? 'PIN เจ้าของถูกจัดเก็บเป็น salted hash'
                          : 'ต้องตั้ง PIN ก่อนเปิดใช้งาน',
                    ),
                  ),
                  ListTile(
                    title: const Text('จำนวน PIN ผิดก่อนสร้างเหตุการณ์'),
                    subtitle: Slider(
                      value: config.failedAttemptThreshold.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '${config.failedAttemptThreshold} ครั้ง',
                      onChanged: (value) => widget.controller.update(
                        failedAttemptThreshold: value.round(),
                      ),
                    ),
                    trailing: Text('${config.failedAttemptThreshold} ครั้ง'),
                  ),
                  ListTile(
                    title: const Text('ระยะเวลาคลิปที่ต้องการ'),
                    subtitle: Slider(
                      value: config.recordingSeconds.toDouble(),
                      min: 30,
                      max: 180,
                      divisions: 5,
                      label: '${config.recordingSeconds} วินาที',
                      onChanged: (value) => widget.controller.update(
                        recordingSeconds: value.round(),
                      ),
                    ),
                    trailing: Text('${config.recordingSeconds} วินาที'),
                  ),
                  SwitchListTile(
                    value: config.uploadOnWifiOnly,
                    onChanged: (value) =>
                        widget.controller.update(uploadOnWifiOnly: value),
                    title: const Text('อัปโหลดเมื่อใช้ Wi‑Fi เท่านั้น'),
                  ),
                  ListTile(
                    leading: Icon(
                      widget.controller.driveAccountEmail == null
                          ? Icons.cloud_off_outlined
                          : Icons.cloud_done_outlined,
                    ),
                    title: Text(
                      widget.controller.driveAccountEmail == null
                          ? 'เก็บในเครื่องเท่านั้น'
                          : 'อัปโหลดสำเนาเข้ารหัสไป Google Drive',
                    ),
                    subtitle: Text(
                      widget.controller.driveAccountEmail ??
                          'เจ้าของต้องเลือกบัญชีและอนุมัติสิทธิ์ก่อน',
                    ),
                    trailing: widget.controller.driveAccountEmail == null
                        ? FilledButton.tonal(
                            onPressed: _connectDrive,
                            child: const Text('เชื่อม Drive'),
                          )
                        : TextButton(
                            onPressed: widget.controller.disconnectGoogleDrive,
                            child: const Text('ยกเลิกการเชื่อม'),
                          ),
                  ),
                  ListTile(
                    title: const Text('เก็บหลักฐานนานที่สุด'),
                    subtitle: Slider(
                      value: config.retentionDays.toDouble(),
                      min: 1,
                      max: 90,
                      divisions: 89,
                      label: '${config.retentionDays} วัน',
                      onChanged: (value) => widget.controller.update(
                        retentionDays: value.round(),
                      ),
                    ),
                    trailing: Text('${config.retentionDays} วัน'),
                  ),
                  ListTile(
                    title: const Text('จำนวนคลิปสูงสุด'),
                    subtitle: Slider(
                      value: config.maximumClips.toDouble(),
                      min: 1,
                      max: 50,
                      divisions: 49,
                      label: '${config.maximumClips} คลิป',
                      onChanged: (value) =>
                          widget.controller.update(maximumClips: value.round()),
                    ),
                    trailing: Text('${config.maximumClips} คลิป'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ตั้ง PIN เจ้าของ',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'PIN ใหม่ 6–12 หลัก',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ยืนยัน PIN',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _setPin,
                      child: const Text('บันทึก PIN'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ทดสอบเหตุการณ์ PIN',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text('ใช้ทดสอบ state machine เท่านั้น ไม่เปิดกล้อง'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _testPin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'กรอก PIN สำหรับทดสอบ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _testAttempt,
                      child: const Text('ทดสอบ'),
                    ),
                    Text('ผิดสะสม: ${widget.controller.failedAttempts} ครั้ง'),
                  ],
                ),
              ),
            ),
            if (widget.controller.evidence.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'ประวัติหลักฐาน',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final evidence in widget.controller.evidence)
                      _EvidenceTile(
                        evidence: evidence,
                        onUpload: () =>
                            widget.controller.uploadEvidence(evidence.id),
                        onExport: () => _export(evidence.id),
                        onDelete: () => _delete(evidence.id),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({
    required this.evidence,
    required this.onUpload,
    required this.onExport,
    required this.onDelete,
  });

  final AntiTheftEvidence evidence;
  final VoidCallback onUpload;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final sizeMb = evidence.encryptedBytes / (1024 * 1024);
    return ListTile(
      leading: Icon(
        evidence.uploadState == EvidenceUploadState.uploaded
            ? Icons.cloud_done_outlined
            : Icons.enhanced_encryption_outlined,
      ),
      title: Text(evidence.createdAt.toLocal().toString()),
      subtitle: Text(
        '${evidence.durationSeconds} วินาที • ${sizeMb.toStringAsFixed(1)} MB • '
        '${evidence.networkType}\n${_statusLabel(evidence)}'
        '${evidence.lastError == null ? '' : '\n${evidence.lastError}'}',
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'upload') onUpload();
          if (value == 'export') onExport();
          if (value == 'delete') onDelete();
        },
        itemBuilder: (context) => [
          if (evidence.uploadState != EvidenceUploadState.uploaded)
            const PopupMenuItem(value: 'upload', child: Text('อัปโหลดใหม่')),
          const PopupMenuItem(value: 'export', child: Text('ถอดรหัสและส่งออก')),
          const PopupMenuItem(value: 'delete', child: Text('ลบ')),
        ],
      ),
    );
  }

  String _statusLabel(AntiTheftEvidence value) {
    return switch (value.uploadState) {
      EvidenceUploadState.local => 'เข้ารหัสในเครื่อง',
      EvidenceUploadState.queued => 'รออัปโหลด',
      EvidenceUploadState.uploading => 'กำลังอัปโหลด',
      EvidenceUploadState.uploaded => 'อัปโหลดสำเร็จ',
      EvidenceUploadState.failed => 'อัปโหลดไม่สำเร็จ',
    };
  }
}
