# AI System Complete Logic

## Scope

This document defines the complete runtime logic for `phakphum-ai-system-assistant`.
The application is Flutter-first and local-first. It does not depend on Laravel,
PHP, a custom backend server, Firebase, or Google Calendar API.

## Runtime pipeline

```text
User input
  -> normalize input
  -> command parser
  -> intent classification
  -> context builder
  -> memory lookup
  -> risk classification
  -> permission policy
  -> task planner
  -> command validator
  -> platform capability check
  -> explicit confirmation when required
  -> execution
  -> result verification
  -> audit logging
  -> response rendering
  -> optional memory persistence
```

## Existing implementation map

- `lib/ai_engine/ai_service.dart`: AI orchestration entry point.
- `lib/ai_engine/command_parser.dart`: rule-based command parsing.
- `lib/ai_engine/command_planner.dart`: converts parsed intent into executable plans.
- `lib/ai_engine/command_validator.dart`: validates a plan before execution.
- `lib/ai_engine/risk_classifier.dart`: assigns the action risk level.
- `lib/core/permissions/permission_policy.dart`: enforces allowed actions.
- `lib/platform/capability_detector.dart`: detects platform support.
- `lib/platform/platform_controller.dart`: executes platform actions.
- `lib/core/audit_log/`: stores action evidence locally.
- `lib/core/emergency_stop/`: blocks execution when emergency stop is active.
- `lib/services/storage_service.dart`: persistent local storage.
- `lib/app/app_dependencies.dart`: composition root and single dependency owner.

## Input logic

1. Reject empty or whitespace-only requests.
2. Normalize Thai and English punctuation without changing user meaning.
3. Detect command, question, explanation, diagnostic, or unsupported intent.
4. Preserve original input for audit evidence.
5. Never silently expand a request into a higher-risk action.

## Context logic

Context may include:

- current platform and capabilities;
- current emergency-stop state;
- local preferences;
- prior local conversation summaries;
- latest verified action result.

Sensitive information must not be injected unless required for the current task.

## Risk logic

```text
LOW
  read-only explanation, local status, capability report

MEDIUM
  file creation, settings changes, application launch

HIGH
  process termination, deletion, destructive changes, privileged operations

BLOCKED
  unsupported, unsafe, concealed, or policy-forbidden operation
```

Rules:

- Risk is calculated before execution.
- Higher-risk actions require stronger validation.
- Destructive actions require explicit confirmation.
- Unsupported actions return a clear failure rather than pretending success.

## Permission logic

The permission policy must answer:

1. Is this action implemented?
2. Is it supported on the current platform?
3. Is the user allowed to request it?
4. Is operating-system permission available?
5. Does it require confirmation?
6. Is emergency stop active?

Execution is allowed only when every required condition passes.

## Planning logic

A plan must contain:

- canonical action name;
- parameters;
- risk level;
- required capability;
- confirmation requirement;
- expected result type;
- verification rule.

Plans must be deterministic for the same normalized input and runtime state.

## Validation logic

Validation rejects:

- missing required parameters;
- unknown action names;
- invalid paths or values;
- unsupported platform capabilities;
- attempts to bypass confirmation;
- plans that conflict with emergency stop;
- actions outside the application architecture.

## Execution logic

1. Record pending audit entry.
2. Execute through `PlatformController` only.
3. Never call platform-specific code directly from screens.
4. Capture structured `ActionResult`.
5. Verify output and final state.
6. Mark audit entry success or failure.
7. Return a user-facing response based on verified evidence.

## Memory logic

Memory is local-first.

Store only when:

- it improves future assistance;
- the data is not transient noise;
- the user has not requested deletion or non-persistence;
- storage policy permits it.

Never store secrets, access tokens, or raw credentials in ordinary preferences.

## Provider logic

The core runtime must remain provider-neutral. An external AI provider is an
optional adapter, not the owner of business logic. The app must continue to
support deterministic local command parsing when no provider is configured.

Provider keys must not be committed to Git. A direct client-side provider key
has exposure risk and must be clearly marked as user-managed configuration.

## Failure logic

Failures return:

- what failed;
- whether any change was made;
- evidence or error category;
- safe next action.

The UI must never display success before verification completes.

## Emergency stop logic

When emergency stop is active:

- no mutating platform action may start;
- queued actions are cancelled;
- read-only status and recovery instructions remain available;
- the event is added to the audit log.

## Architecture prohibitions

The following must not be added without an explicit architecture decision:

- Laravel or PHP runtime;
- custom backend API server;
- Google Calendar API;
- Firebase as hidden backend ownership;
- duplicate business logic in UI widgets;
- direct platform execution outside the platform adapter/controller boundary.

## Definition of done

An AI capability is complete only when it has:

- parser coverage;
- planner coverage;
- risk classification;
- permission rule;
- validation;
- platform capability declaration;
- execution adapter;
- verification;
- audit evidence;
- automated tests;
- documentation updated in the same change.
