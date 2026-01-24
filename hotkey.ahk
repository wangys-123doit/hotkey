#Requires AutoHotkey v2.0
#SingleInstance force
#Include %A_ScriptDir%\lib\Jxon.ahk
#UseHook true   ; 强制使用键盘钩子
SetCapsLockState "AlwaysOff"

#Include hotkeys_public.ahk

; 如果文件存在才加载
if FileExist(A_ScriptDir "\hotkeys_private.ahk") {
    #Include hotkeys_private.ahk
}
;~ ; #:Win,ctrl:^,shift:+,alt:! left左键：<,right右键：>
;~ #Include RunRadiator.ahk
;~ 脚本内强制提权,让 AHK 也以管理员运行
if !A_IsAdmin {
    Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp
}

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
        Run APP_PATH
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
        Run APP_PATH
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
        Run APP_PATH
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
   ControlFocus "Chrome_WidgetWin_01", "ahk_class YodaoMainWndClass"  ; 这里的 "RICHEDIT50W2" 为控件名称，可以根据实际情况修改
    ;~ 如果长文本编辑器没有内容
    /* if (ControlGetText(ControlGetFocus("A")) == '') {
        ;~ 则设置 Edit2编辑框有焦点
        ControlFocus "Chrome_WidgetWin_01", "ahk_class YodaoMainWndClass"  ; 这里的 "Edit2" 为控件名称，可以根据实际情况修改
    } */

    Send "^a"  ; 模拟 Ctrl + A 全选
    Send  "^v"  ; 模拟 Ctrl + V 粘贴剪贴板内容
    Send "{Enter}" ; 如果需要按回车键开始翻译，可以取消注释以下行
    return
     ; 获取窗口的位置和大小
    /* winPos := []
    if WinExist("ahk_class YodaoMainWndClass")
    {
        WinGetPos &winX, &winY, &winWidth, &winHeight
         ToolTip "Notepad is at " winX "," winY

        ; 获取窗口的左上角坐标和宽高
        ;~ winX := winPos[1]
        ;~ winY := winPos[2]
        ;~ winWidth := winPos[3]
        ;~ winHeight := winPos[4]

        ; 目标相对点击位置
        relativeX := 0  ; 相对X坐标
        relativeY := 0  ; 相对Y坐标

        ; 计算绝对坐标（屏幕坐标）
        absoluteX := winX + relativeX
        absoluteY := winY + relativeY

        ; 在窗口内模拟点击相对位置 (100, 200)
        MouseClick("left", absoluteX, absoluteY)

        Send "^a"  ; 模拟 Ctrl + A 全选
        ;~ Send "{Backspace}"
        ;~ Sleep 3000
        ;~ MsgBox A_Clipboard
        ;~ ToolTip(A_Clipboard)
        Send  "^v"  ; 模拟 Ctrl + V 粘贴剪贴板内容

        ; 如果需要按回车键开始翻译，可以取消注释以下行
        Send "{Enter}"
        return
    }
    */
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
        "、", "\",
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

; win+F2打开meeting
#F2::
{
	ahk_exe := "wemeetapp.exe"
	APP_PATH := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\腾讯会议.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+F3打开clash
#F3::
{
    ahk_class := "Tauri Window"
    ahk_exe := "clash-verge.exe"
    winTitle := "Clash Verge"

	APP_PATH := "C:\Program Files\Clash Verge\clash-verge.exe"

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
        Run APP_PATH
    }
}
; Win + F4热键打开小红书
#F4::
{
	ahk_exe := "Androws.exe"
	APP_PATH := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\小红书.lnk"
    WinTitle := "小红书"
    ToggleWindowByTitle(ahk_exe,WinTitle,APP_PATH)

}

; Win + F5热键打开微信读书
#F5::
{
	ahk_exe := "Androws.exe"
    WinTitle := "微信读书"
	APP_PATH := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\微信读书.lnk"
    ToggleWindowByTitle(ahk_exe,WinTitle,APP_PATH)

}
; win+F6打开搜狗PDF阅读编辑器
#F6::
{
	ahk_exe := "fastpdf.exe"
	APP_PATH := "C:\Users\X1\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\PDF阅读编辑器.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+F7打开AdminRadiator
#F7::
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
}
; Win + f8热键打开
#F8::
{



	;~ ahk_exe := "clash-verge.exe"
	;~ APP_PATH := "C:\Program Files\Clash Verge\clash-verge.exe"

    ;~ ToggleWindow(ahk_exe, APP_PATH)

}


