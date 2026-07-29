import '../core/actions/assistant_action.dart';
import 'command_parser.dart';
import 'risk_classifier.dart';

class CommandPlanner {
  const CommandPlanner(this._classifier);

  final RiskClassifier _classifier;

  AssistantAction plan(ParsedCommand command) => AssistantAction(
    id: 'cmd_${DateTime.now().microsecondsSinceEpoch}',
    action: command.action,
    parameters: command.parameters,
    risk: _classifier.classify(command.action),
  );
}
