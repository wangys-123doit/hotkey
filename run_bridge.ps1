$ErrorActionPreference = "Stop"

$scriptDir = Split-Path $MyInvocation.MyCommand.Definition -Parent
$bridgePath = Join-Path $scriptDir "get-source-panel-line-number\bridge.js"

if (-not (Test-Path $bridgePath)) {
    Write-Error "bridge.js not found at $bridgePath"
}

node $bridgePath
