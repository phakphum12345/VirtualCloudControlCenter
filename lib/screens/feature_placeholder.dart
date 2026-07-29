import 'package:flutter/material.dart';

class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    required this.icon,
    required this.title,
    required this.description,
    required this.features,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              for (final feature in features)
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(feature),
                  subtitle: const Text('รอ native platform adapter'),
                  trailing: const Chip(label: Text('ยังไม่พร้อม')),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
