import '../models/risk_level.dart';

class AssistantAction {
  const AssistantAction({
    required this.id,
    required this.action,
    required this.parameters,
    required this.risk,
  });

  final String id;
  final String action;
  final Map<String, Object?> parameters;
  final RiskLevel risk;

  bool get requiresConfirmation => risk == RiskLevel.confirmationRequired;

  Map<String, Object?> toJson() => {
    'id': id,
    'action': action,
    'parameters': parameters,
    'risk': risk.wireName,
    'requiresConfirmation': requiresConfirmation,
  };
}
