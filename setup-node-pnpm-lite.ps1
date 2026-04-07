$ErrorActionPreference = 'Stop'

function Write-Step($msg) {
  Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Ensure-Dir($path) {
  if (-not (Test-Path $path)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    Write-Host "Created: $path"
  } else {
    Write-Host "Exists:  $path"
  }
}

function Ensure-UserPathContains($item) {
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ([string]::IsNullOrWhiteSpace($userPath)) {
    $userPath = $item
    [Environment]::SetEnvironmentVariable('Path', $userPath, 'User')
    return
  }

  $parts = $userPath -split ';' | Where-Object { $_ -ne '' }
  if ($parts -notcontains $item) {
    $newPath = ($parts + $item) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "Added to User Path: $item"
  } else {
    Write-Host "User Path already has: $item"
  }
}

function Ensure-NvmMirrorOfficial() {
  $settings = Join-Path $env:LOCALAPPDATA 'nvm\settings.txt'
  if (-not (Test-Path $settings)) {
    throw "nvm settings not found: $settings"
  }

  $lines = Get-Content $settings
  $updated = $false

  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^node_mirror:\s*') {
      if ($lines[$i] -ne 'node_mirror: https://nodejs.org/dist/') {
        $lines[$i] = 'node_mirror: https://nodejs.org/dist/'
        $updated = $true
      }
    }
  }

  if ($updated) {
    Set-Content -Path $settings -Value $lines -Encoding ASCII
    Write-Host 'Updated node_mirror to official dist.'
  } else {
    Write-Host 'node_mirror already uses official dist.'
  }
}

Write-Step 'Check required commands'
if (-not (Get-Command nvm -ErrorAction SilentlyContinue)) {
  throw 'nvm not found in PATH. Please install nvm-windows first.'
}

Write-Step 'Fix nvm mirror (official dist)'
Ensure-NvmMirrorOfficial

Write-Step 'Ensure Node version is installed and active'
$targetVersion = '24.14.1'
$nvmList = nvm list | Out-String
if ($nvmList -notmatch [Regex]::Escape($targetVersion)) {
  Write-Host "Installing Node $targetVersion ..."
  nvm install $targetVersion 64
} else {
  Write-Host "Node $targetVersion already installed."
}
nvm use $targetVersion

Write-Step 'Prepare D-drive directories'
$npmCache = 'D:\nodejs\npm-cache'
$npmGlobal = 'D:\nodejs\npm-global'
$pnpmStore = 'D:\nodejs\pnpm-store'
$pnpmHome = 'D:\nodejs\pnpm-home'
Ensure-Dir $npmCache
Ensure-Dir $npmGlobal
Ensure-Dir $pnpmStore
Ensure-Dir $pnpmHome

Write-Step 'Configure npm cache/prefix'
npm config set cache $npmCache --global
npm config set prefix $npmGlobal --global

Write-Step 'Enable and activate pnpm via corepack'
corepack enable
corepack prepare pnpm@latest --activate

Write-Step 'Configure pnpm store/cache'
pnpm config set store-dir $pnpmStore --global
pnpm config set cache-dir $npmCache --global

Write-Step 'Set PNPM_HOME and PATH (User + current session)'
[Environment]::SetEnvironmentVariable('PNPM_HOME', $pnpmHome, 'User')
$env:PNPM_HOME = $pnpmHome
Ensure-UserPathContains $pnpmHome

if (($env:Path -split ';') -notcontains $pnpmHome) {
  $env:Path = $env:Path + ';' + $pnpmHome
}

Write-Step 'Quick verification'
Write-Host "nvm version: $(nvm version)"
Write-Host "node: $(node -v)"
Write-Host "npm:  $(npm -v)"
Write-Host "pnpm: $(pnpm -v)"
Write-Host "npm cache:  $(npm config get cache)"
Write-Host "npm prefix: $(npm config get prefix)"
Write-Host "pnpm store: $(pnpm config get store-dir)"
Write-Host "pnpm cache: $(pnpm config get cache-dir)"

Write-Host "`nDone. If any terminal still doesn't see pnpm, reopen terminal/VS Code." -ForegroundColor Green
