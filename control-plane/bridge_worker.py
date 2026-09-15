#!/usr/bin/env python3
"""Sync one GitHub Actions run into DRIVE_VIRTUAL_CLOUD.

The worker is idempotent: retrying a source run updates files with the same name
inside the same Drive folder instead of creating duplicate copies. A receipt is
written only after the run has been processed, with SHA-256 verification results.
"""
from __future__ import annotations

import hashlib
import io
import json
import os
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests
from google.oauth2.credentials import Credentials as UserCredentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

API = "https://api.github.com"
DRIVE_SCOPE = "https://www.googleapis.com/auth/drive"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def github_session(token: str) -> requests.Session:
    session = requests.Session()
    session.headers.update({
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "drive-virtual-cloud-bridge/3.0",
    })
    return session


def get_json(session: requests.Session, url: str) -> Any:
    response = session.get(url, timeout=60)
    response.raise_for_status()
    return response.json()


def download_bytes(session: requests.Session, url: str) -> bytes:
    response = session.get(url, timeout=180, allow_redirects=True)
    response.raise_for_status()
    return response.content


def drive_client(user_credentials_json: str):
    info = json.loads(user_credentials_json)
    if info.get("type") != "authorized_user":
        raise RuntimeError("GDRIVE_USER_CREDENTIALS_JSON must be an authorized_user OAuth JSON.")
    creds = UserCredentials.from_authorized_user_info(info, scopes=[DRIVE_SCOPE])
    return build("drive", "v3", credentials=creds, cache_discovery=False)


