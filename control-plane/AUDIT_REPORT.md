# Virtual Cloud Control Center v3.3 — audit summary

## Scope checked

- Control Center GUI and setup flow
- Google Drive OAuth (Desktop + Web clients)
- Google Drive API readiness verification
- GitHub Control Plane bootstrap
- Windows/macOS runner dispatch and runtime state
- Drive Sync, checksum, receipts and retry
- Artifact manager, live monitor, multi-repo, audit and settings
- EXE build package

## v3.3 changes

- Added **Drive API** to System Health.
- Added **Enable Google Drive API** button to Dashboard and Settings.
- Button opens `drive.googleapis.com` API Library; when OAuth JSON is imported, the page is scoped to the OAuth client's `project_id`.
- Added a strict readiness rule: Drive API becomes **Ready** only after a real Drive v3 `about.get` request succeeds.
- Added detection for common API-disabled errors and reports **Disabled** instead of falsely reporting OAuth as Ready.
- Renumbered guided setup: Enable Drive API -> OAuth Client -> Authorize -> Bootstrap.
- `Setup Everything` now opens the required Google Cloud pages when configuration is missing and pauses for the user's explicit Enable/Allow actions.
- After OAuth, Setup Everything verifies Drive API before Bootstrap.
- No `gcloud` dependency was reintroduced.

## Security observations

- The application cannot and should not silently click Google's **Enable** or **Allow** controls on behalf of the account owner.
- OAuth client/token JSON stays out of the package and Git repository.
- Drive credentials remain in user AppData and GitHub Secrets only.
- Health checks reveal status only; they never display secret values.

## Validation performed

- Python compile check for `control_center.py` and `bridge_worker.py`.
- YAML parse check for all workflow files.
- GUI smoke test verifies the main window starts and the expected tabs/buttons exist.
- Package ZIP integrity and SHA-256 manifest regenerated.


## Bound Google Cloud project

This build is pinned to Google Cloud project `shift-calendar-engine` for Drive API enablement and OAuth Client creation. OAuth JSON from a different project is rejected to prevent accidental cross-project credentials.
