# Architecture Traceability Matrix

This matrix keeps documentation, implementation, tests, and CI aligned.

| Capability | Source owner | Required tests | Required documentation |
|---|---|---|---|
| App composition | `lib/app/app_dependencies.dart` | dependency initialization | architecture and startup logic |
| AI orchestration | `lib/ai_engine/ai_service.dart` | service flow and failure cases | AI system logic |
| Command parsing | `lib/ai_engine/command_parser.dart` | Thai/English parser cases | command grammar |
| Planning | `lib/ai_engine/command_planner.dart` | deterministic plan cases | planning rules |
| Validation | `lib/ai_engine/command_validator.dart` | invalid and unsupported plans | validation rules |
| Risk | `lib/ai_engine/risk_classifier.dart` | low/medium/high/blocked cases | risk model |
| Permissions | `lib/core/permissions/permission_policy.dart` | allowed/denied/confirmation | permission model |
| Emergency stop | `lib/core/emergency_stop/` | mutation blocking | emergency-stop behavior |
| Audit log | `lib/core/audit_log/` | pending/success/failure persistence | audit evidence rules |
| Local storage | `lib/services/storage_service.dart` | read/write/migration/failure | storage policy |
| Capability detection | `lib/platform/capability_detector.dart` | platform matrices | platform support |
| Platform execution | `lib/platform/platform_controller.dart` | adapter result handling | execution boundary |
| UI shell | `lib/screens/app_shell.dart` | navigation smoke test | UI responsibility |
| Windows icon | `windows/runner/resources/app_icon.ico` | file-presence policy test | icon pipeline |
| Flutter web | `web/` | web build | web platform rules |
| CI quality | `.github/workflows/quality.yml` | workflow itself | build policy |
| Web artifact | `.github/workflows/build-web.yml` | successful workflow run | web build and release |

## Change rule

Every pull request or branch commit that changes behavior must update all
applicable columns in this matrix. A behavior change without tests or updated
documentation is incomplete.

## One-truth rule

- Business logic belongs in core/AI/platform layers, never duplicated in UI.
- Platform support is declared by the capability detector and implemented by an adapter.
- Documentation describes current behavior, not hypothetical completed features.
- CI output is the evidence for formatting, analysis, tests, and builds.
