#Requires AutoHotkey v2.0
#SingleInstance force
#Include %A_ScriptDir%\lib\Jxon.ahk
; 引入 UIA 核心和浏览器专用扩展
#Include %A_ScriptDir%\lib\UIA.ahk
#Include %A_ScriptDir%\lib\UIA_Browser.ahk

#UseHook true   ; 强制使用键盘钩子
SetCapsLockState "AlwaysOff"

; 清除重载脚本时可能残留的工具提示
ToolTip("")

; 从外部进程直接触发 VS Code 前台激活
if (A_Args.Length > 0 && A_Args[1] = "--focus-vscode") {
    ; 复用 Ctrl+Space 热键原有逻辑：优先激活已存在的 Code 窗口
    openVSCode("Code.exe", A_Programs "\Visual Studio Code\Visual Studio Code.lnk")
    ExitApp()
}

#Include %A_ScriptDir%\hotkeys_public.ahk
#Include %A_ScriptDir%\OpenControllerFromNetwork.ahk
#Include %A_ScriptDir%\superFlow.ahk
#Include %A_ScriptDir%\rdp.ahk
#Include %A_ScriptDir%\CycleExplorerSwitcher.ahk
; 可选包含：文件不存在时忽略，不会在加载阶段报错
#Include *i %A_ScriptDir%\hotkeys_private.ahk


; 1. 权限自提升与任务注册逻辑
if !A_IsAdmin {
    try {
        ; 尝试提权运行当前脚本
        Run('*RunAs "' A_ScriptFullPath '"')
    } catch {
        MsgBox("错误：脚本必须以管理员权限运行才能修改系统任务。", "权限受限", 16)
    }
    ExitApp()
}

; 此时已是管理员权限，检查文件标记判断是否需要注册任务计划
; 用户配置文件
configPath := A_ScriptDir "\config.ini"
isTaskCreated := IniRead(configPath, "Setup", "TaskCreated", "0")

if (isTaskCreated == "0") {
    taskName := "AutoRunHotkeyTask"
    ; 构造创建任务的命令：登录时以最高权限运行，且不受电源限制
    createTaskCmd := 'schtasks /create /tn "' taskName '" /tr "\"' A_AhkPath '\" \"' A_ScriptFullPath '\"" /sc onlogon /rl highest /f'

    try {
        RunWait(createTaskCmd, , "Hide")
        IniWrite("1", configPath, "Setup", "TaskCreated")
    } catch as e {
        MsgBox("任务计划注册失败：`n" e.Message, "系统错误", 16)
    }
}


global x86ProgramFilesDir := EnvGet("ProgramFiles(x86)")

; 使用正则表达式替换开头的 C: 为 D:
; ^ 表示匹配字符串开头，i 表示不区分大小写
global D_Programs := RegExReplace(A_ProgramFiles, "(?i)^C:", "D:")

; 窗口切换与应用启动框架已拆分到独立模块
#Include %A_ScriptDir%\lib\WindowToggle.ahk

; BlockWinPFor / ToggleWindow 系列 / GetMainWindowByExe 已迁移至 WindowToggle.ahk

; #p::return
; 微信hwnd缓存值
global g_weixinHwnd := 0


; 有道词典复制粘贴并查询翻译
pasteEnter(){
    ; 加入重试机制 (try...catch + Loop)，防止Chrome_WidgetWin_11还没来得及完全初始化，导致ControlFocus失败
    success := false
    Loop 30 {
        try {
            targetHwnd := ControlGetHwnd("Chrome_WidgetWin_11", "ahk_class YodaoMainWndClass")
            ControlFocus(targetHwnd)

            focusedCtrl := ControlGetFocus("ahk_class YodaoMainWndClass")
            focusedHwnd := ControlGetHwnd(focusedCtrl, "ahk_class YodaoMainWndClass")

            if (targetHwnd == focusedHwnd) {
                success := true
                break
            }
        } catch {
            ; 遇到错误时忽略，继续下一次重试
        }
        Sleep 100
    }

    if (!success) {
        return
    }

    ; 确保剪贴板内包含内容后再继续
    if ClipWait(1) {
        ; 使用 SendInput 将按键一次性按顺序送入系统输入队列
        ; Chromium 内核会按顺序同步处理队列中的按键，无需手动 Sleep
        SendInput("^a^v{Enter}")
    }

    return
}

UIAPasteEnter(textToSet) {
    try {
        ; 1. 获取窗口元素
        yodaoEl := UIA.ElementFromHandle("ahk_class YodaoMainWndClass")

        ; 2. 定位输入框元素
        ; 有道词典的输入框通常是一个 Edit 或 Document 类型的控件
        ; 我们查找第一个支持 Value 模式或 Text 模式的输入控件
        inputEl := yodaoEl.FindElement({Type:"Edit"}) ; 如果找不到，尝试 {Type:"Document"}

        ; 3. 使用 UIA 直接设置值（这会瞬间替换原有内容，不需要 ^a）
        inputEl.Value := textToSet

        ; 4. 模拟回车确认（有些应用在设置 Value 后需要点一下或敲回车触发搜索）
        ; 也可以尝试调用该元素的特定的调用方法，但 Send 通常最简单
        WinActivate "ahk_id " yodaoEl.GetHandle()
        Send "{Enter}"

    } catch Error as e {
        MsgBox "UIA 定位失败: " e.Message
    }
}

; 输入法切换引擎已拆分到独立模块
#Include %A_ScriptDir%\lib\ImeSwitcher.ahk

