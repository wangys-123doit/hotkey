$ErrorActionPreference = "Stop"

$scriptDir = Split-Path $MyInvocation.MyCommand.Definition -Parent
$bridgePath = Join-Path $scriptDir "get-source-panel-line-number\bridge.js"
$healthUrl = "http://127.0.0.1:3000/health"

if (-not (Test-Path $bridgePath)) {
    Write-Error "bridge.js not found at $bridgePath"
}

try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 1
    if ($resp.StatusCode -eq 200) {
        Write-Host "Bridge already running at http://localhost:3000"
        exit 0
    }
} catch {
}

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Error "node command not found in PATH"
}

& $nodeCmd.Source $bridgePath
