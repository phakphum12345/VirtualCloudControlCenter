# Virtual Cloud Control Center v3.3

Windows desktop control application for `DRIVE_VIRTUAL_CLOUD` + GitHub Actions.

## Google Cloud + Drive setup is now guided in the app

The Dashboard Setup row now contains the complete sequence:

1. **Enable Google Drive API**
2. **Create / Manage OAuth Client**
3. **Authorize Google Drive**
4. **Bootstrap / Update Control Plane**

`0. Setup Everything` walks through those stages and stops only when Google requires an explicit browser action from the account owner.

### Enable Google Drive API

The **Enable Google Drive API** button opens the official Google Cloud API Library page for `drive.googleapis.com`.

- If an OAuth client JSON has already been imported, Control Center reads its `project_id` and opens the Drive API page scoped to that exact Cloud project.
- If no client has been imported yet, Google Cloud opens with project selection. Choose the same project that will own the OAuth client.
- Click **Enable** in Google Cloud if the API is not already enabled.

Control Center does not claim that the API is enabled merely because the page was opened. After OAuth exists, the `Drive API` System Health item is verified by making a real Drive v3 `about.get` request. It becomes **Ready** only when that request succeeds.

## Google authorization — browser flow

On first use:

1. Click **Create / Manage OAuth Client** and create either a Desktop application client (recommended) or Web application client.
2. Download the OAuth client JSON.
3. Click **Authorize Google Drive** and select that JSON once.
4. The app imports the client configuration to the private app-data folder.
5. Your browser opens the Google consent page.
6. Approve the Drive permission.
7. The app receives the callback and stores refreshable user credentials in the private app-data folder.
8. Click Refresh. `Drive API` and `Drive OAuth` should both become **Ready**.

### Supported OAuth client types

**Desktop application client**

- Recommended for this Windows desktop Control Center.
- Uses Google's installed-app local server flow.

**Web application client**

- Supported through an authorization-code callback.
- Must contain an Authorized redirect URI on localhost.
- Recommended: `http://localhost:8765/oauth2callback`
- OAuth state is validated before token exchange.
- Offline access is requested so Drive Sync can refresh the token without asking for approval on every run.

## Security

- OAuth client JSON is stored at `%APPDATA%\DriveVirtualCloudControlCenter\google-oauth-client.json` by default.
- Generated Drive user credentials are stored at `%APPDATA%\DriveVirtualCloudControlCenter\gdrive-user-credentials.json` by default.
- OAuth/token JSON is not included in the package ZIP.
- OAuth/token files are excluded by `.gitignore` and are never committed by Bootstrap.
- GitHub receives the generated Drive user-credential JSON only through repository Secrets.
- Secret values are never displayed in the Control Center.

## Existing capabilities

- Real Windows/macOS job status from GitHub Actions.
- Run Windows, macOS, or both.
- Cancel / Re-run / Re-run Failed.
- Retry Drive Sync without rebuilding.
- Live job/step monitor.
- Run details: branch, SHA, actor, timestamps and duration.
- Artifact Manager with download and SHA-256 verification.
- Drive sync receipts and Sync History.
- Multi-repo browser and workflow selector.
- Optional private cross-repo access via `MULTI_REPO_TOKEN`.
- Audit log, auto refresh, notifications, settings backup/restore, retention cleanup, and EXE build.

## First setup

1. Ensure GitHub CLI (`gh`), Git and Python are installed.
2. Start `run-control-center.bat` or `VirtualCloudControlCenter.exe`.
3. Click `0. Setup Everything`.
4. Sign into GitHub if prompted.
5. Enable Google Drive API in one Cloud project.
6. Create/download the OAuth client JSON from that same project.
7. Authorize Drive in the browser.
8. When `Drive API` and `Drive OAuth` are Ready, Bootstrap creates/updates the private Control Plane repository and writes Drive folder IDs / OAuth user credentials to GitHub Secrets.
9. Dispatch a Windows/macOS job and verify Artifact -> checksum -> Drive Sync -> receipt.


## Bound Google Cloud project

This build is pinned to Google Cloud project `shift-calendar-engine` for Drive API enablement and OAuth Client creation. OAuth JSON from a different project is rejected to prevent accidental cross-project credentials.