; ============================
;  以下函数已迁移至 ImeSwitcher.ahk：
;    GetLeftText / EnsurePinyinReady / ConvertCharacter / SwitchPunctuation
; ============================
; 打开将光标前英文单词转为中文
LWin & z::
{
    ; 强制清理所有修饰键
   ConvertCharacter()
}
; 打开将光标前英文单词转为中文
^+w::
{
    hwnd := WinGetID("ahk_exe SGSmartAssistant.exe")
    if !hwnd
        return
    state := WinGetMinMax(hwnd)
    if (state = -1) {
        ; 已最小化 → 恢复
        DllCall("ShowWindow", "ptr", hwnd, "int", 9)
        WinActivate hwnd
    } else {
        ; 未最小化 → 最小化
        PostMessage 0x112, 0xF020,,, hwnd
    }
}
; A_ProgramsCommon= "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
; win+F2打开meeting
#F2::
{
	ahk_exe := "wemeetapp.exe"
	APP_PATH := A_ProgramsCommon "\腾讯会议.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+F3打开clash
#F3::
{
    ahk_class := "Tauri Window"
    ahk_exe := "clash-verge.exe"
    winTitle := "Clash Verge"
	  APP_PATH := A_ProgramsCommon "\Clash Verge.lnk"
    if WinExist("ahk_exe " ahk_exe) {
        ; 获取主窗口的进程 ID (PID)
        ahk_id := GetMainWindowByExe(ahk_exe,winTitle)
        if (ahk_id) {
            ; 这是 Clash Verge 程序
            if WinActive("ahk_id " ahk_id) {
                WinMinimize("ahk_id " ahk_id)
            } else {
                WinActivate("ahk_id " ahk_id)
            }
        }
    } else {
        RunAppPathWithPrefixFallback(APP_PATH)
    }
}
; Win + F4热键打开小红书
#F4::
{
	ahk_exe := "Androws.exe"
	APP_PATH := A_ProgramsCommon "\小红书.lnk"
    WinTitle := "小红书"
    ToggleWindowByTitle(ahk_exe,WinTitle,APP_PATH)

}

; Win + F5热键打开微信读书
#F5::
{
	ahk_exe := "Androws.exe"
    WinTitle := "微信读书"
	APP_PATH := A_ProgramsCommon "\微信读书.lnk"
    ToggleWindowByTitle(ahk_exe,WinTitle,APP_PATH)

}
; win+F6打开搜狗PDF阅读编辑器
#F6::
{
	ahk_exe := "fastpdf.exe"
	APP_PATH := A_Programs "\PDF阅读编辑器.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+F7打开AdminRadiator
/* #F7::
{
    ahk_class := "FLUTTER_RUNNER_WIN32_WINDOW"
    UniqueID := WinExist("ahk_class " ahk_class)
    if (UniqueID) {
               ; MsgBox 111

        WinRestore(UniqueID)  ; 恢复窗口
        WinActivate(UniqueID) ; Activate the window found above
    } else {
        ;MsgBox 222
        taskName := "AdminRadiator"
        ; 使用 schtasks 命令启动任务
        Run("schtasks /run /tn " taskName,"","Hide")
    }
} */
; Win + f8热键打开localsend
#F9::
{
    ahk_exe := "localsend_app.exe"
    APP_PATH := A_Programs "\LocalSend.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}


;{Blind}前缀可以将一些按键与之前已经按下或输入的其他修饰键进行组合使用，就是盲目的保留之前的按键组合
;*^1::Send "{Blind}{Home}"
;*^2::Send "{Blind}{End}"


; Win + F12热键打开底部任务状态栏
/* #F12::
{
        ; 激活任务栏窗口 (Shell_TrayWnd 是任务栏的窗口类名)
        if WinExist("ahk_class Shell_TrayWnd") {
        ; 检查窗口是否已激活
        if WinActive("ahk_class Shell_TrayWnd") {
            ; 发送click点击事件实现任务状态栏隐藏
            Send "{Click}"
            ;WinMinimize
        } else {
            WinActivate
        }
    }
}
*/
; Win + ctrl + r热键打开powershell
; #^r::
#r::
{
	ahk_exe := "WindowsTerminal.exe"
	APP_PATH := A_ProgramsCommon "\PowerShell\PowerShell 7 (x64).lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; Win + 8热键打开powerdesigner
#9::
{
	ahk_exe := "PdShell16.exe"
	APP_PATH := A_ProgramsCommon "\SAP\PowerDesigner 16\PowerDesigner.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; Win + ctrl + q热键打开navicat
#8::
{
	ahk_exe := "navicat.exe"
	APP_PATH := A_ProgramsCommon "\PremiumSoft\Navicat Premium 17.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; Win + y热键打开手机连接
#y::
{
	ahk_exe := "PhoneExperienceHost.exe"
    APP_PROTOCOL := "ms-phone:"
    ToggleWindow(ahk_exe, APP_PROTOCOL)
}

; win+ctrl+T打开Telegram
#^t::
{
	ahk_exe := "Telegram.exe"
	APP_PATH := D_Programs " (x86)\Telegram Desktop\Telegram.exe"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+f打开edge
#f::
{
	ahk_exe := "msedge.exe"
	APP_PATH := A_ProgramsCommon "\Microsoft Edge.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}

class ScriptLifecycle
{
    static ENV_KEY := "AHK_SCRIPT_RELOAD"

    static reloadHooks := []
    static startHooks := []
    static exitHooks := []

    static Init()
    {
        reload := EnvGet(this.ENV_KEY)

        if (reload = "1")
        {
            EnvSet(this.ENV_KEY, "")
            this.RunHooks(this.reloadHooks)
        }
        else
        {
            this.RunHooks(this.startHooks)
        }

        OnExit(ObjBindMethod(this, "HandleExit"))
    }

    static Reload()
    {
        EnvSet(this.ENV_KEY, "1")
        Reload()
    }

    static RegisterReload(fn)
    {
        this.reloadHooks.Push(fn)
    }

    static RegisterStart(fn)
    {
        this.startHooks.Push(fn)
    }

    static RegisterExit(fn)
    {
        this.exitHooks.Push(fn)
    }

    static RunHooks(list)
    {
        for fn in list
            fn.Call()
    }

    static HandleExit(reason, code)
    {
        for fn in this.exitHooks
            fn.Call(reason, code)
    }
}
; hwndCache 已迁移至 ChromeAppMgr.ahk
; 不再在 Reload 时重建浏览器缓存：BuildBrowserCache 依赖 UIA_Browser，其 JSExecute
; 保底会把 "javascript:..." 写入地址栏并发送 Ctrl+L+Enter；在 Ctrl+Alt+R 重载
; （修饰键仍按住、Chrome 在前台）时，这串地址栏内容会被注入/覆盖到当前页面。
; 且 ActivateApp 现以进程级 FindExistingAppWindow 为首选路径，无需该缓存。
; ScriptLifecycle.RegisterReload(BuildBrowserCache)

ScriptLifecycle.Init()

^!r::
{
    ; BuildBrowserCache 已通过 ScriptLifecycle.RegisterReload 注册，Reload 时自动调用
    ScriptLifecycle.Reload()
    ToolTip("脚本重载中...")
    SetTimer(() => ToolTip(), 1000)
}

GroupAdd "ShellGroup", "ahk_exe mintty.exe"
GroupAdd "ShellGroup", "ahk_exe Xshell.exe"
GroupAdd "ShellGroup", "ahk_exe Alibaba Cloud Client.exe"
;GroupAdd "ShellGroup", "ahk_exe WindowsTerminal.exe"
; ~修饰符的作用：1.​不阻止默认按键功能2.适用于需要保留原按键功能的情况
; 适用场景为在按键原有功能的基础上，额外执行某些操作​
; 复制热键
CapsLock::
~SC163:: ;Fn
{
    if WinActive("ahk_group ShellGroup") {
        SendEvent "{Ctrl Down}{Insert}{Ctrl Up}"
    } else {
        SendEvent "{Ctrl Down}{c}{Ctrl Up}"
    }
}

; ^!+3: IBeam直接复制，非IBeam检测选中文本→有则复制，无则Alt+Left后退
#HotIf WinActive("ahk_exe chrome.exe")
^!+3:: {
    if A_Cursor = "IBeam" {
        Send "{Ctrl Down}{c}{Ctrl Up}"
    } else {
        savedClip := ClipboardAll()
        A_Clipboard := ""
        Send "{Ctrl Down}{c}{Ctrl Up}"
        if ClipWait(0.3) {
            ; 有选中文本，Ctrl+C已复制成功
        } else {
            A_Clipboard := savedClip
            Send "!{Left}"
        }
    }
}
^!+4:: {
    if A_Cursor = "IBeam" {
        Send "{Ctrl Down}{v}{Ctrl Up}"
    } else {
        savedClip := ClipboardAll()
        A_Clipboard := ""
        Send "{Ctrl Down}{c}{Ctrl Up}"
        if ClipWait(0.3) {
            A_Clipboard := savedClip
            Send "{Ctrl Down}{v}{Ctrl Up}"
        } else {
            A_Clipboard := savedClip
            Send "!{Right}"
        }
    }
}

!s:: SwitchDevToolsPanel("Source")

!n:: SwitchDevToolsPanel("Network")

; 通过 DevTools 命令菜单 (Ctrl+Shift+P) 切换面板
; 官方文档要点（autohotkey.com/docs/v2/lib/Send.htm）：
;   1. 热键触发时用户仍按住修饰键，Send 仅临时释放，后续按键可能带上 Alt 造成乱输入，
;      须先 KeyWait 等修饰键物理松开；
;   2. SendInput 比 SendEvent 更快、更可靠，且发送期间缓冲用户的物理按键，防止击键交错；
;   3. {Text} 模式按字符流发送，不依赖键盘布局与修饰键状态，比按键码翻译更稳。
SwitchDevToolsPanel(keyword) {
    KeyWait("Alt") ; 等用户松开 Alt（!n/!s 触发键），避免残留修饰键污染后续按键
    SendInput("^+p")
    Sleep(200) ; 等待命令菜单弹出（无窗口级可检测状态，给足余量）
    SendInput("{Text}" keyword)
    Sleep(50)
    SendInput("{Enter}")
}
#HotIf
; ^!+3: 文本光标执行复制，箭头光标发送 Alt+Left（后退）
#HotIf WinActive("ahk_class CabinetWClass")
^!+3:: {
    if A_Cursor = "IBeam" {
        ; 文本光标，执行复制
        Send "{Ctrl Down}{c}{Ctrl Up}"
    } else {
        ; 箭头光标，发送 Alt+Left 后退
        Send "!{Left}"
    }
}
^!+4:: {
    if A_Cursor = "IBeam" {
        ; 文本光标，执行粘贴
        Send "{Ctrl Down}{v}{Ctrl Up}"
    } else {
        ; 箭头光标，发送 Alt+Right 前进
        Send "!{Right}"
    }
}
#HotIf

/* global doubleClickInterval := 300 ; 双击判断的时间间隔（毫秒）
global lastPressTime := 0 ; 记录上次 CapsLock 按下的时间

CapsLock::
{
    global doubleClickInterval
    global lastPressTime
    currentTime := A_TickCount ; 获取当前时间戳
    if (currentTime - lastPressTime <= doubleClickInterval) {
        ; 双击执行粘贴操作
        if WinActive("ahk_group ShellGroup") {
            SendEvent "{Shift Down}{Insert}{Shift Up}"
        } else {
            ToolTip 111
            SendEvent "{Ctrl Down}{v}{Ctrl Up}"
        }
    } else {
        ; 单击执行复制操作
        if WinActive("ahk_group ShellGroup") {
            SendEvent "{Ctrl Down}{Insert}{Ctrl Up}"
        } else {
            SendEvent "{Ctrl Down}{c}{Ctrl Up}"
        }
    }
    lastPressTime := currentTime ; 更新最后按下的时间
} */

; LCtrl & CapsLock:: ; Lctrl+CapsLock
; {

; }


; 粘贴热键
LCtrl & CapsLock:: ; Lctrl+CapsLock
~LCtrl & SC163:: ;Lctrl+Fn
~LButton & CapsLock:: ;鼠标左键+fn键
{
    if WinActive("ahk_group ShellGroup") {
        SendEvent "{Shift Down}{Insert}{Shift Up}"
    } else {
        SendEvent "{Ctrl Down}{v}{Ctrl Up}"
    }
}
; ==============================
; MButton 智能处理
; 判断是否是终端环境
; ==============================
/* isTerminal() {
    return WinActive("ahk_exe mintty.exe")  ; Git Bash
        || WinActive("ahk_exe Xshell.exe")
        || WinActive("ahk_exe WindowsTerminal.exe")
        || WinActive("ahk_exe wezterm.exe")
        || WinActive("ahk_exe idea64.exe")  ; 终端工具窗口（如 IntelliJ 的 Terminal）
}
global g_MButtonLastTick := 0

#HotIf !isTerminal()
*~MButton:: ; 仅在可输入光标下触发粘贴，其它场景保留原生中键
{
    cursorType := A_Cursor
    ; ToolTip 111 . " - " . cursorType
    ; SetTimer(ToolTip, -1000)  ; 1秒后自动关闭提示
    if (cursorType = "Unknown") {
        return
    } else {
        global g_MButtonLastTick

        if (A_TickCount - g_MButtonLastTick < 300) {
            return
        }
        g_MButtonLastTick := A_TickCount

        if WinActive("ahk_group ShellGroup") {
            SendInput "+{Insert}"
        } else {
            SendInput "^v"
        }
    }
}
#HotIf */



/**
 * 1. Background: 全局区域仅存放静态配置
 */
global CONTROL_PATH := "D:\software\controlmymonitor\ControlMyMonitor.exe"
global INPUT_SELECT_VCP := 60
; 按主机名配置不同机器的输入源编号
; key 使用大写主机名（A_ComputerName）
global HOST_MONITOR_MAP := Map(
    "X1", 27,
    "17", 17
)

/**
 * 2. Core Framework: 业务逻辑封装在函数内
 * 采用“单点进入”原则，避免函数依赖隐式全局变量
 * input_source: 输入源编号，17 代表 DP，27 代表 HDMI，具体值根据实际情况调整
 */
SwitchMonitor(input_source) {
    ; Implementation Details: 局部变量只在执行时存在
    local cmd := ""

    ; 即使使用了全局常量，函数内部逻辑也是封闭的
    if !FileExist(CONTROL_PATH) {
        throw Error("Path not found: " . CONTROL_PATH)
    }

    cmd := Format('"{1}" /SetValue Primary {2} {3}', CONTROL_PATH, INPUT_SELECT_VCP, input_source)

    ; Optimization: 记录日志或执行
    return RunWait(cmd, , "Hide")
}

GetMonitorTargetByHost(hostname, defaultValue) {
    global HOST_MONITOR_MAP

    host := StrUpper(hostname)
    if HOST_MONITOR_MAP.Has(host) {
        return HOST_MONITOR_MAP[host]
    }

    return defaultValue
}

/**
 * 3. 根据主机名获取输入源编号并切换主机显示器
 */
#[:: {
    try {
        input_source := GetMonitorTargetByHost(A_ComputerName, 17)
        SwitchMonitor(input_source)
    } catch Error as e {
        ; Logging recommendation: 关键路径错误捕获
        MsgBox(e.Message)
    }
}

$!CapsLock::
{
    KeyWait "CapsLock"
    SetCapsLockState GetKeyState("CapsLock", "T") ? "Off" : "On"
}

#SC163:: ; 点击 win+fn键打开有道
$#CapsLock:: ; 点击 win+CapsLock键打开有道
{
	openYoudao()
}

; 打开有道
openYoudao(){
    ; 发送 Tab 键切换焦点
    ahk_exe := "YoudaoDict.exe"
    ; 如果已启动
    if WinExist("ahk_exe " ahk_exe){
        WinActivate("ahk_exe " ahk_exe)
        if WinWaitActive("ahk_exe " ahk_exe,,0.5){
            pasteEnter()
        }

    } else {
        ; 未启动时发送指令键启动程序
        ; Send("^{LWin down}3^{LWin up}")
        APP_PATH := A_Programs "\有道\网易有道翻译\网易有道翻译.lnk"
        RunAppPathWithPrefixFallback(APP_PATH)
        ; 等待程序启动
        WinWait("ahk_exe " ahk_exe)

        if WinExist("ahk_exe " ahk_exe){
            WinActivate("ahk_exe " ahk_exe)
            if WinWaitActive("ahk_exe " ahk_exe,,0.5){
                pasteEnter()
            }

        }
    }

}
; 点击 Shift+win+v键 打开或关闭clash系统代理
/* isProxy := 0  ; 初始值为 0
#+v::
{
    global isProxy  ; 引用全局变量 isProxy

    ; 发送 Tab 键切换焦点
    ahk_exe := "Clash for Windows.exe"
    ;~ 如果已启动
    if WinExist("ahk_exe " ahk_exe){
        WinActivate("ahk_exe " ahk_exe)

        if WinWaitActive("ahk_exe " ahk_exe,,0.5){
            toggleProxy()
        }

    } else {

        APP_PATH := A_Programs "\有道\网易有道翻译\网易有道翻译.lnk"
        RunAppPathWithPrefixFallback(APP_PATH)  ; Open a new Notepad window

        if WinWaitActive("ahk_exe " ahk_exe,,0.5){
            toggleProxy()
        }
    }
    ;~ 切换代理
    toggleProxy()
    {
        Send("^!p")  ; 例如 Ctrl + Alt + p 快捷键
        WinMinimize
        ; 根据 isProxy 变量的值显示不同的内容
        if (isProxy = 0)
        {
            ToolTip("已开启系统代理")
            ; 设置一个定时器，1秒后关闭弹窗
            isProxy := 1  ; 更新 isProxy 值为 1
        }
        else
        {
            ToolTip("已关闭系统代理")
            isProxy := 0  ; 更新 isProxy 值为 0
        }
        ; 设置定时器，1秒后移除工具提示
        SetTimer(RemoveToolTip, 1000)
        Return

    }
    RemoveToolTip()
    {
        SetTimer(RemoveToolTip, 0)  ; 停止定时器
        ToolTip("")  ; 关闭工具提示
    }

} */

; 发送 Ctrl+Alt+C 快捷键，开关灰色滤镜
#a::
{
    SendInput "{LWin Down}{Ctrl Down}c{Ctrl Up}{LWin Up}"
    SendInput "{Ctrl Up}{LWin Up}{RWin Up}"
}
; 禁用 Ctrl+Shift+C 快捷键
$#^c::return
; Alibaba Cloud Client
#^a::
{
	ahk_exe := "Alibaba Cloud Client.exe"
    APP_PATH := A_ProgramsCommon "\Alibaba Cloud Client.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; 打开微软应用商店
^#s::
{
	ahk_exe := "ApplicationFrameHost.exe"
    APP_PROTOCOL := "ms-windows-store://library"
    ToggleWindow(ahk_exe, APP_PROTOCOL)

}

showAppListView(ahk_class) {
    ; 获取所有符合条件的窗口句柄（按类名“CabinetWClass”）
    windows := WinGetList("ahk_class " ahk_class)
    ; 如果只有一个窗口，则return不显示窗口列表弹窗
    if (windows.Length == 1) {
        ; 检查窗口是否已激活
        if WinActive("ahk_class " ahk_class) {
            WinMinimize
        } else {
            WinActivate
        }
        return
    }
    appMap := Map()
    appMap["CabinetWClass"] := "文件资源管理器"
    appMap["XLMAIN"] := "Excel"
    ; 查找如果有AutoHotkeyGUI则先WinClose，然后重新生成AppListView
    if WinExist("ahk_class AutoHotkeyGUI"){

        windows_gui := WinGetList("ahk_class AutoHotkeyGUI")
        for winID in windows_gui {
            ;
            if(WinGetTitle(winID) == appMap[ahk_class] and WinExist("ahk_id " winID)){
                 WinClose
                break
            }
        }

    }

    MyGui := Gui()
    MyGui.Opt("+Resize -MaximizeBox +AlwaysOnTop")

    winList := []
    ; 显示窗口列表（调试用）
    LV := MyGui.AddListView("r8 w200 vColorChoice", ["#","文件名"])

    for winID in windows {
        ;MsgBox WinGetTitle(winID)
        word_array := StrSplit(WinGetTitle(winID), " - ")
        if(A_Index == 1){
            MyGui.Title := word_array[2]
        }
        LV.Add(, A_Index, word_array[1])

        winList.Push(A_Index)
    }
    LV.OnEvent("Click", LV_Click)
    LV_Click(LV, RowNumber)
    {
        if (!RowNumber) {
            return
        }
        HotkeyActivateWindow(RowNumber)
    }
    MyGui.OnEvent("Close", MyGui_Close)
    MyGui.OnEvent("Escape", MyGui_Close)


    MyGui.Show()

    Loop winList.Length {
        if (A_Index > 9)
            break
        Hotkey("~" . A_Index, HotkeyActivateWindow)
    }

    HotkeyActivateWindow(ThisHotkey) {
        index := RegExReplace(ThisHotkey, "^\D+")

        if windows.Has(index) && WinExist("ahk_id " windows[index]) {
            WinActivate("ahk_id " windows[index])
        } else {
            LV.Delete(index)
        }

        MyGui_Close(MyGui)
    }

    MyGui_Close(thisGui) {
        thisGui.Destroy()
        Loop winList.Length {
            if (A_Index > 9)
                break
            Hotkey("~" . A_Index, "Off")
        }
    }
}


#n::
{
	ahk_exe := "notepad++.exe"
	APP_PATH := A_ProgramsCommon "\Notepad++.lnk"

    ToggleWindow(ahk_exe, APP_PATH)

}
/*
A_ProgramsCommon: 公共开始菜单程序目录
默认是 C:\ProgramData\Microsoft\Windows\Start Menu\Programs
A_Programs: 当前用户开始菜单程序目录
例如 C:\Users\yinsh\AppData\Roaming\Microsoft\Windows\Start Menu\Programs
*/
; win+F1打开snipaste
#F1::
{
	ahk_exe := "snipaste.exe"
	APP_PATH := A_Programs "\Snipaste.lnk"
    ToggleWindow(ahk_exe, APP_PATH)

}
; win+ctrl+x打开微信开发者工具
#^x::
{
	ahk_exe := "wechatdevtools.exe"
	APP_PATH := A_Programs "\微信开发者工具\微信开发者工具.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+shift+x打开Xmind
#+x::
{
	ahk_exe := "Xmind.exe"
	APP_PATH := A_Programs "\Xmind.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+ctrl+w打开word
#^w::
{
	ahk_exe := "WINWORD.EXE"
	APP_PATH := A_ProgramsCommon "\Word.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+ctrl+p打开ppt
#^p::
{
	ahk_exe := "POWERPNT.EXE"
	APP_PATH := A_ProgramsCommon "\PowerPoint.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}

; ctrl+space打开vscode
#c::
{
	ahk_exe := "Code.exe"
	APP_PATH := A_Programs "\Visual Studio Code\Visual Studio Code.lnk"

    openVSCode(ahk_exe, APP_PATH)

}


; 应用启动框架已拆分到独立模块
#Include %A_ScriptDir%\lib\AppLauncher.ahk

; ResolveAppPath / LaunchViaLimitedScheduledTask / ShellExecuteAsStandardUser /
; ResolveShortcutTarget / QuoteArg 已迁移至 AppLauncher.ahk

; 快捷键 Win+T 切换置顶状态
#t::
{
    hwnd := WinActive("A")
    if hwnd
        WinSetAlwaysOnTop(-1, "ahk_id " hwnd) ; -1 = 切换
}

+space::
{
    SendEvent "{LWin Down}1{LWin Up}"
}
; 有些程序例如腾讯元宝需要使用ahk_class才能激活窗口
#space::
{
    ahk_class := "Tauri Window"
	ahk_exe := "yuanbao.exe"
	winTitle := "元宝"
	APP_PATH := A_ProgramsCommon "\元宝\元宝.lnk"

    if WinExist("ahk_exe " ahk_exe) {
        ; 获取主窗口的进程 ID (PID)
        ahk_id := GetMainWindowByExe(ahk_exe,winTitle)
        if (ahk_id) {
            ; 这是 Clash Verge 程序
            if WinActive("ahk_id " ahk_id) {
                WinMinimize("ahk_id " ahk_id)
            } else {
                WinActivate("ahk_id " ahk_id)
            }
        }
    } else {
        RunAppPathWithPrefixFallback(APP_PATH)
    }
}

#s::
{
	ahk_exe := "Everything.exe"
	APP_PATH := A_ProgramsCommon "\Everything.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
}
!space::
{
    qoderExeNames := ["Qoder IDE.exe", "Qoder.exe"]
    APP_PATH := A_ProgramsCommon "\Qoder\Qoder IDE.lnk"
    ; Qoder GUI 进程名随版本变化：1.29+ 为 "Qoder IDE.exe"，旧版为 "Qoder.exe"
    ; （当前 "Qoder.exe" 实为无窗口的后端 shared-client 辅助进程）。
    ; 依次按候选名查找真正拥有窗口的编辑器实例，保证跨版本稳定。
    hwnd := 0
    for exeName in qoderExeNames {
        hwnd := WinExist("ahk_exe " exeName)
        if hwnd
            break
    }
    if hwnd {
        if WinActive("ahk_id " hwnd) {
            WinMinimize("ahk_id " hwnd)
        } else {
            WinShow("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
        }
        return
    }

    LaunchQoderAsStandardUser(APP_PATH)
    for exeName in qoderExeNames {
        if WinWait("ahk_exe " exeName, , 6) {
            WinActivate("ahk_exe " exeName)
            return
        }
    }
}
^space::
{
    qoderExeNames := ["Qoder CN IDE.exe"]
    APP_PATH := A_ProgramsCommon "\Qoder\Qoder CN IDE.lnk"
    ; Qoder GUI 进程名随版本变化：1.29+ 为 "Qoder IDE.exe"，旧版为 "Qoder.exe"
    ; （当前 "Qoder.exe" 实为无窗口的后端 shared-client 辅助进程）。
    ; 依次按候选名查找真正拥有窗口的编辑器实例，保证跨版本稳定。
    hwnd := 0
    for exeName in qoderExeNames {
        hwnd := WinExist("ahk_exe " exeName)
        if hwnd
            break
    }
    if hwnd {
        if WinActive("ahk_id " hwnd) {
            WinMinimize("ahk_id " hwnd)
        } else {
            WinShow("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
        }
        return
    }

    LaunchQoderAsStandardUser(APP_PATH)
    for exeName in qoderExeNames {
        if WinWait("ahk_exe " exeName, , 6) {
            WinActivate("ahk_exe " exeName)
            return
        }
    }
}

 ; 微信
 #w::
 {
     global g_weixinHwnd
    ahk_exe := "Weixin.exe"
    WinTitle := "微信"
    APP_PATH := A_ProgramsCommon "\微信\微信.lnk"

    ; BlockWinPFor(400)

    /* BlockWinPFor(400)
    ; 确保 Win 键没有处于按下状态（防止系统接收到残留的 Win+P 等快捷）
    Send("{LWin up}{RWin up}")
    Sleep 30
    KeyWait "LWin"
    KeyWait "RWin" */

    if (g_weixinHwnd && WinExist("ahk_id " g_weixinHwnd)) {
        if WinActive("ahk_id " g_weixinHwnd) {
            WinMinimize("ahk_id " g_weixinHwnd)
        } else {
            WinActivate("ahk_id " g_weixinHwnd)
        }
        return
    }
    ; 若未找到精确/更合适的窗口，则遍历同进程所有窗口，按标题包含匹配并排除 Photos and Videos
    ids := WinGetList("ahk_exe " ahk_exe)
    if (ids && ids.Length > 0) {
        for hwnd in ids {
            this_title := WinGetTitle("ahk_id " hwnd)
            if (this_title != "" && !InStr(this_title, "Photos and Videos") && InStr(this_title, WinTitle)) {
                if WinActive("ahk_id " hwnd) {
                    WinMinimize("ahk_id " hwnd)
                } else {
                    WinActivate("ahk_id " hwnd)
                }
                g_weixinHwnd := hwnd
                return
            }
        }

        ; 激活第一个可见候选窗口（排除可能无标题或系统类窗口）
        for hwnd in ids {
            t := WinGetTitle("ahk_id " hwnd)
            if (t != "" && !InStr(t, "Photos and Videos")) {
                if WinActive("ahk_id " hwnd) {
                    WinMinimize("ahk_id " hwnd)
                } else {
                    WinActivate("ahk_id " hwnd)
                }
                g_weixinHwnd := hwnd
                return
            }
        }
    }
    ; 未运行或未找到窗口 → 启动程序
    RunAppPathWithPrefixFallback(APP_PATH)
}



 ; 微信公众号
#x::
{
    ahk_exe := "WeChatAppEx.exe"
    WinTitle := "微信"
    ; 通过判断应用标题来决定是否激活和隐藏
    if WinExist("ahk_exe " ahk_exe) {
        ; 检查窗口是否已激活
        if WinActive("ahk_exe " ahk_exe) {
            WinMinimize
        } else {
            WinActivate
        }
    }
}
 ; WorkBuddy
#b::
{
    ahk_exe := "WorkBuddy.exe"
	APP_PATH := A_ProgramsCommon "\WorkBuddy.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
}
#q::
{
    ahk_exe := "WXWork.exe"
	APP_PATH := A_ProgramsCommon "\企业微信\企业微信.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
}
^#q::
{
    ahk_exe := "qianwen.exe"
	APP_PATH := A_ProgramsCommon "\千问.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
}
; ONLYOFFICE
#o::
{
    ahk_exe := "editors.exe"
	APP_PATH := A_ProgramsCommon "\ONLYOFFICE\ONLYOFFICE.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
}
; outlook
#^o::
{
    ahk_exe := "olk.exe"
    APP_PROTOCOL := "ms-outlook:"
    ToggleWindow(ahk_exe, APP_PROTOCOL)
}
; 打开钉钉
^#d::
{
    ahk_exe := "DingTalk.exe"
	APP_PATH := A_ProgramsCommon "\Programs\钉钉\钉钉.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
}

$^!+9::
{
    ConfirmAndSuspend()
}

ConfirmAndSuspend() {
    state := {countdown: 3}
    state.gui := Gui("+AlwaysOnTop +ToolWindow -MinimizeBox -MaximizeBox", state.countdown "秒后将进入睡眠模式")
    state.gui.MarginX := 16
    state.gui.MarginY := 14
    state.gui.AddText("w280 Center", state.countdown "秒后将进入睡眠模式")
    state.statusText := state.gui.AddText("w280 Center", state.countdown " 秒后自动执行确定")
    okBtn := state.gui.AddButton("x92 w90", "确定")
    cancelBtn := state.gui.AddButton("x+12 w90 Default", "取消")

    executeSuspend(*) {
        SetTimer(updateCountdown, 0)
        try state.gui.Destroy()
        DoSuspend()
    }

    cancelConfirm(*) {
        SetTimer(updateCountdown, 0)
        try state.gui.Destroy()
    }

    updateCountdown(*) {
        state.countdown -= 1
        if (state.countdown <= 0) {
            executeSuspend()
            return
        }
        state.statusText.Text := state.countdown " 秒后自动执行确定"
    }

    okBtn.OnEvent("Click", executeSuspend)
    cancelBtn.OnEvent("Click", cancelConfirm)
    state.gui.OnEvent("Close", cancelConfirm)
    state.gui.OnEvent("Escape", cancelConfirm)
    state.gui.Show("AutoSize Center")

    SetTimer(updateCountdown, 1000)
}

DoSuspend() {
    try {
        shell := ComObject("Shell.Application")
        shell.Suspend()
        Sleep 500
    } catch Error {
    }

    try {
        result := DllCall("PowrProf\SetSuspendState"
            , "Int", 0
            , "Int", 0
            , "Int", 0)

        if (!result) {
            throw Error("SetSuspendState returned 0")
        }
    } catch Error {
        MsgBox "所有方式失败"
    }
}

#F11::
{
    try {
        shell := ComObject("Shell.Application")
        shell.Suspend()
		Sleep 500
    } catch {
        ; fallback
        DllCall("PowrProf\SetSuspendState", "Int", 0, "Int", 0, "Int", 0)
    }
}

#!g::
{
	ahk_exe := "mintty.exe" ; git-bash
	APP_PATH := A_ProgramsCommon "\Git\Git Bash.lnk" ; git-bash

    ToggleWindow(ahk_exe, APP_PATH)
}

; Chrome App 管理模块已拆分到独立文件
#Include %A_ScriptDir%\lib\ChromeAppMgr.ahk

; 以下函数已迁移至 ChromeAppMgr.ahk：
; GuiAppManager / GenerateSelected / DeleteSelected / DeleteWithTrayTip / GenerateApp
; BuildChromeArgs / CreateChromeApp / CreateWithTrayTip / LoadConfig
; BuildChromeArgs / CreateChromeApp / CreateWithTrayTip / LoadConfig 已迁移
; （原函数块已删除）

; #0 / BuildBrowserCache / DumpMap / ActivateApp 已迁移至 ChromeAppMgr.ahk
; 删除第一段

; DumpMap / ActivateApp 已迁移至 ChromeAppMgr.ahk

; Win + `热键打开Obsidian
#`::
{
	ahk_exe := "Obsidian.exe"
    APP_PATH := A_ProgramsCommon "\Obsidian.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
}

#f12::
{
    ; 1. 轮询 WeChatAppEx.exe 的所有带标题窗口，找到真正包含文章选项卡的窗口，
    ;    并激活其 UIA 树。新版微信按需生成 UI 树，需逐窗口激活后才能暴露选项卡。
    try {
        tabs := FindWechatArticleWindowUIA()
    } catch {
        MsgBox "未找到文章选项卡。请先在微信中打开至少一篇公众号文章，再按 Win+F12。"
        return
    }

    ; 2. 轮询每个标签页：右键“复制链接”取 URL。
    ;    微信 4.1+ 选项卡 Name 为空（标题未暴露给 UIA），标题从文章页 <title> 抓取
    content := ""
    for idx, item in tabs {
        ; 调用自定义函数获取 URL（右键菜单 → 复制链接）
        url := GetUrlByRightClick(item)
        if (url == "" || InStr(url, "http") != 1)
            continue

        ; 标题：优先抓文章页 <title>，失败回退选项卡 Name（旧版微信选项卡有名字）
        title := FetchPageTitle(url)
        if (title == "")
            title := item.Name
        if (title == "")
            title := "文章" idx

        ; 拼接 Markdown 格式，并在末尾添加两个换行以确保在 Obsidian 中清晰分隔
        ; 在循环内部修改为：
        ; title 和 url 后面加两个空格再加换行，这是 Markdown 强制换行的标准
        content .= "`n[" . title . "](" . url . ")`n"
    }

    if (content == "") {
        MsgBox "选项卡找到了 " tabs.Length " 个，但均无有效标题/链接。"
        return
    }

    ; 添加笔记到obsidian
    parentDir := "微信公众号文章" ; 目录名
    noteName := FormatTime(, "yyyy-MM-dd") ; 文件名
    AddNoteToObsidian(parentDir,noteName,content)

}

; ==============================================================================
; 微信文章选项卡 UIA 定位（适配微信 3.9 / 4.1+，Win 11）
; 实测验证的 4.1+ 结构（WeChatAppEx.exe 公众号窗口）：
;   Window(Chrome_WidgetWin_0) → BrowserView → TopContainerView → TabStripRegionView
;     → TabStrip → FlueTabContainer → N × Pane(ClassName="Tab")
; 要点：
;   1. 选项卡 Name 为空（标题未暴露给 UIA），标题需从文章页 <title> 抓取；
;   2. WeChatAppEx.exe 有几十个窗口（含大量隐藏渲染窗口），需逐个轮询带标题窗口；
;   3. 微信 4.x 按需生成 UIA 树：激活（WM_GETOBJECT / UIA 附着）后才暴露完整控件；
;   4. 微信非管理员运行时，同样普通权限的脚本即可读取，无需提权。
; ==============================================================================
FindWechatArticleWindowUIA() {
    ; 微信公众号文章窗口只属于 WeChatAppEx.exe（Chromium），不轮询 Weixin.exe 主程序窗口，
    ; 避免遍历主程序的聊天窗口浪费时间。
    for hwnd in WinGetList("ahk_exe WeChatAppEx.exe") {
        title := ""
        try title := WinGetTitle(hwnd)
        if (title == "") ; 跳过无标题的渲染/工具窗口（含托盘图标窗口）
            continue

        wechatWin := ""
        ; 优先：激活 Chromium 辅助功能后获取窗口元素（旧版微信文章窗口的标准路径）
        try {
            wechatWin := UIA.ElementFromHandle(hwnd)
        }
        ; 备选：微信 4.0+ 窗口可能没有 Chrome_RenderWidgetHostHWND 子控件，
        ;       激活会抛错；直接附着窗口本身，靠 UIA 客户端附着触发按需树构建。
        if (!IsObject(wechatWin)) {
            try wechatWin := UIA.ElementFromHandle(hwnd, , 0)
        }
        if (!IsObject(wechatWin))
            continue

        ; 微信 4.x 的树是激活后按需构建的，需给一点构建时间，短重试最多 3 次（总等待 ≤600ms）
        tabs := []
        loop 3 {
            tabs := FindWechatArticleTabs(wechatWin)
            if (tabs.Length > 0)
                break
            Sleep 200
        }
        if (tabs.Length > 0) {
            try wechatWin.SetFocus() ; 必须激活窗口，否则后续右键可能无效
            return tabs
        }
    }
    throw TargetError("未找到包含文章选项卡的微信窗口", -1)
}

; 抓取文章页面并解析 <title> 作为文章标题（选项卡 Name 异常时的兜底）
FetchPageTitle(url) {
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(3000, 3000, 5000, 8000)
        req.Open("GET", url)
        req.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36")
        req.Send()
        if (req.Status != 200)
            return ""
        if RegExMatch(req.ResponseText, "isU)<title[^>]*>(.*)</title>", &m) {
            title := Trim(m[1])
            title := RegExReplace(title, "s)\s+", " ")
            return DecodeHtmlEntities(title)
        }
    }
    return ""
}

DecodeHtmlEntities(s) {
    s := StrReplace(s, "&lt;", "<")
    s := StrReplace(s, "&gt;", ">")
    s := StrReplace(s, "&quot;", '"')
    s := StrReplace(s, "&apos;", "'")
    s := StrReplace(s, "&nbsp;", " ")
    s := StrReplace(s, "&amp;", "&") ; 必须最后替换，避免二次解码
    return s
}

; 微信更新后文章标签形态随版本而变，按“新版优先、旧版兜底”逐档搜索：
;   4.1+：容器 FlueTabContainer 下的 Pane(ClassName="Tab")，无名字，仅靠位置识别；
;   3.9 等旧版：TabItem / Tab 容器下的 ListItem/Custom。
FindWechatArticleTabs(wechatWin) {
    ; ① 微信 4.1+（Chromium 内嵌）：FlueTabContainer → 子元素 ClassName="Tab"
    try {
        tabs := []
        for container in wechatWin.FindElements({ClassName: "FlueTabContainer"})
            for tab in container.FindElements({ClassName: "Tab"}) {
                ; 标签过多时会溢出滚动区，屏幕外标签无法右键，只保留可见的（l>0 且有宽高）
                try {
                    rect := tab.BoundingRectangle
                    if (rect.r > rect.l && rect.b > rect.t && rect.l > 0)
                        tabs.Push(tab)
                }
            }
        if (tabs.Length > 0)
            return tabs
    }

    ; ② 旧版微信：TabItem，或 Tab 容器内的 TabItem/ListItem/Custom
    tabs := []
    seen := Map()

    AddTabs(wechatWin.FindElements({Type: UIA.Type.TabItem}))

    ; 优先限定在 Tab 容器内，避免把窗口中的其它 Custom/ListItem 当成文章。
    for tabContainer in wechatWin.FindElements({Type: UIA.Type.Tab}) {
        AddTabs(tabContainer.FindElements([{Type: UIA.Type.TabItem}, {Type: UIA.Type.ListItem}, {Type: UIA.Type.Custom}]))
    }

    ; 某些版本连 Tab 容器也会改成 Custom，此时只保留可交互且有名称的候选。
    if (tabs.Length == 0) {
        for element in wechatWin.FindElements([{Type: UIA.Type.ListItem}, {Type: UIA.Type.Custom}]) {
            if (element.Name != "" && (element.IsInvokePatternAvailable || element.IsSelectionItemPatternAvailable))
                AddTabs([element])
        }
    }

    return tabs

    AddTabs(elements) {
        for element in elements {
            if (element.Name = "")
                continue
            try runtimeId := element.RuntimeId
            catch
                continue
            if !seen.Has(runtimeId) {
                seen[runtimeId] := true
                tabs.Push(element)
            }
        }
    }
}

; 添加笔记到obsidian
; @param parentDir：目录名
; @param noteName：文件名
; @param content：文件内容
AddNoteToObsidian(parentDir,noteName,content) {
    ; 基础配置
    DBName := "Lifein" ; Obsidian数据库名

    APP_PATH := A_ProgramsCommon "\Obsidian.lnk"
    if !FileExist(APP_PATH)
        APP_PATH := A_Programs "\Obsidian.lnk"

    ; 解析快捷方式实际路径
    FileGetShortcut(APP_PATH, &targetPath)
    SplitPath(targetPath, , &targetDir)

    dataDir := targetDir "\data"
    ; MsgBox(dataDir)
    if DirExist(dataDir) {
        vaultFolders := []
        Loop Files, dataDir "\*", "D"
            vaultFolders.Push(A_LoopFileName)

        /* vaultListText := ""
        for _, folderName in vaultFolders
            vaultListText .= (vaultListText = "" ? "" : " | ") folderName
        MsgBox("检测到 Obsidian 数据目录下的仓库：" vaultListText) */
        if (vaultFolders.Length == 1) {
            DBName := vaultFolders[1]
        } else if (vaultFolders.Length > 1) {
            myGui := Gui("+AlwaysOnTop -MaximizeBox", "选择 Obsidian 仓库")

            ; 默认选中第一项，防止用户直接点确认导致未选中任何仓库
            myGui.Add("ListBox", "w250 r10 vSelectedVault Choose1", vaultFolders)

            btn := myGui.Add("Button", "w100 Default", "确认")
            selectedVault := ""

            SubmitGui(*) {
                saved := myGui.Submit()
                selectedVault := saved.SelectedVault
                myGui.Destroy()
            }
            btn.OnEvent("Click", SubmitGui)

            myGui.OnEvent("Close", (*) => myGui.Destroy())
            myGui.OnEvent("Escape", (*) => myGui.Destroy())

            myGui.Show()
            WinWaitClose(myGui.Hwnd)

            if (selectedVault != "") {
                DBName := selectedVault
            }
        }

        ; 根据选择的仓库构造路径
        vaultPath := dataDir "\" DBName

        ; 原始路径：微信公众号文章/2026-01-28
        fullPath := parentDir "/" noteName

        ToolTip("正在保存公众号文章到 " vaultPath "\\" StrReplace(fullPath, "/", "\\") " ...")
        SetTimer(() => ToolTip(), -3000)

        ; 构造 URI (append 参数表示追加)
        ; 如果文件不存在会新建，存在则追加
        obsUri := "obsidian://new?vault=" DBName "&file=" EncodeURL(fullPath) "&content=" EncodeURL("`n" content) "&append=true"

        ; 执行
        Run(obsUri)

    }
}

!`::{

    ; 添加笔记到obsidian
    parentDir := "笔记" ; 目录名
    noteName := FormatTime(, "yyyy-MM-dd") ; 文件名
    ; content 为笔记内容
    AddNoteToObsidian(parentDir,noteName,A_Clipboard)

}

; 辅助函数：对 URL 中的特殊字符（如中文/空格）进行编码
EncodeURL(str) {
    static doc := ComObject("HTMLFile")
    doc.write('<meta http-equiv="X-UA-Compatible" content="IE=9">')
    ; 使用 JavaScript 的 encodeURIComponent，它能完美处理中文和换行符 `n
    return doc.parentWindow.encodeURIComponent(str)
}

; ==============================================================================
; 核心函数：模拟右键点击并获取链接
; ==============================================================================
GetUrlByRightClick(uiElement) {
    Critical "On"
    A_Clipboard := ""
    ; 1. 触发右键
    uiElement.Click("right")

    ; 等菜单出现后再开始导航，出现即走，避免固定等待过长
    menuHwnd := 0
    startTick := A_TickCount
    while (A_TickCount - startTick < 300) {
        menuHwnd := WinExist("ahk_class #32768")
        if menuHwnd
            break
        Sleep 10
    }
    if !menuHwnd
        Sleep 80

    SendEvent "{Down 2}{Enter}"

    ; 4. 等待剪贴板
    if ClipWait(1.2) {
        Critical "Off"
        return A_Clipboard
    }
    Critical "Off"
    return "未获取到链接"
}