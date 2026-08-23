/* OpenControllerFromNetwork.ahk
1、!u触发让chrome从网络打开idea controller的工具
2、!+o或!+q热键触发，在source页签下的代码文件，在对应的VSCode或Qoder中打开相应文件以及行数列数
3、SC137、RCtrl Up热键触发打开Chrome以debug port和自定义debug配置文件的方式
4、!q热键触发打开Chrome以debug port和自定义debug配置文件的方式
 */

;~ 1、配置区
global PERF_LOG_ENABLED := true
global DEVTOOLS_MENU_RETRIES := 2
global DEVTOOLS_MENU_RETRIES_FAST := 1
global DEVTOOLS_MENU_RETRY_SLEEP_MS := 35
global DEVTOOLS_MENU_RETRY_SLEEP_MS_FAST := 22
global DEVTOOLS_CONTEXTMENU_SLEEP_MS := 90
global DEVTOOLS_POST_COPY_SLEEP_MS := 60
global DEVTOOLS_CLIPWAIT_SEC := 0.2
global DEVTOOLS_MENU_RETRIES_FALLBACK := 6
global DEVTOOLS_MENU_RETRY_SLEEP_MS_FALLBACK := 70
global DEVTOOLS_CLIPWAIT_SEC_FALLBACK := 0.45
global DEVTOOLS_TRIPLE_C_DISABLE_AFTER_FAILS := 2
global DEVTOOLS_TRIPLE_C_FAIL_STREAK := 0
global DEVTOOLS_TRIPLE_C_SKIP_MODE := false
global DEVTOOLS_MENU_CACHE_TTL_MS := 15000
global DEVTOOLS_MENU_CACHE_DRIFT_X := 520
global DEVTOOLS_MENU_CACHE_DRIFT_Y := 420
global DEVTOOLS_MENU_CALL_ROUND := 0
global DEVTOOLS_MENU_CACHE_DISABLED_ROUND := {copy: 0, url: 0}
global DEVTOOLS_MENU_ANCHOR_CACHE := {
    hwnd: 0,
    copy: {valid: false, x: 0, y: 0, mx: 0, my: 0, ts: 0},
    url: {valid: false, x: 0, y: 0, mx: 0, my: 0, ts: 0}
}
; 热键绑定（仅在 Chrome 激活时生效）
#HotIf WinActive("ahk_exe chrome.exe")
;~ 2、主入口
!u::
{
    CopyDevToolsSelectedRequestURL()

    SendEvent "{LWin Down}1{LWin Up}"

    if WinWaitActive("ahk_exe idea64.exe", , 2) {
        SendEvent "^+s"
        ; 用 UIA 等待搜索弹窗中的输入框出现，超时 2 秒
        try {
            ideaEl := UIA.ElementFromHandle("ahk_exe idea64.exe")
            ideaEl.WaitElement({Type:"Edit"}, 2000)
        } catch {
            Sleep 400
        }
        SendEvent "^v{Enter}"
        return
    }
    ToolTip("未检测到 IDEA 窗口")
    SetTimer(() => ToolTip(), -2000)
}
^!u::CopyDevToolsSelectedRequestURL()
#!l:: {
    if !EnsureBridgeRunning() {
        ToolTip("Bridge 未启动")
        SetTimer () => ToolTip(), -2000
        return
    }

    pos := GetLineNumberFromBridge()
    ToolTip("Line: " . pos.line . ", Col: " . pos.column . ", URL: " . pos.fileUrl)
    SetTimer () => ToolTip(), -2000 ; 2秒后消失
}

; Alt+Shift+O: 在当前虚拟桌面的 Qoder/VS Code 中打开 DevTools Source 文件并定位到行号列号
/* !+o:: {
    ; 1. 通过 Bridge 获取行号、列号和文件 URL
    if !EnsureBridgeRunning() {
        ToolTip("Bridge 未启动")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    pos := GetLineNumberFromBridge()
    if !IsNumber(pos.line) {
        ToolTip("获取位置信息失败: " pos.line)
        SetTimer(() => ToolTip(), -2000)
        return
    }

    lineNum := Integer(pos.line)
    colNum := Integer(pos.column)
    fileUrl := pos.fileUrl

    if !fileUrl {
        ToolTip("未获取到文件 URL")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; 2. 将 URL 转换为本地文件路径
    ;    file:// URL 格式: file:///D:/path/to/file.js 或 file:///C:/path
    ;    webpack:// URL 格式: webpack:///./path/to/file.js
    filePath := DevToolsUrlToLocalPath(fileUrl)
    if !filePath {
        ToolTip("无法转换为本地路径: " fileUrl)
        SetTimer(() => ToolTip(), -3000)
        return
    }

    ; 3. 在当前桌面的 Qoder 中打开文件
    ToolTip("打开: " filePath " (" lineNum ":" colNum ")")
    SetTimer(() => ToolTip(), -2000)
    if lineNum > 0 && colNum > 0 {
        OpenInEditor(filePath, lineNum, colNum)
    } else if lineNum > 0 {
        OpenInEditor(filePath, lineNum)
    } else {
        OpenInEditor(filePath)
    }
} */


; 当按下 Alt+Q 时，手动检测弹窗，若失败则强行唤醒 URL
^!q::
{
    ; 发送原有的快捷键给 Chrome
    ; Send("!q")
    
    ; 延迟等待弹窗出现 (QuicKey 窗口通常有特定的标题或类名)
    ; if !WinWait("ahk_exe chrome.exe", , 0.5) 
    ; {
        ; 如果没检测到弹窗，通过命令行强制预热 popup.html
        ; 这样会强制 Chrome 刷新资源映射并唤醒 Service Worker
      ;   Run("chrome.exe --new-window chrome-extension://ldlghkoiihaelfnggonhjnfiabmaficg/popup.html?props=false")
    ; }
	
	
	; 通过 CDP 协议在【当前虚拟桌面】的调试 Chrome 中另起标签页执行
	; 使用当前桌面对应的调试端口（桌面1:9223，桌面2:9224...）
	{
		cfg := GetDesktopDebugConfig()
		url := "chrome-extension://ldlghkoiihaelfnggonhjnfiabmaficg/popup.html?props=false"
		try {
			http := ComObject("WinHttp.WinHttpRequest.5.1")
			http.SetTimeouts(3000, 3000, 3000, 3000)
			http.Open("PUT", "http://127.0.0.1:" cfg.port "/json/new?" url, false)
			http.Send()
			if (http.Status != 200) {
				; 某些 Chrome 版本 POST 才能 /json/new，回退到 POST
				http := ComObject("WinHttp.WinHttpRequest.5.1")
				http.SetTimeouts(3000, 3000, 3000, 3000)
				http.Open("POST", "http://127.0.0.1:" cfg.port "/json/new?" url, false)
				http.Send()
			}
		} catch Error as e {
			ToolTip("CDP 打开标签页失败（桌面" cfg.desktopIndex " 端口" cfg.port "）：`n" e.Message)
			SetTimer(() => ToolTip(), -3000)
		}
	}
}
#HotIf

