[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$TargetHost = "17",
    [ValidateSet("fast", "safe")]
    [string]$Mode = "safe",
    [switch]$SkipProbe
    ,[string]$Mac = $null
    # [string]$TargetHost = "M1"
)

$logFile = Join-Path $PSScriptRoot "rdp.log"

function Write-RDPLog {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$time] $Message" -Encoding UTF8
}

function Test-TcpFast {
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][int]$Port,
        [int]$TimeoutMs = 500
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $asyncResult = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($asyncResult)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
        $client.Dispose()
    }
}

function Resolve-HostIPv4 {
    param(
        [Parameter(Mandatory=$true)][string]$HostName
    )
    # 如果已经是完整 IPv4 地址，直接返回
    if ($HostName -match '^[0-9]{1,3}(\.[0-9]{1,3}){3}$') {
        return $HostName
    }

    # 支持单数字短主机名（例如: "17"）——当作最后一段，尝试本地私有子网探测
    if ($HostName -match '^[0-9]{1,3}$') {
        $last = [int]$Matches[0]
        if ($last -ge 0 -and $last -le 255) {
            Write-Host "[INFO] Treating short host '$HostName' as last octet, trying DNS suffixes then probing subnets..." -ForegroundColor Cyan

            # 最小修复：首先尝试使用系统的 DNS 后缀列表（SuffixSearchList）逐个拼接解析短名
            try {
                $suffixes = (Get-DnsClientGlobalSetting -ErrorAction Stop).SuffixSearchList
            } catch {
                $suffixes = @()
            }
            foreach ($s in $suffixes) {
                if ([string]::IsNullOrWhiteSpace($s)) { continue }
                $fqdn = "$HostName.$s"
                try {
                    $ipObj = [System.Net.Dns]::GetHostAddresses($fqdn) |
                        Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
                        Select-Object -First 1
                    if ($ipObj) { Write-Host "[INFO] Resolved via suffix: $fqdn -> $($ipObj.IPAddressToString)" -ForegroundColor Green; return $ipObj.IPAddressToString }
                } catch {}
                try {
                    $dns = Resolve-DnsName -Name $fqdn -Type A -ErrorAction Stop |
                        Where-Object { $_.IPAddress } |
                        Select-Object -First 1
                    if ($dns -and $dns.IPAddress) { Write-Host "[INFO] Resolved via suffix: $fqdn -> $($dns.IPAddress)" -ForegroundColor Green; return $dns.IPAddress }
                } catch {}
            }

            $localIPs = @()
            try {
                $localIPs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress
            } catch {
                # 回退：解析 ipconfig 输出
                $ipconfig = (& ipconfig 2>$null) -split "`r?`n"
                foreach ($line in $ipconfig) {
                    if ($line -match 'IPv4.+?:\s*([0-9\.]+)') { $localIPs += $Matches[1] }
                }
            }

            foreach ($lip in $localIPs | Sort-Object -Unique) {
                if ($lip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)') {
                    $parts = $lip.Split('.')
                    if ($parts.Length -ge 3) {
                        $prefix = "$($parts[0]).$($parts[1]).$($parts[2])"
                        $candidate = "$prefix.$last"
                        # 优先用 TCP 快速探测 RDP 端口
                        if (Test-TcpFast -ComputerName $candidate -Port 3389 -TimeoutMs 500) {
                            Write-Host "[INFO] Resolved short host to $candidate (from $lip)" -ForegroundColor Green
                            return $candidate
                        }
                        # 再用 ping 兜底
                        try {
                            $pingText = (& ping.exe -4 -n 1 $candidate 2>$null) -join "`n"
                            if ($pingText -match "\[(\d{1,3}(?:\.\d{1,3}){3})\]") {
                                return $matches[1]
                            }
                        } catch {}
                    }
                }
            }
            # 如果以上探测都未命中，尝试用第一个本地 IP 的前三段作为前缀回退
            if ($localIPs -and $localIPs.Count -gt 0) {
                foreach ($lip in $localIPs) { if ($lip) { $firstLocal = $lip; break } }
                if ($firstLocal -and $firstLocal -match '^(\d+\.\d+\.\d+)') {
                    $prefix = $Matches[1]
                    $fallback = "$prefix.$last"
                    Write-Host "[WARN] No candidate found; falling back to $fallback" -ForegroundColor Yellow
                    return $fallback
                }
            }

            # 最小回退：常见局域网前缀
            $default = "192.168.1.$last"
            Write-Host "[WARN] No local prefix available; defaulting to $default" -ForegroundColor Yellow
            return $default
        }
    }

    # 1) .NET DNS（最快）
    try {
        $ipObj = [System.Net.Dns]::GetHostAddresses($HostName) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            Select-Object -First 1
        if ($ipObj) { return $ipObj.IPAddressToString }
    } catch {}

    # 2) Resolve-DnsName（兼容本地解析路径）
    try {
        $dns = Resolve-DnsName -Name $HostName -Type A -QuickTimeout -ErrorAction Stop |
            Where-Object { $_.IPAddress } |
            Select-Object -First 1
        if ($dns -and $dns.IPAddress) { return $dns.IPAddress }
    } catch {}

    # 3) ping 回显兜底（适配局域网主机名）
    try {
        $pingText = (& ping.exe -4 -n 1 $HostName 2>$null) -join "`n"
        if ($pingText -match "\[(\d{1,3}(?:\.\d{1,3}){3})\]") { return $matches[1] }
    } catch {}

    return $null
}

