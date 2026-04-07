[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$TargetHost = "X1",
    [ValidateSet("fast", "safe")]
    [string]$Mode = "safe",
    [switch]$SkipProbe
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

    # 1) .NET DNS（最快）
    try {
        $ipObj = [System.Net.Dns]::GetHostAddresses($HostName) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            Select-Object -First 1
        if ($ipObj) {
            return $ipObj.IPAddressToString
        }
    } catch {}

    # 2) Resolve-DnsName（兼容本地解析路径）
    try {
        $dns = Resolve-DnsName -Name $HostName -Type A -QuickTimeout -ErrorAction Stop |
            Where-Object { $_.IPAddress } |
            Select-Object -First 1
        if ($dns -and $dns.IPAddress) {
            return $dns.IPAddress
        }
    } catch {}

    # 3) ping 回显兜底（适配局域网主机名）
    try {
        $pingText = (& ping.exe -4 -n 1 $HostName 2>$null) -join "`n"
        if ($pingText -match "\[(\d{1,3}(?:\.\d{1,3}){3})\]") {
            return $matches[1]
        }
    } catch {}

    return $null
}

try {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] Resolving: $TargetHost" -ForegroundColor Cyan

    # 1. 主机名解析（多级兜底）
    $ip = Resolve-HostIPv4 -HostName $TargetHost

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