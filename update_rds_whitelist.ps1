[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# update_rds_whitelist.ps1
# 获取公网IP，SSH登录服务器后更新阿里云RDS白名单

# 1. 获取公网IP
Write-Host "正在获取公网IP..." -ForegroundColor Cyan
$ip = (curl.exe -s https://ipinfo.io/ip).Trim()

if ([string]::IsNullOrWhiteSpace($ip) -or $ip -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    Write-Host "获取IP失败: '$ip'" -ForegroundColor Red
    exit 1
}

Write-Host "当前公网IP: $ip" -ForegroundColor Green

# 2. 构建远程执行的命令（替换IP后的阿里云RDS白名单更新命令）
$remoteCmd = "aliyun rds ModifySecurityIps --RegionId cn-hangzhou --DBInstanceId rm-bp11aw2o82rk8b12v --SecurityIps $ip --ModifyMode Append"

Write-Host "将在服务器上执行以下命令:" -ForegroundColor Cyan
Write-Host $remoteCmd -ForegroundColor Yellow
Write-Host ""

# 3. SSH登录服务器并执行命令
Write-Host "正在SSH登录服务器..." -ForegroundColor Cyan
ssh -t -p 22 prod $remoteCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nRDS白名单更新成功！IP: $ip" -ForegroundColor Green
} else {
    Write-Host "`n命令执行失败，退出码: $LASTEXITCODE" -ForegroundColor Red
}
