import '../core/actions/assistant_action.dart';
import 'action_result.dart';
import 'platform_adapter.dart';

class PlatformController {
  const PlatformController(this._adapter);

  final PlatformAdapter _adapter;

  Future<ActionResult> execute(AssistantAction action) =>
      _adapter.execute(action);
}
