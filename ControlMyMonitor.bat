@echo off
:: ==============================================
:: 自动检测当前输入并切换到台式机 HDMI
:: 适用 Dell Ultra 系列，ControlMyMonitor.exe 路径已指定
:: ==============================================

:: ControlMyMonitor 路径
set CMM_PATH="D:\software\controlmymonitor\ControlMyMonitor.exe"

:: 目标显示器
set DISPLAY="\\.\DISPLAY1"

:: 标准 VCP 60 对应 HDMI 值
set HDMI_VCP60=17

:: Manufacturer Specific VCP E2 对应 HDMI 值（备用方案）
set HDMI_E2=17

:: ==============================================
:: 1️⃣ 获取当前输入
for /f "tokens=2 delims=:" %%A in ('%CMM_PATH% /GetVCP 60 /monitor %DISPLAY% ^| find "Current Value"') do (
    set CURRENT_INPUT=%%A
)
:: 去掉空格
set CURRENT_INPUT=%CURRENT_INPUT: =%

echo 当前输入 VCP60 值: %CURRENT_INPUT%

:: ==============================================
:: 2️⃣ 判断是否已经是 HDMI
if "%CURRENT_INPUT%"=="%HDMI_VCP60%" (
    echo 当前已经是 HDMI 输入，无需切换
    goto :EOF
)

:: ==============================================
:: 3️⃣ 尝试标准 VCP60 切换到 HDMI
echo 尝试使用 VCP 60 切换到 HDMI...
%CMM_PATH% /SetValue %DISPLAY% 60 %HDMI_VCP60%
timeout /t 1 >nul

:: 重新读取，确认是否成功
for /f "tokens=2 delims=:" %%A in ('%CMM_PATH% /GetVCP 60 /monitor %DISPLAY% ^| find "Current Value"') do (
    set CURRENT_INPUT=%%A
)
set CURRENT_INPUT=%CURRENT_INPUT: =%

if "%CURRENT_INPUT%"=="%HDMI_VCP60%" (
    echo 已成功切换到 HDMI 输入
    goto :EOF
)

:: ==============================================
:: 4️⃣ 标准 VCP 无效，尝试 Manufacturer Specific VCP E2
echo VCP 60 切换失败，尝试 Manufacturer Specific VCP E2 切换...
%CMM_PATH% /SetValue %DISPLAY% E2 %HDMI_E2%
timeout /t 1 >nul

:: 再次读取确认
for /f "tokens=2 delims=:" %%A in ('%CMM_PATH% /GetVCP 60 /monitor %DISPLAY% ^| find "Current Value"') do (
    set CURRENT_INPUT=%%A
)
set CURRENT_INPUT=%CURRENT_INPUT: =%

if "%CURRENT_INPUT%"=="%HDMI_VCP60%" (
    echo 已通过 E2 成功切换到 HDMI 输入
    goto :EOF
) else (
    echo ⚠️ 切换 HDMI 失败，请检查 HDMI 信号和 DDC/CI 设置
)

:EOF
echo 脚本执行完成
pause