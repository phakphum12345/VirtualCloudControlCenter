import '../core/actions/assistant_action.dart';
import 'action_result.dart';
import 'android_platform_adapter.dart';
import 'linux_platform_adapter.dart';
import 'windows_platform_adapter.dart';

abstract interface class PlatformAdapter {
  String get platformName;
  Future<ActionResult> execute(AssistantAction action);
}

PlatformAdapter createPlatformAdapter(String platformName) {
  if (platformName == 'windows') {
    return const WindowsPlatformAdapter();
  }
  if (platformName == 'android') {
    return const AndroidPlatformAdapter();
  }
  if (platformName == 'linux') {
    return const LinuxPlatformAdapter();
  }
  return SharedPlatformAdapter(platformName);
}

class SharedPlatformAdapter implements PlatformAdapter {
  const SharedPlatformAdapter(this.platformName);

  @override
  final String platformName;

  @override
  Future<ActionResult> execute(AssistantAction action) async {
    if (action.action == 'diagnostics.status') {
      return ActionResult(
        commandId: action.id,
        success: true,
        message: 'แอปทำงานบน $platformName และ Shared Core พร้อมใช้งาน',
        platform: platformName,
        details: const {'scope': 'shared_core'},
      );
    }
    return ActionResult(
      commandId: action.id,
      success: false,
      message:
          'คำสั่ง ${action.action} ยังไม่มี native adapter สำหรับ $platformName',
      platform: platformName,
      details: const {'reason': 'not_implemented'},
    );
  }
}
