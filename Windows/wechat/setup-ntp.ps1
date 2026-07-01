# setup-ntp.ps1 - 配置 Windows 时间服务，让宿主机+Docker容器始终对齐网络时间
#
# 用途：将 w32time 服务设为自动启动，NTP 源换成阿里/腾讯等国内可靠服务器。
#       Docker 容器与宿主机共享内核时钟，宿主机时间正确，容器自动跟随。
#
# 用法（需管理员权限）：
#   1. 右键 PowerShell -> 以管理员身份运行
#   2. 执行: powershell -ExecutionPolicy Bypass -File setup-ntp.ps1
#
# 验证：
#   w32tm /query /status          # 查看同步状态和源
#   docker exec wechat date       # 容器时间应与宿主机一致

#Requires -RunAsAdministrator

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 配置 Windows 时间同步服务 (w32time)" -ForegroundColor Cyan
Write-Host " NTP 源: 阿里云 / 腾讯云" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. 设为开机自动启动
Write-Host "[1/4] 设置 w32time 为自动启动..." -ForegroundColor Yellow
Set-Service w32time -StartupType Automatic
Write-Host "      StartType = Automatic" -ForegroundColor Green

# 2. 启动服务（配置前必须运行）
Write-Host "[2/4] 启动 w32time 服务..." -ForegroundColor Yellow
Start-Service w32time -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Write-Host "      Status = $((Get-Service w32time).Status)" -ForegroundColor Green

# 3. 配置国内 NTP 源（阿里云主备 + 腾讯云兜底）
#    0x9 = SpecialInterval，按 SpecialPollInterval 定期同步（默认 1024 秒）
Write-Host "[3/4] 配置 NTP 源（阿里云 + 腾讯云）..." -ForegroundColor Yellow
w32tm /config /manualpeerlist:"ntp.aliyun.com,0x9 ntp1.aliyun.com,0x9 time1.cloud.tencent.com,0x9" /syncfromflags:manual /reliable:yes /update | Out-Null
Write-Host "      NtpServer = ntp.aliyun.com, ntp1.aliyun.com, time1.cloud.tencent.com" -ForegroundColor Green

# 4. 重启服务使配置生效，并立即同步一次
Write-Host "[4/4] 重启服务并立即同步..." -ForegroundColor Yellow
Restart-Service w32time -Force
Start-Sleep -Seconds 2
w32tm /resync /force | Out-Null
Write-Host "      已触发立即同步" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " 配置完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "当前同步状态:" -ForegroundColor Cyan
w32tm /query /status
Write-Host ""
Write-Host "验证容器时间:" -ForegroundColor Cyan
Write-Host "  宿主机: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "  （容器时间应与宿主机一致，差 1-2 秒正常）"
