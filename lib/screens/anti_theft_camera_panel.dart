import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/anti_theft/anti_theft_controller.dart';

class AntiTheftCameraPanel extends StatefulWidget {
  const AntiTheftCameraPanel({
    required this.controller,
    required this.recordingSeconds,
    required this.onClosed,
    super.key,
  });

  final AntiTheftController controller;
  final int recordingSeconds;
  final VoidCallback onClosed;

  @override
  State<AntiTheftCameraPanel> createState() => _AntiTheftCameraPanelState();
}

class _AntiTheftCameraPanelState extends State<AntiTheftCameraPanel> {
  CameraController? _camera;
  Timer? _timer;
  int _remaining = 0;
  String? _error;
  bool _recording = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.controller.acknowledgeCaptureRequest();
    _initializeAndRecord();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _initializeAndRecord() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('อุปกรณ์นี้ไม่มีกล้องที่แอปเข้าถึงได้');
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      await controller.startVideoRecording();
      setState(() {
        _recording = true;
        _remaining = widget.recordingSeconds;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        if (_remaining <= 1) {
          timer.cancel();
          _stopAndSave();
        } else {
          setState(() => _remaining--);
        }
      });
    } on CameraException catch (error) {
      _showError(_cameraMessage(error));
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _stopAndSave() async {
    if (!_recording || _saving) return;
    _timer?.cancel();
    setState(() {
      _recording = false;
      _saving = true;
    });
    try {
      final file = await _camera!.stopVideoRecording();
      final elapsed = widget.recordingSeconds - _remaining + 1;
      await widget.controller.completeCapture(
        file.path,
        elapsed.clamp(1, widget.recordingSeconds),
      );
      if (mounted) widget.onClosed();
    } catch (error) {
      _showError('บันทึกหลักฐานไม่สำเร็จ: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    try {
      if (_camera?.value.isRecordingVideo == true) {
        final file = await _camera!.stopVideoRecording();
        await File(file.path).delete();
      }
    } finally {
      if (mounted) widget.onClosed();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  String _cameraMessage(CameraException error) {
    return switch (error.code) {
      'CameraAccessDenied' =>
        'ไม่ได้รับสิทธิ์กล้อง กรุณาอนุญาตจากการตั้งค่าระบบ',
      'CameraAccessDeniedWithoutPrompt' =>
        'สิทธิ์กล้องถูกปิด กรุณาเปิดจากการตั้งค่าระบบ',
      'CameraAccessRestricted' => 'ระบบจำกัดการใช้กล้องบนอุปกรณ์นี้',
      _ => 'เปิดกล้องไม่สำเร็จ: ${error.description ?? error.code}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fiber_manual_record, color: Colors.red),
              title: Text(
                _saving
                    ? 'กำลังเข้ารหัสหลักฐาน'
                    : _recording
                    ? 'กำลังบันทึก $_remaining วินาที'
                    : 'กำลังเปิดกล้อง',
              ),
              subtitle: const Text(
                'กล้องทำงานแบบมองเห็นได้และไม่มีเสียง ระบบจะแสดง indicator '
                'ของกล้องตามข้อกำหนดของอุปกรณ์',
              ),
            ),
            if (camera != null && camera.value.isInitialized)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: AspectRatio(
                    aspectRatio: camera.value.aspectRatio,
                    child: CameraPreview(camera),
                  ),
                ),
              )
            else if (_error == null)
              const Center(child: CircularProgressIndicator()),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Colors.red.shade900)),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: widget.onClosed,
                icon: const Icon(Icons.close),
                label: const Text('ปิด'),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _recording ? _stopAndSave : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('หยุดและบันทึก'),
                  ),
                  TextButton.icon(
                    onPressed: _saving ? null : _cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('ยกเลิก'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
