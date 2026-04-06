[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    # [string]$TargetHost = "X1"
    [string]$TargetHost = "M1"
)

process {
    try {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] Resolving: $TargetHost" -ForegroundColor Cyan
        
        # 1. DNS 解析 (带超时保护与类型过滤)
        $dnsResult = Resolve-DnsName -Name $TargetHost -Type A -ErrorAction Stop
        $ip = $dnsResult.IPAddress | Select-Object -First 1

        if ([string]::IsNullOrWhiteSpace($ip)) {
            throw "Failed to resolve IP for host: $TargetHost"
        }

        Write-Host "[INFO] Resolved IP: $ip" -ForegroundColor Green

        # 2. 端口探测 (3389)
        Write-Host "[INFO] Testing Connectivity on Port 3389..." -ForegroundColor Cyan
        $portTest = Test-NetConnection -ComputerName $ip -Port 3389 -WarningAction SilentlyContinue

        if (-not $portTest.TcpTestSucceeded) {
            throw "TCP Port 3389 is closed or filtered on $ip"
        }

        # 3. 启动 RDP 进程
        Write-Host "[INFO] Establishing RDP Connection..." -ForegroundColor Green
        Start-Process "mstsc.exe" -ArgumentList "/v:$ip /f" # /f 全屏模式

    } catch {
        Write-Host "[FATAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
        # 保持窗口以便查看错误
        Read-Host "Press Enter to exit"
    }
}