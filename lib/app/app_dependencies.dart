import '../ai_engine/ai_service.dart';
import '../ai_engine/command_parser.dart';
import '../ai_engine/command_planner.dart';
import '../ai_engine/command_validator.dart';
import '../ai_engine/risk_classifier.dart';
import '../core/audit_log/audit_log_controller.dart';
import '../core/anti_theft/anti_theft_controller.dart';
import '../core/emergency_stop/emergency_stop_controller.dart';
import '../core/permissions/permission_policy.dart';
import '../platform/capability_detector.dart';
import '../platform/platform_adapter.dart';
import '../platform/platform_controller.dart';
import '../services/storage_service.dart';
import 'app_controller.dart';

class AppDependencies {
  AppDependencies._({
    required this.appController,
    required this.capabilityDetector,
    required this.antiTheftController,
  });

  final AppController appController;
  final CapabilityDetector capabilityDetector;
  final AntiTheftController antiTheftController;

  static Future<AppDependencies> create() async {
    const capabilityDetector = CapabilityDetector();
    final storage = StorageService();
    final auditLog = AuditLogController(storage);
    await auditLog.initialize();
    final antiTheftController = AntiTheftController(storage, auditLog);
    await antiTheftController.initialize();
    final emergencyStop = EmergencyStopController();
    final appController = AppController(
      const AiService(
        RuleBasedCommandParser(),
        CommandPlanner(RiskClassifier()),
        CommandValidator(),
      ),
      const PermissionPolicy(),
      PlatformController(
        createPlatformAdapter(capabilityDetector.platformName),
      ),
      auditLog: auditLog,
      emergencyStop: emergencyStop,
    );
    return AppDependencies._(
      appController: appController,
      capabilityDetector: capabilityDetector,
      antiTheftController: antiTheftController,
    );
  }
}
