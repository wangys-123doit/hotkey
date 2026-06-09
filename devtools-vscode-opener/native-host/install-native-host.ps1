param(
  [Parameter(Mandatory = $true)]
  [string]$ExtensionId,

  [string]$NodeExe = "",

  [switch]$InstallForEdge
)

$ErrorActionPreference = 'Stop'

if (-not $NodeExe) {
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if (-not $nodeCmd) {
    throw "未找到 node.exe，请先安装 Node.js 或通过 -NodeExe 指定路径"
  }
  $NodeExe = $nodeCmd.Source
}

if (-not (Test-Path $NodeExe)) {
  throw "Node 路径不存在: $NodeExe"
}

$hostName = 'com.tduck.vscode_opener'
$installDir = Join-Path $env:LOCALAPPDATA 'TDuckVSCodeNativeHost'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null

Copy-Item -Path (Join-Path $PSScriptRoot 'host.js') -Destination (Join-Path $installDir 'host.js') -Force

$hostCmdPath = Join-Path $installDir 'host.cmd'
$cmdContent = "@echo off`r`n`"$NodeExe`" `"%~dp0host.js`"`r`n"
Set-Content -Path $hostCmdPath -Value $cmdContent -Encoding ASCII

$manifestPath = Join-Path $installDir "$hostName.json"
@{
  name = $hostName
  description = 'TDuck VSCode opener native host'
  path = $hostCmdPath
  type = 'stdio'
  allowed_origins = @("chrome-extension://$ExtensionId/")
} | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

$chromeReg = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$hostName"
New-Item -Path $chromeReg -Force | Out-Null
Set-ItemProperty -Path $chromeReg -Name '(default)' -Value $manifestPath

if ($InstallForEdge) {
  $edgeReg = "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\$hostName"
  New-Item -Path $edgeReg -Force | Out-Null
  Set-ItemProperty -Path $edgeReg -Name '(default)' -Value $manifestPath
}

Write-Host "安装完成" -ForegroundColor Green
Write-Host "Host: $hostName"
Write-Host "Manifest: $manifestPath"
Write-Host "Node: $NodeExe"
Write-Host "ExtensionId: $ExtensionId"
