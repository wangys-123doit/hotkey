<#
.SYNOPSIS
    把 Chrome 主 profile 数据复制到一个或多个桌面专属 DebugProfile 目录。
.DESCRIPTION
    适用场景：
        你已经通过 OpenControllerFromNetwork.ahk 实现了按虚拟桌面隔离调试 Chrome
        （桌面 1 → DebugProfile\Desktop1:9223，桌面 2 → DebugProfile\Desktop2:9224，...），
        希望每个桌面的调试 Chrome 都保留和主 profile 一样的书签、登录状态、扩展。

    本脚本会：
        1. 关闭所有 Chrome 进程（避免 SingletonLock 报错）
        2. 把源 User Data 目录（排除缓存）复制到目标目录
        3. 支持一次性复制到多个桌面目录（-Desktops 1,2,3,4）

    常用场景：
        # 复制到桌面 1 的调试目录（默认）
        pwsh -File copy_chrome_profile_to_desktops.ps1

        # 一次性复制到桌面 1~4
        pwsh -File copy_chrome_profile_to_desktops.ps1 -Desktops 1,2,3,4

        # 指定源和主 profile 目录
        pwsh -File copy_chrome_profile_to_desktops.ps1 -Desktops 1,2,3,4 -SrcRoot 'D:\Chrome\User Data'

        # 只列出脚本会写入的目标目录，不执行复制
        pwsh -File copy_chrome_profile_to_desktops.ps1 -ListOnly
.NOTES
    执行前请确保没有 Chrome 窗口在输入重要内容（脚本会关闭 Chrome）。
    普通用户权限即可，不需要管理员权限。
#>

[CmdletBinding()]
param(
    # 要写入的桌面编号。参数为 [string[]]，支持以下所有传参形式：
    #   -Desktops 1,2,3,4            # 逗号分隔（PowerShell 会拆成字符串数组）
    #   -Desktops "1,2,3,4"          # 单个逗号分隔字符串
    #   -Desktops 1 -Desktops 2 ...  # 多次传参
    #   留空                          # 交互式询问
    #
    # 重要：不要改为 [int[]]，否则 "1,2,3,4" 会被 PowerShell 错误连成整数 1234
    [Parameter()]
    [string[]]$Desktops = @(),

    # 源 User Data 目录（主 profile），默认为 Chrome 默认路径
    [string]$SrcRoot = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),

    # 目标目录的父目录（各桌面目录会作为子目录放在这里）
    # 默认放在 E 盘以减少 C 盘 IO 负载
    [string]$DstParent = 'E:\chrome_profiles',

    # 只列出目标目录，不执行复制
    [switch]$ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# 配置：缓存目录排除列表
# ============================================================
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
    'DebugProfile'   # 避免把旧的 DebugProfile 整体再嵌套复制进去
)

# ============================================================
# 辅助函数
# ============================================================
function Test-ChromeRunning {
    # 用 $null -ne 兼容 0/1/N 进程三种返回类型（Get-Process 返回单对象时无 .Count）
    $null -ne (Get-Process -Name chrome -ErrorAction SilentlyContinue)
}

