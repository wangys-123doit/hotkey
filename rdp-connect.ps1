[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$TargetHost = "X1",
    [ValidateSet("fast", "safe")]
    [string]$Mode = "safe",
    [switch]$SkipProbe
    # [string]$TargetHost = "M1"
)

$configFile = Join-Path $PSScriptRoot "config.ini"

$logFile = Join-Path $PSScriptRoot "rdp.log"

function Write-RDPLog {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$time] $Message" -Encoding UTF8
}

function Get-IniSections {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{}
    }

    $result = @{}
    $currentSection = $null

    foreach ($rawLine in Get-Content -LiteralPath $Path -Encoding Unicode) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';') -or $line.StartsWith('#')) {
            continue
        }

        if ($line -match '^\[(.+?)\]$') {
            $currentSection = $matches[1]
            if (-not $result.ContainsKey($currentSection)) {
                $result[$currentSection] = @{}
            }
            continue
        }

        if ($null -eq $currentSection) {
            continue
        }

        if ($line -match '^(?<key>[^=]+?)\s*=\s*(?<value>.*)$') {
            $key = $matches.key.Trim()
            $value = $matches.value.Trim()
            $result[$currentSection][$key] = $value
        }
    }

    return $result
}

function Get-WakeOnLanTargetsFromConfig {
    param([Parameter(Mandatory=$true)][string]$Path)

    $sections = Get-IniSections -Path $Path
    $targets = @{}

    if (-not $sections.ContainsKey('WakeOnLan')) {
        return $targets
    }

    foreach ($entry in $sections['WakeOnLan'].GetEnumerator()) {
        if ($entry.Key -notmatch '^(?<host>[^.]+?)(?:\.(?<field>Broadcast|Port))?$') {
            continue
        }

        $hostName = $matches.host
        if (-not $targets.ContainsKey($hostName)) {
            $targets[$hostName] = @{
                MacAddress = ""
                BroadcastAddress = "255.255.255.255"
                Port = 9
            }
        }

        switch ($matches.field) {
            'Broadcast' { $targets[$hostName].BroadcastAddress = $entry.Value }
            'Port' {
                if (-not [string]::IsNullOrWhiteSpace($entry.Value)) {
                    $targets[$hostName].Port = [int]$entry.Value
                }
            }
            default { $targets[$hostName].MacAddress = $entry.Value }
        }
    }

    return $targets
}

$WakeOnLanTargets = Get-WakeOnLanTargetsFromConfig -Path $configFile

function Get-WakeOnLanTarget {
    param([Parameter(Mandatory=$true)][string]$HostName)

    if ($WakeOnLanTargets.ContainsKey($HostName)) {
        return $WakeOnLanTargets[$HostName]
    }

    return $null
}

function Send-WakeOnLan {
    param(
        [Parameter(Mandatory=$true)][string]$MacAddress,
        [string]$BroadcastAddress = "255.255.255.255",
        [int]$Port = 9
    )

    $cleanMac = ($MacAddress -replace '[:\-\. ]', '').ToUpperInvariant()
    if ($cleanMac.Length -ne 12) {
        throw "Invalid MAC address for WoL: $MacAddress"
    }

    $macBytes = for ($index = 0; $index -lt 12; $index += 2) {
        [Convert]::ToByte($cleanMac.Substring($index, 2), 16)
    }

    $packet = New-Object byte[] (102)
    for ($index = 0; $index -lt 6; $index++) {
        $packet[$index] = 0xFF
    }

    for ($offset = 6; $offset -lt $packet.Length; $offset += 6) {
        [Array]::Copy($macBytes, 0, $packet, $offset, 6)
    }

    $udpClient = [System.Net.Sockets.UdpClient]::new()
    try {
        $udpClient.EnableBroadcast = $true
        [void]$udpClient.Send($packet, $packet.Length, $BroadcastAddress, $Port)
    }
    finally {
        $udpClient.Close()
        $udpClient.Dispose()
    }
}

function Normalize-MacAddress {
    param([string]$MacAddress)

    if ([string]::IsNullOrWhiteSpace($MacAddress)) {
        return ""
    }

    return ($MacAddress -replace '[:\-\. ]', '').ToUpperInvariant()
}