function Resolve-IPByMac {
    param(
        [Parameter(Mandatory=$true)][string]$Mac
    )

    # 规范化 MAC 格式为小写用短横
    $norm = $Mac.ToLower().Replace(':','-').Replace('.', '-')
    $norm = $norm -replace '\s',''

    # 1) 尝试本机邻居表（推荐）
    try {
        $nb = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.LinkLayerAddress -and ($_.LinkLayerAddress.ToLower().Replace(':','-') -eq $norm) } |
            Select-Object -First 1
        if ($nb -and $nb.IPAddress) { return $nb.IPAddress }
    } catch {}

    # 2) 回退解析 arp -a 输出
    try {
        $arpLines = (& arp -a) -split "`r?`n"
        foreach ($ln in $arpLines) {
            if ($ln -match '^\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s+([0-9a-fA-F:-]+)') {
                $ip = $Matches[1]
                $mac = $Matches[2].ToLower().Replace(':','-')
                if ($mac -eq $norm) { return $ip }
            }
        }
    } catch {}

    return $null
}

try {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] Resolving: $TargetHost" -ForegroundColor Cyan

    # Hostname -> MAC 映射（可按需修改或扩展）
    $HostMacMap = @{
        '17' = 'A2:B3:C4:D5:E6:F1'
        'X1' = '74:56:3C:C8:9A:58'
    }

    # 如果用户没有提供 -Mac，尝试从映射中获取
    if (-not $Mac -and $HostMacMap.ContainsKey($TargetHost)) {
        $Mac = $HostMacMap[$TargetHost]
        Write-Host "[INFO] Found MAC mapping for $TargetHost -> $Mac" -ForegroundColor Cyan
    }

    # 1. 如果有 MAC（映射或传参），优先通过 MAC 在同网段解析 IP
    $ip = $null
    if ($Mac) {
        Write-Host "[INFO] Resolving by MAC (priority): $Mac" -ForegroundColor Cyan
        try {
            $macIp = Resolve-IPByMac -Mac $Mac
            if ($macIp) { $ip = $macIp; Write-Host "[INFO] Resolved MAC $Mac -> $ip" -ForegroundColor Green }
            else { Write-Host "[WARN] MAC lookup failed for $Mac" -ForegroundColor Yellow }
        } catch { Write-Host "[WARN] MAC lookup error: $($_.Exception.Message)" -ForegroundColor Yellow }
    }

    # 2. 若 MAC 未得到 IP，则按主机名逐级解析（FQDN / DNS / DNS 后缀 / ping）
    if (-not $ip) { $ip = Resolve-HostIPv4 -HostName $TargetHost }

    if ([string]::IsNullOrWhiteSpace($ip)) {
        throw "Failed to resolve IPv4 for host: $TargetHost"
    }

    Write-Host "[INFO] Resolved IP: $ip" -ForegroundColor Green

    # 2. 端口探测 (3389) - 快速模式可跳过
    if (-not $SkipProbe) {
        Write-Host "[INFO] Testing Connectivity on Port 3389..." -ForegroundColor Cyan
        if (-not (Test-TcpFast -ComputerName $ip -Port 3389 -TimeoutMs 500)) {
            throw "TCP Port 3389 is closed or filtered on $ip"
        }
    }

    # 3. 启动 RDP 进程
    Write-Host "[INFO] Establishing RDP Connection..." -ForegroundColor Green
    Start-Process "mstsc.exe" -ArgumentList "/v:$ip /f" # /f 全屏模式

} catch {
    $reason = $_.Exception.Message
    Write-RDPLog "mode=$Mode host=$TargetHost failed=$reason"
    Write-Host "[FATAL ERROR] $reason" -ForegroundColor Red
    exit 1
}