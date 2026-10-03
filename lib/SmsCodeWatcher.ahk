/**
 * SmsCodeWatcher - 从 Phone Link 应用中主动抓取短信验证码到剪贴板
 *
 * 原理：通过热键激活 PhoneExperienceHost.exe，提示用户手动右键点击目标短信，
 * 脚本监听右键事件后自动选择菜单项并提取验证码。
 *
 * 热键：Win+Alt+C（在 hotkey.ahk 中绑定）
 * 依赖：lib\UIA.ahk（用于 ElementFromHandle、FindElement、菜单项定位）
 */
class SmsCodeWatcher
{
    ; 调试开关，开启后 OutputDebug 输出匹配信息（验证码绝不写盘）
    static Debug := false

    ; Tab 次数常量（用于从标题栏焦点起始位导航到第一条短信）
    static _tabCount := 5

    ; 内部状态
    static _lastCode := ""
    static _lastTime := 0
    static _clipSaved := ""

    ; 验证码关键词（粗筛用）
    static _keywords := ["验证码", "校验码", "动态码", "授权码", "确认码", "激活码", "安全码"]

    ; 多模式正则提取（按序回退，命中即取捕获组）
    static _patterns := [
        "(?:验证码|校验码|动态码|授权码|确认码|激活码|安全码)[：:是为\s]*([0-9]{4,8})",
        "([0-9]{4,8})\s*(?:是您的|为您的)?\s*(?:验证码|校验码|动态码)",
        "i)(?:verification|verify|otp|security)\s*code\s*(?:is\s*)?[：:]?\s*([0-9]{4,8})",
        "i)\bcode\s*(?:is\s*)?[：:]?\s*([0-9]{4,8})"
    ]

    /**
     * 纯正则提取方法：遍历 _patterns 返回第一个匹配的验证码
     * @param text 短信全文
     * @returns {String} 验证码字符串，未命中返回 ""
     */
    static _ExtractCode(text)
    {
        for pattern in SmsCodeWatcher._patterns {
            if RegExMatch(text, pattern, &match) {
                return match[1]
            }
        }
        return ""
    }

