[CmdletBinding()]
param(
  [string]$Python = 'py',
  [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

if (-not (Get-Command $Python -ErrorAction SilentlyContinue)) {
  if (Get-Command python -ErrorAction SilentlyContinue) { $Python = 'python' }
  else { throw 'Python 3 is required. Install Python and re-run this script.' }
}

if ($Clean) {
  Remove-Item -Recurse -Force build, dist -ErrorAction SilentlyContinue
  Remove-Item -Force VirtualCloudControlCenter.spec -ErrorAction SilentlyContinue
}

& $Python -m pip install --upgrade pyinstaller
if ($LASTEXITCODE -ne 0) { throw 'Failed to install PyInstaller.' }
& $Python -m pip install -r (Join-Path $here 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Failed to install Control Center dependencies.' }

& $Python -m PyInstaller `
  --noconfirm `
  --clean `
  --onefile `
  --windowed `
  --collect-submodules googleapiclient `
  --collect-submodules google_auth_oauthlib `
  --collect-submodules google.oauth2 `
  --name VirtualCloudControlCenter `
  control_center.py
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller build failed.' }

$exe = Join-Path $here 'dist\VirtualCloudControlCenter.exe'
if (-not (Test-Path $exe)) { throw "EXE not found after build: $exe" }
$portable = Join-Path $here 'dist\VirtualCloudControlCenter_Package'
New-Item -ItemType Directory -Force -Path $portable | Out-Null
Copy-Item $exe $portable -Force
$files = @(
  'bootstrap-control-plane.ps1','authorize-gdrive-user.ps1','build-control-center.ps1','run-control-center.bat',
  'bridge_worker.py','requirements.txt','virtual-cloud-runners.yml','virtual-cloud-drive-sync.yml','build-control-center.yml',
  '.gitignore','README.md','CONTROL_CENTER_README.md','AUDIT_REPORT.md','control_center.py'
)
foreach ($file in $files) {
  $src = Join-Path $here $file
  if (Test-Path $src) { Copy-Item $src $portable -Force }
}
Write-Host "Built: $exe"
Write-Host "Portable package: $portable"
