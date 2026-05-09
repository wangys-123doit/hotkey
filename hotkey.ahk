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

#Include hotkeys_public.ahk
#Include OpenControllerFromNetwork.ahk
#Include rdp.ahk
#Include CycleExplorerSwitcher.ahk
; 可选包含：文件不存在时忽略，不会在加载阶段报错
#Include *i hotkeys_private.ahk
;~ ; #:Win,ctrl:^,shift:+,alt:! left左键：<,right右键：>
;~ #Include RunRadiator.ahk


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
;~ 用户配置文件
configPath := A_ScriptDir "\config.ini"
isTaskCreated := IniRead(configPath, "Setup", "TaskCreated", "0")

if (isTaskCreated == "0") {
    taskName := "AutoRunHotkeyTask"
    ; 构造创建任务的命令：登录时以最高权限运行，且不受电源限制
    createTaskCmd := 'schtasks /create /tn "' taskName '" /tr "\"' A_AhkPath '\" \"' A_ScriptFullPath '\"" /sc onlogon /rl highest /f'

    try {
        RunWait(createTaskCmd, , "Hide")
        IniWrite("1", configPath, "Setup", "TaskCreated")
        ;~ MsgBox("自启任务已成功注册！下次开机脚本将自动以管理员权限运行。", "注册成功", 64)
    } catch as e {
        MsgBox("任务计划注册失败：`n" e.Message, "系统错误", 16)
    }
}


global x86ProgramFilesDir := EnvGet("ProgramFiles(x86)")

; 使用正则表达式替换开头的 C: 为 D:
; ^ 表示匹配字符串开头，i 表示不区分大小写
global D_Programs := RegExReplace(A_ProgramFiles, "(?i)^C:", "D:")

; 获取 C:\Users\用户名\AppData\Local
;~ global LocalPath := EnvGet("LOCALAPPDATA")

SwapProgramsPrefix(path) {
    if InStr(path, A_ProgramsCommon, false) = 1 {
        return A_Programs SubStr(path, StrLen(A_ProgramsCommon) + 1)
    }

    if InStr(path, A_Programs, false) = 1 {
        return A_ProgramsCommon SubStr(path, StrLen(A_Programs) + 1)
    }

    return ""
}

RunAppPathWithPrefixFallback(path) {
    ; 协议路径（如 ms-phone: / obsidian://）不走文件存在判断，直接尝试运行
    if (RegExMatch(path, "i)^[a-z][a-z0-9+.-]*:(//)?") && !RegExMatch(path, "i)^[a-z]:\\")) {
        try {
            Run path
            return true
        } catch Error as e {
            MsgBox("协议启动失败：`n" path "`n`n" e.Message, "启动失败", 16)
            return false
        }
    }

    primary := path
    alternate := SwapProgramsPrefix(primary)

    if FileExist(primary) {
        try {
            Run primary
            return true
        } catch Error as e {
            MsgBox("启动失败：`n" primary "`n`n" e.Message, "启动失败", 16)
            return false
        }
    }

    if (alternate != "" && FileExist(alternate)) {
        try {
            Run alternate
            return true
        } catch Error as e {
            MsgBox("启动失败：`n" alternate "`n`n" e.Message, "启动失败", 16)
            return false
        }
    }

    if (alternate != "") {
        MsgBox("路径不存在：`n1) " primary "`n2) " alternate, "启动失败", 16)
    } else {
        MsgBox("路径不存在：`n" primary, "启动失败", 16)
    }

    return false
}

BlockWinPFor(durationMs := 300) {
    static handler := (*) => 0
    Hotkey("#p", handler, "On")
    SetTimer(() => Hotkey("#p", handler, "Off"), -durationMs)
}

; #p::return
; 微信hwnd缓存值
global g_weixinHwnd := 0

; 开关窗口函数，判断窗口激活状态并执行显示隐藏操作
; ahk_exe:exe程序名
; APP_PATH:程序路径
ToggleWindow(ahk_exe, APP_PATH) {
    if WinExist("ahk_exe " ahk_exe) {
        ; 检查窗口是否已激活
        if WinActive("ahk_exe " ahk_exe) {
            WinMinimize
        } else {
            WinActivate
        }
    } else {
        RunAppPathWithPrefixFallback(APP_PATH)
    }
}
ToggleWindowByTitle(ahk_exe, WinTitle, APP_PATH) {
    if WinExist(WinTitle) {
        ; 检查窗口是否已激活
        if WinActive(WinTitle) {
            WinMinimize
        } else {
            WinActivate
        }
    } else {
        RunAppPathWithPrefixFallback(APP_PATH)
    }

}
; 开关窗口函数，判断窗口激活状态并执行显示隐藏操作
; ahk_exe:exe程序名
; WinTitle :程序窗口标题
; APP_PATH:程序路径
ToggleWindow2(ahk_exe, WinTitle, APP_PATH) {
    if WinExist("ahk_exe " ahk_exe,WinTitle, "Photos and Videos") {
        ; 检查窗口是否已激活
        if WinActive("ahk_exe " ahk_exe,WinTitle, "Photos and Videos") {
            WinMinimize
        } else {
            WinActivate
        }
    } else {
        RunAppPathWithPrefixFallback(APP_PATH)
    }
}
; 开关窗口函数，判断窗口激活状态并执行显示隐藏操作
; ahk_exe:exe程序名
; WinTitle :程序窗口标题
; APP_PATH:程序路径
ToggleWindow12(ahk_exe, WinTitle, APP_PATH) {
    ;WinGetTitle(WinGetID(ahk_exe))
    ;MsgBox WinGetID("ahk_exe " ahk_exe)

    ;SetTitleMatchMode 2
        ; ahk_id:应用窗口id
    ;ahk_id := WinGetCount(WinTitle)
              ;      MsgBox ahk_id . WinGetTitle(WinTitle)
;CountAll := WinGetCount("ahk_exe " ahk_exe)
;CountExcluded := WinGetCount(,, "Weixin|Chrome")
;MsgBox CountExcluded " out of " CountAll " windows were counted"

ids := WinGetList("ahk_exe " ahk_exe,WinTitle, "Photos and Videos")
for this_id in ids
{
    WinActivate this_id
    this_class := WinGetClass(this_id)
    this_title := WinGetTitle(this_id)
    Result := MsgBox(
    (
        "Visiting All Windows
        " A_Index " of " ids.Length "
        ahk_id " this_id "
        ahk_class " this_class "
        " this_title "

        Continue?"
    ),, 4)
    if (Result = "No")
        break
}

}
ToggleWindow22(ahk_exe, WinTitle, APP_PATH) {
    ids := WinGetList("ahk_exe " ahk_exe,WinTitle, "Program Manager")
    for this_id in ids
    {
        WinActivate this_id
        this_class := WinGetClass(this_id)
        this_title := WinGetTitle(this_id)
        Result := MsgBox(
        (
            "Visiting All Windows
            " A_Index " of " ids.Length "
            ahk_id " this_id "
            ahk_class " this_class "
            " this_title "

            Continue?"
        ),, 4)
        if (Result = "No")
            break
    }
}
; 获取进程名称的函数
GetProcessName(pid) {
    ; 创建一个足够大的缓冲区来存储进程路径
    buffer := DllCall("GlobalAlloc", "uint", 0x40, "uint", 255, "ptr")  ; 0x40 为堆分配标志，255 为最大大小

    ; 使用 DllCall 来获取进程名称
    DllCall("psapi.dll\GetModuleFileNameExW", "ptr", pid, "ptr", buffer, "uint", 255)

    ; 将缓冲区转换为字符串
    processName := StrGet(buffer)

    ; 释放缓冲区
    DllCall("GlobalFree", "ptr", buffer)

    return processName
}
;~ 过滤「可见 + 有标题」窗口
GetMainWindowByExe(ahk_exe,winTitle) {
    hwnds := WinGetList("ahk_exe " ahk_exe)
    for hwnd in hwnds {
        title := WinGetTitle("ahk_id " hwnd)
        style := WinGetStyle("ahk_id " hwnd)
        ;~ MsgBox title
        ; 必须：可见 + 有标题
        if (title == winTitle && (style & 0x10000000)) ; WS_VISIBLE
            return hwnd
    }
    return 0
}


