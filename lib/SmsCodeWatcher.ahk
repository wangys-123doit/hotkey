/**
 * SmsCodeWatcher - 从 Phone Link 应用中主动抓取短信验证码到剪贴板
 *
 * 原理：通过热键激活 PhoneExperienceHost.exe，用 UIA 打开第一条会话，
 * 在右侧消息气泡上触发右键菜单"全部复制"获取短信全文，正则提取验证码写入剪贴板。
 *
 * 热键：Win+Alt+C（在 hotkey.ahk 中绑定）
 * 依赖：lib\UIA.ahk（用于 ElementFromHandle、FindElement、ElementFromPoint、
 *       GetFocusedElement、ShowContextMenu、菜单项定位）
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
        "(?:验证码|校验码|动态码|授权码|确认码|激活码|安全码)[：:是为]?\s*([0-9]{4,8})",
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
        Sleep(300)

        ; 2. 最小化再恢复，强制重置焦点到默认起始位置（不依赖坐标，100%可靠）
        WinMinimize(winTitle)
        Sleep(80)
        WinActivate(winTitle)
        if !WinWaitActive(winTitle,, 2) {
            ToolTip("无法激活 Phone Link")
            SetTimer(() => ToolTip(), -2000)
            return ""
        }
        Sleep(300)  ; 等待窗口从最小化恢复后布局完全稳定

        ; 获取窗口坐标（后续步骤 4 定位消息区域需要）
        local wx, wy, ww, wh
        WinGetPos(&wx, &wy, &ww, &wh, winTitle)

        ; 3. Tab 导航到第一条短信并按 Enter 打开会话
        Send("{Tab " SmsCodeWatcher._tabCount "}")
        Sleep(100)
        Send("{Enter}")
        Sleep(600)  ; 等待会话面板加载和消息气泡渲染

        ; 4. 定位消息区域并触发惰性实体化
        ; 消息气泡通常在窗口右侧 2/3 区域的下半部分（使用步骤2已获取的窗口坐标）
        ; 目标坐标：窗口右侧面板中下部（最新消息通常在底部）
        local bubbleX := wx + ww * 3 // 4
        local bubbleY := wy + wh * 3 // 4

        ; hover 到消息区域触发实体化
        MouseMove(bubbleX, bubbleY, 5)
        Sleep(200)
        ; ElementFromPoint 强制该点节点实体化
        local bubbleEl := ""
        try bubbleEl := UIA.ElementFromPoint(bubbleX, bubbleY)
        Sleep(200)

        ; 5. 尝试找到消息气泡元素（Text 类型或最近的 ListItem）
        ; 如果 ElementFromPoint 拿到的元素太小或不对，向上找父级
        local targetEl := bubbleEl
        if (targetEl) {
            ; 尝试获取更精确的位置
            local targetRect := ""
            try targetRect := targetEl.Location
            if (targetRect && targetRect.w > 0 && targetRect.h > 0 && targetRect.x > -20000) {
                bubbleX := targetRect.x + targetRect.w // 2
                bubbleY := targetRect.y + targetRect.h // 2
            }
        }

        ; 6. 保存剪贴板并清空
        local savedClip := ClipboardAll()
        A_Clipboard := ""

        ; 7. 在消息气泡上执行右键（hover + 物理右键）
        MouseMove(bubbleX, bubbleY, 3)
        Sleep(250)  ; 确保 hover 生效

        local menuOpened := false

        ; 方案一：物理右键
        Click(bubbleX, bubbleY, "Right", "Down")
        Sleep(80)
        Click(bubbleX, bubbleY, "Right", "Up")
        menuOpened := SmsCodeWatcher._WaitForMenu(800)

        ; 方案二：UIA ShowContextMenu
        if (!menuOpened && targetEl) {
            Sleep(100)
            try {
                targetEl.ShowContextMenu()
                menuOpened := SmsCodeWatcher._WaitForMenu(800)
            }
        }

        ; 方案三：键盘回退
        if (!menuOpened && targetEl) {
            try targetEl.SetFocus()
            Sleep(100)
            Send("{AppsKey}")
            menuOpened := SmsCodeWatcher._WaitForMenu(600)
        }

        if (!menuOpened) {
            A_Clipboard := savedClip
            ToolTip("无法弹出右键菜单")
            SetTimer(() => ToolTip(), -2000)
            return ""
        }
        Sleep(200)  ; 菜单完全渲染

        ; 8. 在弹出菜单中查找"全部复制"或"复制"并点击
        local menuItem := ""
        try {
            local popupHwnd := WinExist("ahk_class Microsoft.UI.Content.PopupWindowSiteBridge ahk_exe PhoneExperienceHost.exe")
            if (popupHwnd) {
                local popupEl := UIA.ElementFromHandle(popupHwnd)
                ; 优先找"全部复制"，其次找"复制"
                try menuItem := popupEl.FindElement({Name: "全部复制"}, 4)
                if (!menuItem) {
                    try menuItem := popupEl.FindElement({Name: "复制"}, 4)
                }
                if (!menuItem) {
                    try menuItem := popupEl.FindElement({Type: "MenuItem"}, 4)  ; 兜底取第一个菜单项
                }
            }
        }
        if (menuItem) {
            try {
                menuItem.Click()
            } catch {
                menuItem.Invoke()
            }
        } else {
            ; UIA 找不到菜单项，键盘回退
            Send("{End}{Enter}")
        }
        Sleep(150)

        ; 9. 等待剪贴板更新
        if !ClipWait(2) {
            A_Clipboard := savedClip
            ToolTip("复制超时")
            SetTimer(() => ToolTip(), -1500)
            return ""
        }
        local smsText := A_Clipboard

        ; 10. Escape 清理
        Send("{Escape}")

        if SmsCodeWatcher.Debug
            OutputDebug("[SmsCodeWatcher] 短信原文: " smsText "`n")

        ; 11. 检查内容
        if (smsText = "") {
            A_Clipboard := savedClip
            ToolTip("未能复制短信内容")
            SetTimer(() => ToolTip(), -1500)
            return ""
        }

        ; 12. 提取验证码
        local code := SmsCodeWatcher._ExtractCode(smsText)
        if (code = "") {
            A_Clipboard := savedClip
            ToolTip("短信中未发现验证码")
            SetTimer(() => ToolTip(), -1500)
            return ""
        }

        ; 13. 去重：60秒内相同验证码不重复触发
        local now := A_TickCount
        if (code = SmsCodeWatcher._lastCode && (now - SmsCodeWatcher._lastTime) < 60000) {
            A_Clipboard := savedClip
            return ""
        }
        SmsCodeWatcher._lastCode := code
        SmsCodeWatcher._lastTime := now

        ; 14. 提取公司名（短信开头【XXX】格式）
        local company := ""
        if RegExMatch(smsText, "【(.+?)】", &m)
            company := m[1]

        ; 15. 写入验证码到剪贴板
        Critical "On"
        A_Clipboard := code
        Critical "Off"

        ; 16. 提示
        local tip := (company ? "【" company "】" : "") "验证码 " code " 已复制"
        ToolTip(tip)
        SetTimer(() => ToolTip(), -2500)

        ; 17. 30秒后恢复剪贴板
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