    /**
     * 主入口：从 Phone Link 应用中抓取第一条短信的验证码
     */
    static GrabFromPhoneLink()
    {
        local t0 := A_TickCount

        ; 1. 确保 Phone Link 运行并激活
        local winTitle := "ahk_exe PhoneExperienceHost.exe"
        if !WinExist(winTitle) {
            Run("ms-phone:")
            if !WinWait(winTitle,, 5) {
                ToolTip("Phone Link 未响应")
                SetTimer(() => ToolTip(), -2000)
                return ""
            }
            Sleep(800)  ; 首次启动额外等待
        }
        WinActivate(winTitle)
        if !WinWaitActive(winTitle,, 2) {
            ToolTip("无法激活 Phone Link")
            SetTimer(() => ToolTip(), -2000)
            return ""
        }
        Sleep(300)  ; 等待窗口激活后布局稳定

        ; 2. 保存剪贴板并清空
        local savedClip := ClipboardAll()
        A_Clipboard := ""

        ; 3. 提示用户手动右键点击目标短信
        ToolTip("请手动右键点击目标短信...")

        ; 4. 监听右键点击事件（轮询 GetAsyncKeyState，VK_RBUTTON = 0x02）
        local startTime := A_TickCount
        local rightClicked := false
        local timeoutMs := 5000  ; 5秒超时

        while (A_TickCount - startTime < timeoutMs) {
            ; 检测右键是否按下（最高位为1表示当前按下）
            if (DllCall("GetAsyncKeyState", "Int", 0x02) & 0x8000) {
                rightClicked := true
                break
            }
            Sleep(50)  ; 50ms 轮询间隔
        }

        ; 清除提示
        ToolTip()

        if (!rightClicked) {
            A_Clipboard := savedClip
            ToolTip("等待右键超时，已取消")
            SetTimer(() => ToolTip(), -2000)
            return ""
        }

        ; 5. 等待上下文菜单出现（用户右键后菜单需要时间渲染）
        Sleep(300)
        local menuOpened := SmsCodeWatcher._WaitForMenu(1500)

        if (!menuOpened) {
            A_Clipboard := savedClip
            ToolTip("未检测到右键菜单")
            SetTimer(() => ToolTip(), -2000)
            return ""
        }
        Sleep(200)  ; 菜单完全渲染

        ; 6. 键盘选择"全部复制"（菜单最后一项：Up 键定位 + Enter 确认，一次性发送）
        SendEvent("{Up}{Enter}")

        ; 7. 等待剪贴板更新
        if !ClipWait(2) {
            A_Clipboard := savedClip
            ToolTip("复制超时")
            SetTimer(() => ToolTip(), -1500)
            return ""
        }
        local smsText := A_Clipboard

        ; 8. Escape 清理
        Send("{Escape}")

        if SmsCodeWatcher.Debug
            OutputDebug("[SmsCodeWatcher] 短信原文: " smsText "`n")

        ; 9. 检查内容
        if (smsText = "") {
            A_Clipboard := savedClip
            ToolTip("未能复制短信内容")
            SetTimer(() => ToolTip(), -1500)
            return ""
        }

        ; 10. 提取验证码
        local code := SmsCodeWatcher._ExtractCode(smsText)
        if (code = "") {
            A_Clipboard := savedClip
            ToolTip("短信中未发现验证码")
            SetTimer(() => ToolTip(), -1500)
            return ""
        }

        ; 11. 去重：60秒内相同验证码不重复触发
        local now := A_TickCount
        if (code = SmsCodeWatcher._lastCode && (now - SmsCodeWatcher._lastTime) < 60000) {
            A_Clipboard := savedClip
            return ""
        }
        SmsCodeWatcher._lastCode := code
        SmsCodeWatcher._lastTime := now

        ; 12. 提取公司名（短信开头【XXX】格式）
        local company := ""
        if RegExMatch(smsText, "【(.+?)】", &m)
            company := m[1]

        ; 13. 写入验证码到剪贴板
        Critical "On"
        A_Clipboard := code
        Critical "Off"

        ; 14. 提示
        local tip := (company ? "【" company "】" : "") "验证码 " code " 已复制"
        ToolTip(tip)
        SetTimer(() => ToolTip(), -2500)

        ; 15. 30秒后恢复剪贴板
        SmsCodeWatcher._clipSaved := savedClip
        SetTimer(() => SmsCodeWatcher._RestoreClipboard(savedClip, code), -30000)

        if SmsCodeWatcher.Debug {
            local elapsed := A_TickCount - t0
            OutputDebug("[SmsCodeWatcher] 提取成功: " code " | 耗时: " elapsed "ms`n")
        }

        return code
    }

    /**
     * 等待 WinUI 3 上下文菜单出现
     * 检测方式：PopupWindowSiteBridge 窗口（WinAppSDK 弹出层宿主）或 UIA Menu/MenuItem 元素
     * @param timeoutMs 超时毫秒数
     * @returns {Boolean} 菜单是否成功打开
     */
    static _WaitForMenu(timeoutMs := 800)
    {
        local start := A_TickCount
        while (A_TickCount - start < timeoutMs) {
            ; 方式1：检测 WinAppSDK 弹出层宿主窗口
            if WinExist("ahk_class Microsoft.UI.Content.PopupWindowSiteBridge ahk_exe PhoneExperienceHost.exe")
                return true
            ; 方式2：检测通用弹出菜单窗口类
            if WinExist("ahk_class Windows.UI.Core.CoreWindow ahk_exe PhoneExperienceHost.exe")
                return true
            Sleep(30)
        }
        return false
    }

    /**
     * 恢复剪贴板（仅当用户未修改时）
     */
    static _RestoreClipboard(clipData, expectedCode)
    {
        ; 若当前剪贴板仍等于验证码，则恢复；否则用户已改动，跳过
        if (A_Clipboard = expectedCode && clipData != "") {
            Critical "On"
            A_Clipboard := clipData
            Critical "Off"
        }
        SmsCodeWatcher._clipSaved := ""
    }
}