function Stop-AllChrome {
    if (-not (Test-ChromeRunning)) { return }
    Write-Host "⏳ 正在关闭所有 Chrome 进程..." -ForegroundColor Yellow
    Get-Process -Name chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
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

function Copy-WithExclude {
    param(
        [string]$Src,
        [string]$Dst
    )

    if (-not (Test-Path $Dst)) {
        New-Item -ItemType Directory -Path $Dst -Force | Out-Null
    }

    Get-ChildItem -Path $Src -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $item = $_
        $dstPath = Join-Path $Dst $item.Name

        if ($item.PSIsContainer) {
            if ($script:excludeDirs -contains $item.Name) {
                $script:skippedDirs += $item.Name
                return
            }
            Copy-WithExclude -Src $item.FullName -Dst $dstPath
        } else {
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

# ============================================================
# 主流程
# ============================================================

# 1. 验证源目录
if (-not (Test-Path $SrcRoot)) {
    throw "未找到 Chrome 主 profile 目录：$SrcRoot"
}
$srcSizeMB = Get-DirSizeMB $SrcRoot
Write-Host "`n📂 源 User Data：$SrcRoot" -ForegroundColor Cyan
Write-Host "💾 大小：$srcSizeMB MB" -ForegroundColor Cyan
Write-Host "🎯 目标父目录：$DstParent" -ForegroundColor Cyan

# 2. 确定目标桌面编号
# 参数类型为 [string[]]，遍历每个元素并按逗号/空格进一步拆分，然后解析为整数
# 这样可以同时支持 -Desktops 1,2,3,4 / -Desktops "1,2,3,4" / -Desktops 1 -Desktops 2 等多种传参形式
$desktopList = [System.Collections.Generic.List[int]]::new()

# 交互式询问
if ($Desktops.Count -eq 0) {
    $inputStr = Read-Host "`n请输入要写入的桌面编号（逗号分隔，如 1,2,3,4；直接回车默认只写 1）"
    if ([string]::IsNullOrWhiteSpace($inputStr)) {
        $Desktops = @('1')
    } else {
        $Desktops = @($inputStr)
    }
}

# 把每个元素进一步按逗号/空格拆分（主要为了处理单个元素是 "1,2,3,4" 这种情况）
$tokens = [System.Collections.Generic.List[string]]::new()
foreach ($item in $Desktops) {
    foreach ($part in $item -split '[,，\s]+') {
        $t = $part.Trim()
        if ($t -ne '') { $tokens.Add($t) }
    }
}

foreach ($tok in $tokens) {
    if ($tok -notmatch '^\d+$') {
        throw "无效的桌面编号：'$tok'（只接受正整数）"
    }
    $n = [int]$tok
    if ($n -lt 1 -or $n -gt 99) {
        throw "桌面编号 $n 超出合理范围（1~99），请检查 -Desktops 参数"
    }
    if (-not $desktopList.Contains($n)) {
        $desktopList.Add($n)
    }
}

if ($desktopList.Count -eq 0) {
    throw "未解析到任何有效的桌面编号"
}

$desktopList.Sort()
$Desktops = [int[]]$desktopList.ToArray()

Write-Host "🖥  目标桌面编号：$($Desktops -join ', ')" -ForegroundColor Cyan
Write-Host "   (类型: $($Desktops.GetType().FullName), 数量: $($Desktops.Count))" -ForegroundColor Gray

# 3. 计算目标路径
$targetDirs = $Desktops | ForEach-Object { Join-Path $DstParent "desktop$_" }

# 4. 列出目录（-ListOnly 到此结束）
Write-Host "`n即将写入的目标目录：" -ForegroundColor Cyan
foreach ($d in $targetDirs) {
    $exists = Test-Path $d
    Write-Host "   $(if ($exists){'🔄 已存在'}else{'🆕 新建'}) $d"
}
if ($ListOnly) { return }

# 5. 询问是否继续
Write-Host "`n⚠  即将执行以下操作：" -ForegroundColor Yellow
Write-Host "   - 关闭所有 Chrome 进程"
Write-Host "   - 清空已存在的目标目录（如有）"
Write-Host "   - 把源 User Data（排除缓存目录）复制到每个桌面目录"
$confirm = Read-Host "`n是否继续？(y/N)"
if ($confirm -notin 'y','Y','yes','YES') {
    Write-Host "❌ 已取消" -ForegroundColor Gray
    return
}

# 6. 关闭 Chrome
Stop-AllChrome

# 7. 清空所有目标目录
foreach ($d in $targetDirs) {
    if (Test-Path $d) {
        Write-Host "`n🧹 清空：$d" -ForegroundColor Yellow
        Remove-Item -Path $d -Recurse -Force
    }
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# 8. 依次复制到每个桌面目录
$overallSw = [System.Diagnostics.Stopwatch]::StartNew()
$grandCopiedFiles = 0
$grandCopiedBytes = 0L

foreach ($d in $targetDirs) {
    Write-Host "`n🚀 复制到：$d" -ForegroundColor Green
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $script:copiedFiles  = 0
    $script:copiedBytes  = 0L
    $script:skippedDirs  = @()
    $script:failedFiles  = @()

    Copy-WithExclude -Src $SrcRoot -Dst $d

    $sw.Stop()
    $elapsed  = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $copiedMB = [math]::Round($script:copiedBytes / 1MB, 1)
    $dstSizeMB = Get-DirSizeMB $d

    Write-Host "   耗时：$elapsed 秒 | 文件：$($script:copiedFiles) | 大小：$copiedMB MB | 最终：$dstSizeMB MB"
    if ($script:failedFiles.Count -gt 0) {
        Write-Host "   ⚠  $($script:failedFiles.Count) 个文件失败" -ForegroundColor Yellow
    }

    $grandCopiedFiles += $script:copiedFiles
    $grandCopiedBytes += $script:copiedBytes
}

$overallSw.Stop()
$overallElapsed = [math]::Round($overallSw.Elapsed.TotalSeconds, 1)
$grandCopiedMB  = [math]::Round($grandCopiedBytes / 1MB, 1)

# 9. 汇总报告
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "✅ 复制完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "总耗时：        $overallElapsed 秒"
Write-Host "总复制文件数：  $grandCopiedFiles"
Write-Host "总复制大小：    $grandCopiedMB MB"
Write-Host "写入的目录："
foreach ($d in $targetDirs) {
    $size = Get-DirSizeMB $d
    Write-Host "   - $d  ($size MB)"
}
Write-Host "`n跳过的缓存目录（去重）："
$script:skippedDirs | Select-Object -Unique | ForEach-Object { Write-Host "  - $_" }

# 10. 后续指引
Write-Host "`n📌 端口映射（与 OpenControllerFromNetwork.ahk 一致）：" -ForegroundColor Cyan
foreach ($n in $Desktops) {
    $port = 9222 + $n
    Write-Host "   桌面 $n → E:\chrome_profiles\desktop$n : 端口 $port"
}
Write-Host "`n📌 下一步：" -ForegroundColor Cyan
Write-Host "   1. 切换到目标桌面，按 PrtSc/RCtrl 启动该桌面的调试 Chrome"
Write-Host "   2. 首次启动后登录 Google 账号（同步扩展/书签），或使用本脚本已复制的 profile"
Write-Host "   3. 其他桌面如需同样数据，再次运行本脚本 -Desktops <N> 即可"