function Get-IPv4FromNeighborByMac {
    param([Parameter(Mandatory=$true)][string]$MacAddress)

    $normalized = Normalize-MacAddress -MacAddress $MacAddress
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    try {
        $neighbor = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                (Normalize-MacAddress -MacAddress $_.LinkLayerAddress) -eq $normalized -and
                $_.IPAddress -match '^\d{1,3}(?:\.\d{1,3}){3}$'
            } |
            Select-Object -First 1

        if ($neighbor -and $neighbor.IPAddress) {
            return $neighbor.IPAddress
        }
    } catch {}

    try {
        $arpRows = (& arp.exe -a 2>$null)
        foreach ($row in $arpRows) {
            if ($row -match '^\s*(?<ip>\d{1,3}(?:\.\d{1,3}){3})\s+(?<mac>[0-9a-fA-F\-]{17})\s+') {
                if ((Normalize-MacAddress -MacAddress $matches.mac) -eq $normalized) {
                    return $matches.ip
                }
            }
        }
    } catch {}

    return $null
}

function Resolve-IPv4FromMacWithRetry {
    param(
        [Parameter(Mandatory=$true)][string]$MacAddress,
        [int]$Retries = 20,
        [int]$DelayMs = 1000
    )

    for ($attempt = 0; $attempt -le $Retries; $attempt++) {
        $ip = Get-IPv4FromNeighborByMac -MacAddress $MacAddress
        if (-not [string]::IsNullOrWhiteSpace($ip)) {
            return $ip
        }

        if ($attempt -lt $Retries) {
            Start-Sleep -Milliseconds $DelayMs
        }
    }

    return $null
}

function Resolve-HostIPv4WithRetry {
    param(
        [Parameter(Mandatory=$true)][string]$HostName,
        [int]$Retries = 20,
        [int]$DelayMs = 1000
    )

    for ($attempt = 0; $attempt -le $Retries; $attempt++) {
        $ip = Resolve-HostIPv4 -HostName $HostName
        if (-not [string]::IsNullOrWhiteSpace($ip)) {
            return $ip
        }

        if ($attempt -lt $Retries) {
            Start-Sleep -Milliseconds $DelayMs
        }
    }

    return $null
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
    $wakeProfile = $null
    $wakeSent = $false

    if ([string]::IsNullOrWhiteSpace($ip)) {
        $wakeProfile = Get-WakeOnLanTarget -HostName $TargetHost

        if ($null -ne $wakeProfile -and -not [string]::IsNullOrWhiteSpace($wakeProfile.MacAddress)) {
            Write-Host "[INFO] Host not resolved, sending Wake-on-LAN..." -ForegroundColor Cyan
            Send-WakeOnLan -MacAddress $wakeProfile.MacAddress -BroadcastAddress $wakeProfile.BroadcastAddress -Port $wakeProfile.Port
            $wakeSent = $true
            Write-RDPLog "mode=$Mode host=$TargetHost wol=sent mac=$($wakeProfile.MacAddress) broadcast=$($wakeProfile.BroadcastAddress) port=$($wakeProfile.Port)"
            $ip = Resolve-HostIPv4WithRetry -HostName $TargetHost -Retries 20 -DelayMs 1000

            if ([string]::IsNullOrWhiteSpace($ip)) {
                Write-Host "[INFO] Hostname unresolved, trying MAC->IP fallback..." -ForegroundColor Cyan
                $ip = Resolve-IPv4FromMacWithRetry -MacAddress $wakeProfile.MacAddress -Retries 20 -DelayMs 1000
                if (-not [string]::IsNullOrWhiteSpace($ip)) {
                    Write-RDPLog "mode=$Mode host=$TargetHost mac_fallback_ip=$ip"
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($ip)) {
            if ($null -eq $wakeProfile) {
                throw "Failed to resolve IPv4 for host: $TargetHost"
            }

            if ([string]::IsNullOrWhiteSpace($wakeProfile.MacAddress)) {
                throw "Failed to resolve IPv4 for host: $TargetHost. WoL is configured in config.ini, but MacAddress is empty for this host."
            }

            throw "Failed to resolve IPv4 for host: $TargetHost after Wake-on-LAN retry"
        }
    }

    Write-Host "[INFO] Resolved IP: $ip" -ForegroundColor Green

    # 2. 端口探测 (3389) - 快速模式可跳过
    if (-not $SkipProbe) {
        Write-Host "[INFO] Testing Connectivity on Port 3389..." -ForegroundColor Cyan
        $probeAttempts = if ($wakeSent) { 20 } else { 1 }
        $probeDelayMs = if ($wakeSent) { 1000 } else { 0 }
        $probeOk = $false

        for ($attempt = 0; $attempt -lt $probeAttempts; $attempt++) {
            if (Test-TcpFast -ComputerName $ip -Port 3389 -TimeoutMs 500) {
                $probeOk = $true
                break
            }

            if ($attempt -lt ($probeAttempts - 1)) {
                Start-Sleep -Milliseconds $probeDelayMs
            }
        }

        if (-not $probeOk) {
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