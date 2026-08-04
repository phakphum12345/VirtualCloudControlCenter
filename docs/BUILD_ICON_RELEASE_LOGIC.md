# Build, Icon, and Release Logic

## Canonical inputs

- Flutter source: `lib/`
- Tests: `test/`
- Web shell: `web/`
- Windows icon: `windows/runner/resources/app_icon.ico`
- Dependency manifest: `pubspec.yaml`

## Required pipeline

```text
checkout
→ install Flutter stable
→ flutter pub get
→ dart format check
→ flutter analyze
→ flutter test
→ verify required assets
→ build target
→ upload artifact
```

## Web build

The Web workflow must run `flutter build web --release` and upload `build/web` as an artifact. Deployment is a separate owner decision; a successful Web build must not automatically publish the private application.

## Icon logic

The icon system uses one visual identity across all platforms.

```text
canonical 1024×1024 PNG
├── Windows ICO
├── Android launcher icons
├── Android adaptive foreground/background
├── iOS AppIcon sizes
├── macOS AppIcon sizes
├── Linux PNG
└── Web favicon and PWA icons
```

### Windows requirement

`windows/runner/resources/app_icon.ico` is mandatory. The ICO should contain multiple embedded sizes such as 16, 24, 32, 48, 64, 128, and 256 pixels so Windows Explorer and the executable display correctly at different scales.

### Web requirement

The Web package must contain:

- `web/favicon.png` or a supported favicon referenced by `web/index.html`
- `web/icons/Icon-192.png`
- `web/icons/Icon-512.png`
- maskable icons when used by the manifest

## Target artifacts

- Android: release APK and optional AAB
- iOS: unsigned build artifact unless signing is configured
- Windows: complete Release directory, not only the EXE
- macOS: application bundle artifact
- Linux: release bundle directory
- Web: `build/web`

## Versioning

Use `version` in `pubspec.yaml` as the canonical application version. Release tags should follow semantic versioning, for example `v1.1.0`.

## Release safety

- Do not publish provider keys.
- Do not publish OAuth client secrets.
- Web releases must use public-client authentication patterns only.
- Artifacts must be generated from a clean checkout.
- A failed analyze or test step blocks the build.
- Automatic merge is outside this workflow.

## Failure handling

A failed job must preserve useful logs and identify the failing phase. Fixes are committed to the working branch and CI is allowed to rerun. The branch is not merged until the owner explicitly requests it.
