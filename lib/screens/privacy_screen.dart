import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Card(
          child: SwitchListTile(
            value: false,
            onChanged: null,
            title: Text('Protection'),
            subtitle: Text(
              'ยังไม่มีตัวกรองที่ยืนยันการทำงานได้ จึงปิดไว้เป็นค่าเริ่มต้น',
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _Counter(label: 'Ads blocked', value: '0'),
            _Counter(label: 'Trackers blocked', value: '0'),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: false,
                onChanged: null,
                title: const Text('Block pop-ups'),
              ),
              SwitchListTile(
                value: false,
                onChanged: null,
                title: const Text('Block autoplay'),
              ),
              const ListTile(
                leading: Icon(Icons.list_alt),
                title: Text('Filter lists'),
                subtitle: Text('ยังไม่ได้ติดตั้ง'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
