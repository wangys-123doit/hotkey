<#
.SYNOPSIS
    管理系统级 Chrome 启动命令（HKLM 注册表 ChromeHTML 协议）。
.DESCRIPTION
    让系统所有打开 Chrome 的入口（点链接/任务栏/开始菜单/邮件/其他应用 URL）
    都走 DebugProfile 目录，或还原为默认。

    注册表位置：
        HKLM\Software\Classes\ChromeHTML\shell\open\command

    工作原理：
        Windows 处理 http/https 链接时走：
        URLAssociations → UserChoice.ProgId=ChromeHTML
        → HKLM\Software\Classes\ChromeHTML\shell\open\command
        → 执行的命令（本脚本修改的就是这条命令）

    用法：
        pwsh -File set_chrome_system_protocol.ps1 -Action <show|enable|disable>

        show    - 查看当前启动命令（无需管理员权限）
        enable  - 修改为 DebugProfile 模式（需管理员权限，脚本自动提权）
        disable - 还原为默认启动命令（需管理员权限，脚本自动提权）

    示例：
        pwsh -File set_chrome_system_protocol.ps1 -Action show
        pwsh -File set_chrome_system_protocol.ps1 -Action enable
        pwsh -File set_chrome_system_protocol.ps1 -Action disable

    备份位置（enable 时自动保存，disable 时优先读取还原）：
        HKCU\Software\Classes\ChromeBackup\ProtocolCommand
.NOTES
    enable/disable 需要修改 HKLM，脚本会自动以管理员身份重新运行（弹 UAC 对话框）
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('show','enable','disable')]
    [string]$Action = 'show'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# 配置区
# ============================================================
$RegRoot       = 'HKLM'
$RegSubKey     = 'Software\Classes\ChromeHTML\shell\open\command'
$RegPath       = "Registry::$RegRoot\$RegSubKey"
$BackupPath    = 'Registry::HKCU\Software\Classes\ChromeBackup'
$BackupValue   = 'ProtocolCommand'

$DebugPort     = 9223
$ChromeExe     = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$DebugProfile  = Join-Path $env:LOCALAPPDATA 'Google\Chrome\DebugProfile'

# 候选 chrome.exe 路径（按优先级）
$ChromeCandidates = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
)

# ============================================================
# 辅助函数
# ============================================================
function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ChromeExePath {
    foreach ($p in $ChromeCandidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Invoke-AdminSelf {
    # 以管理员身份重新运行本脚本并传递相同参数
    if (-not (Test-Administrator)) {
        Write-Host "⚠  操作需要管理员权限，正在提权重新运行..." -ForegroundColor Yellow
        $argStr = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action"
        $proc = Start-Process -FilePath 'pwsh' -ArgumentList $argStr -Verb RunAs -Wait -PassThru
        exit $proc.ExitCode
    }
}

function Get-CurrentCommand {
    try {
        return (Get-ItemProperty -Path $RegPath -ErrorAction Stop).'(default)'
    } catch {
        return $null
    }
}

function Set-CurrentCommand {
    param([string]$Command)
    Set-ItemProperty -Path $RegPath -Name '(default)' -Value $Command -Type String -Force
}

function Backup-CurrentCommand {
    try {
        $cmd = Get-CurrentCommand
        if ($cmd) {
            if (-not (Test-Path $BackupPath)) {
                New-Item -Path $BackupPath -Force | Out-Null
            }
            Set-ItemProperty -Path $BackupPath -Name $BackupValue -Value $cmd -Type String -Force
            return $cmd
        }
    } catch { }
    return $null
}

function Get-BackupCommand {
    try {
        if (Test-Path $BackupPath) {
            return (Get-ItemProperty -Path $BackupPath -Name $BackupValue -ErrorAction Stop).$BackupValue
        }
    } catch { }
    return $null
}

function Remove-BackupKey {
    try {
        if (Test-Path $BackupPath) {
            Remove-Item -Path $BackupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

# ============================================================
# 三个核心操作
# ============================================================
function Do-Show {
    $cmd = Get-CurrentCommand
    Write-Host "`n📋 当前系统 Chrome 启动命令（$RegRoot\$RegSubKey）：" -ForegroundColor Cyan
    if (-not $cmd) {
        Write-Host "   (未找到)" -ForegroundColor Gray
        return
    }
    Write-Host "   $cmd" -ForegroundColor White

    $target = "--user-data-dir=`"$DebugProfile`""
    if ($cmd -match [regex]::Escape($target)) {
        Write-Host "`n✅ 已指向 DebugProfile" -ForegroundColor Green
        Write-Host "   → 系统所有打开 Chrome 的入口都会走：$DebugProfile"
    } else {
        Write-Host "`n⚠  未指向 DebugProfile（系统打开 Chrome 仍走默认 User Data）" -ForegroundColor Yellow
        Write-Host "   → 运行：pwsh -File `"$PSCommandPath`" -Action enable"
    }

    Write-Host "`n💡 常用操作：" -ForegroundColor Gray
    Write-Host "   pwsh -File `"$PSCommandPath`" -Action show     # 查看"
    Write-Host "   pwsh -File `"$PSCommandPath`" -Action enable   # 启用 DebugProfile（需管理员）"
    Write-Host "   pwsh -File `"$PSCommandPath`" -Action disable  # 还原默认（需管理员）"
}

function Do-Enable {
    Invoke-AdminSelf

    $chromeExe = Get-ChromeExePath
    if (-not $chromeExe) {
        Write-Host "❌ 未找到 chrome.exe" -ForegroundColor Red
        exit 1
    }

    # 备份当前命令
    $oldCmd = Backup-CurrentCommand

    # 写入新命令
    $newCmd = "`"$chromeExe`" --remote-debugging-port=$DebugPort --user-data-dir=`"$DebugProfile`" --single-argument %1"
    Set-CurrentCommand -Command $newCmd

    # 验证写入成功
    $verify = Get-CurrentCommand
    if ($verify -eq $newCmd) {
        Write-Host "`n✅ 已启用系统级 DebugProfile" -ForegroundColor Green
        Write-Host "`n旧命令（已备份）：" -ForegroundColor Gray
        Write-Host "   $oldCmd" -ForegroundColor Gray
        Write-Host "`n新命令：" -ForegroundColor Gray
        Write-Host "   $newCmd" -ForegroundColor Green
        Write-Host "`n📌 生效范围：系统所有打开 Chrome 的入口都会走：" -ForegroundColor Cyan
        Write-Host "   $DebugProfile"
        Write-Host "`n💡 如需还原：" -ForegroundColor Gray
        Write-Host "   pwsh -File `"$PSCommandPath`" -Action disable"
    } else {
        Write-Host "❌ 写入失败，当前值未匹配预期" -ForegroundColor Red
        exit 2
    }
}

function Do-Disable {
    Invoke-AdminSelf

    $chromeExe = Get-ChromeExePath
    # 优先用备份值，否则用默认值
    $defaultCmd = "`"$chromeExe`" --single-argument %1"
    $backup = Get-BackupCommand
    if ($backup) { $defaultCmd = $backup }

    Set-CurrentCommand -Command $defaultCmd
    Remove-BackupKey

    Write-Host "`n✅ 已还原系统 Chrome 启动命令" -ForegroundColor Green
    Write-Host "   $defaultCmd"
}

# ============================================================
# 入口
# ============================================================
switch ($Action) {
    'show'    { Do-Show }
    'enable'  { Do-Enable }
    'disable' { Do-Disable }
}
