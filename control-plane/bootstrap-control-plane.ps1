[CmdletBinding()]
param(
  [string]$Repo = 'phakphoum38-stack/DRIVE_VIRTUAL_CLOUD_CONTROL_PLANE',
  [string]$DriveUserCredentialsJsonPath = '',
  [switch]$SkipSecrets
)

$ErrorActionPreference = 'Stop'

function Require-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

function Set-RepoSecret([string]$Name, [string]$Value) {
  $Value | gh secret set $Name --repo $Repo
  if ($LASTEXITCODE -ne 0) { throw "Failed to configure GitHub secret: $Name" }
}

Require-Command gh
Require-Command git

gh auth status | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated.' }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ("drive-virtual-cloud-control-plane-" + [guid]::NewGuid().ToString('N'))
$repoDir = Join-Path $workspace 'repo'
New-Item -ItemType Directory -Force -Path $workspace | Out-Null

try {
  gh repo view $Repo --json nameWithOwner *> $null
  $repoExists = ($LASTEXITCODE -eq 0)

  if ($repoExists) {
    Write-Host "Updating existing control plane repository: $Repo"
    gh repo clone $Repo $repoDir | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Failed to clone the existing control plane repository.' }
  }
  else {
    Write-Host "Creating new private control plane repository: $Repo"
    New-Item -ItemType Directory -Force -Path $repoDir | Out-Null
    Push-Location $repoDir
    try {
      git init -b main | Out-Host
      git config user.name 'Drive Virtual Cloud Bootstrap'
      git config user.email 'drive-virtual-cloud@users.noreply.github.com'
    }
    finally { Pop-Location }
  }

  New-Item -ItemType Directory -Force -Path (Join-Path $repoDir '.github/workflows') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $repoDir 'tools/virtual-cloud') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $repoDir 'app') | Out-Null

  $copies = @{
    'virtual-cloud-runners.yml' = '.github/workflows/virtual-cloud-runners.yml'
    'virtual-cloud-drive-sync.yml' = '.github/workflows/virtual-cloud-drive-sync.yml'
    'build-control-center.yml' = '.github/workflows/build-control-center.yml'
    'bridge_worker.py' = 'tools/virtual-cloud/bridge_worker.py'
    'requirements.txt' = 'tools/virtual-cloud/requirements.txt'
    'bootstrap-control-plane.ps1' = 'tools/virtual-cloud/bootstrap-control-plane.ps1'
    'authorize-gdrive-user.ps1' = 'tools/virtual-cloud/authorize-gdrive-user.ps1'
    'build-control-center.ps1' = 'tools/virtual-cloud/build-control-center.ps1'
    'run-control-center.bat' = 'tools/virtual-cloud/run-control-center.bat'
    'control_center.py' = 'app/control_center.py'
    'README.md' = 'README.md'
    'CONTROL_CENTER_README.md' = 'CONTROL_CENTER_README.md'
    'AUDIT_REPORT.md' = 'AUDIT_REPORT.md'
  }
  foreach ($srcName in $copies.Keys) {
    $src = Join-Path $here $srcName
    if (Test-Path $src) {
      Copy-Item -Force $src (Join-Path $repoDir $copies[$srcName])
    }
  }

  @'
# Never commit credentials
*.json
*credentials*.json
.env
.env.*
__pycache__/
*.pyc
dist/
build/
*.spec
'@ | Set-Content -Encoding utf8 (Join-Path $repoDir '.gitignore')

  Push-Location $repoDir
  try {
    git add .
    $changes = git status --porcelain
    if ($changes) {
      git config user.name 'Drive Virtual Cloud Bootstrap'
      git config user.email 'drive-virtual-cloud@users.noreply.github.com'
      if ($repoExists) {
        git commit -m 'update virtual cloud control plane' | Out-Host
        git push origin HEAD | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Failed to push control plane updates.' }
      }
      else {
        git commit -m 'bootstrap virtual cloud control plane' | Out-Host
        gh repo create $Repo --private --description 'Windows/macOS GitHub Runner control plane for Drive Virtual Cloud' --source . --remote origin --push | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create/push the GitHub repository.' }
      }
    }
    elseif (-not $repoExists) {
      throw 'Nothing was staged for the new repository.'
    }
    else {
      Write-Host 'Control plane files are already up to date.'
    }
  }
  finally { Pop-Location }

  if (-not $SkipSecrets) {
    if (-not $DriveUserCredentialsJsonPath) {
      Write-Warning 'Repository is ready, but Drive OAuth secrets were not set because no credential JSON was provided.'
    }
    else {
      $resolved = (Resolve-Path $DriveUserCredentialsJsonPath).Path
      Get-Content -Raw $resolved | gh secret set GDRIVE_USER_CREDENTIALS_JSON --repo $Repo
      if ($LASTEXITCODE -ne 0) { throw 'Failed to configure GDRIVE_USER_CREDENTIALS_JSON.' }
      Set-RepoSecret 'GDRIVE_ARTIFACTS_FOLDER_ID' '1TG6_gSbKcBpf1dkKV9FlL53jcM6GPqV_'
      Set-RepoSecret 'GDRIVE_LOGS_FOLDER_ID' '18J7X0eWZ7HrLuEifgxqN2r6d-fISJeVc'
      Set-RepoSecret 'GDRIVE_RUN_METADATA_FOLDER_ID' '1vNhGkENLe9LqMDgBf9tqmhRpdX3zHb0T'
      Set-RepoSecret 'GDRIVE_CHECKSUMS_FOLDER_ID' '1uBfISC3ABeXk0xepFCXCfkBUo3hi97vl'
      Set-RepoSecret 'GDRIVE_RECEIPTS_FOLDER_ID' '1rsuP77T6Nag74SoVqHqWmGhqPdi4Hnfg'
      Set-RepoSecret 'GDRIVE_SYNC_PENDING_FOLDER_ID' '149OM0kuuKzQnbTfkP3fEYvMZQaGXXnk9'
      Set-RepoSecret 'GDRIVE_SYNC_COMPLETED_FOLDER_ID' '1ZPQJoLRrYxfER-Wl9hMB3rrY1IZT7Sw_'
      Set-RepoSecret 'GDRIVE_SYNC_FAILED_FOLDER_ID' '1ftk85NR9oVpv5fow7ou7N1J44Mi__KZB'
      Write-Host 'GitHub Drive secrets configured.'
    }
  }

  Write-Host "Control plane repository: https://github.com/$Repo"
}
finally {
  Remove-Item -Recurse -Force $workspace -ErrorAction SilentlyContinue
}