; win+F8打开手机连接
;~ #F8::
;~ {
	;~ ahk_exe := "PhoneExperienceHost.exe"
	;~ APP_PATH := "C:\Program Files\WindowsApps\Microsoft.YourPhone_1.25072.63.0_x64__8wekyb3d8bbwe\PhoneExperienceHost.exe"

    ;~ ToggleWindow(ahk_exe, APP_PATH)

;~ }
;{Blind}前缀可以将一些按键与之前已经按下或输入的其他修饰键进行组合使用，就是盲目的保留之前的按键组合
;*^1::Send "{Blind}{Home}"
;*^2::Send "{Blind}{End}"


; Win + F12热键打开底部任务状态栏
#F12::
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
; Win + ctrl + r热键打开powershell
#^r::
{
	ahk_exe := "WindowsTerminal.exe"
	APP_PATH := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\PowerShell\PowerShell 7 (x64).lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; Win + 8热键打开powerdesigner
#9::
{
	ahk_exe := "PdShell16.exe"
	APP_PATH := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SAP\PowerDesigner 16\PowerDesigner.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; Win + ctrl + q热键打开navicat
#8::
{
	ahk_exe := "navicat.exe"
	APP_PATH := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\PremiumSoft\Navicat Premium 17.lnk"
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
	APP_PATH := "D:\Program Files (x86)\Telegram Desktop\Telegram.exe"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+f打开edge
#f::
{
	ahk_exe := "msedge.exe"
	APP_PATH := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; Win + `热键打开Obsidian
#`::
{
	ahk_exe := "Obsidian.exe"
	APP_PATH := "D:\Obsidian\Obsidian.exe"
    ToggleWindow(ahk_exe, APP_PATH)
}

^!r::Reload  ; Ctrl+Alt+R 快捷键会重新加载脚本

GroupAdd "ShellGroup", "ahk_exe mintty.exe"
GroupAdd "ShellGroup", "ahk_exe Xshell.exe"
;GroupAdd "ShellGroup", "ahk_exe WindowsTerminal.exe"
; ~修饰符的作用：1.​不阻止默认按键功能2.适用于需要保留原按键功能的情况
; 适用场景为在按键原有功能的基础上，额外执行某些操作​
; 复制热键
;~ CapsLock::
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


global doubleClickInterval := 180 ; 双击判断的时间间隔（毫秒）
global capsPending := false ; 单击行为必须延迟执行，直到确认不是双击



$CapsLock::
{
    if GetKeyState("LWin","P") || GetKeyState("RWin","P") {
        return
    }
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
            ;  临时屏蔽 Win
            BlockInput "On"
            ;~ SendEvent "^c"
            SendInput "{Ctrl Down}v{Ctrl Up}"
            BlockInput "Off"

        }

        return
    }

    ; 第一次按下
    capsPending := true
    SetTimer(CapsSingle, -doubleClickInterval)
            ;  等 CapsLock 彻底释放
        KeyWait "CapsLock"

}
;~ Caps键单击
CapsSingle() {
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
        ;  临时屏蔽 Win
        BlockInput "On"
        ;~ SendEvent "^c"
        SendInput "{Ctrl Down}c{Ctrl Up}"
        BlockInput "Off"

    }
   if !ClipWait(0.5) {
       MsgBox '复制失败！'
       A_Clipboard := backup
       return
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
	;~ APP_PATH := "C:\Users\X1\AppData\Local\youdao\dict\Application\YoudaoDict.exe"
    ;~ 如果已启动
    if WinExist("ahk_exe " ahk_exe){
        WinActivate("ahk_exe " ahk_exe)
        if WinWaitActive("ahk_exe " ahk_exe,,0.5){
            pasteEnter
        }

    } else {
        ;~ 未启动时发送指令键启动程序
        Send("^{LWin down}3^{LWin up}")
        ;~ 等待程序启动
        Sleep 3000

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

        APP_PATH := "D:\Program Files\Clash\Clash for Windows.exe"
        Run APP_PATH  ; Open a new Notepad window

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



AppHotkeyMap := Map(
    "#^e", Map("class", "XLMAIN",         "run", "Excel"),
    "#e",  Map("class", "CabinetWClass",  "run", "explorer"),
    "#a",  Map("class", "windowsApp",  "run", "windowsApp")

)

#^e::HandleAppHotkey(A_ThisHotkey) ;~ 打开Excel
#e:: HandleAppHotkey(A_ThisHotkey) ;~ 打开文件资源管理器
#a:: HandleAppHotkey(A_ThisHotkey) ;~ 打开文件资源管理器

HandleAppHotkey(hotkey) {
    global AppHotkeyMap

    if !AppHotkeyMap.Has(hotkey)
        return

    cfg := AppHotkeyMap[hotkey]
    global Switcher
    if (Switcher.Has("initialized")) {
        CloseSwitcher()
    } else {  ; GUI 不存在 → 显示
        InitSwitcher(cfg["class"])

    }
    if (cfg["class"] == "windowsApp") {
        return
    }
    ;~ 如果未启动
    if !WinExist("ahk_class " cfg["class"]){
        ;~ 未启动时发送指令键启动程序
        Run(cfg["run"])
    }
}

;~ !`::Send "#{Space}"
;~ ; Alt + ` → 系统切换输入法（最稳）
!`::{
    SendEvent "{LWin down}{Space}{LWin up}"
}




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
	APP_PATH := "D:\Program Files\Notepad++\notepad++.exe"

    ToggleWindow(ahk_exe, APP_PATH)

}
; win+F1打开snipaste
#F1::
{
	ahk_exe := "snipaste.exe"
	APP_PATH := "C:\Users\X1\AppData\Local\Microsoft\WindowsApps\Snipaste.exe"

    ToggleWindow(ahk_exe, APP_PATH)

}
; win+ctrl+x打开微信开发者工具
#^x::
{
	ahk_exe := "wechatdevtools.exe"
	APP_PATH := "C:\Users\X1\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\微信开发者工具\微信开发者工具.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+shift+x打开Xmind
#+x::
{
	ahk_exe := "Xmind.exe"
	APP_PATH := "C:\Users\X1\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Xmind.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+ctrl+w打开word
#^w::
{
	ahk_exe := "WINWORD.EXE"
	APP_PATH := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Word.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}
; win+ctrl+p打开ppt
#^p::
{
	ahk_exe := "POWERPNT.EXE"
	APP_PATH := "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\PowerPoint.lnk"
    ToggleWindow(ahk_exe, APP_PATH)
}

; win+b打开vscode
^space::
{
	ahk_exe := "Code.exe"
	APP_PATH := "C:\Users\X1\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Visual Studio Code\Visual Studio Code.lnk"

    ToggleWindow(ahk_exe, APP_PATH)

}

; 快捷键 Win+T 切换置顶状态
#t::
{
    hwnd := WinActive("A")
    if hwnd
        WinSetAlwaysOnTop(-1, "ahk_id " hwnd) ; -1 = 切换
}
; Prtsc键或者LAlt & space都能打开chrome
SC137::
RAlt Up:: {
    SendEvent "{LWin Down}2{LWin Up}"
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
	APP_PATH := "D:\Program Files\Tencent\Yuanbao\yuanbao.exe"

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
        Run APP_PATH
    }
}

#s::
{
	ahk_exe := "Everything.exe"
	APP_PATH := "C:\Program Files (x86)\Everything 1.5a\Everything.exe"

    ToggleWindow(ahk_exe, APP_PATH)
}
#c::
{
	ahk_exe := "Xshell.exe"
	APP_PATH := "C:\Program Files (x86)\NetSarang\Xshell 8\Xshell.exe"

    ToggleWindow(ahk_exe, APP_PATH)
}
 ; 微信
#w::
{
    ahk_exe := "Weixin.exe"
    WinTitle := "Weixin"
    APP_PATH := "D:\Program Files\Tencent\Weixin\Weixin.exe"

    ToggleWindow2(ahk_exe, WinTitle, APP_PATH)
}
 ; 微信公众号
#x::
{
    ahk_exe := "WeChatAppEx.exe"
    WinTitle := "WeChat"
	APP_PATH := "WeChatAppEx.exe"
    ; 通过判断应用标题来决定是否激活和隐藏
    if WinExist(WinTitle) {
        ; 检查窗口是否已激活
        if WinActive(WinTitle) {
            WinMinimize
        } else {
            WinActivate
        }
    }

    ;    if WinExist("ahk_exe " ahk_exe,WinTitle, "Photos and Videos") {
    ;    ; 检查窗口是否已激活
    ;    if WinActive("ahk_exe " ahk_exe,WinTitle, "Photos and Videos") {
    ;        WinMinimize
    ;    } else {
    ;        WinActivate
    ;    }
    ;} else {
    ;    Run APP_PATH
    ;}
}
#q::
{
    ahk_exe := "WXWork.exe"
	APP_PATH := "D:\Program Files (x86)\WXWork\WXWork.exe"

    ToggleWindow(ahk_exe, APP_PATH)
}
#F11::
{
    ahk_exe := "SciTE.exe"
	APP_PATH := "C:\Program Files\AutoHotkey\SciTE\SciTE.exe"

    ToggleWindow(ahk_exe, APP_PATH)
}

#!g::
{
	ahk_exe := "mintty.exe" ; git-bash
	APP_PATH := "C:\Program Files\Git\git-bash.exe" ; git-bash

    ToggleWindow(ahk_exe, APP_PATH)
}

global CONFIG := LoadConfig()
global APP_DIR := A_ScriptDir "\apps"


global AppMgr := {}
#f10::
{

	GuiAppManager()
    ;~ APP_DIR := "C:\Users\you\Desktop\BrowserApps"
;~ CONFIG := { "browsers": { "chrome": { "path": "C:\Program Files\Google\Chrome\Application\chrome.exe", "profile": "Default" } },
            ;~ "commonArgs": [ "--disable-extensions", "--disable-sync" ] }

;~ app := { "name": "ChatGPT", "url": "https://chat.openai.com", "browser": "chrome", "aumid": "BrowserApp.ChatGPT" }

;~ chromeArgs := "--profile-directory=Default --app=https://chat.openai.com --disable-extensions --disable-sync"



;~ ps := Format(("$Target = '{1}'`n"
;~ "$Args   = '{2}'`n"
;~ "$Lnk    = '{3}'`n"
;~ "$AUMID  = '{4}'`n`n"

;~ "$Wsh = New-Object -ComObject WScript.Shell`n"
;~ "$S = $Wsh.CreateShortcut($Lnk)`n"
;~ "$S.TargetPath = $Target`n"
;~ "$S.Arguments  = $Args`n"
;~ "$S.IconLocation = `"$Target,0`"`n"
;~ "$S.WorkingDirectory = Split-Path $Target`n"
;~ "$S.Save()`n`n"

;~ "$bytes = [System.Text.Encoding]::Unicode.GetBytes(`"`0$AUMID`")`n"
;~ "$stream = [System.IO.File]::Open($Lnk, 'Open', 'ReadWrite')`n"
;~ "$stream.Seek(0x800, 'Begin') | Out-Null`n"
;~ "$stream.Write($bytes, 0, $bytes.Length)`n"
;~ "$stream.Close()"
;~ ),
;~ 1, 2, 3 , 4
;~ )

;~ MsgBox ps  ; 可先验证生成的 PowerShell 内容

}

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

ActivateApp(app) {
    WinTitle := app["title"]
    exe := app["browser"] = "edge" ? "msedge.exe" : "chrome.exe"

    if WinExist(WinTitle) {
        ; 检查窗口是否已激活
        if WinActive(WinTitle) {
            WinMinimize
        } else {
            WinActivate
        }
    } else {
        file := APP_DIR "\" app["name"] ".lnk"
        run file
    }
}



