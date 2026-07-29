import 'package:flutter/material.dart';

import '../core/anti_theft/anti_theft_controller.dart';

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
    _message(result.message);
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
              child: const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('สถานะกล้องและ Google Drive'),
                subtitle: Text(
                  'ยังไม่เชื่อม native camera และ Google Drive OAuth '
                  'เหตุการณ์ PIN ผิดจึงบันทึกเฉพาะ activity log และไม่อ้างว่าถ่ายหรือส่งไฟล์แล้ว',
                ),
              ),
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
                  const ListTile(
                    leading: Icon(Icons.cloud_off_outlined),
                    title: Text('ปลายทาง: เก็บในเครื่องเท่านั้น'),
                    subtitle: Text(
                      'Google Drive จะเลือกได้หลังเจ้าของเชื่อมบัญชีและอนุมัติโฟลเดอร์',
                    ),
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
          ],
        );
      },
    );
  }
}