def escape_drive_query(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def find_named_files(drive, folder_id: str, name: str) -> list[dict[str, Any]]:
    q = f"'{folder_id}' in parents and name = '{escape_drive_query(name)}' and trashed = false"
    result = drive.files().list(q=q, fields="files(id,name,webViewLink,parents)", pageSize=20).execute()
    return result.get("files", [])


def upsert_file(drive, local_path: Path, folder_id: str, name: str | None = None):
    final_name = name or local_path.name
    media = MediaFileUpload(str(local_path), resumable=True)
    existing = find_named_files(drive, folder_id, final_name)
    if existing:
        file_id = existing[0]["id"]
        return drive.files().update(fileId=file_id, media_body=media, fields="id,name,webViewLink,parents").execute()
    return drive.files().create(
        body={"name": final_name, "parents": [folder_id]},
        media_body=media,
        fields="id,name,webViewLink,parents",
    ).execute()


def delete_named(drive, folder_id: str, name: str) -> None:
    for item in find_named_files(drive, folder_id, name):
        drive.files().delete(fileId=item["id"]).execute()


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def verify_artifact_zip(raw: bytes) -> dict[str, Any]:
    result: dict[str, Any] = {"ok": False, "checked": 0, "errors": []}
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as zf:
            names = set(zf.namelist())
            checksum_members = [n for n in names if n.endswith("SHA256SUMS.txt")]
            if not checksum_members:
                result["errors"].append("SHA256SUMS.txt missing")
                return result
            manifest_name = sorted(checksum_members)[0]
            manifest = zf.read(manifest_name).decode("utf-8", errors="replace")
            manifest_prefix = manifest_name.rsplit("/", 1)[0] + "/" if "/" in manifest_name else ""
            for line in manifest.splitlines():
                if not line.strip():
                    continue
                parts = line.split(None, 1)
                if len(parts) != 2:
                    result["errors"].append(f"invalid manifest line: {line[:100]}")
                    continue
                expected, rel = parts[0].lower(), parts[1].strip().lstrip("*")
                candidates = [rel, manifest_prefix + rel]
                member = next((c for c in candidates if c in names), None)
                if not member:
                    result["errors"].append(f"missing {rel}")
                    continue
                actual = hashlib.sha256(zf.read(member)).hexdigest().lower()
                result["checked"] += 1
                if actual != expected:
                    result["errors"].append(f"checksum mismatch {rel}")
            result["ok"] = result["checked"] > 0 and not result["errors"]
            return result
    except Exception as exc:
        result["errors"].append(str(exc))
        return result


def write_status(drive, root: Path, folder_id: str, run_id: str, status: str, extra: dict[str, Any] | None = None):
    name = f"sync-run-{run_id}.json"
    path = root / name
    payload = {"run_id": run_id, "status": status, "updated_at": now_iso()}
    if extra:
        payload.update(extra)
    write_json(path, payload)
    return upsert_file(drive, path, folder_id, name)


def main() -> int:
    token = require("GITHUB_TOKEN")
    repo = require("GITHUB_REPOSITORY")
    run_id = require("GITHUB_RUN_ID")
    drive_user = require("GDRIVE_USER_CREDENTIALS_JSON")
    folders = {
        "artifacts": require("GDRIVE_ARTIFACTS_FOLDER_ID"),
        "logs": require("GDRIVE_LOGS_FOLDER_ID"),
        "metadata": require("GDRIVE_RUN_METADATA_FOLDER_ID"),
        "checksums": require("GDRIVE_CHECKSUMS_FOLDER_ID"),
        "receipts": require("GDRIVE_RECEIPTS_FOLDER_ID"),
        "pending": require("GDRIVE_SYNC_PENDING_FOLDER_ID"),
        "completed": require("GDRIVE_SYNC_COMPLETED_FOLDER_ID"),
        "failed": require("GDRIVE_SYNC_FAILED_FOLDER_ID"),
    }

    session = github_session(token)
    drive = drive_client(drive_user)
    pending_name = f"sync-run-{run_id}.json"

    with tempfile.TemporaryDirectory(prefix="virtual-cloud-bridge-") as td:
        root = Path(td)
        write_status(drive, root, folders["pending"], run_id, "pending", {"repo": repo})
        uploaded: list[dict[str, Any]] = []
        artifact_names: list[str] = []
        verification: dict[str, Any] = {}
        try:
            run = get_json(session, f"{API}/repos/{repo}/actions/runs/{run_id}")
            jobs = get_json(session, f"{API}/repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")
            artifacts = get_json(session, f"{API}/repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100")

            run_meta = root / f"run-{run_id}.json"
            write_json(run_meta, {"run": run, "jobs": jobs})
            uploaded.append(upsert_file(drive, run_meta, folders["metadata"]))

            for artifact in artifacts.get("artifacts", []):
                artifact_id = artifact["id"]
                artifact_name = artifact["name"]
                artifact_names.append(artifact_name)
                raw = download_bytes(session, f"{API}/repos/{repo}/actions/artifacts/{artifact_id}/zip")
                verification[artifact_name] = verify_artifact_zip(raw)

                zip_path = root / f"{artifact_name}.zip"
                zip_path.write_bytes(raw)
                uploaded.append(upsert_file(drive, zip_path, folders["artifacts"]))

                with zipfile.ZipFile(io.BytesIO(raw)) as zf:
                    checksum_members = [m for m in zf.namelist() if m.endswith("SHA256SUMS.txt")]
                    if checksum_members:
                        checksum_path = root / f"{artifact_name}-SHA256SUMS.txt"
                        checksum_path.write_bytes(zf.read(sorted(checksum_members)[0]))
                        uploaded.append(upsert_file(drive, checksum_path, folders["checksums"]))

            for job in jobs.get("jobs", []):
                job_id = job["id"]
                job_name = str(job.get("name", job_id)).replace("/", "-").replace("\\", "-")
                try:
                    log_bytes = download_bytes(session, f"{API}/repos/{repo}/actions/jobs/{job_id}/logs")
                except requests.HTTPError as exc:
                    # GitHub may not expose logs for a job that was skipped/cancelled before execution.
                    log_bytes = f"Job log unavailable: {exc}\n".encode("utf-8")
                log_path = root / f"job-{job_id}-{job_name}.log"
                log_path.write_bytes(log_bytes)
                uploaded.append(upsert_file(drive, log_path, folders["logs"]))

            receipt = {
                "ok": True,
                "repo": repo,
                "run_id": run_id,
                "source_conclusion": run.get("conclusion"),
                "source_status": run.get("status"),
                "artifact_names": artifact_names,
                "verification": verification,
                "uploaded": uploaded,
                "synced_at": now_iso(),
            }
            receipt_path = root / f"receipt-run-{run_id}.json"
            write_json(receipt_path, receipt)
            upsert_file(drive, receipt_path, folders["receipts"])
            write_status(drive, root, folders["completed"], run_id, "completed", {
                "repo": repo, "receipt": receipt, "artifact_count": len(artifact_names)
            })
            delete_named(drive, folders["pending"], pending_name)
            delete_named(drive, folders["failed"], pending_name)
            print(json.dumps(receipt, indent=2))
            return 0
        except Exception as exc:
            error = str(exc)
            failed_receipt = {
                "ok": False, "repo": repo, "run_id": run_id, "artifact_names": artifact_names,
                "verification": verification, "uploaded": uploaded, "error": error, "synced_at": now_iso(),
            }
            try:
                receipt_path = root / f"receipt-run-{run_id}.json"
                write_json(receipt_path, failed_receipt)
                upsert_file(drive, receipt_path, folders["receipts"])
                write_status(drive, root, folders["failed"], run_id, "failed", {"repo": repo, "error": error})
                delete_named(drive, folders["pending"], pending_name)
            except Exception as marker_exc:
                print(f"Could not write Drive failure receipt: {marker_exc}", file=sys.stderr)
            print(json.dumps(failed_receipt, indent=2), file=sys.stderr)
            raise


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}), file=sys.stderr)
        raise
