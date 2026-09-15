@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  set "PY=py"
) else (
  set "PY=python"
)
%PY% -c "import google_auth_oauthlib" >nul 2>nul
if errorlevel 1 (
  echo Installing Virtual Cloud Control Center dependencies...
  %PY% -m pip install --disable-pip-version-check -r requirements.txt
  if errorlevel 1 pause & exit /b 1
)
%PY% control_center.py
if errorlevel 1 pause
