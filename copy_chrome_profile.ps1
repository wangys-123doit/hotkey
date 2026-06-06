<#
.SYNOPSIS
    把 Chrome 主 profile 数据复制到 DebugProfile，保留书签/登录/扩展，跳过缓存目录。
.DESCRIPTION
    Chrome 主 profile 目录: %LocalAppData%\Google\Chrome\User Data
    调试 profile 目录:       %LocalAppData%\Google\Chrome\DebugProfile

    使用场景：
        你已经通过 hotkey.ahk 启用了 Chrome 远程调试端口，并希望调试 profile 拥有
        和主 profile 完全一样的书签、登录状态、扩展、历史记录等数据。

    流程：
        1. 强制关闭所有 chrome.exe 进程（避免文件被占用）
        2. 如 DebugProfile 已存在 → 删除重建
        3. 把 User Data 下所有内容（排除缓存和调试自身）复制到 DebugProfile
        4. 输出耗时与统计

    用法（以当前用户权限执行即可）：
        pwsh -ExecutionPolicy Bypass -File copy_chrome_profile.ps1
.NOTES
    执行前请确保没有 Chrome 窗口在输入重要内容（脚本会关闭 Chrome）
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# 配置区
# ============================================================
$userDataDir   = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$debugDataDir  = Join-Path $env:LOCALAPPDATA 'Google\Chrome\DebugProfile'

# 跳过这些目录（缓存/崩溃报告/临时数据），不复制；可自由增删
$excludeDirs = @(
    'Cache',
    'Code Cache',
    'GPUCache',
    'Service Worker',
    'DawnCache',
    'GrShaderCache',
    'ShaderCache',
    'DawnWebGPUCache',
    'GraphiteDawnCache',
    'Crashpad',
    'component_crx_cache',
    'extensions_crx_cache',
    'optimization_guide_model_store',
    'Local Traces',
    'DebugProfile'
)

# ============================================================
# 辅助函数
# ============================================================
function Test-ChromeRunning {
    # 注意：Get-Process 返回 1 个对象时是单个 ProcessInfo（无 .Count），
    # 返回多个时才是数组。用 $null -ne 判断最稳健，能同时兼容三种情况：
    #   - 0 个进程 → $null
    #   - 1 个进程 → 单个对象（非 $null）
    #   - N 个进程 → 数组（非 $null）
    $null -ne (Get-Process -Name chrome -ErrorAction SilentlyContinue)
}

function Stop-AllChrome {
    if (-not (Test-ChromeRunning)) { return }
    Write-Host "⏳ 正在关闭所有 Chrome 进程..." -ForegroundColor Yellow
    Get-Process -Name chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    # 二次确认
    if (Test-ChromeRunning) {
        Write-Host "⚠  仍有 chrome.exe 残留，再等待 2 秒..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
    if (Test-ChromeRunning) {
        throw "无法完全关闭 Chrome，请手动关闭后重试"
    }
}

function Get-DirSizeMB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $bytes = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue `
        | Measure-Object -Property Length -Sum).Sum
    [math]::Round($bytes / 1MB, 1)
}

# ============================================================
# 主流程
# ============================================================

# 1. 验证主 profile
if (-not (Test-Path $userDataDir)) {
    throw "未找到 Chrome 主 profile 目录：$userDataDir"
}
$srcSizeMB = Get-DirSizeMB $userDataDir
Write-Host "`n📂 主 profile 目录：$userDataDir" -ForegroundColor Cyan
Write-Host "💾 大小：$srcSizeMB MB" -ForegroundColor Cyan
Write-Host "🎯 目标目录：$debugDataDir" -ForegroundColor Cyan

# 2. 询问是否继续
Write-Host "`n⚠  即将执行以下操作：" -ForegroundColor Yellow
Write-Host "   - 关闭所有 Chrome 进程"
Write-Host "   - 如目标已存在则删除重建"
Write-Host "   - 复制主 profile（排除缓存目录）到 DebugProfile"
$confirm = Read-Host "`n是否继续？(y/N)"
if ($confirm -notin 'y','Y','yes','YES') {
    Write-Host "❌ 已取消" -ForegroundColor Gray
    return
}

# 3. 关闭 Chrome
Stop-AllChrome

# 4. 清空目标目录
if (Test-Path $debugDataDir) {
    Write-Host "`n🧹 清空已有 DebugProfile 目录..." -ForegroundColor Yellow
    Remove-Item -Path $debugDataDir -Recurse -Force
}
New-Item -ItemType Directory -Path $debugDataDir -Force | Out-Null

# 5. 复制（排除缓存）
Write-Host "`n🚀 开始复制..." -ForegroundColor Green
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$copiedFiles   = 0
$copiedBytes   = 0L
$skippedDirs   = @()
$failedFiles   = @()

function Copy-WithExclude {
    param(
        [string]$Src,
        [string]$Dst
    )

    # 确保目标目录存在
    if (-not (Test-Path $Dst)) {
        New-Item -ItemType Directory -Path $Dst -Force | Out-Null
    }

    Get-ChildItem -Path $Src -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $item = $_
        $dstPath = Join-Path $Dst $item.Name

        if ($item.PSIsContainer) {
            # 目录：检查排除列表
            if ($script:excludeDirs -contains $item.Name) {
                $script:skippedDirs += $item.Name
                return
            }
            Copy-WithExclude -Src $item.FullName -Dst $dstPath
        } else {
            # 文件：复制（遇错跳过）
            try {
                Copy-Item -Path $item.FullName -Destination $dstPath -Force
                $script:copiedFiles++
                $script:copiedBytes += $item.Length
            } catch {
                $script:failedFiles += $item.FullName
            }
        }
    }
}

Copy-WithExclude -Src $userDataDir -Dst $debugDataDir

$sw.Stop()
$elapsed   = [math]::Round($sw.Elapsed.TotalSeconds, 1)
$copiedMB  = [math]::Round($script:copiedBytes / 1MB, 1)
$dstSizeMB = Get-DirSizeMB $debugDataDir

# 6. 输出统计
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "✅ 复制完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "耗时：            $elapsed 秒"
Write-Host "复制文件数：      $($script:copiedFiles)"
Write-Host "复制大小：        $copiedMB MB"
Write-Host "DebugProfile 大小：$dstSizeMB MB"
Write-Host ""
Write-Host "跳过的缓存目录（去重）："
$script:skippedDirs | Select-Object -Unique | ForEach-Object { Write-Host "  - $_" }

if ($script:failedFiles.Count -gt 0) {
    Write-Host "`n⚠  $($script:failedFiles.Count) 个文件因占用/权限等原因复制失败：" -ForegroundColor Yellow
    $script:failedFiles | ForEach-Object { Write-Host "  - $_" }
}

Write-Host "`n📌 下一步：" -ForegroundColor Cyan
Write-Host "   按 PrtSc / RCtrl 触发热键启动 Chrome，将使用新复制的 DebugProfile。"
Write-Host "   如已启用系统级注册表（Win+Alt+8），点任何链接也会走 DebugProfile。"