; 有道词典复制粘贴并查询翻译
pasteEnter(){
    ;~ 先设置长文本编辑器获取焦点
    ; 加入重试机制 (try...catch + Loop)，防止Chrome_WidgetWin_01还没来得及完全初始化，导致ControlFocus失败
    success := false
    Loop 30 {
        try {
            targetHwnd := ControlGetHwnd("Chrome_WidgetWin_01", "ahk_class YodaoMainWndClass")
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

; ===============================================================
;  InputHook + 智能中英文输入法自动切换引擎 (AHK v2)
; ===============================================================
; 功能：
;   1. 输入自然语言 → 自动切中文
;   2. 输入代码符号 → 自动切英文
;   3. 行首字母 → 自动切英文（函数、变量命名）
;   4. 不影响 Ctrl / Alt / Win / Shift 组合键
;   5. 所有逻辑只在“普通文本输入”时触发
; ===============================================================


global g_IME := "zh"  ; 输入法默认中文状态

SwitchToChinese() {
    global g_IME
    if g_IME != "zh" {
        Send "{Shift}"
        ; 确保输入法已进入拼音组合态
        EnsurePinyinReady()
        g_IME := "zh"
    }
}

SwitchToEnglish() {
    global g_IME
    if g_IME != "en" {
        Send "{Shift}"
        g_IME := "en"
    }
}



; 末尾是字母/数字/下划线 → 代码环境
IsCodeContext() {
    text := GetLeftText("")
    return RegExMatch(text, "[A-Za-z0-9_]$")
}

; 末尾不是字母/数字 → 自然语言环境
IsNaturalContext() {
    return !IsCodeContext()
}

; 行首时输入字母 → 多数情况是写代码
IsLineStart() {
    backup := A_Clipboard
    A_Clipboard := ""

    Send "+{Left}"
    Send WinActive("ahk_group ShellGroup") ? "^{insert}" : "^c"
    ClipWait 0.2
    char := A_Clipboard

    A_Clipboard := backup
    Send "{Right}"

    return (char = "" || char = "`n")
}

; ============================
;    InputHook 输入拦截引擎
; ============================
;global ih := InputHook("V")   ; 'V' = OnChar 事件
;ih.OnChar := (ihObj, char) => HandleChar(char)
;ih.Start()

; ============================
;       核心策略逻辑
; ============================
HandleChar(char) {

    ; 1. 如果是 Ctrl / Alt / Win 组合，不处理
    if GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") || GetKeyState("LWin", "P")
        return

    ; 2. 输入字母：判断环境
    if RegExMatch(char, "[A-Za-z]") {

        ; 行首输入字母 = 基本是代码
        if IsLineStart() {
            SwitchToEnglish()
            return
        }

        ; 光标前是代码上下文 → 英文
        if IsCodeContext() {
            SwitchToEnglish()
            return
        }

        ; 否则是自然语言 → 中文sSsS
        SwitchToChinese()
        return
    }

    ; 3. 输入代码符号 → 强制英文
    if RegExMatch(char, "[\(\)\{\}\[\]\<\>\=\+\-\*\/\.\:]") {
        SwitchToEnglish()
        return
    }

    ; 4. 中文标点或空格 → 切中文
    if RegExMatch(char, "[，。；：？！、 ]") {
        SwitchToChinese()
        return
    }
}

; ============================
;  上下文检测：获取光标前内容
; ============================
GetLeftText(switchType) {
    backup := A_Clipboard
    A_Clipboard := ""
    Switch switchType
    {
    ;~ 判断如果是标点符号则发送shift left 只复制光标前一位标点符号
    Case "punctuation":
        SendEvent "{Shift Down}{Left}{Shift Up}"
    Case "pinyin":
        ;~ 非标点符号则则发送ctrl+shift left复制整个拼音字母
        SendEvent "{Ctrl Down}{Shift Down}{Left}{Ctrl Up}{Shift Up}"
    Default:
        SendEvent "{Ctrl Down}{Shift Down}{Left}{Ctrl Up}{Shift Up}"
    }

    Sleep 20
    ; 根据当前活动窗口如果是shell环境执行ctrl+insert复制，否则ctrl+c
    if WinActive("ahk_group ShellGroup")
        SendEvent "{Ctrl Down}{Insert}{Ctrl Up}"
    else
        SendEvent "{Ctrl Down}{c}{Ctrl Up}"
    ;ClipWait 0.2
   if !ClipWait(0.3) {
        A_Clipboard := backup
        return ""
    }
    text := A_Clipboard
    A_Clipboard := backup
    ; 取消选择（恢复光标）
    ;Send "{Right}"
    return text
}


EnsurePinyinReady() {
    Loop 2 {
        Send "a"
        Sleep 50
        Send "{Backspace}"
        Sleep 20
    }
}

; 转换字符1、转换标点符号 2、转换拼音为中文
ConvertCharacter() {
    ;~ 1、转换标点符号
    switchType := "punctuation"
    ;~ 先获取光标前第一位字符
    lastChar := GetLeftText(switchType)
    ;~ ToolTip("111111111" lastChar)
    ;~ 判断末尾字符为中文标点符号
    static CN_PUNCT := "，。！？；：、（）【】《》“”‘’·￥—"
    ;~ ToolTip("match:" match . "lastChar:" lastChar)
    if InStr(CN_PUNCT, lastChar) {
        Switch lastChar
        {
        ;~ 判断如果是标点符号则再发送一次shift left 只复制光标前两格标点符号
        Case "…":
        Case "—":
        Case "、":
            Send "+{Left}"
        ;~ Case "todo":
            ;~ 非标点符号则则发送ctrl+shift left复制整个拼音字母
            ;~ Send "^+{Left}"
        ;~ Default:

        }
        ;~ 将中文标点符号替换成英文标点符号
        SwitchPunctuation(true,lastChar)
        return
    }
    
     ;~ Chr(34)：双引号，Chr(39)：单引号，Chr(96)：反引号`
    static ENG_PUNCT := ",.;:?!()[]<>\\$" . Chr(34) . Chr(96)
    ; 已经是英文标点
    if InStr(ENG_PUNCT, lastChar) {
        SwitchPunctuation(false,lastChar)
        return
    }
    ;~ 2、转换拼音为中文
    ; 获取光标前文本
    switchType := "pinyin"
    text := GetLeftText(switchType)
    ; 3. 正则：匹配“末尾连续的英文字母”
    word := ""
    if RegExMatch(text, "([A-Za-z]+)$", &m)
        word := m[1]

    if word = ""
        return

    ;~ 状态触发
    ; 1. 强制 IME 进入拼音 composing
    SendEvent "a"
    Sleep 20
    SendEvent "{Backspace}"
    Sleep 20

    ;~ SendEvent word
    for ch in StrSplit(word) {
        SendEvent ch
        Sleep 10
    }
     ;~ 发送空格前稍等一下（输入法处理）
    Sleep 50
    SendInput "{Space}"
    ;~ IME 自动化里，没有“等事件”，只有“触发状态 + 给时间”。
    ;~ 彻底最小化 Sleep（不同窗口自适应）
    ;~ 拼音失败自动重试 / 回退机制
}

;~ cnToEng：是否中文转英文标点的标识，判断文本末尾是否有中文标点符号，有则替换成英文标点符号输出
SwitchPunctuation(cnToEng,char) {
    ; 中文标点和英文标点的映射数组
    static punctuationMap := [
        "，", ",",
        "。", ".",
        "；", ";",
        "：", ":",
        "？", "?",
        "！", "!",
        "（", "(",
        "）", ")",
        "【", "[",
        "】", "]",
        "《", "<",
        "》", ">",
        "、", "// ", ; 中文顿号替换为代码注释符号
        "“",'"',
        "”",'"',
        "‘","'",
        "·",Chr(96), ; Chr(96)代表反引号`,todo: `不能转 ·
        "￥","$",
        ;~ "……","^",
        "—","_",
    ]
    ; 查找对应的英文标点
    for index, value in punctuationMap {
        if (value == char) {
            if (cnToEng) {
                engPunctuation := punctuationMap[index + 1]  ; 返回对应的英文标点
            } else {
                engPunctuation := punctuationMap[index - 1]  ; 返回对应的中文标点
            }
            ;~ SendText 的工作方式
            ;~ ❌ 不模拟按键
            ;~ ❌ 不经过 Alt / Shift / Ctrl
            ;~ ❌ 不生成 KeyDown / KeyUp
            ;~ ✅ 直接向当前输入上下文插入 Unicode 文本
            ;~ 输出元字符创+转换后的英文标点
            SendText(engPunctuation)
            return
        }
    }
}
; 打开将光标前英文单词转为中文
LWin & z::
{
    ; 强制清理所有修饰键
    ;~ Send "{LAlt Up}"
    ;~ Sleep 20
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

        ;~ WinWait("ahk_class " ahk_class)  ; 等待窗口准备好
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


; win+F8打开手机连接
;~ #F8::
;~ {
	;~ ahk_exe := "PhoneExperienceHost.exe"
	;~ APP_PATH := A_ProgramFiles "\WindowsApps\Microsoft.YourPhone_1.25072.63.0_x64__8wekyb3d8bbwe\PhoneExperienceHost.exe"

    ;~ ToggleWindow(ahk_exe, APP_PATH)

;~ }
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
global hwndCache := Map()
ScriptLifecycle.RegisterReload(BuildBrowserCache)

ScriptLifecycle.Init()

^!r::ScriptLifecycle.Reload()

GroupAdd "ShellGroup", "ahk_exe mintty.exe"
GroupAdd "ShellGroup", "ahk_exe Xshell.exe"
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
;~ CapsLock 双击触发粘贴操作
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


/* global doubleClickInterval := 180 ; 双击判断的时间间隔（毫秒）
global capsPending := false ; 单击行为必须延迟执行，直到确认不是双击



$CapsLock::
{
    global doubleClickInterval
    global capsPending
    if (capsPending) {
        ; 第二次按下 → 双击
        capsPending := false
        SetTimer(CapsSingle, 0)  ; 取消单击定时器
        ; 双击执行粘贴操作
        if WinActive("ahk_group ShellGroup") {
            SendInput "{Shift Down}{Insert}{Shift Up}"
        } else {
            SendInput "{Ctrl Down}v{Ctrl Up}"

        }

        return
    }

    ; 第一次按下
    capsPending := true
    SetTimer(CapsSingle, -doubleClickInterval)
            ;  等 CapsLock 彻底释放
        KeyWait "CapsLock"

} */
;~ Caps键单击
/* CapsSingle() {
    global capsPending
    if (!capsPending)
        return

    capsPending := false
    ; 确保 CapsLock 已彻底释放
    ;~ KeyWait "CapsLock"

    ; 给系统一点处理时间（非常关键）
    ;~ Sleep 20

    backup := A_Clipboard
    A_Clipboard := ""
    ; 单击执行复制操作
    if WinActive("ahk_group ShellGroup") {
        SendInput "{Ctrl Down}{Insert}{Ctrl Up}"
    } else {
        SendInput "{Ctrl Down}c{Ctrl Up}"

    }
   if !ClipWait(0.5) {
       MsgBox '复制失败！'
       A_Clipboard := backup
       return
    }
} */

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

    ;~ ahk_exe := "YoudaoDict.exe"
	;~ APP_PATH := "C:\Users\X1\AppData\Local\youdao\dict\Application\YoudaoDict.exe"
        ;~ WinActivate  ; Activate the window found above
    ;~ if WinExist("ahk_exe " ahk_exe){
		    ;~ ; 等待窗口激活（替换为实际窗口标题或 ahk_exe）
    ;~ }else{
        ;~ Run APP_PATH  ; Open a new Notepad window
		;~ ; 等待窗口激活（替换为实际窗口标题）
		;~ if !WinWaitActive(APP_PATH, , 5) {
			;~ MsgBox "窗口未找到或未激活"
			;~ return
		;~ }
	;~ }
;~ WinGetClientPos &x, &y, &width, &height, "ahk_exe " ahk_exe

;~ MsgBox "Calculator is at " x "," y " and its size is " width "x" height
;~ logMessage :="`nCalculator is at " x "," y " and its size is " width "x" height
;~ OutputDebug logMessage



    ;~ ; 获取窗口位置和尺寸
    ;~ if !(width>0) {
        ;~ MsgBox("窗口位置无法获取3444")
        ;~ return
    ;~ }

    ;~ ; 计算点击位置（例如窗口中间）
    ;~ clickX := x + (width / 2)
    ;~ clickY := y + 230
;~ logMessage2 :="`nclickX is at " clickX "," clickY " and its size is " width "x" height
;~ OutputDebug logMessage2
    ;~ ; 模拟鼠标点击
			;~ Sleep 1000
			    ;~ Click(clickX, clickY)
    ; 发送 Tab 键切换焦点
    ahk_exe := "YoudaoDict.exe"
    ;~ 如果已启动
    if WinExist("ahk_exe " ahk_exe){
        WinActivate("ahk_exe " ahk_exe)
        if WinWaitActive("ahk_exe " ahk_exe,,0.5){
            pasteEnter()
        }

    } else {
        ;~ 未启动时发送指令键启动程序
        ; Send("^{LWin down}3^{LWin up}")
        APP_PATH := A_Programs "\有道\网易有道翻译\网易有道翻译.lnk"
        RunAppPathWithPrefixFallback(APP_PATH)
        ;~ 等待程序启动
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
isProxy := 0  ; 初始值为 0
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

}


$#^c::return



; ==============================
; 窗口选择器对象
; ==============================
global Switcher := Map()

; ==============================
; 初始化 窗口选择器对象
; ahk_class:
; CabinetWClass：文件资源管理器
; XLMAIN：Excel
; ==============================
InitSwitcher(ahk_class) {
    global Switcher
    ;~ ToolTip(ahk_class)
    ; 获取所有符合条件的窗口句柄（按类名“CabinetWClass”）
    windows := []
    Switch ahk_class
    {
    ;~ 判断如果是标点符号则发送shift left 只复制光标前一位标点符号
    Case "windowsApp":

    Case "pinyin":
        ;~ 非标点符号则则发送ctrl+shift left复制整个拼音字母
        SendInput "{Ctrl Down}{Shift Down}{Left}{Ctrl Up}{Shift Up}"
    Default:
        windows := WinGetList("ahk_class " ahk_class)

    }
    ; 如果只有一个窗口，则return不显示窗口列表弹窗
    if (windows.Length = 1) {
        hwnd := windows[1]

        if WinActive("ahk_id " hwnd) {
            WinMinimize "ahk_id " hwnd
        } else {
            WinActivate "ahk_id " hwnd
        }
        return
    }
    ;~ appMap := Map()
    ;~ appMap["CabinetWClass"] := "文件资源管理器"
    ;~ appMap["XLMAIN"] := "Excel"
    ;~ 查找如果有AutoHotkeyGUI则先WinClose，然后重新生成AppListView
    ;~ if WinExist("ahk_class AutoHotkeyGUI"){

        ;~ windows_gui := WinGetList("ahk_class AutoHotkeyGUI")
        ;~ for winID in windows_gui {
            ;~ ;
            ;~ if(WinGetTitle(winID) == appMap[ahk_class] and WinExist("ahk_id " winID)){
                 ;~ WinClose
                ;~ break
            ;~ }
        ;~ }

    ;~ }


    if Switcher.Has("initialized")
        return

    Switcher["initialized"] := true

    ; 创建 GUI
    Switcher.gui := Gui()
    Switcher.gui.Opt("+AlwaysOnTop -Caption +ToolWindow")
    ; 显示窗口列表（调试用）
    LV := Switcher.gui.AddListView("r8 w200 vColorChoice", ["#", "文件名"])
    Switcher.LV := LV   ; 保存到 Switcher 对象里

    winList := []
    for winID in windows {
        ;MsgBox WinGetTitle(winID)
        word_array := StrSplit(WinGetTitle(winID), " - ")
        if(A_Index == 1){
            ;~ MyGuiSwitcher.gui.Title := word_array[2]
        }
        LV.Add(, A_Index, word_array[1])

        winList.Push(A_Index)
    }
    Switcher["winListLength"] := winList.Length

    LV.OnEvent("Click", LV_Click)
    LV_Click(LV, RowNumber)
    {
        if (!RowNumber) {
            return
        }
        HotkeyActivateWindow(RowNumber)
    }
    ;~ 数字热键绑定激活对应窗口 todo
    ;~ Loop winList.Length {
        ;~ if (A_Index > 9)
            ;~ break
        ;~ Hotkey("~" . A_Index, HotkeyActivateWindow)
    ;~ }

    HotkeyActivateWindow(ThisHotkey) {
        index := RegExReplace(ThisHotkey, "^\D+")

        if windows.Has(index) && WinExist("ahk_id " windows[index]) {
            WinActivate("ahk_id " windows[index])
        } else {
            LV.Delete(index)
        }
    }


    ; 尺寸 & 位置
    Switcher.w := 200
    Switcher.h := 160
    Switcher.showX := 0
    Switcher.hiddenX := -Switcher.w
    Switcher.y := (A_ScreenHeight - Switcher.h) // 2

    ; 状态
    Switcher["visible"] := false
    Switcher.sliding := false
    Switcher.lastHover := 0

    SlideIn()
    ;~ Switcher.gui.Show("NoActivate")

    ; 初始隐藏
    ;~ Switcher.gui.Show("x" Switcher.hiddenX " y" Switcher.y " w" Switcher.w " h" Switcher.h " NoActivate")

    ; 开启定时器检查鼠标
    SetTimer(CheckMouse, 30)
}

; ==============================
; 滑入动画
; ==============================
SlideIn() {
    global Switcher

    if (Switcher["visible"] || Switcher.sliding)
        return

    Switcher.sliding := true
    Switcher.gui.Show("NoActivate")
    ;~ Switcher.gui.Show()

    x := Switcher.hiddenX
    while (x < Switcher.showX) {
        x += 20
        if (x > Switcher.showX)
            x := Switcher.showX
        Switcher.gui.Move(x, Switcher.y)
        Sleep 10
    }

    Switcher["visible"] := true
    Switcher.sliding := false

    ; 初始化 lastHover 防止立即滑出
    Switcher.lastHover := A_TickCount

    ; 动画结束后确保第一个项目被选中
    LV := Switcher.LV
    if LV.GetCount() > 0 {
        LV.Modify(1, "Select")
        LV.Focus()
        LV.Modify(1, "Focus")

        ;~ hwnd := LV.Hwnd
        ;~ x1 := 0, y1 := 0, w := 0, h := 0
        ;~ LV_GetItemRect(hwnd, 1, &x1, &y1, &w, &h)

        ;~ mouseX := Switcher.gui.X + x1 + w // 2
        ;~ mouseY := Switcher.gui.Y + y1 + h // 2

        ;~ MouseMove(mouseX, mouseY, 0)
    }
}

; ==============================
; 滑出动画
; ==============================
SlideOut() {
    global Switcher

    if (!Switcher["visible"] || Switcher.sliding)
        return

    Switcher.sliding := true

    x := Switcher.showX
    while (x > Switcher.hiddenX) {
        x -= 20
        if (x < Switcher.hiddenX)
            x := Switcher.hiddenX
        Switcher.gui.Move(x, Switcher.y)
        Sleep 10
    }

    Switcher.gui.Hide()
    Switcher["visible"] := false
    Switcher.sliding := false
}

; ==============================
; 检查鼠标位置，决定滑入/滑出
; ==============================
CheckMouse() {
    global Switcher

    static EDGE_TRIGGER := 3          ; 离屏幕左侧 px
    static EDGE_HOLD_TIME := 200      ; 停留 ms 才算有意图
    static GUI_HOVER_PAD := 10
    static HIDE_DELAY := 500

    static edgeEnterTime := 0

    ; 坐标模式：屏幕绝对坐标
    CoordMode("Mouse", "Screen")
    MouseGetPos &mx, &my
    now := A_TickCount

    ; ==============================
    ; ① GUI 未显示：靠近屏幕左侧才滑入
    ; ==============================
    if (!Switcher["visible"] && !Switcher.sliding) {

        if (mx <= EDGE_TRIGGER) {
            if (edgeEnterTime = 0)
                edgeEnterTime := now

            if (now - edgeEnterTime >= EDGE_HOLD_TIME) {
                SlideIn()
                edgeEnterTime := 0
            }
        } else {
            edgeEnterTime := 0
        }
        return
    }

    ; ==============================
    ; ② GUI 已显示：鼠标在 GUI 内 → 永不隐藏
    ; ==============================
    if (Switcher["visible"] && !Switcher.sliding) {

        ; 获取 GUI 坐标和尺寸
        Switcher.gui.GetPos(&x, &y, &w, &h)
        ;~ ToolTip("x" X . "y" Y . "Width " Width . "Height" Height)
        ; 判断鼠标是否在 GUI 内
        if (mx >= x - GUI_HOVER_PAD
            && mx <= x + w + GUI_HOVER_PAD
            && my >= y - GUI_HOVER_PAD
            && my <= y + h + GUI_HOVER_PAD) {

                Switcher.lastHover := now
                return
            }

            ; ==============================
            ; ③ GUI 离开延迟隐藏
            ; ==============================
            if (now - Switcher.lastHover > HIDE_DELAY) {
                SlideOut()
            }
    }
}

CloseSwitcher() {
    global Switcher
    if (!Switcher.Has("initialized")) {
        return
    }
    ; 隐藏 GUI
    ;~ Switcher.gui.Hide()
    Switcher.gui.Destroy()

    ;~ Loop Switcher["winListLength"] {
        ;~ if (A_Index > 9)
            ;~ break
        ;~ Hotkey("~" . A_Index, "Off")
    ;~ }
    ;~ 清空map
    Switcher.Clear()

    ; 停掉鼠标监听定时器
    SetTimer(CheckMouse, 0)
    ; 显示提示
    ToolTip("已关闭窗口选择器")

    ; 1 秒后自动消失
    SetTimer(() => ToolTip(), -1000)  ; -1000 表示一次性计时器
}
;~ #6::
;~ {
;~ ; Paste a command into cmd.exe without activating the window.
;~ A_Clipboard := "echo Hello, world!`r"
;~ MenuSelect "ahk_exe WeChatAppEx.exe",,  "3&", "1&"
;~ }


^#s::
{
	ahk_exe := "ApplicationFrameHost.exe"
    APP_PROTOCOL := "ms-windows-store://library"
    ToggleWindow(ahk_exe, APP_PROTOCOL)

}
;~ ^#s::Run("ms-windows-store://library")

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
    ;~ 查找如果有AutoHotkeyGUI则先WinClose，然后重新生成AppListView
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
^space::
{
	ahk_exe := "Code.exe"
	APP_PATH := A_Programs "\Visual Studio Code\Visual Studio Code.lnk"

    openVSCode(ahk_exe, APP_PATH)

}


openVSCode(ahkExe, appPath, workspace := "") {
    hwnd := WinExist("ahk_exe " ahkExe)
    if hwnd {
        if WinActive("ahk_id " hwnd) {
            WinMinimize("ahk_id " hwnd)
        } else {
            WinShow("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
        }
        return
    }

    LaunchVSCodeAsStandardUser(appPath, workspace)

    ; 启动后尝试激活
    if WinWait("ahk_exe " ahkExe, , 6) {
        WinActivate("ahk_exe " ahkExe)
    }
}

LaunchVSCodeAsStandardUser(appPath, workspace := "") {
    try {
        primary := appPath
        alternate := SwapProgramsPrefix(primary)

        launchPath := ""
        if FileExist(primary) {
            launchPath := primary
        } else if (alternate != "" && FileExist(alternate)) {
            launchPath := alternate
        } else {
            if (alternate != "") {
                throw Error("VS Code 路径不存在:`n1) " primary "`n2) " alternate)
            }
            throw Error("VS Code 路径不存在:`n" primary)
        }

        args := "--reuse-window"
        if (workspace != "") {
            args .= " " QuoteArg(workspace)
        }

        launchTarget := ResolveShortcutTarget(launchPath)
        if !LaunchViaLimitedScheduledTask(launchTarget, args) {
            throw Error("无法通过任务计划（LIMITED）启动 VS Code。")
        }
    } catch Error as e {
        MsgBox "启动 VSCode 失败:`n" e.Message, "错误", "Iconx"
    }
}

LaunchViaLimitedScheduledTask(target, args := "") {
    static taskName := "AHK_LaunchVSCode_Unelevated"

    taskRun := '\"' target '\"'
    if (args != "") {
        taskRun .= " " args
    }

    createCmd := 'schtasks /create /tn "' taskName '" /tr "' taskRun '" /sc ONCE /st 00:00 /rl LIMITED /it /f'
    runCmd := 'schtasks /run /tn "' taskName '"'

    createExitCode := RunWait(createCmd, , "Hide")
    if (createExitCode != 0) {
        return false
    }

    runExitCode := RunWait(runCmd, , "Hide")
    return (runExitCode = 0)
}

ShellExecuteAsStandardUser(target, args := "", workDir := "") {
    try {
        if (workDir = "") {
            SplitPath(target, , &workDir)
        }

        ; 关键点：通过 Shell.Application（Explorer 进程）发起，保持普通权限
        shellApp := ComObject("Shell.Application")
        shellApp.ShellExecute(target, args, workDir, "open", 1)
        return true
    } catch {
        return false
    }
}

ResolveShortcutTarget(path) {
    if !RegExMatch(path, "i)\.lnk$") {
        return path
    }

    try {
        shortcut := ComObject("WScript.Shell").CreateShortcut(path)
        target := shortcut.TargetPath
        if (target != "" && FileExist(target)) {
            return target
        }
    } catch {
    }

    return path
}

QuoteArg(s) {
    ; Windows 参数安全引用
    return '"' StrReplace(s, '"', '\"') '"'
}

; 快捷键 Win+T 切换置顶状态
#t::
{
    hwnd := WinActive("A")
    if hwnd
        WinSetAlwaysOnTop(-1, "ahk_id " hwnd) ; -1 = 切换
}

; Prtsc键或者LAlt & space都能打开chrome
; 仅在非 RDP 场景下允许触发，避免连接/切换 RDP 时误发 Win 键
; #HotIf !IsRdpContext()
SC137::
RCtrl Up:: {
    SendEvent "{LWin Down}2{LWin Up}"
    ; 原有逻辑保持不变
}
; #HotIf

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
    ; 释放可能按下的修饰键，避免产生意外的组合键（如 Win+RAlt 等）
    Send("{LWin up}{RWin up}{Ctrl up}{Shift up}{Alt up}")

    ; 1. 清空剪贴板并直接发送复制指令（绕过 CapsLock 钩子，直接执行复制动作更稳定）
    A_Clipboard := ""
    if WinActive("ahk_group ShellGroup") {
        SendEvent("{Ctrl Down}{Insert}{Ctrl Up}")
    } else {
        SendEvent("^{c}")
    }
    
    if !ClipWait(1) {
        ToolTip("未能获取到选中文本")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; 2. 直接发送打开浏览器的快捷键 (Win+2)
    ; 使用 AHK 原生的 #2 语法，防止拆分发送导致 Windows 识别为按下了单独的 Win 键（弹出开始菜单）
    Send("#2")

    ; 3. 等待 Chrome 浏览器被激活
    success := false
    Loop 30 {
        if WinActive("ahk_exe chrome.exe") {
            success := true
            break
        }
        Sleep 100
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

;~ LWin & d:: SendEvent "{LWin Down}1{LWin Up}"

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
        ;~ ToolTip 1111 ':' ahk_id
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
#c::
{
	; ahk_exe := "Xshell.exe"
	; APP_PATH := A_ProgramFiles " (x86)\NetSarang\Xshell 8\Xshell.exe"
	ahk_exe := "Qoder.exe"
    APP_PATH := A_ProgramsCommon "\Qoder\Qoder.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
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
; ONLYOFFICE
#o::
{
    ahk_exe := "editors.exe"
	APP_PATH := A_ProgramsCommon "\ONLYOFFICE\ONLYOFFICE.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
}
; 打开钉钉
^#d::
{
    ahk_exe := "DingTalk.exe"
	APP_PATH := A_ProgramsCommon "\Programs\钉钉\钉钉.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
}

^#F11::
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

global CONFIG := LoadConfig()
global APP_DIR := A_ScriptDir "\apps"


global AppMgr := {}
; #f10::
; {
; 	GuiAppManager()
; }

GuiAppManager() {
    global CONFIG, AppMgr

    AppMgr.gui := Gui("+AlwaysOnTop", "Browser App Manager")

    lv := AppMgr.gui.AddListView("w520 r10", ["App", "⭐", "Hotkey", "Browser"])

    for app in CONFIG["apps"] {
        stars := ""
        Loop app["memory"]
            stars .= "⭐"

        lv.Add(
            "",
            app["name"],
            stars,
            app["hotkey"],
            app["browser"],
            app["aumid"],
        )
    }


    btnGen := AppMgr.gui.AddButton("x10 y+10 w120", "生成 App")
    btnDel := AppMgr.gui.AddButton("x+10 w120", "删除 App")

    btnGen.OnEvent("Click", (*) => GenerateSelected(lv))
    btnDel.OnEvent("Click", (*) => DeleteSelected(lv))

    AppMgr.gui.Show()
}


; ==========================
; 生成 / 删除
; ==========================
GenerateSelected(lv) {
    row := lv.GetNext()
    if !row
        return

    app := CONFIG["apps"][row]
    CreateChromeApp(app)
}

DeleteSelected(lv) {
    row := lv.GetNext()
    if !row
        return

    app := CONFIG["apps"][row]
    file := APP_DIR "\run_" app["name"] ".ps1"
    isDelete := DeleteWithTrayTip(file)
    if (isDelete) {
        file := APP_DIR "\" app["name"] ".lnk"
        DeleteWithTrayTip(file)
    }
}
DeleteWithTrayTip(file) {
    if !FileExist(file)
        return false

    try {
        FileDelete(file)
        SplitPath(file, &name)
        TrayTip("文件已删除", name)
        return true
    } catch Error as e {
        TrayTip("删除失败", e.Message)
        return false
    }
}

; ==========================
; 生成 CMD
; ==========================
GenerateApp(app) {
    global CONFIG, APP_DIR

    DirCreate(APP_DIR)

    browser := CONFIG["browsers"][app["browser"]]
    args := StrJoin(" ", CONFIG["commonArgs"])

    cmd := Format(
        '"{}" --profile-directory={} --app={} {}',
        browser["path"],
        browser["profile"],
        app["url"],
        args
    )

    file := APP_DIR "\run_" app["name"] ".cmd"
    if FileExist(file) {
        FileDelete(file)
    }
    FileAppend(cmd, file, "UTF-8")
}
BuildChromeArgs(app) {
    global CONFIG

    browser := CONFIG["browsers"][app["browser"]]

    args := []
    args.Push("--profile-directory=" browser["profile"])
    args.Push("--app=" app["url"])

    ; 合并 commonArgs
    for a in CONFIG["commonArgs"]
        args.Push(a)

    return StrJoin(" ", args)
}

CreateChromeApp(app) {
    global CONFIG


    browser := CONFIG["browsers"][app["browser"]]
    chromeArgs := BuildChromeArgs(app)

    ps := Format(("$Target = '{1}'`n"
    "$Arguments   = '{2}'`n"
    "$Lnk    = '{3}'`n"
    "$AUMID  = '{4}'`n`n"

    "$Wsh = New-Object -ComObject WScript.Shell`n"
    "$S = $Wsh.CreateShortcut($Lnk)`n"
    "$S.TargetPath = $Target`n"
    "$S.Arguments  = $Arguments`n"
    "$S.IconLocation = `"$Target,0`"`n"
    "$S.WorkingDirectory = Split-Path $Target`n"
    "$S.Save()`n`n"

    "$bytes = [System.Text.Encoding]::Unicode.GetBytes(`"`0$AUMID`")`n"
    "$stream = [System.IO.File]::Open($Lnk, 'Open', 'ReadWrite')`n"
    "$stream.Seek(0x800, 'Begin') | Out-Null`n"
    "$stream.Write($bytes, 0, $bytes.Length)`n"
    "$stream.Close()"
    ),
    browser["path"], chromeArgs, APP_DIR "\" app["name"] ".lnk", app["aumid"]
    )


    file :=  APP_DIR "\run_" app["name"] ".ps1"
    isCreate := CreateWithTrayTip(ps, file, "UTF-8")
    if (isCreate) {
        RunWait 'powershell -NoProfile -ExecutionPolicy Bypass -File "' file '"', , "Hide"
        TrayTip("点击" app["hotkey"] "按键可激活" app["name"])

    }
}

CreateWithTrayTip(ps, file, encode) {
    try {
        if FileExist(file) {
            FileDelete(file)
        }
        FileAppend(ps, file, encode)
        SplitPath(file, &name)
        TrayTip("文件创建成功", name)
        return true
    } catch Error as e {
        TrayTip("文件创建失败", e.Message)
        return false
    }
}
; ==========================
; JSON 读取
; ==========================
; 读取 JSON 文件

LoadConfig() {
    json := FileRead(A_ScriptDir "\browser_apps.json", "UTF-8")
    /* app := Jxon_Load(json)
    MsgBox(app)
    */

    return Jxon_Load(json)
}


; 示例访问第一个 App
;~ url := CONFIG["apps"][1].url
;~ MsgBox("第一个 App URL: " url)

; 遍历所有 App，添加热键
for app in CONFIG["apps"] {
    Hotkey app["hotkey"], BindActivateApp(app)
}

BindActivateApp(app) {
    return (*) => ActivateApp(app)
}

; Win + 0热键打开chrome app
#0::
{
	BuildBrowserCache()
}
BuildBrowserCache() {
    global hwndCache
    hwndCache.Clear()

    ; 获取所有 chrome.exe 句柄
    ids := WinGetList("ahk_exe chrome.exe")


    for hwnd in ids {
        ; 1. 过滤掉没有标题的隐藏窗口（Chrome 后台进程）
        title := WinGetTitle("ahk_id " hwnd)
        if (title == "")
            continue

        ;~ ToolTip title
        ; 2. 识别是否为 App 窗口
        try {
            ; 很多版本的 UIA_Browser 在创建时会自动 WinActivate
            cUIA := UIA_Browser("ahk_id " hwnd)

			; 优先尝试 UIA 属性获取，若失败则用 JS 保底
            url := cUIA.GetCurrentURL(false)
            if (url == "" || url == "https://") {
                url := cUIA.JSExecute("window.location.href")
            }


            url := Trim(url, " `"")
            if (InStr(url, "https://chatgpt.com")) {
				; chatgpt和dms两个PWA，存入缓存
                hwndCache["chatgpt"] := hwnd
			} else if (InStr(url, "https://dms.aliyun.com")) {
                hwndCache["dms"] := hwnd
            } else {
                 ; 激活chrome浏览器窗口
                WinActivate(hwnd) ; 瞬间切回，尽量减少干扰
            }

            ;~ 解除引用，AHK 的引用计数机制会自动释放这些 COM 对象
			cUIA := ""

        } catch {
            continue
        }
    }
	;~ DumpMap(hwndCache)
}

DumpMap(hwndCache) {
    i := 1
    out := ""
    for url, hwnd in hwndCache {
        out .= i ".key:`n" url "`nvalue:`n" hwnd "`n`n"
        i++
    }

	local _gui := Gui("+AlwaysOnTop", "Dump")
    _gui.AddEdit("w400 h300 ReadOnly", out)
    _gui.Show()
}

ActivateApp(app) {
    global hwndCache

    exe := app["browser"] = "chrome" ? "chrome.exe" : "msedge.exe"

    targetURL := app["url"]
   if (InStr(targetURL, "https://chatgpt.com")) {
        targetURL := "chatgpt"
    } else if (InStr(targetURL, "https://dms.aliyun.com")) {
        targetURL := "dms"
    }

    ; 精准匹配 URL
    if hwndCache.Has(targetURL) {
        ahk_id := hwndCache[targetURL]
        if WinActive("ahk_id " ahk_id) {
            WinMinimize("ahk_id " ahk_id)
        } else {
            WinActivate("ahk_id " ahk_id)
        }
        return
    }
    ; 2️找不到 → 启动 App
    Run APP_DIR "\" app["name"] ".lnk"
}

; Win + `热键打开Obsidian
#`::
{
	ahk_exe := "Obsidian.exe"
    APP_PATH := A_ProgramsCommon "\Obsidian.lnk"

    ToggleWindow(ahk_exe, APP_PATH)
}

#f12::
{
    ; 1. 获取微信主窗口
    try {
        wechatWin := UIA.ElementFromHandle("ahk_exe WeChatAppEx.exe")
        wechatWin.SetFocus() ; 必须激活窗口，否则右键可能无效
    } catch {
        MsgBox "未找到微信窗口"
        ExitApp
    }

    ; 2. 获取所有文章选项卡 (TabItem)
    try {
        tabs := wechatWin.FindElements({Type: 50019}) ; 50019 = TabItem
    } catch {
        MsgBox "未找到选项卡"
        ExitApp
    }

    if (tabs.Length == 0) {
        MsgBox "当前没有打开的文章标签页"
        ExitApp
    }

    ;~ results := "抓取结果：`n----------------`n"

    ; 3. 遍历每个标签页并执行“右键复制”
    for item in tabs {
        title := item.Name
        if (title == "")
            continue

        ; 调用自定义函数获取 URL
        url := GetUrlByRightClick(item)

        ; 拼接 Markdown 格式，并在末尾添加两个换行以确保在 Obsidian 中清晰分隔
        ; 在循环内部修改为：
        ; title 和 url 后面加两个空格再加换行，这是 Markdown 强制换行的标准
        content .= "`n[" . title . "](" . url . ")`n"
    }

    ; 添加笔记到obsidian
    parentDir := "微信公众号文章" ; 目录名
    noteName := FormatTime(, "yyyy-MM-dd") ; 文件名
    AddNoteToObsidian(parentDir,noteName,content)

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

;~ !`::Send "#{Space}"
;~ ; Alt + ` → 系统切换输入法（最稳）
!`::{
    ;~ SendEvent "{LWin down}{Space}{LWin up}"

    ; 添加笔记到obsidian
    parentDir := "笔记" ; 目录名
    noteName := FormatTime(, "yyyy-MM-dd") ; 文件名
    ;~ content 为笔记内容
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

    ; 等菜单出现后再开始导航，避免 Up 发到菜单外
    menuReady := false
    Loop 20 {
        if WinExist("ahk_class #32768") {
            menuReady := true
            break
        }
        Sleep 30
    }
    if !menuReady {
        Sleep 200
    }

    Loop 5 {
        SendEvent "{Up}"
        Sleep 120
    }

    ; 最后一次 Up 处理后再回车，避免 Enter 抢跑
    Sleep 120
    SendEvent "{Enter}"

    ; 4. 等待剪贴板
    if ClipWait(1.2) {
        Critical "Off"
        return A_Clipboard
    }
    Critical "Off"
    return "未获取到链接"
}

/**
 * 获取 Chrome DevTools Source 面板当前行号
 * @returns {Integer} 成功返回行号，失败返回 0
 */
GetDevToolsLineNumber() {
    ; 1. 环境检查：确保 Chrome 处于活动状态
    if !WinActive("ahk_exe chrome.exe") {
        return 0
    }

    ; 保存当前剪贴板，以便后续恢复 (System Guardian: Data Integrity)
    savedClipboard := ClipboardAll()
    A_Clipboard := "" 

    try {
        ; 2. 核心交互逻辑
        ; 发送 Ctrl+G 打开 "Go to line" 输入框
        Send("^g")
        if !ClipWait(1, 1) { ; 等待 UI 响应并自动选中文本
            Send("^a^c") ; 强制全选并复制
        } else {
            Send("^c")
        }
        
        ; 等待剪贴板填充
        if !ClipWait(0.5) {
            throw Error("Clipboard timeout")
        }

        ; 3. 数据解析 (RegEx 提取)
        ; DevTools 通常显示格式为 "行:列" 或单纯 "行"
        rawText := A_Clipboard
        if RegExMatch(rawText, "^\d+", &match) {
            lineNumber := Integer(match[0])
        } else {
            lineNumber := 0
        }

        ; 4. UI 清理：发送 Esc 关闭跳转框
        Send("{Esc}")
        
        return lineNumber

    } catch Error as err {
        ; 异常处理与日志建议
        FileAppend(FormatTime() ": " err.Message "`n", "debug.log")
        return 0
    } finally {
        ; 恢复现场
        A_Clipboard := savedClipboard
    }
}

; 示例热键：Ctrl + Alt + L
; ^!l:: {
;     line := GetDevToolsLineNumber()
;     if (line > 0) {
;         MsgBox("当前行号: " . line, "DevTools Info", "Iconi T3")
;     }
; }

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
	
	
	; 使用当前 Chrome 窗口另起标签页执行
Run("chrome.exe chrome-extension://ldlghkoiihaelfnggonhjnfiabmaficg/popup.html?props=false")
}

