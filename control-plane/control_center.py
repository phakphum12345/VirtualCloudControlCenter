#!/usr/bin/env python3
"""Virtual Cloud Control Center.

Windows-first desktop control plane for DRIVE_VIRTUAL_CLOUD + GitHub Actions.
The application keeps secrets out of its config: only paths and non-secret settings
are persisted locally. GitHub secrets are written with `gh secret set`.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import queue
import secrets
import shutil
import subprocess
import sys
import threading
import time
import webbrowser
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse
import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk

APP_NAME = "Virtual Cloud Control Center"
APP_VERSION = "3.3"
DEFAULT_REPO = "phakphoum38-stack/DRIVE_VIRTUAL_CLOUD_CONTROL_PLANE"
GITHUB_BASE = "https://github.com"

DRIVE_ROOT_ID = "1FqR9bfxgaSNL99jmSR9hRPdmkhFyKlEY"
DRIVE_ARTIFACTS_ID = "1TG6_gSbKcBpf1dkKV9FlL53jcM6GPqV_"
DRIVE_LOGS_ID = "18J7X0eWZ7HrLuEifgxqN2r6d-fISJeVc"
DRIVE_RUNS_ID = "1vNhGkENLe9LqMDgBf9tqmhRpdX3zHb0T"
DRIVE_CHECKSUMS_ID = "1uBfISC3ABeXk0xepFCXCfkBUo3hi97vl"
DRIVE_RECEIPTS_ID = "1rsuP77T6Nag74SoVqHqWmGhqPdi4Hnfg"
DRIVE_SYNC_PENDING_ID = "149OM0kuuKzQnbTfkP3fEYvMZQaGXXnk9"
DRIVE_SYNC_COMPLETED_ID = "1ZPQJoLRrYxfER-Wl9hMB3rrY1IZT7Sw_"
DRIVE_SYNC_FAILED_ID = "1ftk85NR9oVpv5fow7ou7N1J44Mi__KZB"

def drive_url(folder_id: str) -> str:
    return f"https://drive.google.com/drive/folders/{folder_id}"

DRIVE_ROOT_URL = drive_url(DRIVE_ROOT_ID)
DRIVE_ARTIFACTS_URL = drive_url(DRIVE_ARTIFACTS_ID)
DRIVE_LOGS_URL = drive_url(DRIVE_LOGS_ID)
DRIVE_RUNS_URL = drive_url(DRIVE_RUNS_ID)
DRIVE_RECEIPTS_URL = drive_url(DRIVE_RECEIPTS_ID)
DRIVE_SYNC_COMPLETED_URL = drive_url(DRIVE_SYNC_COMPLETED_ID)
DRIVE_SYNC_FAILED_URL = drive_url(DRIVE_SYNC_FAILED_ID)

EXPECTED_SECRETS = {
    "GDRIVE_USER_CREDENTIALS_JSON",
    "GDRIVE_ARTIFACTS_FOLDER_ID",
    "GDRIVE_LOGS_FOLDER_ID",
    "GDRIVE_RUN_METADATA_FOLDER_ID",
    "GDRIVE_CHECKSUMS_FOLDER_ID",
    "GDRIVE_RECEIPTS_FOLDER_ID",
    "GDRIVE_SYNC_PENDING_FOLDER_ID",
    "GDRIVE_SYNC_COMPLETED_FOLDER_ID",
    "GDRIVE_SYNC_FAILED_FOLDER_ID",
}

REQUIRED_CONTROL_FILES = [
    ".github/workflows/virtual-cloud-runners.yml",
    ".github/workflows/virtual-cloud-drive-sync.yml",
    ".github/workflows/build-control-center.yml",
    "tools/virtual-cloud/bridge_worker.py",
    "tools/virtual-cloud/requirements.txt",
]


def app_data_dir() -> Path:
    if os.name == "nt":
        base = Path(os.environ.get("APPDATA", Path.home()))
    else:
        base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    path = base / "DriveVirtualCloudControlCenter"
    path.mkdir(parents=True, exist_ok=True)
    return path


APP_DATA = app_data_dir()
CONFIG_PATH = APP_DATA / "config.json"
LOG_PATH = APP_DATA / "control-center.log"
AUDIT_PATH = APP_DATA / "audit.jsonl"
OAUTH_CLIENT_PATH = APP_DATA / "google-oauth-client.json"
DEFAULT_OAUTH_TOKEN_PATH = APP_DATA / "gdrive-user-credentials.json"
WEB_OAUTH_DEFAULT_REDIRECT = "http://localhost:8765/oauth2callback"
DEFAULT_GOOGLE_CLOUD_PROJECT = "shift-calendar-engine"
GOOGLE_OAUTH_CLIENTS_URL = f"https://console.cloud.google.com/apis/credentials?project={DEFAULT_GOOGLE_CLOUD_PROJECT}"
GOOGLE_DRIVE_API_URL = "https://console.cloud.google.com/apis/library/drive.googleapis.com"
GOOGLE_DRIVE_API_SERVICE = "drive.googleapis.com"


def default_download_dir() -> str:
    base = Path.home() / "Downloads" / "VirtualCloudArtifacts"
    return str(base)


@dataclass
class AppConfig:
    repo: str = DEFAULT_REPO
    credential_path: str = str(DEFAULT_OAUTH_TOKEN_PATH)
    oauth_client_path: str = str(OAUTH_CLIENT_PATH)
    package_dir: str = ""
    auto_refresh: bool = True
    refresh_seconds: int = 15
    notifications: bool = True
    retention_days: int = 14
    download_dir: str = default_download_dir()
    selected_repo: str = ""

    @classmethod
    def load(cls) -> "AppConfig":
        try:
            data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
            base = cls()
            for key in asdict(base):
                if key in data:
                    setattr(base, key, data[key])
            base.refresh_seconds = max(5, int(base.refresh_seconds))
            base.retention_days = max(1, int(base.retention_days))
            return base
        except Exception:
            return cls()

    def save(self) -> None:
        CONFIG_PATH.write_text(json.dumps(asdict(self), indent=2), encoding="utf-8")


class CommandRunner:
    def __init__(self, output_queue: queue.Queue):
        self.output_queue = output_queue
        self.busy = False
        self.process: subprocess.Popen | None = None

    @staticmethod
    def display_cmd(args: list[str]) -> str:
        def q(v: str) -> str:
            return f'"{v}"' if any(c.isspace() for c in v) else v
        return " ".join(q(str(a)) for a in args)

    def run_async(self, args: list[str], cwd: Path | None = None, callback=None, env=None):
        if self.busy:
            self.output_queue.put(("warn", "Another foreground command is already running.\n"))
            return False
        self.busy = True

        def worker():
            code = 1
            lines: list[str] = []
            try:
                self.output_queue.put(("cmd", f"$ {self.display_cmd(args)}\n"))
                self.process = subprocess.Popen(
                    args,
                    cwd=str(cwd) if cwd else None,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    env=env,
                    creationflags=(subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0),
                )
                assert self.process.stdout is not None
                for line in self.process.stdout:
                    lines.append(line)
                    self.output_queue.put(("out", line))
                code = self.process.wait()
                self.output_queue.put(("ok" if code == 0 else "err", f"[exit {code}]\n"))
            except Exception as exc:
                lines.append(str(exc))
                self.output_queue.put(("err", f"{exc}\n"))
            finally:
                self.process = None
                self.busy = False
                if callback:
                    try:
                        callback(code, "".join(lines))
                    except Exception as exc:
                        self.output_queue.put(("err", f"Callback error: {exc}\n"))

        threading.Thread(target=worker, daemon=True).start()
        return True

    def stop(self):
        if self.process and self.process.poll() is None:
            try:
                self.process.terminate()
                return True
            except Exception:
                return False
        return False


class ControlCenter(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(f"{APP_NAME} v{APP_VERSION}")
        self.geometry("1280x820")
        self.minsize(1050, 700)

        self.base_dir = Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent
        self.config_data = AppConfig.load()
        if not self.config_data.package_dir:
            self.config_data.package_dir = str(self.base_dir)
        self.output_queue: queue.Queue = queue.Queue()
        self.runner = CommandRunner(self.output_queue)

        self.run_rows: dict[str, dict] = {}
        self.run_state_cache: dict[str, tuple[str, str]] = {}
        self.repo_rows: dict[str, dict] = {}
        self.workflow_rows: dict[str, dict] = {}
        self.artifact_rows: dict[str, dict] = {}
        self.monitor_jobs: dict[str, dict] = {}
        self.receipt_cache: dict[str, dict] = {}
        self.health_snapshot: dict[str, str] = {}
        self.auto_refresh_after_id = None
        self.monitor_after_id = None

        self._build_style()
        self._build_ui()
        self.after(100, self._drain_output)
        self.after(300, self.refresh_all)
        self.after(900, self.refresh_audit)
        self._schedule_auto_refresh()

    # ---------- UI ----------
    def _build_style(self):
        style = ttk.Style(self)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        style.configure("Title.TLabel", font=("Segoe UI", 19, "bold"))
        style.configure("Sub.TLabel", font=("Segoe UI", 10))
        style.configure("CardTitle.TLabel", font=("Segoe UI", 11, "bold"))
        style.configure("Big.TButton", padding=(14, 9))
        style.configure("Status.TLabel", font=("Segoe UI", 10, "bold"))
        style.configure("Metric.TLabel", font=("Segoe UI", 15, "bold"))

    def _build_ui(self):
        header = ttk.Frame(self, padding=(18, 14, 18, 8))
        header.pack(fill="x")
        ttk.Label(header, text="Virtual Cloud Control Center", style="Title.TLabel").pack(side="left")
        ttk.Label(header, text=f"Drive Virtual Cloud × GitHub Actions · v{APP_VERSION}", style="Sub.TLabel").pack(side="left", padx=(14, 0), pady=(8, 0))
        ttk.Button(header, text="Refresh", command=self.refresh_all).pack(side="right")

        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill="both", expand=True, padx=14, pady=(4, 8))
        self.dashboard = ttk.Frame(self.notebook, padding=12)
        self.runs_tab = ttk.Frame(self.notebook, padding=12)
        self.monitor_tab = ttk.Frame(self.notebook, padding=12)
        self.artifacts_tab = ttk.Frame(self.notebook, padding=12)
        self.repos_tab = ttk.Frame(self.notebook, padding=12)
        self.sync_tab = ttk.Frame(self.notebook, padding=12)
        self.audit_tab = ttk.Frame(self.notebook, padding=12)
        self.logs_tab = ttk.Frame(self.notebook, padding=12)
        self.settings_tab = ttk.Frame(self.notebook, padding=12)
        for frame, title in [
            (self.dashboard, "Dashboard"), (self.runs_tab, "Runs / Queue"),
            (self.monitor_tab, "Live Monitor"), (self.artifacts_tab, "Artifacts"),
            (self.repos_tab, "Repositories"), (self.sync_tab, "Sync History"),
            (self.audit_tab, "Audit"), (self.logs_tab, "Console"), (self.settings_tab, "Settings"),
        ]:
            self.notebook.add(frame, text=title)

        self._build_dashboard()
        self._build_runs()
        self._build_monitor()
        self._build_artifacts()
        self._build_repositories()
        self._build_sync_history()
        self._build_audit()
        self._build_console()
        self._build_settings()

        self.status_var = tk.StringVar(value="Ready")
        status = ttk.Frame(self, padding=(14, 0, 14, 9))
        status.pack(fill="x")
        ttk.Label(status, textvariable=self.status_var).pack(side="left")
        self.auto_status_var = tk.StringVar(value="")
        ttk.Label(status, textvariable=self.auto_status_var).pack(side="right", padx=(0, 15))
        ttk.Label(status, text=f"Log: {LOG_PATH}").pack(side="right")

    def _card(self, parent, title: str, row: int, col: int, colspan: int = 1):
        frame = ttk.LabelFrame(parent, text=title, padding=11)
        frame.grid(row=row, column=col, columnspan=colspan, sticky="nsew", padx=6, pady=6)
        return frame

    def _build_dashboard(self):
        for i in range(3):
            self.dashboard.columnconfigure(i, weight=1)
        self.dashboard.rowconfigure(3, weight=1)

        health = self._card(self.dashboard, "System Health", 0, 0)
        names = [
            "GitHub CLI", "GitHub Login", "Git", "Python", "Control repo", "GitHub Workflows",
            "GitHub Secrets", "Drive API", "OAuth Client", "Drive OAuth", "Drive Sync", "Bridge Worker", "Last Sync",
        ]
        self.health_vars = {name: tk.StringVar(value="Checking…") for name in names}
        split = 7
        for i, name in enumerate(names):
            block = 0 if i < split else 1
            r = i if i < split else i - split
            c = block * 2
            ttk.Label(health, text=name).grid(row=r, column=c, sticky="w", pady=2, padx=(0 if block == 0 else 18, 0))
            ttk.Label(health, textvariable=self.health_vars[name], style="Status.TLabel").grid(row=r, column=c + 1, sticky="e", padx=(10, 0), pady=2)
        health.columnconfigure(1, weight=1); health.columnconfigure(3, weight=1)

        runtime = self._card(self.dashboard, "Runner Runtime", 0, 1)
        self.windows_runtime_var = tk.StringVar(value="Checking…")
        self.macos_runtime_var = tk.StringVar(value="Checking…")
        for r, (label, var) in enumerate([("Windows", self.windows_runtime_var), ("macOS", self.macos_runtime_var)]):
            ttk.Label(runtime, text=label).grid(row=r, column=0, sticky="w", pady=4)
            ttk.Label(runtime, textvariable=var, style="Status.TLabel").grid(row=r, column=1, sticky="e", padx=(20, 0))
        runtime.columnconfigure(1, weight=1)
        ttk.Separator(runtime).grid(row=2, column=0, columnspan=2, sticky="ew", pady=7)
        ttk.Button(runtime, text="▶ Run Windows + macOS", style="Big.TButton", command=lambda: self.dispatch_control("all")).grid(row=3, column=0, columnspan=2, sticky="ew", pady=3)
        ttk.Button(runtime, text="▶ Run Windows", command=lambda: self.dispatch_control("windows")).grid(row=4, column=0, columnspan=2, sticky="ew", pady=3)
        ttk.Button(runtime, text="▶ Run macOS", command=lambda: self.dispatch_control("macos")).grid(row=5, column=0, columnspan=2, sticky="ew", pady=3)
        ttk.Button(runtime, text="Open GitHub Actions", command=self.open_actions).grid(row=6, column=0, columnspan=2, sticky="ew", pady=(8, 3))

        drive = self._card(self.dashboard, "Virtual Cloud", 0, 2)
        for text, url in [
            ("Open DRIVE_VIRTUAL_CLOUD", DRIVE_ROOT_URL), ("Open Artifacts", DRIVE_ARTIFACTS_URL),
            ("Open Logs", DRIVE_LOGS_URL), ("Open Run Metadata", DRIVE_RUNS_URL), ("Open Sync Receipts", DRIVE_RECEIPTS_URL),
        ]:
            ttk.Button(drive, text=text, command=lambda u=url: webbrowser.open(u)).pack(fill="x", pady=3)

        metrics = self._card(self.dashboard, "Overview", 1, 0, 3)
        self.metric_vars = {k: tk.StringVar(value="0") for k in ["Queued", "Running", "Failed", "Synced"]}
        for i, key in enumerate(["Queued", "Running", "Failed", "Synced"]):
            box = ttk.Frame(metrics, padding=(20, 4))
            box.grid(row=0, column=i, sticky="nsew")
            ttk.Label(box, textvariable=self.metric_vars[key], style="Metric.TLabel").pack()
            ttk.Label(box, text=key).pack()
            metrics.columnconfigure(i, weight=1)
        self.latest_artifact_var = tk.StringVar(value="Latest artifact: —")
        ttk.Label(metrics, textvariable=self.latest_artifact_var).grid(row=1, column=0, columnspan=4, sticky="w", pady=(8, 0))

        setup = self._card(self.dashboard, "Setup", 2, 0, 3)
        buttons = ttk.Frame(setup); buttons.pack(fill="x")
        for text, cmd, big in [
            ("0. Setup Everything", self.setup_everything, True),
            ("1. Enable Google Drive API", self.open_drive_api_enable, False),
            ("2. Create / Manage OAuth Client", self.open_google_oauth_setup, False),
            ("3. Authorize Google Drive", self.authorize_drive, False),
            ("4. Bootstrap / Update Control Plane", self.bootstrap, False),
            ("Check GitHub Login", self.check_github_login, False),
            ("Build EXE", self.build_exe_on_github, False),
            ("Open Package", self.open_package_folder, False),
        ]:
            ttk.Button(buttons, text=text, command=cmd, style="Big.TButton" if big else "TButton").pack(side="left", padx=(0, 7), pady=2)
        self.setup_hint_var = tk.StringVar(value="Checking setup state…")
        ttk.Label(setup, textvariable=self.setup_hint_var, wraplength=1120, justify="left").pack(fill="x", pady=(8, 0))

        recent = self._card(self.dashboard, "Latest GitHub Actions Runs", 3, 0, 3)
        self.latest_tree = ttk.Treeview(recent, columns=("id", "title", "status", "result", "created"), show="headings", height=8)
        for col, txt, width in [
            ("id", "Run ID", 105), ("title", "Title", 380), ("status", "Status", 100),
            ("result", "Conclusion", 110), ("created", "Created", 190),
        ]:
            self.latest_tree.heading(col, text=txt); self.latest_tree.column(col, width=width, anchor="w")
        self.latest_tree.pack(fill="both", expand=True)
        self.latest_tree.bind("<Double-1>", lambda e: self.open_selected_run())

    def _build_runs(self):
        toolbar = ttk.Frame(self.runs_tab); toolbar.pack(fill="x", pady=(0, 8))
        for text, cmd in [
            ("Refresh", self.refresh_runs), ("Open", self.open_selected_run), ("Details", self.load_selected_details),
            ("Live Monitor", self.monitor_selected_run), ("Cancel", self.cancel_selected_run),
            ("Re-run", self.rerun_selected), ("Re-run Failed", self.rerun_failed), ("Retry Drive Sync", self.retry_drive_sync),
        ]:
            ttk.Button(toolbar, text=text, command=cmd).pack(side="left", padx=(0, 6))
        ttk.Button(toolbar, text="Stop Foreground Command", command=self.stop_foreground_command).pack(side="right")

        paned = ttk.Panedwindow(self.runs_tab, orient="vertical"); paned.pack(fill="both", expand=True)
        tree_frame = ttk.Frame(paned)
        self.runs_tree = ttk.Treeview(tree_frame, columns=("id", "workflow", "status", "result", "branch", "sha", "created", "duration"), show="headings", height=15)
        for col, txt, width in [
            ("id", "Run ID", 100), ("workflow", "Workflow / Title", 300), ("status", "Status", 90),
            ("result", "Conclusion", 100), ("branch", "Branch", 110), ("sha", "SHA", 90),
            ("created", "Created", 170), ("duration", "Duration", 90),
        ]:
            self.runs_tree.heading(col, text=txt); self.runs_tree.column(col, width=width, anchor="w")
        self.runs_tree.pack(fill="both", expand=True)
        self.runs_tree.bind("<<TreeviewSelect>>", lambda e: self._selected_run_changed())
        self.runs_tree.bind("<Double-1>", lambda e: self.open_selected_run())
        paned.add(tree_frame, weight=3)
        detail_frame = ttk.LabelFrame(paned, text="Run Details", padding=8)
        self.run_details = tk.Text(detail_frame, height=8, wrap="word", font=("Cascadia Mono", 9))
        self.run_details.pack(fill="both", expand=True)
        paned.add(detail_frame, weight=1)

    def _build_monitor(self):
        bar = ttk.Frame(self.monitor_tab); bar.pack(fill="x", pady=(0, 8))
        ttk.Label(bar, text="Run ID").pack(side="left")
        self.monitor_run_var = tk.StringVar(value="")
        ttk.Entry(bar, textvariable=self.monitor_run_var, width=16).pack(side="left", padx=6)
        ttk.Button(bar, text="Refresh Jobs", command=self.refresh_monitor).pack(side="left")
        ttk.Button(bar, text="Load Full Logs", command=self.load_monitor_logs).pack(side="left", padx=6)
        self.monitor_auto_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(bar, text="Auto monitor", variable=self.monitor_auto_var, command=self._schedule_monitor).pack(side="left", padx=10)
        self.monitor_summary_var = tk.StringVar(value="Select a run in Runs / Queue and click Live Monitor.")
        ttk.Label(bar, textvariable=self.monitor_summary_var).pack(side="right")

        paned = ttk.Panedwindow(self.monitor_tab, orient="vertical"); paned.pack(fill="both", expand=True)
        top = ttk.Frame(paned)
        self.jobs_tree = ttk.Treeview(top, columns=("job", "os", "status", "result", "started", "duration"), show="headings")
        for col, txt, width in [
            ("job", "Job", 350), ("os", "Runner", 120), ("status", "Status", 100),
            ("result", "Conclusion", 110), ("started", "Started", 190), ("duration", "Duration", 100),
        ]:
            self.jobs_tree.heading(col, text=txt); self.jobs_tree.column(col, width=width, anchor="w")
        self.jobs_tree.pack(fill="both", expand=True)
        self.jobs_tree.bind("<<TreeviewSelect>>", lambda e: self._populate_selected_job_steps())
        paned.add(top, weight=2)
        bottom = ttk.LabelFrame(paned, text="Steps", padding=6)
        self.steps_tree = ttk.Treeview(bottom, columns=("step", "status", "result", "number", "duration"), show="headings", height=8)
        for col, txt, width in [
            ("step", "Step", 500), ("status", "Status", 110), ("result", "Conclusion", 120),
            ("number", "#", 50), ("duration", "Duration", 100),
        ]:
            self.steps_tree.heading(col, text=txt); self.steps_tree.column(col, width=width, anchor="w")
        self.steps_tree.pack(fill="both", expand=True)
        paned.add(bottom, weight=1)

    def _build_artifacts(self):
        bar = ttk.Frame(self.artifacts_tab); bar.pack(fill="x", pady=(0, 8))
        ttk.Label(bar, text="Run ID").pack(side="left")
        self.artifact_run_var = tk.StringVar(value="")
        ttk.Entry(bar, textvariable=self.artifact_run_var, width=16).pack(side="left", padx=6)
        for text, cmd in [
            ("Load Artifacts", self.refresh_artifacts), ("Download Selected", self.download_selected_artifact),
            ("Verify Download", self.verify_selected_download), ("Retry Drive Sync", self.retry_drive_sync_from_artifact),
            ("Open Drive Artifacts", lambda: webbrowser.open(DRIVE_ARTIFACTS_URL)),
        ]:
            ttk.Button(bar, text=text, command=cmd).pack(side="left", padx=(0, 6))
        self.artifact_status_var = tk.StringVar(value="")
        ttk.Label(bar, textvariable=self.artifact_status_var).pack(side="right")

        self.artifact_tree = ttk.Treeview(self.artifacts_tab, columns=("name", "size", "expired", "created", "drive", "verified"), show="headings")
        for col, txt, width in [
            ("name", "Artifact", 400), ("size", "Size", 100), ("expired", "Expired", 80),
            ("created", "Created", 190), ("drive", "Drive Sync", 110), ("verified", "Integrity", 110),
        ]:
            self.artifact_tree.heading(col, text=txt); self.artifact_tree.column(col, width=width, anchor="w")
        self.artifact_tree.pack(fill="both", expand=True)

    def _build_repositories(self):
        top = ttk.Frame(self.repos_tab); top.pack(fill="x", pady=(0, 10))
        ttk.Button(top, text="Load Repositories", command=self.load_repositories).pack(side="left")
        ttk.Label(top, text="Repository").pack(side="left", padx=(12, 4))
        self.source_repo_var = tk.StringVar(value=self.config_data.selected_repo or self.repo())
        self.repo_combo = ttk.Combobox(top, textvariable=self.source_repo_var, width=48, state="normal")
        self.repo_combo.pack(side="left", padx=4)
        ttk.Button(top, text="Load Workflows", command=self.load_repo_workflows).pack(side="left", padx=6)
        ttk.Button(top, text="Open Actions", command=self.open_selected_repo_actions).pack(side="left")

        via = ttk.LabelFrame(self.repos_tab, text="Run repository through Virtual Cloud Windows/macOS", padding=10)
        via.pack(fill="x", pady=(0, 10))
        ttk.Label(via, text="Target").grid(row=0, column=0, sticky="w")
        self.source_target_var = tk.StringVar(value="all")
        ttk.Combobox(via, textvariable=self.source_target_var, values=["all", "windows", "macos"], state="readonly", width=12).grid(row=0, column=1, padx=6)
        ttk.Label(via, text="Ref (optional)").grid(row=0, column=2, sticky="w", padx=(12, 0))
        self.source_ref_var = tk.StringVar(value="")
        ttk.Entry(via, textvariable=self.source_ref_var, width=30).grid(row=0, column=3, padx=6)
        ttk.Button(via, text="Run via Control Plane", command=self.dispatch_selected_repo).grid(row=0, column=4, padx=6)
        ttk.Label(via, text="Private cross-repo checkout requires optional GitHub secret MULTI_REPO_TOKEN.").grid(row=1, column=0, columnspan=5, sticky="w", pady=(7, 0))

        direct = ttk.LabelFrame(self.repos_tab, text="Run an existing workflow directly", padding=10)
        direct.pack(fill="x", pady=(0, 10))
        ttk.Label(direct, text="Workflow").grid(row=0, column=0, sticky="w")
        self.workflow_var = tk.StringVar(value="")
        self.workflow_combo = ttk.Combobox(direct, textvariable=self.workflow_var, width=55, state="readonly")
        self.workflow_combo.grid(row=0, column=1, sticky="ew", padx=6)
        ttk.Label(direct, text="Inputs JSON").grid(row=1, column=0, sticky="nw", pady=(8, 0))
        self.workflow_inputs = tk.Text(direct, height=4, width=70, font=("Cascadia Mono", 9))
        self.workflow_inputs.insert("1.0", "{}")
        self.workflow_inputs.grid(row=1, column=1, sticky="ew", padx=6, pady=(8, 0))
        ttk.Button(direct, text="Run Selected Workflow", command=self.run_selected_repo_workflow).grid(row=0, column=2, rowspan=2, padx=8)
        direct.columnconfigure(1, weight=1)

        self.repo_tree = ttk.Treeview(self.repos_tab, columns=("repo", "private", "default", "url"), show="headings")
        for col, txt, width in [("repo", "Repository", 420), ("private", "Private", 80), ("default", "Default Branch", 140), ("url", "URL", 420)]:
            self.repo_tree.heading(col, text=txt); self.repo_tree.column(col, width=width, anchor="w")
        self.repo_tree.pack(fill="both", expand=True)
        self.repo_tree.bind("<<TreeviewSelect>>", lambda e: self._repo_tree_selected())

    def _build_sync_history(self):
        bar = ttk.Frame(self.sync_tab); bar.pack(fill="x", pady=(0, 8))
        ttk.Button(bar, text="Refresh from Drive", command=self.refresh_sync_history).pack(side="left")
        ttk.Button(bar, text="Retry Selected Source Run", command=self.retry_sync_from_history).pack(side="left", padx=6)
        ttk.Button(bar, text="Open Receipts", command=lambda: webbrowser.open(DRIVE_RECEIPTS_URL)).pack(side="left", padx=6)
        ttk.Button(bar, text="Open Completed", command=lambda: webbrowser.open(DRIVE_SYNC_COMPLETED_URL)).pack(side="left", padx=6)
        ttk.Button(bar, text="Open Failed", command=lambda: webbrowser.open(DRIVE_SYNC_FAILED_URL)).pack(side="left", padx=6)
        self.sync_info_var = tk.StringVar(value="")
        ttk.Label(bar, textvariable=self.sync_info_var).pack(side="right")
        self.sync_tree = ttk.Treeview(self.sync_tab, columns=("run", "status", "repo", "artifacts", "verified", "time"), show="headings")
        for col, txt, width in [
            ("run", "Source Run", 120), ("status", "Status", 100), ("repo", "Repository", 300),
            ("artifacts", "Artifacts", 90), ("verified", "Integrity", 120), ("time", "Synced At", 210),
        ]:
            self.sync_tree.heading(col, text=txt); self.sync_tree.column(col, width=width, anchor="w")
        self.sync_tree.pack(fill="both", expand=True)

    def _build_audit(self):
        bar = ttk.Frame(self.audit_tab); bar.pack(fill="x", pady=(0, 8))
        ttk.Button(bar, text="Refresh", command=self.refresh_audit).pack(side="left")
        ttk.Button(bar, text="Open Audit File", command=self.open_audit_file).pack(side="left", padx=6)
        self.audit_tree = ttk.Treeview(self.audit_tab, columns=("time", "action", "target", "result", "details"), show="headings")
        for col, txt, width in [
            ("time", "Time", 190), ("action", "Action", 170), ("target", "Target", 250),
            ("result", "Result", 90), ("details", "Details", 480),
        ]:
            self.audit_tree.heading(col, text=txt); self.audit_tree.column(col, width=width, anchor="w")
        self.audit_tree.pack(fill="both", expand=True)

    def _build_console(self):
        toolbar = ttk.Frame(self.logs_tab); toolbar.pack(fill="x", pady=(0, 8))
        ttk.Button(toolbar, text="Clear", command=lambda: self.console.delete("1.0", "end")).pack(side="left")
        ttk.Button(toolbar, text="Open Local Log", command=self.open_local_log).pack(side="left", padx=6)
        ttk.Button(toolbar, text="Stop Foreground Command", command=self.stop_foreground_command).pack(side="left", padx=6)
        self.console = tk.Text(self.logs_tab, wrap="word", font=("Cascadia Mono", 10), undo=False)
        scroll = ttk.Scrollbar(self.logs_tab, orient="vertical", command=self.console.yview)
        self.console.configure(yscrollcommand=scroll.set)
        self.console.pack(side="left", fill="both", expand=True); scroll.pack(side="right", fill="y")
        for tag in ["cmd", "out", "ok", "warn", "err"]:
            self.console.tag_configure(tag)

    def _build_settings(self):
        form = ttk.LabelFrame(self.settings_tab, text="Control Plane Settings", padding=14)
        form.pack(fill="x"); form.columnconfigure(1, weight=1)
        self.repo_var = tk.StringVar(value=self.config_data.repo)
        self.cred_var = tk.StringVar(value=self.config_data.credential_path)
        self.oauth_client_var = tk.StringVar(value=self.config_data.oauth_client_path)
        self.package_var = tk.StringVar(value=self.config_data.package_dir or str(self.base_dir))
        self.refresh_seconds_var = tk.IntVar(value=self.config_data.refresh_seconds)
        self.auto_refresh_var = tk.BooleanVar(value=self.config_data.auto_refresh)
        self.notifications_var = tk.BooleanVar(value=self.config_data.notifications)
        self.retention_var = tk.IntVar(value=self.config_data.retention_days)
        self.download_var = tk.StringVar(value=self.config_data.download_dir)

        rows = [
            ("Control repository", self.repo_var, None),
            ("Google OAuth client JSON", self.oauth_client_var, self.browse_oauth_client),
            ("Drive OAuth credential JSON", self.cred_var, self.browse_credential),
            ("Package directory", self.package_var, self.browse_package),
            ("Artifact download directory", self.download_var, self.browse_download_dir),
        ]
        for r, (label, var, browse) in enumerate(rows):
            ttk.Label(form, text=label).grid(row=r, column=0, sticky="w", pady=5)
            ttk.Entry(form, textvariable=var).grid(row=r, column=1, sticky="ew", padx=8, pady=5)
            if browse:
                ttk.Button(form, text="Browse…", command=browse).grid(row=r, column=2, pady=5)

        opts_row = len(rows)
        opts = ttk.Frame(form); opts.grid(row=opts_row, column=0, columnspan=3, sticky="ew", pady=(8, 4))
        ttk.Checkbutton(opts, text="Auto refresh", variable=self.auto_refresh_var).pack(side="left")
        ttk.Label(opts, text="every").pack(side="left", padx=(8, 3))
        ttk.Spinbox(opts, from_=5, to=300, width=6, textvariable=self.refresh_seconds_var).pack(side="left")
        ttk.Label(opts, text="seconds").pack(side="left", padx=(3, 14))
        ttk.Checkbutton(opts, text="Completion notifications", variable=self.notifications_var).pack(side="left")
        ttk.Label(opts, text="Retention").pack(side="left", padx=(18, 3))
        ttk.Spinbox(opts, from_=1, to=90, width=6, textvariable=self.retention_var).pack(side="left")
        ttk.Label(opts, text="days").pack(side="left", padx=3)

        buttons = ttk.Frame(form); buttons.grid(row=opts_row + 1, column=0, columnspan=3, sticky="w", pady=(10, 0))
        ttk.Button(buttons, text="Save Settings", style="Big.TButton", command=self.save_settings).pack(side="left")
        ttk.Button(buttons, text="Export Settings", command=self.export_settings).pack(side="left", padx=6)
        ttk.Button(buttons, text="Import Settings", command=self.import_settings).pack(side="left", padx=6)
        ttk.Button(buttons, text="Authorize Drive in Browser", command=self.authorize_drive).pack(side="left", padx=6)
        ttk.Button(buttons, text="Enable Drive API", command=self.open_drive_api_enable).pack(side="left", padx=6)
        ttk.Button(buttons, text="Google OAuth Setup", command=self.open_google_oauth_setup).pack(side="left", padx=6)

        security = ttk.LabelFrame(self.settings_tab, text="Credential / Security Status", padding=14)
        security.pack(fill="x", pady=(12, 0))
        self.security_info_var = tk.StringVar(value="Credentials are never displayed. Drive API is verified with a real Drive v3 request after OAuth; secret values are never shown.")
        ttk.Label(security, textvariable=self.security_info_var, wraplength=1050, justify="left").pack(anchor="w")
        sec_buttons = ttk.Frame(security)
        sec_buttons.pack(fill="x", pady=(8, 0))
        ttk.Button(sec_buttons, text="Configure Private Multi-Repo Access", command=self.configure_multi_repo_token).pack(side="left")
        ttk.Label(sec_buttons, text="Uses the current gh login token and stores it only as the control repo secret MULTI_REPO_TOKEN.").pack(side="left", padx=10)

        cleanup = ttk.LabelFrame(self.settings_tab, text="Drive Retention Cleanup (manual only)", padding=14)
        cleanup.pack(fill="x", pady=(12, 0))
        ttk.Label(cleanup, text="Preview or delete Virtual Cloud files older than the retention period. Deletion always requires confirmation.").pack(anchor="w")
        ttk.Button(cleanup, text="Preview Cleanup", command=lambda: self.cleanup_drive(False)).pack(side="left", pady=(8, 0))
        ttk.Button(cleanup, text="Delete Old Drive Files…", command=lambda: self.cleanup_drive(True)).pack(side="left", padx=8, pady=(8, 0))

    # ---------- common helpers ----------
    def package_dir(self) -> Path:
        raw = self.package_var.get().strip() if hasattr(self, "package_var") else self.config_data.package_dir
        p = Path(raw) if raw else self.base_dir
        return p if p.exists() else self.base_dir

    def repo(self) -> str:
        return self.repo_var.get().strip() if hasattr(self, "repo_var") else self.config_data.repo

    def command_exists(self, name: str) -> bool:
        return shutil.which(name) is not None

    def _run_quiet(self, args: list[str], timeout: int = 20, input_text: str | None = None) -> tuple[int, str]:
        try:
            r = subprocess.run(
                args, capture_output=True, text=True, timeout=timeout, input=input_text,
                encoding="utf-8", errors="replace",
                creationflags=(subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0),
            )
            return r.returncode, (r.stdout or "") + (r.stderr or "")
        except Exception as exc:
            return 1, str(exc)

    def _drain_output(self):
        try:
            while True:
                tag, text = self.output_queue.get_nowait()
                ts = datetime.now().strftime("%H:%M:%S")
                formatted = f"[{ts}] {text}" if tag in {"cmd", "warn", "err"} else text
                self.console.insert("end", formatted, tag); self.console.see("end")
                try:
                    with LOG_PATH.open("a", encoding="utf-8") as f:
                        f.write(formatted)
                except Exception:
                    pass
        except queue.Empty:
            pass
        self.after(100, self._drain_output)

    def log(self, text: str, tag: str = "out"):
        self.output_queue.put((tag, text.rstrip() + "\n"))

    def audit(self, action: str, target: str = "", result: str = "requested", details: str = ""):
        entry = {
            "time": datetime.now(timezone.utc).isoformat(),
            "action": action, "target": target, "result": result, "details": details[:1500],
        }
        try:
            with AUDIT_PATH.open("a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except Exception:
            pass
        self.after(50, self.refresh_audit)

    def _notify(self, text: str):
        self.status_var.set(text)
        if not getattr(self, "notifications_var", None) or not self.notifications_var.get():
            return
        if os.name == "nt":
            try:
                import winsound
                winsound.MessageBeep(winsound.MB_ICONASTERISK)
            except Exception:
                pass

    @staticmethod
    def _parse_dt(raw: str | None):
        if not raw:
            return None
        try:
            return datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except Exception:
            return None

    @classmethod
    def _duration(cls, start: str | None, end: str | None) -> str:
        a, b = cls._parse_dt(start), cls._parse_dt(end)
        if not a:
            return "—"
        if not b:
            b = datetime.now(timezone.utc)
        secs = max(0, int((b - a).total_seconds()))
        if secs < 60:
            return f"{secs}s"
        return f"{secs // 60}m {secs % 60}s"

    @staticmethod
    def _bytes(value: int | None) -> str:
        n = float(value or 0)
        for unit in ["B", "KB", "MB", "GB"]:
            if n < 1024 or unit == "GB":
                return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
            n /= 1024
        return str(value or 0)

    def _selected_tree_run_id(self) -> str | None:
        for tree in (self.runs_tree, self.latest_tree):
            sel = tree.selection()
            if sel:
                vals = tree.item(sel[0], "values")
                if vals:
                    return str(vals[0])
        return None

    # ---------- settings / files ----------
    def save_settings(self):
        repo = self.repo_var.get().strip()
        if "/" not in repo:
            messagebox.showerror(APP_NAME, "Control repository must be in owner/name format.")
            return
        self.config_data.repo = repo
        self.config_data.credential_path = self.cred_var.get().strip()
        self.config_data.oauth_client_path = self.oauth_client_var.get().strip()
        self.config_data.package_dir = self.package_var.get().strip()
        self.config_data.auto_refresh = bool(self.auto_refresh_var.get())
        self.config_data.refresh_seconds = max(5, int(self.refresh_seconds_var.get()))
        self.config_data.notifications = bool(self.notifications_var.get())
        self.config_data.retention_days = max(1, int(self.retention_var.get()))
        self.config_data.download_dir = self.download_var.get().strip() or default_download_dir()
        self.config_data.selected_repo = self.source_repo_var.get().strip() if hasattr(self, "source_repo_var") else ""
        self.config_data.save()
        self.audit("save-settings", self.repo(), "success")
        self._schedule_auto_refresh()
        self.refresh_health()
        self.status_var.set("Settings saved")

    def browse_credential(self):
        path = filedialog.askopenfilename(title="Select gdrive-user-credentials.json", filetypes=[("JSON", "*.json"), ("All files", "*.*")])
        if path: self.cred_var.set(path)

    def browse_oauth_client(self):
        path = filedialog.askopenfilename(title="Select Google OAuth Client JSON", filetypes=[("JSON", "*.json"), ("All files", "*.*")])
        if path:
            try:
                imported = self._import_oauth_client_json(path)
                self.oauth_client_var.set(str(imported))
                self.save_settings()
                messagebox.showinfo(APP_NAME, "Google OAuth client imported. Click 'Authorize Google Drive (Browser)' to grant permission.")
            except Exception as exc:
                messagebox.showerror(APP_NAME, f"Could not import OAuth client JSON: {exc}")

    def _oauth_project_id(self) -> str:
        """Return the Google Cloud project_id embedded in the imported OAuth JSON."""
        raw = self.oauth_client_var.get().strip() if hasattr(self, "oauth_client_var") else self.config_data.oauth_client_path
        if not raw or not Path(raw).exists():
            return ""
        try:
            data = json.loads(Path(raw).read_text(encoding="utf-8"))
            section = data.get("web") or data.get("installed") or {}
            return str(section.get("project_id") or data.get("project_id") or "").strip()
        except Exception:
            return ""

    def open_drive_api_enable(self):
        """Open the official Drive API library page for the OAuth project's project_id when known."""
        project_id = self._oauth_project_id() or DEFAULT_GOOGLE_CLOUD_PROJECT
        url = GOOGLE_DRIVE_API_URL
        from urllib.parse import quote
        url += "?project=" + quote(project_id, safe="")
        self.audit("open-drive-api-enable", project_id, "success")
        webbrowser.open(url)
        messagebox.showinfo(
            APP_NAME,
            "Google Cloud opened for project:\n\n"
            + project_id
            + "\n\nClick Enable if the Google Drive API is not already enabled. Then create the OAuth Client in this same project.",
        )

    def _drive_api_status(self) -> tuple[str, str]:
        """Verify Drive API by making a real Drive v3 request when OAuth credentials exist."""
        if not self._drive_oauth_ready():
            return ("Not verified", "Authorize Google Drive first; then Refresh will verify Drive API with a real request.")
        ok, detail = self._drive_test()
        if ok:
            return ("Ready", detail)
        low = detail.lower()
        disabled_markers = [
            "accessnotconfigured", "service_disabled", "service disabled", "has not been used in project",
            "is disabled", "drive.googleapis.com", "api has not been used",
        ]
        if any(m in low for m in disabled_markers):
            return ("Disabled", detail)
        return ("Error", detail)

    def open_google_oauth_setup(self):
        webbrowser.open(GOOGLE_OAUTH_CLIENTS_URL)
        self.audit("open-google-oauth-setup", GOOGLE_OAUTH_CLIENTS_URL, "success")

    def open_google_drive_api_setup(self):
        webbrowser.open(GOOGLE_DRIVE_API_URL)
        self.audit("open-google-drive-api", GOOGLE_DRIVE_API_URL, "success")

    def browse_package(self):
        path = filedialog.askdirectory(title="Select Virtual Cloud package folder")
        if path: self.package_var.set(path)

    def browse_download_dir(self):
        path = filedialog.askdirectory(title="Select artifact download directory")
        if path: self.download_var.set(path)

    def export_settings(self):
        path = filedialog.asksaveasfilename(defaultextension=".json", filetypes=[("JSON", "*.json")], initialfile="virtual-cloud-control-center-settings.json")
        if not path: return
        self.save_settings()
        data = asdict(self.config_data)
        Path(path).write_text(json.dumps(data, indent=2), encoding="utf-8")
        self.audit("export-settings", path, "success")

    def import_settings(self):
        path = filedialog.askopenfilename(filetypes=[("JSON", "*.json")])
        if not path: return
        try:
            data = json.loads(Path(path).read_text(encoding="utf-8"))
            current = asdict(self.config_data)
            current.update({k: v for k, v in data.items() if k in current})
            self.config_data = AppConfig(**current)
            self.config_data.save()
            self.audit("import-settings", path, "success")
            messagebox.showinfo(APP_NAME, "Settings imported. Reopen the Control Center to apply every UI field.")
        except Exception as exc:
            messagebox.showerror(APP_NAME, f"Could not import settings: {exc}")

    def open_package_folder(self):
        self._open_local_path(self.package_dir())

    def open_local_log(self):
        LOG_PATH.touch(exist_ok=True); self._open_local_path(LOG_PATH)

    def open_audit_file(self):
        AUDIT_PATH.touch(exist_ok=True); self._open_local_path(AUDIT_PATH)

    def _open_local_path(self, path: Path):
        if os.name == "nt": os.startfile(str(path))
        elif sys.platform == "darwin": subprocess.Popen(["open", str(path)])
        else: subprocess.Popen(["xdg-open", str(path)])

    # ---------- Google Drive ----------
    def _oauth_client_ready(self) -> bool:
        raw = self.oauth_client_var.get().strip() if hasattr(self, "oauth_client_var") else self.config_data.oauth_client_path
        if not raw or not Path(raw).exists():
            return False
        try:
            data = json.loads(Path(raw).read_text(encoding="utf-8"))
            section = data.get("web") or data.get("installed")
            return bool(section and section.get("client_id") and section.get("client_secret"))
        except Exception:
            return False

    def _import_oauth_client_json(self, source: str | Path) -> Path:
        src = Path(source)
        data = json.loads(src.read_text(encoding="utf-8"))
        section = data.get("web") or data.get("installed")
        if not section or not section.get("client_id") or not section.get("client_secret"):
            raise ValueError("This is not a Google OAuth client JSON (web or desktop).")
        json_project = str(section.get("project_id") or data.get("project_id") or "").strip()
        if json_project and json_project != DEFAULT_GOOGLE_CLOUD_PROJECT:
            raise ValueError(
                f"OAuth Client belongs to project '{json_project}', but this Control Center is configured for "
                f"'{DEFAULT_GOOGLE_CLOUD_PROJECT}'. Create/download the OAuth Client from the configured project."
            )
        if "web" in data:
            redirects = section.get("redirect_uris") or []
            local = [u for u in redirects if str(u).startswith("http://localhost:") or str(u).startswith("http://127.0.0.1:")]
            if not local:
                raise ValueError(
                    "Web OAuth client needs an Authorized redirect URI on localhost, for example "
                    + WEB_OAUTH_DEFAULT_REDIRECT
                )
        OAUTH_CLIENT_PATH.parent.mkdir(parents=True, exist_ok=True)
        OAUTH_CLIENT_PATH.write_text(json.dumps(data, indent=2), encoding="utf-8")
        try:
            os.chmod(OAUTH_CLIENT_PATH, 0o600)
        except Exception:
            pass
        return OAUTH_CLIENT_PATH

    def _drive_oauth_ready(self) -> bool:
        raw = self.cred_var.get().strip() if hasattr(self, "cred_var") else self.config_data.credential_path
        if not raw or not Path(raw).exists(): return False
        try:
            data = json.loads(Path(raw).read_text(encoding="utf-8"))
            return bool(data.get("refresh_token") and data.get("client_id") and data.get("client_secret"))
        except Exception:
            return False

    def _drive_service(self):
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build
        raw = self.cred_var.get().strip()
        if not raw: raise RuntimeError("Drive OAuth credential path is not configured.")
        info = json.loads(Path(raw).read_text(encoding="utf-8"))
        creds = Credentials.from_authorized_user_info(info, scopes=["https://www.googleapis.com/auth/drive"])
        return build("drive", "v3", credentials=creds, cache_discovery=False)

    def _drive_test(self) -> tuple[bool, str]:
        if not self._drive_oauth_ready(): return False, "Not configured"
        try:
            drive = self._drive_service()
            about = drive.about().get(fields="user(displayName,emailAddress)").execute()
            user = about.get("user", {})
            return True, user.get("emailAddress") or user.get("displayName") or "Ready"
        except Exception as exc:
            return False, f"OAuth error: {str(exc)[:60]}"

    def _drive_list(self, folder_id: str, page_size: int = 200) -> list[dict]:
        drive = self._drive_service()
        out: list[dict] = []; token = None
        while True:
            res = drive.files().list(
                q=f"'{folder_id}' in parents and trashed=false",
                fields="nextPageToken,files(id,name,size,createdTime,modifiedTime,webViewLink,mimeType)",
                pageSize=min(1000, page_size), pageToken=token, orderBy="createdTime desc",
            ).execute()
            out.extend(res.get("files", [])); token = res.get("nextPageToken")
            if not token or len(out) >= page_size: break
        return out[:page_size]

    def _drive_read_json(self, file_id: str) -> dict:
        drive = self._drive_service()
        data = drive.files().get_media(fileId=file_id).execute()
        if isinstance(data, bytes): return json.loads(data.decode("utf-8"))
        if isinstance(data, str): return json.loads(data)
        return json.loads(bytes(data).decode("utf-8"))

    def _load_receipts_map(self, limit: int = 100) -> dict[str, dict]:
        result: dict[str, dict] = {}
        for f in self._drive_list(DRIVE_RECEIPTS_ID, limit):
            if not f.get("name", "").startswith("receipt-run-"): continue
            try:
                data = self._drive_read_json(f["id"])
                rid = str(data.get("run_id") or "")
                if rid: result[rid] = data
            except Exception:
                continue
        self.receipt_cache = result
        return result

    # ---------- health ----------
    def _apply_health(self, values: dict[str, str]):
        self.health_snapshot.update(values)
        for key, value in values.items():
            if key in self.health_vars: self.health_vars[key].set(value)
        self._update_setup_hint()

    def _update_setup_hint(self):
        h = self.health_snapshot
        if h.get("GitHub CLI") == "Missing": msg = "Next: install GitHub CLI (gh), then Refresh."
        elif h.get("GitHub Login") != "Connected": msg = "Next: sign in to GitHub with 'gh auth login'."
        elif h.get("OAuth Client") != "Ready": msg = "Next: click 1. Enable Google Drive API, then 2. Create / Manage OAuth Client and import the downloaded JSON."
        elif h.get("Drive OAuth") not in {"Ready", "Connected"}: msg = "Next: ensure Drive API is enabled for the OAuth project, then click 3. Authorize Google Drive and approve access in the browser."
        elif h.get("Drive API") != "Ready": msg = "Drive API is not verified. Click 1. Enable Google Drive API, click Enable in Google Cloud, then Refresh or authorize again."
        elif h.get("Control repo") != "Ready": msg = "Next: click 4. Bootstrap / Update Control Plane to create the private control repository."
        elif h.get("GitHub Workflows") != "Ready": msg = "Next: run Bootstrap / Update again to publish all required workflows."
        elif h.get("GitHub Secrets") != "Ready": msg = "Next: run Bootstrap / Update with Drive OAuth configured to set all Drive folder secrets."
        elif h.get("Drive Sync") != "Ready": msg = "Drive Sync is not ready. Refresh and inspect Console / Sync History."
        else: msg = "Setup complete. Runtime status is derived from actual GitHub jobs; Idle means no job is currently consuming a runner."
        self.setup_hint_var.set(msg)

    def refresh_health(self):
        gh_ready = self.command_exists("gh")
        local = {
            "GitHub CLI": "Ready" if gh_ready else "Missing",
            "Git": "Ready" if self.command_exists("git") else "Missing",
            "Python": "Ready" if (self.command_exists("python") or self.command_exists("py") or getattr(sys, "frozen", False)) else "Missing",
            "Bridge Worker": "Ready" if all((self.package_dir() / n).exists() for n in ["bridge_worker.py", "requirements.txt"]) else "Missing",
            "Drive API": "Checking" if self._drive_oauth_ready() else "Not verified",
            "OAuth Client": "Ready" if self._oauth_client_ready() else "Not configured",
        }
        self._apply_health(local)
        if not gh_ready:
            self._apply_health({"GitHub Login": "gh required", "Control repo": "gh required", "GitHub Workflows": "gh required", "GitHub Secrets": "gh required", "Drive API": self._drive_api_status()[0], "Drive OAuth": "Not configured" if not self._drive_oauth_ready() else "Local", "Drive Sync": "Not ready", "Last Sync": "Unknown"})
            self.windows_runtime_var.set("Not ready"); self.macos_runtime_var.set("Not ready")
            return

        repo = self.repo()
        def worker():
            result: dict[str, str] = {}
            code, _ = self._run_quiet(["gh", "auth", "status", "--hostname", "github.com"])
            if code != 0:
                result.update({"GitHub Login": "Not logged in", "Control repo": "Unknown", "GitHub Workflows": "Unknown", "GitHub Secrets": "Unknown", "Drive Sync": "Not ready", "Last Sync": "Unknown"})
                self.after(0, lambda: self._apply_health(result)); return
            result["GitHub Login"] = "Connected"
            drive_ok, drive_detail = self._drive_test()
            api_status, api_detail = self._drive_api_status()
            result["Drive API"] = api_status
            result["Drive OAuth"] = "Ready" if drive_ok else ("Not configured" if not self._drive_oauth_ready() else "Error")
            self.after(0, lambda: self.security_info_var.set(f"Drive API: {api_status}. Drive OAuth: {drive_detail}. Secret values are never displayed."))

            code, _ = self._run_quiet(["gh", "repo", "view", repo, "--json", "nameWithOwner"])
            if code != 0:
                result.update({"Control repo": "Not created", "GitHub Workflows": "Not ready", "GitHub Secrets": "Not ready", "Drive Sync": "Not ready", "Last Sync": "Never"})
                self.after(0, lambda: self._apply_health(result)); self.after(0, lambda: self._apply_runtime("Not ready", "Not ready")); return
            result["Control repo"] = "Ready"

            wf_ok = True
            for wf in ["virtual-cloud-runners.yml", "virtual-cloud-drive-sync.yml", "build-control-center.yml"]:
                c, _ = self._run_quiet(["gh", "workflow", "view", wf, "--repo", repo])
                wf_ok = wf_ok and c == 0
            result["GitHub Workflows"] = "Ready" if wf_ok else "Missing"

            sc, so = self._run_quiet(["gh", "secret", "list", "--repo", repo])
            names = {line.split()[0] for line in so.splitlines() if line.strip()} if sc == 0 else set()
            present = EXPECTED_SECRETS & names
            secrets_ok = EXPECTED_SECRETS.issubset(names)
            result["GitHub Secrets"] = "Ready" if secrets_ok else (f"{len(present)}/{len(EXPECTED_SECRETS)}" if sc == 0 else "Unknown")
            multi_repo = "configured" if "MULTI_REPO_TOKEN" in names else "not configured (optional)"
            self.after(0, lambda: self.security_info_var.set(f"Drive API: {api_status}. Drive OAuth: {drive_detail}. Private multi-repo access: {multi_repo}. Secret values are never displayed."))
            result["Drive Sync"] = "Ready" if wf_ok and secrets_ok and drive_ok else "Not ready"

            rc, ro = self._run_quiet(["gh", "run", "list", "--repo", repo, "--workflow", "virtual-cloud-drive-sync.yml", "--limit", "1", "--json", "status,conclusion,createdAt,updatedAt"])
            if rc == 0:
                try:
                    rows = json.loads(ro or "[]")
                    if rows:
                        rr = rows[0]; stamp = str(rr.get("updatedAt") or rr.get("createdAt") or "").replace("T", " ").replace("Z", " UTC")
                        state = rr.get("conclusion") or rr.get("status") or "unknown"
                        result["Last Sync"] = f"{state} · {stamp}" if stamp else str(state)
                    else: result["Last Sync"] = "Never"
                except Exception: result["Last Sync"] = "Unknown"
            else: result["Last Sync"] = "Unknown"

            windows, macos = self._runtime_status(repo)
            self.after(0, lambda: self._apply_runtime(windows, macos))
            self.after(0, lambda: self._apply_health(result))
        threading.Thread(target=worker, daemon=True).start()

    def _apply_runtime(self, windows: str, macos: str):
        self.windows_runtime_var.set(windows); self.macos_runtime_var.set(macos)

    def _runtime_status(self, repo: str) -> tuple[str, str]:
        code, out = self._run_quiet(["gh", "run", "list", "--repo", repo, "--workflow", "virtual-cloud-runners.yml", "--limit", "1", "--json", "databaseId,status,conclusion"])
        if code != 0: return "Not ready", "Not ready"
        try:
            runs = json.loads(out or "[]")
            if not runs: return "Idle", "Idle"
            rid = str(runs[0]["databaseId"])
            jc, jo = self._run_quiet(["gh", "api", f"repos/{repo}/actions/runs/{rid}/jobs?per_page=100"])
            if jc != 0: return "Idle", "Idle"
            jobs = json.loads(jo).get("jobs", [])
            statuses = {"windows": "Idle", "macos": "Idle"}
            for j in jobs:
                oskey = self._classify_job_os(j)
                if not oskey: continue
                status = j.get("status") or "unknown"; conc = j.get("conclusion")
                if status in {"queued", "waiting", "pending"}: text = "Queued"
                elif status == "in_progress": text = "Running"
                elif status == "completed": text = (conc or "Completed").replace("_", " ").title()
                else: text = status.title()
                statuses[oskey] = text
            return statuses["windows"], statuses["macos"]
        except Exception:
            return "Unknown", "Unknown"

    @staticmethod
    def _classify_job_os(job: dict) -> str | None:
        text = " ".join([str(job.get("name") or ""), str(job.get("runner_name") or ""), " ".join(job.get("labels") or [])]).lower()
        if "windows" in text: return "windows"
        if "macos" in text or "mac-" in text: return "macos"
        return None


    def configure_multi_repo_token(self):
        if not self.command_exists("gh"):
            messagebox.showwarning(APP_NAME, "GitHub CLI is required.")
            return
        if not messagebox.askyesno(
            APP_NAME,
            "Use the token from the current GitHub CLI login as the private cross-repository checkout secret?\n\n"
            "The token value will not be displayed or written to the Control Center config."
        ):
            return
        code, token = self._run_quiet(["gh", "auth", "token"], timeout=10)
        token = token.strip()
        if code != 0 or not token:
            messagebox.showerror(APP_NAME, "Could not read the current gh login token.")
            return
        set_code, out = self._run_quiet(["gh", "secret", "set", "MULTI_REPO_TOKEN", "--repo", self.repo()], timeout=30, input_text=token + "\n")
        token = ""
        if set_code == 0:
            self.audit("configure-multi-repo-token", self.repo(), "success")
            messagebox.showinfo(APP_NAME, "Private multi-repo access secret configured.")
            self.refresh_health()
        else:
            self.audit("configure-multi-repo-token", self.repo(), "failed", out[-500:])
            messagebox.showerror(APP_NAME, "Could not configure MULTI_REPO_TOKEN. See Console/Audit for details.")

    # ---------- setup ----------
    def check_github_login(self):
        if not self.command_exists("gh"):
            messagebox.showwarning(APP_NAME, "GitHub CLI (gh) is not installed."); return
        self.notebook.select(self.logs_tab); self.runner.run_async(["gh", "auth", "status"])

    def setup_everything(self):
        if not self.command_exists("gh"):
            messagebox.showwarning(APP_NAME, "GitHub CLI (gh) is required."); return
        code, _ = self._run_quiet(["gh", "auth", "status", "--hostname", "github.com"])
        if code != 0:
            messagebox.showinfo(APP_NAME, "GitHub is not logged in. A terminal will open for 'gh auth login'. Return here and click Setup Everything again.")
            if os.name == "nt": subprocess.Popen(["cmd.exe", "/c", "start", "cmd.exe", "/k", "gh auth login"])
            else: self.runner.run_async(["gh", "auth", "login"])
            return

        if not self._oauth_client_ready():
            self.open_drive_api_enable()
            self.open_google_oauth_setup()
            messagebox.showinfo(
                APP_NAME,
                "Google Cloud setup pages were opened.\n\n"
                "1) Select one Cloud project and Enable Google Drive API.\n"
                "2) In Google Auth Platform create a Desktop app (recommended) or Web app OAuth client.\n"
                "3) Download its JSON.\n\n"
                "Return here, click 3. Authorize Google Drive, select that JSON once, and approve access.",
            )
            return

        if not self._drive_oauth_ready():
            self.open_drive_api_enable()
            self.authorize_drive(after_success=self._after_drive_authorized_setup)
            return

        api_status, api_detail = self._drive_api_status()
        if api_status != "Ready":
            self.open_drive_api_enable()
            messagebox.showwarning(
                APP_NAME,
                "Google Drive API is not verified yet.\n\n"
                + api_detail
                + "\n\nClick Enable in Google Cloud, wait a few seconds, then click Refresh / Setup Everything again.",
            )
            return
        self.bootstrap()

    def _after_drive_authorized_setup(self):
        api_status, api_detail = self._drive_api_status()
        if api_status == "Ready":
            self.bootstrap()
            return
        self.open_drive_api_enable()
        messagebox.showwarning(
            APP_NAME,
            "OAuth permission was granted, but the Drive API request is not ready yet.\n\n"
            + api_detail
            + "\n\nEnable Google Drive API for the same project, then click Setup Everything again.",
        )

    def authorize_drive(self, after_success=None):
        client = self.oauth_client_var.get().strip() if hasattr(self, "oauth_client_var") else self.config_data.oauth_client_path
        if not client or not Path(client).exists():
            picked = filedialog.askopenfilename(
                title="Select Google OAuth Client JSON (Web or Desktop)",
                filetypes=[("JSON", "*.json"), ("All files", "*.*")],
            )
            if not picked:
                return
            try:
                client = str(self._import_oauth_client_json(picked))
                self.oauth_client_var.set(client)
            except Exception as exc:
                messagebox.showerror(
                    APP_NAME,
                    f"OAuth client JSON is not ready: {exc}\n\n"
                    f"For a Web application client, add an Authorized redirect URI such as:\n{WEB_OAUTH_DEFAULT_REDIRECT}",
                )
                return

        output = self.cred_var.get().strip() or str(DEFAULT_OAUTH_TOKEN_PATH)
        try:
            if Path(output).resolve().parent == self.package_dir().resolve():
                output = str(DEFAULT_OAUTH_TOKEN_PATH)
        except Exception:
            pass
        self.cred_var.set(output)
        self.save_settings()
        self.notebook.select(self.logs_tab)
        cmd = [sys.executable, "--authorize-drive", client, output] if getattr(sys, "frozen", False) else [sys.executable, str(Path(__file__).resolve()), "--authorize-drive", client, output]
        self.audit("authorize-drive", output)
        self.status_var.set("Opening Google authorization in your browser…")

        def done(code, text):
            self.audit("authorize-drive", output, "success" if code == 0 else "failed", text[-900:])
            self.after(0, self.refresh_health)
            if code == 0:
                def auth_ok_message():
                    api_status, api_detail = self._drive_api_status()
                    if api_status == "Ready":
                        messagebox.showinfo(APP_NAME, "Google Drive permission granted and Drive API verified. OAuth credentials were saved locally for Drive Sync.")
                    else:
                        messagebox.showwarning(APP_NAME, "Google Drive permission was granted, but Drive API is not verified yet.\n\n" + api_detail)
                self.after(0, auth_ok_message)
                if after_success:
                    self.after(500, after_success)
            else:
                self.after(0, lambda: messagebox.showerror(APP_NAME, "Google Drive authorization failed. See Console for the exact OAuth/redirect error."))

        self.runner.run_async(cmd, cwd=self.package_dir(), callback=done)

    def bootstrap(self):
        script = self.package_dir() / "bootstrap-control-plane.ps1"
        if not script.exists(): messagebox.showerror(APP_NAME, f"Missing: {script}"); return
        cred = self.cred_var.get().strip()
        args = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), "-Repo", self.repo()]
        if cred and Path(cred).exists(): args += ["-DriveUserCredentialsJsonPath", cred]
        else:
            if not messagebox.askyesno(APP_NAME, "Drive OAuth is not configured. Create/update the repo without Drive secrets?"): return
            args.append("-SkipSecrets")
        self.notebook.select(self.logs_tab); self.audit("bootstrap-control-plane", self.repo())
        def done(c, o):
            self.audit("bootstrap-control-plane", self.repo(), "success" if c == 0 else "failed", o[-700:]); self.after(0, self.refresh_all)
        self.runner.run_async(args, cwd=self.package_dir(), callback=done)

    def build_exe_on_github(self):
        if not self.command_exists("gh"): messagebox.showwarning(APP_NAME, "GitHub CLI is required."); return
        self.notebook.select(self.logs_tab); self.audit("build-exe", self.repo())
        self.runner.run_async(["gh", "workflow", "run", "build-control-center.yml", "--repo", self.repo()], callback=lambda c, o: self._after_action("build-exe", self.repo(), c, o))

    # ---------- control plane run actions ----------
    def dispatch_control(self, target: str, source_repo: str = "", source_ref: str = ""):
        if not self.command_exists("gh"): messagebox.showwarning(APP_NAME, "GitHub CLI is required."); return
        args = ["gh", "workflow", "run", "virtual-cloud-runners.yml", "--repo", self.repo(), "-f", f"target={target}", "-f", "artifact_name=virtual-cloud-build", "-f", f"retention_days={max(1, int(self.retention_var.get()))}"]
        if source_repo: args += ["-f", f"source_repository={source_repo}"]
        if source_ref: args += ["-f", f"source_ref={source_ref}"]
        target_desc = f"{target}:{source_repo or self.repo()}@{source_ref or 'default'}"
        self.audit("dispatch-runner", target_desc); self.notebook.select(self.logs_tab)
        self.runner.run_async(args, callback=lambda c, o: self._after_action("dispatch-runner", target_desc, c, o))

    def _after_action(self, action: str, target: str, code: int, output: str):
        self.audit(action, target, "success" if code == 0 else "failed", output[-700:])
        self.after(1000, self.refresh_all)

    def cancel_selected_run(self):
        rid = self._selected_tree_run_id()
        if not rid: messagebox.showinfo(APP_NAME, "Select a run first."); return
        if not messagebox.askyesno(APP_NAME, f"Cancel GitHub Actions run {rid}?"): return
        self.audit("cancel-run", rid); self.notebook.select(self.logs_tab)
        self.runner.run_async(["gh", "run", "cancel", rid, "--repo", self.repo()], callback=lambda c, o: self._after_action("cancel-run", rid, c, o))

    def rerun_selected(self):
        rid = self._selected_tree_run_id()
        if not rid: messagebox.showinfo(APP_NAME, "Select a run first."); return
        self.audit("rerun", rid); self.notebook.select(self.logs_tab)
        self.runner.run_async(["gh", "run", "rerun", rid, "--repo", self.repo()], callback=lambda c, o: self._after_action("rerun", rid, c, o))

    def rerun_failed(self):
        rid = self._selected_tree_run_id()
        if not rid: messagebox.showinfo(APP_NAME, "Select a run first."); return
        self.audit("rerun-failed", rid); self.notebook.select(self.logs_tab)
        self.runner.run_async(["gh", "run", "rerun", rid, "--repo", self.repo(), "--failed"], callback=lambda c, o: self._after_action("rerun-failed", rid, c, o))

    def retry_drive_sync(self):
        rid = self._selected_tree_run_id()
        if not rid: messagebox.showinfo(APP_NAME, "Select the source runner run first."); return
        self._retry_sync_run(rid)

    def _retry_sync_run(self, rid: str):
        self.audit("retry-drive-sync", rid); self.notebook.select(self.logs_tab)
        args = ["gh", "workflow", "run", "virtual-cloud-drive-sync.yml", "--repo", self.repo(), "-f", f"source_run_id={rid}"]
        self.runner.run_async(args, callback=lambda c, o: self._after_action("retry-drive-sync", rid, c, o))

    def stop_foreground_command(self):
        if self.runner.stop(): self.log("Foreground command termination requested.", "warn")
        else: self.log("No foreground command is running.", "warn")

    # ---------- runs ----------
    def refresh_runs(self, silent: bool = False):
        if not self.command_exists("gh"): return
        repo = self.repo()
        def worker():
            code, output = self._run_quiet([
                "gh", "run", "list", "--repo", repo, "--limit", "30", "--json",
                "databaseId,displayTitle,workflowName,status,conclusion,headBranch,headSha,createdAt,updatedAt,url,event"
            ])
            if code != 0:
                if not silent: self.log(f"Could not refresh runs: {output}", "err")
                return
            try: data = json.loads(output or "[]")
            except Exception as exc:
                if not silent: self.log(f"Could not parse runs: {exc}", "err")
                return
            self.after(0, lambda: self._populate_runs(data))
        threading.Thread(target=worker, daemon=True).start()

    def _populate_runs(self, data: list[dict]):
        previous = dict(self.run_state_cache)
        self.run_rows.clear()
        for tree in (self.runs_tree, self.latest_tree):
            for item in tree.get_children(): tree.delete(item)
        queued = running = failed = 0
        for idx, row in enumerate(data):
            rid = str(row.get("databaseId", "")); self.run_rows[rid] = row
            state = (row.get("status") or "", row.get("conclusion") or "")
            self.run_state_cache[rid] = state
            if state[0] in {"queued", "waiting", "pending"}: queued += 1
            if state[0] == "in_progress": running += 1
            if state[1] == "failure": failed += 1
            created = str(row.get("createdAt", "")).replace("T", " ").replace("Z", " UTC")
            title = row.get("displayTitle") or row.get("workflowName") or ""
            sha = str(row.get("headSha") or "")[:8]
            duration = self._duration(row.get("createdAt"), row.get("updatedAt") if state[0] == "completed" else None)
            self.runs_tree.insert("", "end", iid=f"run-{rid}", values=(rid, title, state[0], state[1], row.get("headBranch") or "", sha, created, duration))
            if idx < 8: self.latest_tree.insert("", "end", iid=f"latest-{rid}", values=(rid, title, state[0], state[1], created))
            if rid in previous and previous[rid][0] != "completed" and state[0] == "completed":
                self._notify(f"Run {rid} completed: {state[1] or 'completed'}")
        self.metric_vars["Queued"].set(str(queued)); self.metric_vars["Running"].set(str(running)); self.metric_vars["Failed"].set(str(failed))
        self.status_var.set(f"Loaded {len(data)} GitHub Actions runs")

    def _selected_run_changed(self):
        rid = self._selected_tree_run_id()
        if rid:
            self.monitor_run_var.set(rid); self.artifact_run_var.set(rid)
            self.load_selected_details(silent=True)

    def open_selected_run(self):
        rid = self._selected_tree_run_id()
        if not rid: return
        row = self.run_rows.get(rid, {})
        webbrowser.open(row.get("url") or f"{GITHUB_BASE}/{self.repo()}/actions/runs/{rid}")

    def load_selected_details(self, silent: bool = False):
        rid = self._selected_tree_run_id()
        if not rid:
            if not silent: messagebox.showinfo(APP_NAME, "Select a run first.")
            return
        repo = self.repo()
        def worker():
            code, out = self._run_quiet(["gh", "api", f"repos/{repo}/actions/runs/{rid}"])
            if code != 0:
                if not silent: self.log(out, "err")
                return
            try:
                d = json.loads(out); actor = (d.get("actor") or {}).get("login", "")
                text = (
                    f"Run ID: {rid}\nWorkflow: {d.get('name','')}\nStatus: {d.get('status','')} / {d.get('conclusion') or ''}\n"
                    f"Repository: {d.get('repository',{}).get('full_name',repo)}\nBranch: {d.get('head_branch','')}\nSHA: {d.get('head_sha','')}\n"
                    f"Event: {d.get('event','')}\nActor: {actor}\nCreated: {d.get('created_at','')}\nUpdated: {d.get('updated_at','')}\n"
                    f"Duration: {self._duration(d.get('run_started_at') or d.get('created_at'), d.get('updated_at') if d.get('status') == 'completed' else None)}\nURL: {d.get('html_url','')}"
                )
                self.after(0, lambda: self._set_run_details(text))
            except Exception as exc:
                if not silent: self.log(str(exc), "err")
        threading.Thread(target=worker, daemon=True).start()

    def _set_run_details(self, text: str):
        self.run_details.delete("1.0", "end"); self.run_details.insert("1.0", text)

    # ---------- live monitor ----------
    def monitor_selected_run(self):
        rid = self._selected_tree_run_id()
        if not rid: messagebox.showinfo(APP_NAME, "Select a run first."); return
        self.monitor_run_var.set(rid); self.notebook.select(self.monitor_tab); self.refresh_monitor(); self._schedule_monitor()

    def refresh_monitor(self):
        rid = self.monitor_run_var.get().strip()
        if not rid: return
        repo = self.repo()
        def worker():
            c, o = self._run_quiet(["gh", "api", f"repos/{repo}/actions/runs/{rid}/jobs?per_page=100"])
            if c != 0:
                self.after(0, lambda: self.monitor_summary_var.set("Could not load jobs")); return
            try: jobs = json.loads(o).get("jobs", [])
            except Exception: return
            self.after(0, lambda: self._populate_monitor_jobs(rid, jobs))
        threading.Thread(target=worker, daemon=True).start()

    def _populate_monitor_jobs(self, rid: str, jobs: list[dict]):
        self.monitor_jobs.clear()
        for item in self.jobs_tree.get_children(): self.jobs_tree.delete(item)
        active = 0
        for job in jobs:
            jid = str(job.get("id")); self.monitor_jobs[jid] = job
            oskey = self._classify_job_os(job) or ",".join(job.get("labels") or [])[:30] or "—"
            status = job.get("status") or ""; result = job.get("conclusion") or ""
            if status != "completed": active += 1
            self.jobs_tree.insert("", "end", iid=f"job-{jid}", values=(job.get("name") or jid, oskey, status, result, job.get("started_at") or "", self._duration(job.get("started_at"), job.get("completed_at") if status == "completed" else None)))
        self.monitor_summary_var.set(f"Run {rid}: {len(jobs)} jobs · {active} active")
        if active == 0 and self.monitor_after_id:
            try: self.after_cancel(self.monitor_after_id)
            except Exception: pass
            self.monitor_after_id = None

    def _populate_selected_job_steps(self):
        sel = self.jobs_tree.selection()
        if not sel: return
        jid = sel[0].replace("job-", ""); job = self.monitor_jobs.get(jid, {})
        for item in self.steps_tree.get_children(): self.steps_tree.delete(item)
        for step in job.get("steps") or []:
            self.steps_tree.insert("", "end", values=(step.get("name") or "", step.get("status") or "", step.get("conclusion") or "", step.get("number") or "", self._duration(step.get("started_at"), step.get("completed_at"))))

    def _schedule_monitor(self):
        if self.monitor_after_id:
            try: self.after_cancel(self.monitor_after_id)
            except Exception: pass
            self.monitor_after_id = None
        if self.monitor_auto_var.get() and self.monitor_run_var.get().strip():
            self.monitor_after_id = self.after(5000, self._monitor_tick)

    def _monitor_tick(self):
        self.monitor_after_id = None
        if self.monitor_auto_var.get():
            self.refresh_monitor(); self._schedule_monitor()

    def load_monitor_logs(self):
        rid = self.monitor_run_var.get().strip()
        if not rid: return
        self.notebook.select(self.logs_tab); self.audit("load-run-logs", rid)
        self.runner.run_async(["gh", "run", "view", rid, "--repo", self.repo(), "--log"])

    # ---------- artifacts ----------
    def refresh_artifacts(self):
        rid = self.artifact_run_var.get().strip() or self._selected_tree_run_id()
        if not rid: messagebox.showinfo(APP_NAME, "Enter or select a run ID first."); return
        self.artifact_run_var.set(rid); repo = self.repo(); self.artifact_status_var.set("Loading…")
        def worker():
            c, o = self._run_quiet(["gh", "api", f"repos/{repo}/actions/runs/{rid}/artifacts?per_page=100"])
            if c != 0:
                self.after(0, lambda: self.artifact_status_var.set("GitHub artifact query failed")); return
            try: artifacts = json.loads(o).get("artifacts", [])
            except Exception: artifacts = []
            receipt = {}
            try: receipt = self._load_receipts_map(120).get(rid, {})
            except Exception: pass
            self.after(0, lambda: self._populate_artifacts(rid, artifacts, receipt))
        threading.Thread(target=worker, daemon=True).start()

    def _populate_artifacts(self, rid: str, artifacts: list[dict], receipt: dict):
        self.artifact_rows.clear()
        for item in self.artifact_tree.get_children(): self.artifact_tree.delete(item)
        synced_names = set(receipt.get("artifact_names") or [])
        verification = receipt.get("verification") or {}
        for art in artifacts:
            aid = str(art.get("id")); self.artifact_rows[aid] = art
            name = art.get("name") or aid
            drive_state = "Synced" if name in synced_names or receipt.get("ok") else "Unknown"
            v = verification.get(name, {}) if isinstance(verification, dict) else {}
            integ = "Verified" if v.get("ok") is True else ("Failed" if v.get("ok") is False else "—")
            self.artifact_tree.insert("", "end", iid=f"artifact-{aid}", values=(name, self._bytes(art.get("size_in_bytes")), str(bool(art.get("expired"))), art.get("created_at") or "", drive_state, integ))
        self.artifact_status_var.set(f"{len(artifacts)} artifacts · Drive receipt {'found' if receipt else 'not found'}")
        if artifacts: self.latest_artifact_var.set(f"Latest artifact: {artifacts[0].get('name')} · {self._bytes(artifacts[0].get('size_in_bytes'))}")

    def _selected_artifact(self) -> tuple[str, dict] | tuple[None, None]:
        sel = self.artifact_tree.selection()
        if not sel: messagebox.showinfo(APP_NAME, "Select an artifact first."); return None, None
        aid = sel[0].replace("artifact-", ""); return aid, self.artifact_rows.get(aid, {})

    def download_selected_artifact(self):
        aid, art = self._selected_artifact()
        if not aid: return
        rid = self.artifact_run_var.get().strip(); name = str(art.get("name") or aid)
        root = Path(self.download_var.get().strip() or default_download_dir()) / f"run-{rid}" / name
        root.mkdir(parents=True, exist_ok=True)
        self.notebook.select(self.logs_tab); self.audit("download-artifact", f"{rid}:{name}")
        args = ["gh", "run", "download", rid, "--repo", self.repo(), "-n", name, "-D", str(root)]
        def done(c, o):
            if c == 0:
                ok, detail = self._verify_directory(root)
                self.log(f"Integrity: {'verified' if ok else detail}", "ok" if ok else "warn")
                self.audit("download-artifact", f"{rid}:{name}", "success", detail)
                self.after(0, lambda: self._open_local_path(root))
            else: self.audit("download-artifact", f"{rid}:{name}", "failed", o[-600:])
        self.runner.run_async(args, callback=done)

    def verify_selected_download(self):
        aid, art = self._selected_artifact()
        if not aid: return
        rid = self.artifact_run_var.get().strip(); name = str(art.get("name") or aid)
        root = Path(self.download_var.get().strip() or default_download_dir()) / f"run-{rid}" / name
        ok, detail = self._verify_directory(root)
        messagebox.showinfo(APP_NAME, f"Integrity {'verified' if ok else 'not verified'}\n\n{detail}")
        self.audit("verify-artifact", f"{rid}:{name}", "success" if ok else "failed", detail)

    @staticmethod
    def _verify_directory(root: Path) -> tuple[bool, str]:
        if not root.exists(): return False, f"Download directory not found: {root}"
        sums = list(root.rglob("SHA256SUMS.txt"))
        if not sums: return False, "SHA256SUMS.txt not found"
        base = sums[0].parent; errors = [] ; checked = 0
        for line in sums[0].read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.strip(): continue
            parts = line.split(None, 1)
            if len(parts) != 2: continue
            expected, rel = parts[0], parts[1].strip().lstrip("*")
            p = base / rel
            if not p.exists(): errors.append(f"missing {rel}"); continue
            actual = hashlib.sha256(p.read_bytes()).hexdigest(); checked += 1
            if actual.lower() != expected.lower(): errors.append(f"mismatch {rel}")
        return (not errors and checked > 0), (f"Verified {checked} files" if not errors and checked > 0 else "; ".join(errors[:10]) or "No checksum entries")

    def retry_drive_sync_from_artifact(self):
        rid = self.artifact_run_var.get().strip()
        if rid: self._retry_sync_run(rid)

    # ---------- repositories ----------
    def load_repositories(self):
        if not self.command_exists("gh"): return
        owner = self.repo().split("/", 1)[0]
        def worker():
            c, o = self._run_quiet(["gh", "repo", "list", owner, "--limit", "200", "--json", "nameWithOwner,isPrivate,defaultBranchRef,url"])
            if c != 0: self.log(o, "err"); return
            try: data = json.loads(o or "[]")
            except Exception: return
            self.after(0, lambda: self._populate_repositories(data))
        threading.Thread(target=worker, daemon=True).start()

    def _populate_repositories(self, data: list[dict]):
        self.repo_rows.clear()
        for item in self.repo_tree.get_children(): self.repo_tree.delete(item)
        values = []
        for idx, r in enumerate(data):
            name = r.get("nameWithOwner") or ""; values.append(name); self.repo_rows[name] = r
            default = (r.get("defaultBranchRef") or {}).get("name") if isinstance(r.get("defaultBranchRef"), dict) else r.get("defaultBranchRef") or ""
            self.repo_tree.insert("", "end", iid=f"repo-{idx}", values=(name, str(bool(r.get("isPrivate"))), default, r.get("url") or ""))
        self.repo_combo["values"] = values
        if not self.source_repo_var.get().strip() and values: self.source_repo_var.set(values[0])
        self.status_var.set(f"Loaded {len(values)} repositories")

    def _repo_tree_selected(self):
        sel = self.repo_tree.selection()
        if not sel: return
        vals = self.repo_tree.item(sel[0], "values")
        if vals: self.source_repo_var.set(str(vals[0])); self.load_repo_workflows()

    def load_repo_workflows(self):
        repo = self.source_repo_var.get().strip()
        if not repo: return
        def worker():
            c, o = self._run_quiet(["gh", "api", f"repos/{repo}/actions/workflows?per_page=100"])
            if c != 0: self.log(o, "err"); return
            try: workflows = json.loads(o).get("workflows", [])
            except Exception: workflows = []
            self.after(0, lambda: self._populate_workflows(workflows))
        threading.Thread(target=worker, daemon=True).start()

    def _populate_workflows(self, workflows: list[dict]):
        self.workflow_rows.clear(); display = []
        for w in workflows:
            key = str(w.get("id")); label = f"{w.get('name')}  [{w.get('path')}]"
            self.workflow_rows[label] = w; display.append(label)
        self.workflow_combo["values"] = display
        self.workflow_var.set(display[0] if display else "")

    def dispatch_selected_repo(self):
        repo = self.source_repo_var.get().strip()
        if not repo: messagebox.showinfo(APP_NAME, "Select a repository first."); return
        self.config_data.selected_repo = repo; self.config_data.save()
        self.dispatch_control(self.source_target_var.get(), repo, self.source_ref_var.get().strip())

    def run_selected_repo_workflow(self):
        repo = self.source_repo_var.get().strip(); label = self.workflow_var.get().strip()
        w = self.workflow_rows.get(label)
        if not repo or not w: messagebox.showinfo(APP_NAME, "Load and select a workflow first."); return
        try:
            raw = self.workflow_inputs.get("1.0", "end").strip() or "{}"; inputs = json.loads(raw)
            if not isinstance(inputs, dict): raise ValueError("Inputs JSON must be an object")
        except Exception as exc:
            messagebox.showerror(APP_NAME, f"Invalid Inputs JSON: {exc}"); return
        args = ["gh", "workflow", "run", str(w.get("id")), "--repo", repo]
        for k, v in inputs.items(): args += ["-f", f"{k}={v}"]
        self.audit("run-repo-workflow", f"{repo}:{w.get('name')}", details=json.dumps(inputs))
        self.notebook.select(self.logs_tab); self.runner.run_async(args, callback=lambda c, o: self._after_action("run-repo-workflow", f"{repo}:{w.get('name')}", c, o))

    def open_selected_repo_actions(self):
        repo = self.source_repo_var.get().strip()
        if repo: webbrowser.open(f"{GITHUB_BASE}/{repo}/actions")

    # ---------- sync history ----------
    def refresh_sync_history(self):
        if not self._drive_oauth_ready(): self.sync_info_var.set("Drive OAuth not configured"); return
        self.sync_info_var.set("Loading Drive receipts…")
        def worker():
            try: receipts = self._load_receipts_map(200)
            except Exception as exc:
                self.after(0, lambda: self.sync_info_var.set(f"Drive error: {exc}")); return
            self.after(0, lambda: self._populate_sync_history(receipts))
        threading.Thread(target=worker, daemon=True).start()

    def _populate_sync_history(self, receipts: dict[str, dict]):
        for item in self.sync_tree.get_children(): self.sync_tree.delete(item)
        rows = sorted(receipts.items(), key=lambda kv: str(kv[1].get("synced_at") or ""), reverse=True)
        for rid, d in rows:
            verification = d.get("verification") or {}
            vlist = list(verification.values()) if isinstance(verification, dict) else []
            verified = "Verified" if vlist and all(v.get("ok") for v in vlist) else ("Failed" if any(v.get("ok") is False for v in vlist) else "—")
            self.sync_tree.insert("", "end", iid=f"sync-{rid}", values=(rid, "Success" if d.get("ok") else "Failed", d.get("repo") or "", len(d.get("artifact_names") or []), verified, d.get("synced_at") or ""))
        self.metric_vars["Synced"].set(str(len(rows))); self.sync_info_var.set(f"{len(rows)} receipts")
        if rows:
            first = rows[0][1]
            names = first.get("artifact_names") or []
            if names: self.latest_artifact_var.set(f"Latest artifact: {names[0]} · synced")

    def retry_sync_from_history(self):
        sel = self.sync_tree.selection()
        if not sel: messagebox.showinfo(APP_NAME, "Select a sync receipt first."); return
        vals = self.sync_tree.item(sel[0], "values")
        if vals: self._retry_sync_run(str(vals[0]))

    # ---------- audit ----------
    def refresh_audit(self):
        if not hasattr(self, "audit_tree"): return
        for item in self.audit_tree.get_children(): self.audit_tree.delete(item)
        if not AUDIT_PATH.exists(): return
        try: lines = AUDIT_PATH.read_text(encoding="utf-8", errors="replace").splitlines()[-250:]
        except Exception: return
        for idx, line in enumerate(reversed(lines)):
            try:
                d = json.loads(line); stamp = str(d.get("time") or "").replace("T", " ").replace("+00:00", " UTC")
                self.audit_tree.insert("", "end", iid=f"audit-{idx}", values=(stamp, d.get("action") or "", d.get("target") or "", d.get("result") or "", d.get("details") or ""))
            except Exception: continue

    # ---------- cleanup ----------
    def cleanup_drive(self, delete: bool):
        if not self._drive_oauth_ready(): messagebox.showwarning(APP_NAME, "Drive OAuth is required."); return
        days = max(1, int(self.retention_var.get()))
        cutoff = datetime.now(timezone.utc).timestamp() - days * 86400
        folders = {
            "artifacts": DRIVE_ARTIFACTS_ID, "logs": DRIVE_LOGS_ID, "metadata": DRIVE_RUNS_ID,
            "checksums": DRIVE_CHECKSUMS_ID, "receipts": DRIVE_RECEIPTS_ID,
            "sync-completed": DRIVE_SYNC_COMPLETED_ID, "sync-failed": DRIVE_SYNC_FAILED_ID,
        }
        def worker():
            candidates = []
            try:
                drive = self._drive_service()
                for label, fid in folders.items():
                    for f in self._drive_list(fid, 1000):
                        dt = self._parse_dt(f.get("createdTime"))
                        if dt and dt.timestamp() < cutoff: candidates.append((label, f))
                if not delete:
                    total = sum(int(f.get("size") or 0) for _, f in candidates)
                    self.after(0, lambda: messagebox.showinfo(APP_NAME, f"Cleanup preview\n\n{len(candidates)} files older than {days} days\nApprox. {self._bytes(total)}")); return
                def confirm():
                    if not messagebox.askyesno(APP_NAME, f"Delete {len(candidates)} Drive files older than {days} days? This cannot be undone."): return
                    def deleter():
                        removed = 0
                        for _, f in candidates:
                            try: drive.files().delete(fileId=f["id"]).execute(); removed += 1
                            except Exception: pass
                        self.audit("drive-cleanup", f">{days}d", "success", f"deleted={removed}")
                        self.after(0, lambda: messagebox.showinfo(APP_NAME, f"Deleted {removed} old Drive files."))
                        self.after(0, self.refresh_sync_history)
                    threading.Thread(target=deleter, daemon=True).start()
                self.after(0, confirm)
            except Exception as exc:
                self.after(0, lambda: messagebox.showerror(APP_NAME, f"Cleanup failed: {exc}"))
        threading.Thread(target=worker, daemon=True).start()

    # ---------- auto refresh ----------
    def _schedule_auto_refresh(self):
        if self.auto_refresh_after_id:
            try: self.after_cancel(self.auto_refresh_after_id)
            except Exception: pass
            self.auto_refresh_after_id = None
        enabled = self.auto_refresh_var.get() if hasattr(self, "auto_refresh_var") else self.config_data.auto_refresh
        seconds = max(5, int(self.refresh_seconds_var.get() if hasattr(self, "refresh_seconds_var") else self.config_data.refresh_seconds))
        self.auto_status_var.set(f"Auto refresh: {'on' if enabled else 'off'}" + (f" · {seconds}s" if enabled else "")) if hasattr(self, "auto_status_var") else None
        if enabled: self.auto_refresh_after_id = self.after(seconds * 1000, self._auto_refresh_tick)

    def _auto_refresh_tick(self):
        self.auto_refresh_after_id = None
        self.refresh_health(); self.refresh_runs(silent=True)
        if self._drive_oauth_ready():
            self.refresh_sync_history()
        self._schedule_auto_refresh()

    def refresh_all(self):
        self.refresh_health(); self.refresh_runs(silent=True)
        if self._drive_oauth_ready(): self.refresh_sync_history()

    def open_actions(self):
        webbrowser.open(f"{GITHUB_BASE}/{self.repo()}/actions")


