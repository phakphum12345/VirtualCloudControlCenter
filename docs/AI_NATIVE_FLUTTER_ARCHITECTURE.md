# AI-Native Flutter Architecture

## Status

This document is the canonical architecture contract for `phakphum-ai-system-assistant`.

## Non-negotiable boundaries

- Flutter is the application runtime and composition root.
- The application must work without a project-owned backend server.
- Laravel, PHP, Apache, Nginx, MySQL, PostgreSQL, MongoDB, Firebase, and Google Calendar API are outside the approved architecture.
- Google Drive may be used only for user-authorized backup, restore, and file synchronization.
- Local storage is the source of truth for normal application operation.
- AI providers are accessed through explicit provider adapters and must never bypass permission, risk, validation, or audit controls.
- No secret API key may be committed to source control.

## Runtime topology

```text
Flutter application
├── UI shell
├── App controller
├── AI engine
│   ├── command parser
│   ├── context builder
│   ├── planner
│   ├── risk classifier
│   ├── command validator
│   ├── provider router
│   └── response formatter
├── permission policy
├── platform controller
├── local storage
├── audit log
├── emergency stop
├── Google sign-in adapter
└── Google Drive adapter
```

## Startup sequence

```text
WidgetsFlutterBinding.ensureInitialized
→ create AppDependencies
→ initialize local storage
→ initialize audit log
→ initialize security controllers
→ construct AI engine
→ construct platform controller
→ run application shell
```

A startup failure must produce a visible, actionable error. The application must not silently fall back to an unapproved remote service.

## Data ownership

### Local source of truth

The following data is local-first:

- settings
- user preferences
- AI conversation metadata
- approved memory records
- audit events
- permission decisions
- cached provider responses
- backup manifests

### Google Drive scope

Google Drive is optional and user-authorized. It may perform:

- encrypted backup upload
- encrypted backup download
- restore package selection
- explicit file synchronization requested by the user

Google Drive must not become an implicit database or mandatory login dependency.

## AI execution pipeline

```text
User input
→ normalize
→ parse intent
→ collect minimum relevant context
→ classify risk
→ check permission
→ create plan
→ validate plan
→ execute approved actions
→ verify result
→ append audit event
→ format response
→ store approved memory
```

No action may skip risk classification and permission evaluation.

## Agent boundaries

Agents are logical modules, not autonomous unrestricted processes.

- Chat agent: conversation and response composition
- File agent: local file operations within approved paths
- Drive agent: explicit backup, restore, and sync
- GitHub agent: repository operations after user authorization
- Build agent: analyze, test, build, and package
- Security agent: risk, permissions, audit, and emergency stop
- Storage agent: local persistence and migrations
- Update agent: version checks and verified update metadata

Each agent must expose typed inputs, typed results, clear failure states, and an auditable action record.

## Security invariants

- Default-deny for destructive or privileged actions.
- Explicit confirmation for irreversible operations.
- Emergency stop overrides all active plans.
- Audit records are append-oriented and must not contain secrets.
- Tokens belong in platform-secure storage when available.
- Provider keys must be supplied at runtime or build time through secure configuration.
- Web builds must not embed private provider secrets.

## Platform targets

Approved targets:

- Android
- iOS
- Windows
- macOS
- Linux
- Web

Platform-specific features must be represented by capability detection and adapters. Unsupported features must return explicit unsupported results rather than crash.

## Asset and icon contract

One canonical source image should generate platform assets.

- Windows: `windows/runner/resources/app_icon.ico`
- Android: launcher and adaptive icons
- iOS: AppIcon asset catalog
- macOS: AppIcon asset catalog / ICNS output where packaging requires it
- Linux: PNG desktop icon
- Web: favicon and PWA icons

The Windows `.ico` file is a required build input and CI must fail when it is missing.

## Build quality gates

Every build must run:

1. dependency resolution
2. formatting verification
3. static analysis
4. unit and widget tests
5. architecture policy tests
6. target build
7. artifact upload

## Change rules

Any proposal that introduces a backend, Google Calendar API, or a new external data owner requires explicit owner approval and an Architecture Decision Record before implementation.
