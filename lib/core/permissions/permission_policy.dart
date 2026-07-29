import '../actions/assistant_action.dart';
import '../models/risk_level.dart';

class PermissionDecision {
  const PermissionDecision({
    required this.allowed,
    required this.requiresConfirmation,
    required this.reason,
  });

  final bool allowed;
  final bool requiresConfirmation;
  final String reason;
}

class PermissionPolicy {
  const PermissionPolicy();

  PermissionDecision evaluate(AssistantAction action) => switch (action.risk) {
    RiskLevel.safe => const PermissionDecision(
      allowed: true,
      requiresConfirmation: false,
      reason: 'Safe action.',
    ),
    RiskLevel.confirmationRequired => const PermissionDecision(
      allowed: true,
      requiresConfirmation: true,
      reason: 'User confirmation is required.',
    ),
    RiskLevel.restricted => const PermissionDecision(
      allowed: false,
      requiresConfirmation: false,
      reason: 'This action is blocked by the safety policy.',
    ),
  };
}