def authorize_google_drive(client_file: str, output_file: str) -> int:
    """Authorize Google Drive from either a Desktop or Web OAuth client JSON.

    Desktop clients use Google's installed-app local server helper.
    Web clients use an explicit localhost callback, state validation, offline access,
    and the authorization-code exchange described in Google's web-server OAuth flow.
    """
    try:
        from google_auth_oauthlib.flow import Flow, InstalledAppFlow

        client_path = Path(client_file)
        data = json.loads(client_path.read_text(encoding="utf-8"))
        scopes = ["https://www.googleapis.com/auth/drive"]

        if "installed" in data:
            flow = InstalledAppFlow.from_client_secrets_file(str(client_path), scopes=scopes)
            credentials = flow.run_local_server(port=0, access_type="offline", prompt="consent")
        elif "web" in data:
            cfg = data["web"]
            redirects = [str(x) for x in (cfg.get("redirect_uris") or [])]
            local_redirects = [
                u for u in redirects
                if u.startswith("http://localhost:") or u.startswith("http://127.0.0.1:")
            ]
            if not local_redirects:
                raise RuntimeError(
                    "Web OAuth client has no localhost Authorized redirect URI. Add one in Google Cloud, e.g. "
                    + WEB_OAUTH_DEFAULT_REDIRECT
                )

            redirect_uri = WEB_OAUTH_DEFAULT_REDIRECT if WEB_OAUTH_DEFAULT_REDIRECT in local_redirects else local_redirects[0]
            parsed_redirect = urlparse(redirect_uri)
            host = parsed_redirect.hostname or "localhost"
            port = parsed_redirect.port
            callback_path = parsed_redirect.path or "/oauth2callback"
            if port is None:
                raise RuntimeError("The localhost redirect URI must include an explicit port, e.g. :8765.")

            flow = Flow.from_client_secrets_file(str(client_path), scopes=scopes, redirect_uri=redirect_uri)
            authorization_url, expected_state = flow.authorization_url(
                access_type="offline",
                include_granted_scopes="true",
                prompt="consent",
            )

            result = {"authorization_response": None, "error": None}

            class OAuthCallbackHandler(BaseHTTPRequestHandler):
                def log_message(self, fmt, *args):
                    return

                def do_GET(self):
                    parsed = urlparse(self.path)
                    if parsed.path != callback_path:
                        self.send_response(404)
                        self.end_headers()
                        return
                    params = parse_qs(parsed.query)
                    returned_state = (params.get("state") or [""])[0]
                    if returned_state != expected_state:
                        result["error"] = "OAuth state mismatch. Authorization was rejected for safety."
                    elif params.get("error"):
                        result["error"] = (params.get("error_description") or params.get("error") or ["authorization denied"])[0]
                    else:
                        result["authorization_response"] = redirect_uri.split(callback_path, 1)[0] + self.path

                    body = (
                        "<html><body style='font-family:Segoe UI,Arial;padding:32px'>"
                        "<h2>Virtual Cloud Control Center</h2>"
                        + ("<p>Google Drive permission received. You can close this browser tab.</p>" if not result["error"] else f"<p>Authorization failed: {result['error']}</p>")
                        + "</body></html>"
                    ).encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)

            server = HTTPServer((host, port), OAuthCallbackHandler)
            server.timeout = 300
            print(f"Opening Google consent page. Callback: {redirect_uri}")
            if not webbrowser.open(authorization_url):
                print("Open this authorization URL in your browser:\n" + authorization_url)

            deadline = time.time() + 300
            while result["authorization_response"] is None and result["error"] is None and time.time() < deadline:
                server.handle_request()
            server.server_close()

            if result["error"]:
                raise RuntimeError(str(result["error"]))
            if not result["authorization_response"]:
                raise TimeoutError("Timed out waiting for Google OAuth callback after 5 minutes.")

            flow.fetch_token(authorization_response=str(result["authorization_response"]))
            credentials = flow.credentials
        else:
            raise RuntimeError("OAuth JSON must contain either a 'web' or 'installed' client configuration.")

        out = Path(output_file)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(credentials.to_json(), encoding="utf-8")
        try:
            os.chmod(out, 0o600)
        except Exception:
            pass
        print(f"Drive OAuth credentials created: {out}")
        return 0
    except Exception as exc:
        print(f"Google Drive OAuth failed: {exc}", file=sys.stderr)
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--authorize-drive", nargs=2, metavar=("CLIENT_JSON", "OUTPUT_JSON"))
    args, _ = parser.parse_known_args()
    if args.authorize_drive:
        return authorize_google_drive(args.authorize_drive[0], args.authorize_drive[1])
    app = ControlCenter(); app.mainloop(); return 0


if __name__ == "__main__":
    raise SystemExit(main())