; Prtsc键或者LCtrl都能打开chrome
; 仅在非 RDP 场景下允许触发，避免连接/切换 RDP 时误发 Win 键
; #HotIf !IsRdpContext()
SC137::
^!+2::
RCtrl Up:: {
    chromeHwnd := GetChromeHwndOnCurrentDesktop()
    cfg := GetDesktopDebugConfig(chromeHwnd)  ; 传入已找到的hwnd，避免重复WMI搜索
    if chromeHwnd && IsChromeDebugPortReady(cfg.port) {
        if WinActive("ahk_id " chromeHwnd) {
            WinMinimize("ahk_id " chromeHwnd)
        } else {
            WinActivate("ahk_id " chromeHwnd)
        }
    } else {
        LaunchChromeWithDebugPort()
    }
}

; 全局缓存：当前桌面的 Chrome 窗口句柄（热键快速路径，避免每次全量搜索）
global g_cachedChromeHwnd := 0
; 全局缓存：调试端口状态 [ready, tick]（避免每次 HTTP 请求）
global g_debugPortCache := Map()
; 全局缓存：PWA 进程 PID 集合（避免重复查询）
global g_pwaPids := Map()
global g_pwaPidsTick := 0

; 获取进程的命令行参数（不使用 WMI，通过 NtQueryInformationProcess 读取）
GetProcessCommandLine(pid) {
    try {
        hProcess := DllCall("OpenProcess", "UInt", 0x1010, "Int", 0, "UInt", pid, "Ptr")  ; PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ
        if !hProcess
            return ""
        buf := Buffer(32768, 0)  ; UNICODE_STRING 最大 32K
        ; ProcessCommandLineInformation = 60
        status := DllCall("ntdll\NtQueryInformationProcess", "Ptr", hProcess, "UInt", 60, "Ptr", buf, "UInt", buf.Size, "UInt*", 0, "UInt")
        DllCall("CloseHandle", "Ptr", hProcess)
        if (status = 0) {
            ; UNICODE_STRING: Length(2) + MaxLength(2) + Buffer(8)
            strLen := NumGet(buf, 0, "UShort")
            strPtr := NumGet(buf, A_PtrSize == 8 ? 8 : 4, "Ptr")
            if (strLen > 0 && strPtr)
                return StrGet(strPtr, strLen // 2, "UTF-16")
        }
        return ""
    } catch
        return ""
}

; 判断进程是否为 PWA（命令行包含 --app=）
IsPwaProcess(pid) {
    global g_pwaPids, g_pwaPidsTick
    if g_pwaPids.Has(pid)
        return g_pwaPids[pid]

    ; 检查缓存是否过期（60秒 TTL）
    if (A_TickCount - g_pwaPidsTick > 60000) {
        g_pwaPids := Map()
        g_pwaPidsTick := A_TickCount
    }

    cmdLine := GetProcessCommandLine(pid)
    isPwa := InStr(cmdLine, "--app=") > 0
    g_pwaPids[pid] := isPwa
    return isPwa
}

; 获取当前虚拟桌面的 Chrome 窗口句柄
; 返回：hwnd（找到）或 0（未找到）
; ★ 快速路径：缓存验证 <1ms；慢路径：WinGetList + 排除 PWA + DWMWA_CLOAKED
GetChromeHwndOnCurrentDesktop() {
    global g_cachedChromeHwnd

    ; ★ 快速路径：验证缓存（WinExist + DwmGetWindowAttribute，<1ms）
    if g_cachedChromeHwnd && WinExist("ahk_id " g_cachedChromeHwnd) {
        buf := Buffer(4, 0)
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", g_cachedChromeHwnd, "UInt", 14, "Ptr", buf, "UInt", 4, "Int")
        if (hr = 0 && !NumGet(buf, 0, "Int"))
            return g_cachedChromeHwnd
    }
    g_cachedChromeHwnd := 0

    ; WinGetList 获取所有 Chrome 实例（包括所有虚拟桌面）
    chromeList := WinGetList("ahk_exe chrome.exe")
    for hwnd in chromeList {
        ; 过滤无标题窗口（通知、托盘等）
        title := ""
        try title := WinGetTitle("ahk_id " hwnd)
        if !title
            continue

        ; 排除 PWA 窗口（通过 NtQueryInformationProcess 检查 --app=）
        pid := 0
        try pid := WinGetPID("ahk_id " hwnd)
        if IsPwaProcess(pid)
            continue

        ; DWMWA_CLOAKED: 非当前桌面的窗口 cloaked=1
        buf := Buffer(4, 0)
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Ptr", buf, "UInt", 4, "Int")
        if (hr = 0 && !NumGet(buf, 0, "Int")) {
            g_cachedChromeHwnd := hwnd
            return hwnd
        }
    }
    return 0
}

; 获取当前虚拟桌面的 ID（GUID 字符串）
; 通过 ImmersiveShell COM 接口的 IVirtualDesktopManager.GetWindowDesktopId 从当前桌面窗口反查
; 如果当前桌面没有任何窗口，回退到通过焦点窗口查询
; ★ 优化：接受可选 chromeHwnd 参数，避免重复调用 GetChromeHwndOnCurrentDesktop
GetCurrentVirtualDesktopId(chromeHwnd := 0) {
    ; 优先用传入的 Chrome 窗口（调用方已找到，无需重复搜索）
    if chromeHwnd {
        id := GetWindowDesktopId(chromeHwnd)
        if id
            return id
    }
    ; 回退：用当前桌面的 Chrome 窗口
    chromeHwnd := GetChromeHwndOnCurrentDesktop()
    if chromeHwnd {
        id := GetWindowDesktopId(chromeHwnd)
        if id
            return id
    }
    ; 回退：用当前焦点窗口
    focusHwnd := WinExist("A")
    if focusHwnd {
        id := GetWindowDesktopId(focusHwnd)
        if id
            return id
    }
    return ""
}

; 通过 IVirtualDesktopManager COM 接口获取窗口所属虚拟桌面 ID
GetWindowDesktopId(hwnd) {
    if !hwnd
        return ""
    try {
        vdm := ComObject("{AA509086-5CA9-4C25-8F95-589D3C07B48A}", "{A5CD92FF-29BE-454C-8D04-D82879FB3F1B}")
        ; IVirtualDesktopManager.GetWindowDesktopId(hwnd, &desktopId)
        desktopId := Buffer(16)
        ComCall(4, vdm, "Ptr", hwnd, "Ptr", desktopId)
        ; GUID → 字符串
        buf := Buffer(39 * 2)
        DllCall("ole32\StringFromGUID2", "Ptr", desktopId, "Ptr", buf, "Int", 39)
        return StrGet(buf, "UTF-16")
    } catch {
        return ""
    }
}

; 使用 IVirtualDesktopManager 判断窗口是否位于当前虚拟桌面
IsWindowOnCurrentVirtualDesktop(hwnd) {
    if !hwnd
        return false

    try {
        vdm := ComObject("{AA509086-5CA9-4C25-8F95-589D3C07B48A}", "{A5CD92FF-29BE-454C-8D04-D82879FB3F1B}")
        onCurrent := 0
        ComCall(3, vdm, "Ptr", hwnd, "IntP", &onCurrent)
        return onCurrent != 0
    } catch {
        return false
    }
}

; 根据当前虚拟桌面确定调试 Chrome 的 profile 目录和端口
; 目录统一放在 E:\chrome_profiles 以减少 C 盘 IO 负载
; 桌面 1 → E:\chrome_profiles\desktop1:9223
; 桌面 2 → E:\chrome_profiles\desktop2:9224
; 桌面 N → E:\chrome_profiles\desktopN:9222+N
; 识别失败时回退到 desktop1:9223（保证总能启动）
; ★ 优化：接受可选 chromeHwnd 参数，透传给 GetCurrentVirtualDesktopId 避免重复搜索
GetDesktopDebugConfig(chromeHwnd := 0) {
    baseDir := "E:\chrome_profiles"
    basePort := 9222
    desktopId := GetCurrentVirtualDesktopId(chromeHwnd)
    index := 1
    if desktopId != "" {
        idx := GetDesktopIndexById(desktopId)
        if idx > 0
            index := idx
    }
    return { profileDir: baseDir "\desktop" index, port: basePort + index, desktopIndex: index }
}

; 从注册表中查询桌面 GUID 对应的序号（1-based）
; 注册表路径：HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops\Desktops\{id}
; 其中 Index 值为 DWORD
GetDesktopIndexById(desktopId) {
    try {
        ; 桌面 ID 形如 {XXXX-XXXX-...}，注册表子键通常不带花括号
        cleanId := RegExReplace(desktopId, "^\{|\}$", "")
        val := RegRead("HKCU", "Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops\Desktops\" cleanId, "Index")
        return Integer(val) + 1
    } catch {
        return 0
    }
}

; ==========================================================
; 检测 Chrome 调试端口是否已开启
; 关键：必须用 127.0.0.1（Chrome 只监听 IPv4，localhost 可能被解析为 IPv6 ::1 导致失败）
; ★ 优化：缓存端口状态 5 秒，避免每次热键都创建 COM + HTTP 请求
IsChromeDebugPortReady(port) {
    global g_debugPortCache
    now := A_TickCount
    if g_debugPortCache.Has(port) {
        cached := g_debugPortCache[port]
        if (now - cached[2] < 5000)  ; 5秒缓存
            return cached[1]
    }

    ready := false
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(500, 500, 500, 500)
        http.Open("GET", "http://127.0.0.1:" port "/json/version", false)
        http.Send()
        ready := (http.Status = 200)
    } catch {
    }

    g_debugPortCache[port] := [ready, now]
    return ready
}

; 定位 chrome.exe 的真实路径（避开任何快捷方式）
GetChromeExePath() {
    candidates := [
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        EnvGet("LocalAppData") . "\Google\Chrome\Application\chrome.exe"
    ]
    for path in candidates {
        if FileExist(path)
            return path
    }
    return ""
}

; 启动 Chrome 并确保调试端口生效。
; 按虚拟桌面隔离：每个桌面独立的 profile 目录和调试端口，互不影响。
; Chrome 136+ 强制要求：--remote-debugging-port 必须配合 --user-data-dir=<非默认目录>
; 官方文档：https://developer.chrome.com/blog/remote-debugging-port
LaunchChromeWithDebugPort() {
    cfg := GetDesktopDebugConfig()
    debugPort := cfg.port
    debugProfileDir := cfg.profileDir
    desktopIndex := cfg.desktopIndex

    ; 1. 调试端口已就绪 且 当前桌面有 Chrome 窗口 → 激活/最小化切换
    chromeHwnd := GetChromeHwndOnCurrentDesktop()
    if IsChromeDebugPortReady(debugPort) && chromeHwnd {
        if WinActive("ahk_id " chromeHwnd) {
            WinMinimize("ahk_id " chromeHwnd)
        } else {
            WinActivate("ahk_id " chromeHwnd)
        }
        return
    }

    ; 2. 调试端口未启用：只关闭【当前虚拟桌面】的 chrome.exe 进程，其他桌面的调试 Chrome 保持不动
    ;    原理：Chrome 单实例锁按 --user-data-dir 隔离，不同目录可以共存
    currentDesktopId := GetCurrentVirtualDesktopId(chromeHwnd)
    killedCount := 0
    if currentDesktopId != "" && WinExist("ahk_exe chrome.exe") {
        chromeList := WinGetList("ahk_exe chrome.exe")
        targetPids := Map()
        for hwnd in chromeList {
            dId := GetWindowDesktopId(hwnd)
            if (dId != "" && dId = currentDesktopId) {
                try {
                    pid := WinGetPID("ahk_id " hwnd)
                    if pid
                        targetPids[pid] := true
                }
            }
        }
        if targetPids.Count > 0 {
            ToolTip("重启当前桌面（" desktopIndex "）的 Chrome 以启用调试端口...")
            for pid in targetPids {
                try ProcessClose(pid)
                killedCount++
            }
            Sleep(800)
        }
    }

    ; 3. 确保永久调试配置目录存在
    try {
        if !DirExist(debugProfileDir)
            DirCreate(debugProfileDir)
    } catch Error as e {
        ToolTip()
        MsgBox("创建调试配置目录失败: " e.Message "`n目录: " debugProfileDir, "启动失败", 16)
        return
    }

    ; 4. 直接调用 chrome.exe 显式拼接参数（不依赖任何 .lnk）
    ;    必须同时包含 --remote-debugging-port 和 --user-data-dir=<非默认>
    chromeExe := GetChromeExePath()
    if chromeExe = "" {
        ToolTip()
        MsgBox("未找到 chrome.exe，请检查 Chrome 安装路径", "启动失败", 16)
        return
    }
    try {
        ; 加载 DevTools VSCode Opener 扩展，确保每个桌面 Chrome 实例都有打开文件功能
        extensionPath := A_ScriptDir "\devtools-vscode-opener"
        Run(Format('"{1}" --remote-debugging-port={2} --user-data-dir="{3}" --load-extension="{4}" --disable-infobars --variations-override-country=us'
            , chromeExe, debugPort, debugProfileDir, extensionPath))
    } catch Error as e {
        ToolTip()
        MsgBox("启动 Chrome 失败: " e.Message, "启动失败", 16)
        return
    }

    ; 5. 轮询调试端口，确认是否生效（最多等 8 秒）
    Loop 40 {
        Sleep(200)
        if IsChromeDebugPortReady(debugPort) {
            ToolTip()
            return
        }
    }
    ToolTip()
    MsgBox("桌面 " desktopIndex " Chrome 已启动但调试端口 " debugPort " 未开启。`n`n可能原因：`n1. Chrome 未使用 --remote-debugging-port 参数启动`n2. Chrome 136+ 需要同时指定 --user-data-dir=<非默认目录>", "调试端口未开启", 48)
}

IsRdpContext() {
    ; 远程会话中，或当前焦点在 mstsc 窗口，都视为 RDP 场景
    return IsWindowsRemoteSession()
        || WinActive("ahk_exe mstsc.exe")
        || WinActive("ahk_class TscShellContainerClass")
        || WinActive("ahk_class TscShellWndClass")
}

; [新加] 复制并在浏览器搜索
#f10::
{
    ; 等待 Win 键真实松开，避免后续按键被解释为 Win 组合键（如 Win+L）
    KeyWait "LWin"
    KeyWait "RWin"
    Send("{Ctrl up}{Shift up}{Alt up}")

    ; 1. 清空剪贴板并直接发送复制指令（绕过 CapsLock 钩子，直接执行复制动作更稳定）
    A_Clipboard := ""
    if WinActive("ahk_group ShellGroup") {
        SendEvent("{Ctrl Down}{Insert}{Ctrl Up}")
    } else {
        SendEvent("^{c}")
    }

    if !ClipWait(1) {

        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; 2. 若当前已在 Chrome 应用内，则跳过等待与切换
    success := false
    if WinActive("ahk_exe chrome.exe") {
        success := true
    } else {
        ; 直接发送打开浏览器的快捷键 (Win+2)
        ; 使用 AHK 原生的 #2 语法，防止拆分发送导致 Windows 识别为按下了单独的 Win 键（弹出开始菜单）
        LaunchChromeWithDebugPort()

        ; 3. 等待 Chrome 浏览器被激活
        Loop 30 {
            if WinActive("ahk_exe chrome.exe") {
                success := true
                break
            }
            Sleep 100
        }
    }

    if (success) {
        Sleep 200 ; 保留一点小缓冲，防止刚刚激活时输入被吞
        ; 4. 新建标签页 (Ctrl+T)，然后定位地址栏 (Ctrl+L)，粘贴文本并回车搜索
        ; 注意：新建标签页的标准快捷键是 Ctrl+T (`^t`)
        ; SendInput("^t")
        ; Sleep 100 ; 给浏览器哪怕一点点新建标签页和聚焦地址栏的渲染时间
        SendInput("^t^l^v{Enter}")
    } else {
        ToolTip("未检测到 Chrome 窗口被激活")
        SetTimer(() => ToolTip(), -2000)
    }
}


;~ 3、主流程
OpenControllerFromNetwork()
{
    try
    {
        url := DevTools_GetSelectedURL()

        if (url = "")
            url := DevTools_GetSelectedURLFromClipboard()

        if (url = "")
            throw Error("No URL selected")

        path := ParseAPIPath(url)

        A_Clipboard := path

    }
    catch Error as err
    {
        MsgBox "Error:`n" err.Message
    }
}
; ~ 4、DevTools 读取 URL（核心） 
CopyDevToolsSelectedRequestURL()
{
    try
    {
        t0 := A_TickCount
        PerfLog("CopyDevToolsSelectedRequestURL start")

        ; 优先模拟 DevTools 常规操作：右键 -> 复制 -> 复制 URL
        t := A_TickCount
        url := DevTools_CopyURLViaContextMenu()
        PerfLog(Format("after DevTools_CopyURLViaContextMenu (+{1} ms)", A_TickCount - t))

        if (url = "")
        {
            t := A_TickCount
            url := DevTools_GetSelectedURL()
        }

        if (url = "")
        {
            t := A_TickCount
            url := DevTools_GetSelectedURLFromClipboard()
        }

        if (url = "")
            throw Error("No selected request URL found in DevTools Network.`n请将鼠标停在 Network 请求行上后再按热键。")

        ; A_Clipboard := url
        ; 解析 URL，提取 path 部分并放入剪贴板 供后续使用
        A_Clipboard := ParseAPIPath(url)
        PerfLog(Format("CopyDevToolsSelectedRequestURL done total={1} ms", A_TickCount - t0))
        ; ToolTip "Copied URL: " url
        ; SetTimer () => ToolTip(), -1200
    }
    catch Error as err
    {
        PerfLog("CopyDevToolsSelectedRequestURL error: " err.Message)
        MsgBox "Error:`n" err.Message
    }
}

;~ 4、DevTools 读取 URL（核心）
DevTools_GetSelectedURL()
{
    row := DevTools_GetSelectedRequestRowElement()
    if !row
        return ""

    try name := Trim(row.CurrentName)
    catch
        return ""

    if RegExMatch(name, "i)https?://[^\s]+", &m)
        return m[0]

    ; 有些 DevTools 行名不是完整 URL（可能是 path/状态列拼接），这里返回原文本给上层继续走复制兜底
    return name
}

DevTools_GetSelectedURLFromClipboard()
{
    clipBak := A_Clipboard
    A_Clipboard := ""

    Send "^c"
    ClipWait 0.25

    copied := Trim(A_Clipboard)
    A_Clipboard := clipBak

    if (copied = "")
        return ""

    if RegExMatch(copied, "i)https?://[^\s]+", &m)
        return m[0]

    return ""
}

DevTools_CopyURLViaContextMenu()
{
    totalStart := A_TickCount
    PerfLog("DevTools_CopyURLViaContextMenu start")

    clipBak := A_Clipboard
    A_Clipboard := ""

    ; 快速路径：优先在聚焦/选中请求行上右键；失败再退回鼠标位置
    MouseGetPos &mx, &my
    t := A_TickCount
    opened := DevTools_OpenContextMenuOnFocusedOrSelectedRequest(&mx, &my)
    if !opened
    {
        opened := DevTools_OpenContextMenuOnSelectedRequestByKeyboard(&mx, &my, DEVTOOLS_CONTEXTMENU_SLEEP_MS)
    }
    if !opened
    {
        DevTools_OpenContextMenuAtPoint(mx, my, DEVTOOLS_CONTEXTMENU_SLEEP_MS)
    }

    ; 鼠标快速路径：允许一次 full-scan，尽量首轮命中，避免二次开菜单
    copiedUrl := DevTools_TryCopyURLFromOpenedMenu(mx, my, true)
    if (copiedUrl != "")
    {
        A_Clipboard := clipBak
        PerfLog(Format("DevTools_CopyURLViaContextMenu done total={1} ms (mouse fast path)", A_TickCount - totalStart))
        return copiedUrl
    }

    Send "{Esc}"

    ; 次级兜底：尝试按选中请求行打开菜单后再次复制
    opened := DevTools_OpenContextMenuOnSelectedRequest(&mx, &my)

    if opened
    {
        copiedUrl := DevTools_TryCopyURLFromOpenedMenu(mx, my, true)
        if (copiedUrl != "")
        {
            A_Clipboard := clipBak
            PerfLog(Format("DevTools_CopyURLViaContextMenu done total={1} ms (row fallback path)", A_TickCount - totalStart))
            return copiedUrl
        }
    }

    ; 极限兜底：聚焦鼠标所在请求行后直接 Ctrl+C
    copiedUrl := DevTools_TryCopyURLViaCtrlCAtMouse(mx, my)
    if (copiedUrl != "")
    {
        A_Clipboard := clipBak
        PerfLog(Format("DevTools_CopyURLViaContextMenu done total={1} ms (ctrl+c fallback)", A_TickCount - totalStart))
        return copiedUrl
    }

    ; 取消菜单
    Send "{Esc}"
    A_Clipboard := clipBak
    PerfLog(Format("DevTools_CopyURLViaContextMenu done total={1} ms (empty)", A_TickCount - totalStart))
    return ""
}

DevTools_TryCopyURLFromOpenedMenu(mx, my, allowFullScan := true)
{
    global DEVTOOLS_POST_COPY_SLEEP_MS
    global DEVTOOLS_CLIPWAIT_SEC
    global DEVTOOLS_MENU_RETRIES_FAST
    global DEVTOOLS_MENU_RETRY_SLEEP_MS_FAST
    global DEVTOOLS_MENU_RETRIES_FALLBACK
    global DEVTOOLS_MENU_RETRY_SLEEP_MS_FALLBACK
    global DEVTOOLS_CLIPWAIT_SEC_FALLBACK
    global DEVTOOLS_TRIPLE_C_DISABLE_AFTER_FAILS
    global DEVTOOLS_TRIPLE_C_FAIL_STREAK
    global DEVTOOLS_TRIPLE_C_SKIP_MODE
    global DEVTOOLS_MENU_CALL_ROUND

    DEVTOOLS_MENU_CALL_ROUND += 1

    ; 自适应快速键：连续失败后进入 skip 模式，稳定优先不自动 probe
    shouldTryTripleC := true
    if DEVTOOLS_TRIPLE_C_SKIP_MODE
    {
        shouldTryTripleC := false
    }

    if shouldTryTripleC
    {
        Send "c"
        Sleep 40
        Send "c"
        Sleep 40
        Send "c"
        Sleep DEVTOOLS_POST_COPY_SLEEP_MS
        ClipWait DEVTOOLS_CLIPWAIT_SEC
        copied := Trim(A_Clipboard)
        if RegExMatch(copied, "i)https?://[^\s]+", &m)
        {
            DEVTOOLS_TRIPLE_C_FAIL_STREAK := 0
            DEVTOOLS_TRIPLE_C_SKIP_MODE := false
            return m[0]
        }

        DEVTOOLS_TRIPLE_C_FAIL_STREAK += 1
        if (DEVTOOLS_TRIPLE_C_FAIL_STREAK >= DEVTOOLS_TRIPLE_C_DISABLE_AFTER_FAILS)
        {
            DEVTOOLS_TRIPLE_C_SKIP_MODE := true
        }
    }

    ; 常规路径：UIA 定位 Copy 后双 Enter 选中子菜单首项（通常是 Copy URL）
    if DevTools_WaitAndInvokeMenuItem("copy", mx, my, DEVTOOLS_MENU_RETRIES_FAST, DEVTOOLS_MENU_RETRY_SLEEP_MS_FAST, allowFullScan)
    {
        Sleep DEVTOOLS_POST_COPY_SLEEP_MS

        ; 快速路径：点击 Copy 后，直接双 Enter 选择子菜单首项（通常是 Copy URL）
        Send "{Enter}{Enter}"
        ClipWait DEVTOOLS_CLIPWAIT_SEC
        copied := Trim(A_Clipboard)
        if RegExMatch(copied, "i)https?://[^\s]+", &m)
            return m[0]

        ; 双 Enter 未命中时，回退到原 URL 菜单查找
        if DevTools_WaitAndInvokeMenuItem("url", mx, my, DEVTOOLS_MENU_RETRIES_FAST, DEVTOOLS_MENU_RETRY_SLEEP_MS_FAST, allowFullScan)
        {
            ClipWait DEVTOOLS_CLIPWAIT_SEC
            copied := Trim(A_Clipboard)
            if RegExMatch(copied, "i)https?://[^\s]+", &m)
                return m[0]
        }
    }

    ; 轻量兜底：尝试一级菜单中的 Copy URL（仅局部查找，不做全局扫描）
    if DevTools_WaitAndInvokeMenuItem("url", mx, my, 1, DEVTOOLS_MENU_RETRY_SLEEP_MS_FAST, false)
    {
        ClipWait DEVTOOLS_CLIPWAIT_SEC
        copied := Trim(A_Clipboard)
        if RegExMatch(copied, "i)https?://[^\s]+", &m)
            return m[0]
    }

    ; 强兜底：放宽重试与等待，兼容慢机器/菜单渲染慢
    PerfLog("enter reliable fallback menu flow")

    if DevTools_WaitAndInvokeMenuItem("copy", mx, my, DEVTOOLS_MENU_RETRIES_FALLBACK, DEVTOOLS_MENU_RETRY_SLEEP_MS_FALLBACK, allowFullScan)
    {
        Sleep 120

        ; 可靠模式也优先尝试双 Enter，减少一次菜单扫描
        Send "{Enter}{Enter}"
        ClipWait DEVTOOLS_CLIPWAIT_SEC_FALLBACK
        copied := Trim(A_Clipboard)
        if RegExMatch(copied, "i)https?://[^\s]+", &m)
            return m[0]

        if DevTools_WaitAndInvokeMenuItem("url", mx, my, DEVTOOLS_MENU_RETRIES_FALLBACK, DEVTOOLS_MENU_RETRY_SLEEP_MS_FALLBACK, allowFullScan)
        {
            ClipWait DEVTOOLS_CLIPWAIT_SEC_FALLBACK
            copied := Trim(A_Clipboard)
            if RegExMatch(copied, "i)https?://[^\s]+", &m)
                return m[0]
        }
    }

    return ""
}

PerfLog(msg)
{
    global PERF_LOG_ENABLED

    if !PERF_LOG_ENABLED
        return

    line := Format("[{1}] {2}`n", A_TickCount, msg)
    OutputDebug line
    FileAppend line, A_ScriptDir "\\ahk_devtools_perf.log", "UTF-8"
}

DevTools_GetSelectedRequestRowElement()
{
    hwnd := WinActive("A")
    if !hwnd
        return ""

    root := UIA.ElementFromHandle(hwnd)
    cond := UIA.CreatePropertyCondition(UIA.Property.ControlType, UIA.Type.DataItem)
    rows := root.FindAll(cond, UIA.TreeScope.Subtree)

    best := ""
    bestScore := -1


    for row in rows
    {
        try name := Trim(row.CurrentName)
        catch
            continue

        if (name = "")
            continue

        try br := row.BoundingRectangle
        catch
            continue

        w := br.r - br.l
        h := br.b - br.t
        if (w < 20 || h < 10)
            continue

        score := 0

        try if row.CurrentIsSelected
            score += 10

        try if row.HasKeyboardFocus
            score += 8

        if RegExMatch(name, "i)^https?://")
            score += 12
        if InStr(name, "api")
            score += 2

        if (score > bestScore)
        {
            best := row
            bestScore := score
        }
    }

    return (bestScore >= 8) ? best : ""
}

DevTools_OpenContextMenuOnSelectedRequest(&mx, &my)
{
    row := DevTools_GetSelectedRequestRowElement()
    if !row
        return false

    return DevTools_OpenContextMenuOnRow(row, &mx, &my, 180)
}

DevTools_OpenContextMenuOnSelectedRequestByKeyboard(&mx, &my, waitMs := 120)
{
    row := DevTools_GetSelectedRequestRowElement()
    if !row
        return false

    try br := row.BoundingRectangle
    catch
        return false

    mx := br.l + ((br.r - br.l) // 2)
    my := br.t + ((br.b - br.t) // 2)

    try row.SetFocus()
    catch
    {
    }

    try row.Click()
    catch
    {
    }

    Send "{AppsKey}"
    DevTools_WaitForContextMenu(waitMs)
    return true
}

DevTools_GetFocusedRequestRowElement()
{
    try focused := UIA.GetFocusedElement()
    catch
        return ""

    if !IsObject(focused)
        return ""

    el := focused
    loop 8
    {
        try ct := el.CurrentControlType
        catch
            break

        if (ct = UIA.Type.DataItem)
            return el

        try el := UIA.TreeWalkerTrue.GetParentElement(el)
        catch
            break

        if !IsObject(el)
            break
    }

    return ""
}

DevTools_OpenContextMenuOnFocusedOrSelectedRequest(&mx, &my)
{
    row := DevTools_GetFocusedRequestRowElement()
    if !row
        row := DevTools_GetSelectedRequestRowElement()

    if !row
        return false

    return DevTools_OpenContextMenuOnRow(row, &mx, &my, DEVTOOLS_CONTEXTMENU_SLEEP_MS)
}

DevTools_OpenContextMenuOnRow(row, &mx, &my, waitMs)
{
    try br := row.BoundingRectangle
    catch
        return false

    mx := br.l + ((br.r - br.l) // 2)
    my := br.t + ((br.b - br.t) // 2)

    try
    {
        row.Click("Right")
        DevTools_WaitForContextMenu(waitMs)
        return true
    }
    catch
    {
    }

    return DevTools_OpenContextMenuAtPoint(mx, my, waitMs)
}

DevTools_OpenContextMenuAtPoint(mx, my, waitMs := 120)
{
    MouseGetPos &oldX, &oldY
    MouseMove mx, my, 0
    Click "Right"
    MouseMove oldX, oldY, 0
    DevTools_WaitForContextMenu(waitMs)
    return true
}

DevTools_WaitForContextMenu(waitMs := 120)
{
    start := A_TickCount
    while (A_TickCount - start < waitMs)
    {
        if WinExist("ahk_class #32768")
            return true
        Sleep 10
    }

    return false
}

DevTools_TryCopyURLViaCtrlCAtMouse(mx, my)
{
    MouseGetPos &oldX, &oldY
    MouseMove mx, my, 0
    Click
    Sleep 40
    Send "^c"
    ClipWait 0.25
    MouseMove oldX, oldY, 0

    copied := Trim(A_Clipboard)
    if (copied = "")
        return ""

    if RegExMatch(copied, "i)https?://[^\s]+", &m)
        return m[0]

    return ""
}

DevTools_WaitAndInvokeMenuItem(mode, mx, my, retries := "", sleepMs := "", enableFinalFullScan := true)
{
    global DEVTOOLS_MENU_RETRIES
    global DEVTOOLS_MENU_RETRY_SLEEP_MS

    if (retries = "")
        retries := DEVTOOLS_MENU_RETRIES

    if (sleepMs = "")
        sleepMs := DEVTOOLS_MENU_RETRY_SLEEP_MS

    loop retries
    {
        if DevTools_InvokeBestMenuItem(mode, mx, my, false)
            return true
        Sleep sleepMs
    }

    if enableFinalFullScan
    {
        if DevTools_InvokeBestMenuItem(mode, mx, my, true)
            return true
    }

    return false
}

DevTools_InvokeBestMenuItem(mode, mx, my, allowFullScan := true)
{
    cond := UIA.CreatePropertyCondition(UIA.Property.ControlType, UIA.Type.MenuItem)
    menuRoot := DevTools_GetContextMenuRoot()
    if IsObject(menuRoot)
    {
        best := DevTools_FindBestMenuItemInElement(menuRoot, cond, mode, mx, my, 1200, 800)
        if IsObject(best)
            return DevTools_ClickOrInvoke(best, mode, mx, my)
    }
    ; 优先在焦点和鼠标附近做局部查找，避免全桌面 Subtree 扫描
    anchors := []

    ; 命中缓存时先单独尝试，若失败则本轮禁用缓存避免重复命中空耗
    cachedAnchor := DevTools_GetCachedMenuAnchor(mode, mx, my)
    if IsObject(cachedAnchor)
    {
        best := DevTools_FindBestMenuItemNearAnchor(cachedAnchor, cond, mode, mx, my)
        if IsObject(best)
            return DevTools_ClickOrInvoke(best, mode, mx, my)

        if allowFullScan
        {
            best := DevTools_FindBestMenuItemNearAnchor(cachedAnchor, cond, mode, mx, my, 980, 760)
            if IsObject(best)
            {
                PerfLog("DevTools_InvokeBestMenuItem fallback anchor-wide-scan")
                return DevTools_ClickOrInvoke(best, mode, mx, my)
            }
        }

        DevTools_DisableMenuCacheForCurrentRound(mode)
    }

    try
    {
        focused := UIA.GetFocusedElement()
        if IsObject(focused)
            anchors.Push(focused)
    }
    catch
    {
    }

    ; 补充更多菜单常见偏移点，提高局部命中率，降低触发 full-scan 概率
    for offset in [[18, 12], [10, 22], [0, 0], [60, 18], [96, 22], [132, 30], [72, 44], [118, 56], [-18, 16]]
    {
        try
        {
            el := UIA.ElementFromPoint(mx + offset[1], my + offset[2],, 0)
            if IsObject(el)
                anchors.Push(el)
        }
        catch
        {
        }
    }

    for anchor in anchors
    {
        best := DevTools_FindBestMenuItemNearAnchor(anchor, cond, mode, mx, my)
        if IsObject(best)
            return DevTools_ClickOrInvoke(best, mode, mx, my)
    }

    if allowFullScan
    {
        ; 先做锚点子树的宽范围扫描，减少直接全桌面扫描的概率
        for anchor in anchors
        {
            best := DevTools_FindBestMenuItemNearAnchor(anchor, cond, mode, mx, my, 980, 760)
            if IsObject(best)
            {
                PerfLog("DevTools_InvokeBestMenuItem fallback anchor-wide-scan")
                return DevTools_ClickOrInvoke(best, mode, mx, my)
            }
        }
    }

    if allowFullScan
    {
        ; 最后兜底：若局部查找失败，再做一次全局扫描
        PerfLog("DevTools_InvokeBestMenuItem fallback full-scan")
        root := UIA.GetRootElement()
        best := DevTools_FindBestMenuItemInElement(root, cond, mode, mx, my, 1100, 760)
        if IsObject(best)
            return DevTools_ClickOrInvoke(best, mode, mx, my)
    }

    return false
}

DevTools_GetContextMenuRoot()
{
    hwnd := WinExist("ahk_class #32768")
    if !hwnd
        return ""

    try
        return UIA.ElementFromHandle(hwnd)
    catch
        return ""
}

DevTools_GetCachedMenuAnchor(mode, mx, my)
{
    global DEVTOOLS_MENU_ANCHOR_CACHE
    global DEVTOOLS_MENU_CACHE_TTL_MS
    global DEVTOOLS_MENU_CACHE_DRIFT_X
    global DEVTOOLS_MENU_CACHE_DRIFT_Y
    global DEVTOOLS_MENU_CALL_ROUND
    global DEVTOOLS_MENU_CACHE_DISABLED_ROUND

    if !IsObject(DEVTOOLS_MENU_ANCHOR_CACHE)
        return ""

    hwnd := WinActive("A")
    if !hwnd
        return ""

    if (DEVTOOLS_MENU_ANCHOR_CACHE.hwnd != hwnd)
        return ""

    slotName := (mode = "url") ? "url" : "copy"

    if IsObject(DEVTOOLS_MENU_CACHE_DISABLED_ROUND)
    {
        if (DEVTOOLS_MENU_CACHE_DISABLED_ROUND.%slotName% = DEVTOOLS_MENU_CALL_ROUND)
            return ""
    }

    slot := DEVTOOLS_MENU_ANCHOR_CACHE.%slotName%
    if !IsObject(slot)
        return ""

    if !slot.valid
        return ""

    if (A_TickCount - slot.ts > DEVTOOLS_MENU_CACHE_TTL_MS)
        return ""

    if (Abs(slot.mx - mx) > DEVTOOLS_MENU_CACHE_DRIFT_X || Abs(slot.my - my) > DEVTOOLS_MENU_CACHE_DRIFT_Y)
        return ""

    try anchor := UIA.ElementFromPoint(slot.x, slot.y,, 0)
    catch
        return ""

    return IsObject(anchor) ? anchor : ""
}

DevTools_DisableMenuCacheForCurrentRound(mode)
{
    global DEVTOOLS_MENU_CALL_ROUND
    global DEVTOOLS_MENU_CACHE_DISABLED_ROUND

    slotName := (mode = "url") ? "url" : "copy"
    if !IsObject(DEVTOOLS_MENU_CACHE_DISABLED_ROUND)
        DEVTOOLS_MENU_CACHE_DISABLED_ROUND := {copy: 0, url: 0}

    DEVTOOLS_MENU_CACHE_DISABLED_ROUND.%slotName% := DEVTOOLS_MENU_CALL_ROUND
}

DevTools_RememberMenuAnchor(mode, item, mx, my)
{
    global DEVTOOLS_MENU_ANCHOR_CACHE

    if !IsObject(item)
        return

    try br := item.BoundingRectangle
    catch
        return

    cx := br.l + ((br.r - br.l) // 2)
    cy := br.t + ((br.b - br.t) // 2)

    slotName := (mode = "url") ? "url" : "copy"
    slot := DEVTOOLS_MENU_ANCHOR_CACHE.%slotName%
    if !IsObject(slot)
        slot := {}

    slot.valid := true
    slot.x := cx
    slot.y := cy
    slot.mx := mx
    slot.my := my
    slot.ts := A_TickCount

    DEVTOOLS_MENU_ANCHOR_CACHE.%slotName% := slot
    DEVTOOLS_MENU_ANCHOR_CACHE.hwnd := WinActive("A")
}

DevTools_FindBestMenuItemNearAnchor(anchor, cond, mode, mx, my, nearX := 500, nearY := 360)
{
    bases := []

    if IsObject(anchor)
        bases.Push(anchor)

    try
    {
        p1 := UIA.TreeWalkerTrue.GetParentElement(anchor)
        if IsObject(p1)
            bases.Push(p1)

        p2 := UIA.TreeWalkerTrue.GetParentElement(p1)
        if IsObject(p2)
            bases.Push(p2)
    }
    catch
    {
    }

    for base in bases
    {
        best := DevTools_FindBestMenuItemInElement(base, cond, mode, mx, my, nearX, nearY)
        if IsObject(best)
            return best
    }

    return ""
}

DevTools_FindBestMenuItemInElement(base, cond, mode, mx, my, nearX := 700, nearY := 500)
{
    try items := base.FindAll(cond, UIA.TreeScope.Subtree)
    catch
        return ""

    best := ""
    bestScore := -1

    for item in items
    {
        try name := StrLower(Trim(item.CurrentName))
        catch
            continue

        if (name = "")
            continue

        try br := item.BoundingRectangle
        catch
            continue

        w := br.r - br.l
        h := br.b - br.t
        if (w < 8 || h < 8)
            continue

        cx := br.l + (w // 2)
        cy := br.t + (h // 2)
        if !(Abs(cx - mx) <= nearX && Abs(cy - my) <= nearY)
            continue

        score := DevTools_ScoreMenuItemName(mode, name)

        if (score > bestScore)
        {
            best := item
            bestScore := score
        }
    }

    return (bestScore >= 6) ? best : ""
}

DevTools_ScoreMenuItemName(mode, name)
{
    score := 2

    if (mode = "url")
    {
        if (InStr(name, "复制") || InStr(name, "copy")) && (InStr(name, "url") || InStr(name, "网址") || InStr(name, "链接"))
            score += 20
        if InStr(name, "url")
            score += 8
        if InStr(name, "网址") || InStr(name, "链接")
            score += 7
        if InStr(name, "复制") || InStr(name, "copy")
            score += 4
        if InStr(name, "curl") || InStr(name, "har") || InStr(name, "fetch") || InStr(name, "powershell") || InStr(name, "open") || InStr(name, "source")
            score -= 3
    }
    else
    {
        if (name = "复制" || name = "copy")
            score += 16
        if InStr(name, "复制") || InStr(name, "copy")
            score += 5
        if InStr(name, "url") || InStr(name, "网址") || InStr(name, "链接")
            score -= 8
    }

    return score
}

DevTools_ClickOrInvoke(item, mode := "", mx := 0, my := 0)
{
    try
    {
        item.Click()
        if (mode != "")
            DevTools_RememberMenuAnchor(mode, item, mx, my)
        return true
    }
    catch
    {
    }

    try
    {
        item.Invoke()
        if (mode != "")
            DevTools_RememberMenuAnchor(mode, item, mx, my)
        return true
    }
    catch
    {
        return false
    }
}
;~ 5、URL 解析
ParseAPIPath(url)
{
    pos := InStr(url, "/", false, InStr(url, "://") + 3)
    if !pos
        return ""

    path := SubStr(url, pos)

    qpos := InStr(path, "?")
    if qpos
        path := SubStr(path, 1, qpos - 1)

    return TrimFirstPathSegmentFast(path)
}

TrimFirstPathSegmentFast(path)
{
    if (path = "" || SubStr(path, 1, 1) != "/")
        return path

    pos := InStr(path, "/", false, 2)

    if (pos = 0)
        return ""   ; 只有一层

    return SubStr(path, pos)
}

;~ 6、Controller 搜索（fd + rg）
FindController(path)
{
    global CONFIG

    try
    {
        ; 转换 REST path → 关键词
        keyword := StrReplace(path, "/", " ")

        cmd := Format(
            'cmd /c fd -t f -e java -e ts "{1}" "{2}"',
            keyword,
            CONFIG.projectRoot
        )

        result := ExecCmd(cmd)

        if (result != "")
        {
            lines := StrSplit(result, "`n")
            return lines[1]
        }
    }
    catch
    {
    }

    return ""
}

;~ 6.5、DevTools URL 转本地文件路径
; 支持 file:///D:/path、webpack:///./path、http://localhost:3000/D:/path 等格式
DevToolsUrlToLocalPath(url) {
    if !url
        return ""

    ; file:// URL: file:///D:/path/to/file.js → D:/path/to/file.js
    if RegExMatch(url, "^file:///([A-Za-z]:/.+)$", &m) {
        return m[1]
    }
    ; file:// URL (无第三个斜杠): file://D:/path → D:/path
    if RegExMatch(url, "^file://([A-Za-z]:/.+)$", &m) {
        return m[1]
    }
    ; webpack:// URL: webpack:///./path/to/file.js → 需要匹配项目根目录
    ;   或 webpack-internal:///D:/path → D:/path
    if RegExMatch(url, "^webpack-internal:///(.+)$", &m) {
        path := m[1]
        if RegExMatch(path, "^[A-Za-z]:/", &_) 
            return path
    }
    ; webpack://namespace/./path → 尝试去前缀
    if RegExMatch(url, "^webpack://[^/]+/(?:\\./)?(.+)$", &m) {
        path := m[1]
        ; 如果包含 Windows 盘符路径
        if RegExMatch(path, "^[A-Za-z]:/", &_)
            return path
        ; 否则返回相对路径，让编辑器尝试解析
        return path
    }
    ; http/https URL (如 Vite dev server): 可能包含 /@fs/D:/path
    if RegExMatch(url, "^https?://[^/]+/(?:@fs/)?([A-Za-z]:/.+)$", &m) {
        return m[1]
    }
    ; 已经是本地路径
    if RegExMatch(url, "^[A-Za-z]:/", &_)
        return url

    return ""
}

;~ 7、在编辑器中打开文件（虚拟桌面感知 + --reuse-window）
; 流程：1. IVirtualDesktopManager 检测当前桌面的编辑器窗口 → 2. 激活窗口 → 3. 延迟等待 Qoder IPC 注册 → 4. --reuse-window 打开文件
; 关键：--reuse-window 复用"最近激活"的窗口，所以必须先激活当前桌面的窗口
OpenInEditor(file, lineNum?, colNum?)
{
    ; 1. 找到当前虚拟桌面的 Qoder/VS Code 窗口，并获取其进程路径
    editorHwnd := GetEditorHwndOnCurrentDesktop()
    editorPath := ""

    if editorHwnd {
        ; 用当前桌面窗口的 PID 获取编辑器可执行文件路径
        pid := WinGetPID("ahk_id " editorHwnd)
        try editorPath := WinGetProcessPath("ahk_id " editorHwnd)
        if (editorPath = "" && pid)
            editorPath := ProcessPath(pid)

        ; 先激活，确保 --reuse-window 复用此窗口
        WinActivate("ahk_id " editorHwnd)
        WinWaitActive("ahk_id " editorHwnd, , 2)
        ; 等待 Qoder/VS Code 的 IPC 机制注册当前窗口为"最近激活"
        Sleep(150)
        ToolTip("[OpenInEditor] 桌面匹配 hwnd=" editorHwnd " pid=" pid " path=" editorPath)
        SetTimer(() => ToolTip(), -5000)
    } else {
        ToolTip("[OpenInEditor] 当前桌面未找到编辑器窗口")
        SetTimer(() => ToolTip(), -5000)
    }

    ; 2. 如果当前桌面没有找到，回退：检测任何桌面是否有编辑器
    if editorPath = "" {
        qoderHwnd := WinExist("ahk_exe Qoder IDE.exe")
        if !qoderHwnd
            qoderHwnd := WinExist("ahk_exe Qoder.exe")
        if qoderHwnd {
            editorPath := ProcessPath(WinGetPID("ahk_id " qoderHwnd))
            ToolTip("[OpenInEditor] 回退: 使用其他桌面的 Qoder path=" editorPath)
            SetTimer(() => ToolTip(), -5000)
        } else if WinExist("ahk_exe Code.exe") {
            editorPath := ProcessPath(WinGetPID("ahk_exe Code.exe"))
            ToolTip("[OpenInEditor] 回退: 使用其他桌面的 VS Code path=" editorPath)
            SetTimer(() => ToolTip(), -5000)
        }
    }

    if editorPath = "" {
        ToolTip("未找到 Qoder 或 VS Code 进程")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; Qoder IDE.exe 是 GUI 进程，跳转参数必须交给 bin\qoder.cmd
    editorCliPath := GetEditorCliPath(editorPath)

    ; 3. 拼接命令行参数: --reuse-window --goto file:line:column
    args := "--reuse-window"
    if IsSet(lineNum) && lineNum {
        if IsSet(colNum) && colNum {
            args .= ' --goto "' file ':' lineNum ':' colNum '"'
        } else {
            args .= ' --goto "' file ':' lineNum '"'
        }
    } else {
        args .= ' "' file '"'
    }

    ToolTip("打开: " file (lineNum ? " (" lineNum ":" (colNum ? colNum : "") ")" : ""))
    SetTimer(() => ToolTip(), -3000)
    Run Format('"{1}" {2}', editorCliPath, args)
}

; 获取编辑器 CLI 入口。Qoder 新版不再由 GUI 主程序直接处理 --goto。
GetEditorCliPath(editorPath)
{
    SplitPath(editorPath, &editorName, &editorDir)
    if (StrLower(editorName) = "qoder ide.exe") {
        qoderCliPath := editorDir "\bin\qoder.cmd"
        if FileExist(qoderCliPath)
            return qoderCliPath
    }

    return editorPath
}

; 获取当前虚拟桌面上 Qoder 或 VS Code 的窗口句柄
; 使用 DWMWA_CLOAKED 检测当前桌面窗口
GetEditorHwndOnCurrentDesktop() {
    for exeName in ["Qoder IDE.exe", "Qoder.exe", "Code.exe"] {
        winList := WinGetList("ahk_exe " exeName)
        for hwnd in winList {
            ; 过滤无标题窗口
            title := ""
            try title := WinGetTitle("ahk_id " hwnd)
            if !title
                continue
            if IsWindowOnCurrentVirtualDesktop(hwnd)
                return hwnd
        }
    }
    return 0
}

; 获取进程的可执行文件路径
ProcessPath(pid) {
    try {
        hProcess := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
        if !hProcess
            return ""
        buf := Buffer(520, 0)  ; MAX_PATH * 2 (Unicode)
        DllCall("QueryFullProcessImageNameW", "Ptr", hProcess, "UInt", 0, "Ptr", buf, "UIntP", &bufLen:=260, "Int")
        DllCall("CloseHandle", "Ptr", hProcess)
        return StrGet(buf, "UTF-16")
    } catch {
        return ""
    }
}
;~ 8、执行命令工具
ExecCmd(cmd)
{
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(cmd)

    result := exec.StdOut.ReadAll()
    return result
}

/**
 * 获取行号请求封装
 */
GetLineNumberFromBridge() {
    Http := ComObject("WinHttp.WinHttpRequest.5.1")
    try {
        Http.Open("GET", "http://localhost:3000/line-number", true)
        Http.Send()
        if !Http.WaitForResponse(1) ; 1秒超时
            return {line: "Timeout", column: 0, fileUrl: ""}
            
        ; JSON 解析：同时提取行号、列号和文件 URL
        response := Http.ResponseText
        lineNum := 0, colNum := 0, fileUrl := ""
        if RegExMatch(response, '"lineNumber":(\d+)', &matchLine) {
            lineNum := matchLine[1]
        }
        if RegExMatch(response, '"columnNumber":(\d+)', &matchCol) {
            colNum := matchCol[1]
        }
        if RegExMatch(response, '"fileUrl":"([^"]+)"', &matchUrl) {
            fileUrl := matchUrl[1]
        }
        if lineNum {
            return {line: lineNum, column: colNum, fileUrl: fileUrl}
        }
        if RegExMatch(response, '"error"\s*:\s*"([^"]+)"', &errMatch) {
            return {line: errMatch[1], column: 0, fileUrl: ""}
        }
        return {line: "Not in Source Panel", column: 0, fileUrl: ""}    
    } catch Error as err {
        return {line: "Offline", column: 0, fileUrl: ""}
    }
}

EnsureBridgeRunning() {
    if IsBridgeRunning() {
        return true
    }

    bridgeScript := A_ScriptDir "\run_bridge.ps1"
    if FileExist(bridgeScript) {
        try {
            Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' bridgeScript '"', , "Hide")
        } catch {
        }
    }

    Loop 20 {
        if IsBridgeRunning() {
            return true
        }
        Sleep 200
    }

    return false
}

IsBridgeRunning() {
    Http := ComObject("WinHttp.WinHttpRequest.5.1")
    try {
        Http.SetTimeouts(300, 300, 300, 800)
        Http.Open("GET", "http://127.0.0.1:3000/health", false)
        Http.Send()
        return (Http.Status = 200)
    } catch {
        return false
    }
}

