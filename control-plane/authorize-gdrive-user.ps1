[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$OAuthClientJson,
  [string]$OutputCredentialPath = "$env:APPDATA\DriveVirtualCloudControlCenter\gdrive-user-credentials.json",
  [switch]$OpenDriveApi
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir = Split-Path -Parent $OutputCredentialPath
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

if ($OpenDriveApi) {
  $projectId = $null
  try {
    $json = Get-Content -Raw -Path $OAuthClientJson | ConvertFrom-Json
    if ($json.web) { $projectId = $json.web.project_id }
    elseif ($json.installed) { $projectId = $json.installed.project_id }
  } catch {}
  $url = 'https://console.cloud.google.com/apis/library/drive.googleapis.com'
  if ($projectId) { $url = "$url?project=$([uri]::EscapeDataString($projectId))" }
  Start-Process $url
  Write-Host 'Google Drive API page opened. Click Enable if needed, then return to this terminal.'
}

$python = $null
foreach ($candidate in @('py', 'python')) {
  if (Get-Command $candidate -ErrorAction SilentlyContinue) { $python = $candidate; break }
}
if (-not $python) { throw 'Python is required for Google Drive OAuth.' }

$requirements = Join-Path $here 'requirements.txt'
if (Test-Path $requirements) {
  & $python -m pip install --disable-pip-version-check -r $requirements
  if ($LASTEXITCODE -ne 0) { throw 'Failed to install Google OAuth dependencies.' }
}

$controlCenter = Join-Path $here 'control_center.py'
if (-not (Test-Path $controlCenter)) { throw "control_center.py not found near $here" }

$clientFile = (Resolve-Path $OAuthClientJson).Path
& $python $controlCenter --authorize-drive $clientFile $OutputCredentialPath
if ($LASTEXITCODE -ne 0) { throw 'Google Drive OAuth authorization failed.' }

Write-Host "Drive user credential JSON created: $OutputCredentialPath"
Write-Host 'Return to Control Center and click Refresh. Drive API should become Ready only after a real Drive v3 request succeeds.'
Write-Host 'Web OAuth clients must include a localhost Authorized redirect URI (for example http://localhost:8765/oauth2callback).'
Write-Host 'Desktop OAuth clients are also supported and recommended for the desktop app.'
Write-Host 'Keep both the OAuth client JSON and generated user credentials private.'
