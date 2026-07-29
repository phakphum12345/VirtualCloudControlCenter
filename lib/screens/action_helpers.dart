import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/actions/assistant_action.dart';
import '../core/models/risk_level.dart';
import '../platform/action_result.dart';

AssistantAction createAction(
  String name, {
  Map<String, Object?> parameters = const {},
  RiskLevel risk = RiskLevel.safe,
}) => AssistantAction(
  id: 'cmd_${DateTime.now().microsecondsSinceEpoch}',
  action: name,
  parameters: parameters,
  risk: risk,
);

Future<bool> confirmAction(
  BuildContext context,
  AssistantAction action,
) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการทำงาน'),
        content: SelectableText(
          const JsonEncoder.withIndent('  ').convert(action.toJson()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    ) ??
    false;

void showActionResult(BuildContext context, ActionResult result) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.message),
      backgroundColor: result.success
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.error,
    ),
  );
}
