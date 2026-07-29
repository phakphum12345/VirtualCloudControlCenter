import '../core/actions/assistant_action.dart';
import 'command_parser.dart';
import 'command_planner.dart';
import 'command_validator.dart';

class PreparedCommand {
  const PreparedCommand({required this.action, required this.validation});

  final AssistantAction action;
  final ValidationResult validation;
}

class AiService {
  const AiService(this._parser, this._planner, this._validator);

  final CommandParser _parser;
  final CommandPlanner _planner;
  final CommandValidator _validator;

  PreparedCommand prepare(String input) {
    final action = _planner.plan(_parser.parse(input));
    return PreparedCommand(
      action: action,
      validation: _validator.validate(action),
    );
  }
}
