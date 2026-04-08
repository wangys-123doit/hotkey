;~ #Requires AutoHotkey v2.0

; ============================================
; rdp配置区
; ============================================

class RDPConfig {
    static baseDir := "C:\Users\X1\OneDrive\文档\"   ; .rdp 文件目录

    static servers := Map(
        "dev", "Default.rdp",
        "prod", "prod.rdp"
    )
}

; ============================================
; 核心管理器
; ============================================

class RDPManager {

    static connect(name) {
        try {
            ; ---------- 1. 检查 mstsc ----------
            mstscPath := A_WinDir "\System32\mstsc.exe"
            if !FileExist(mstscPath) {
                throw Error("mstsc.exe not found: " mstscPath)
            }

            ; ---------- 2. 校验配置 ----------
            if !RDPConfig.servers.Has(name) {
                throw Error("RDP config not found: " name)
            }

            rdpFile := RDPConfig.baseDir "\" RDPConfig.servers[name]

            if !FileExist(rdpFile) {
                throw Error("RDP file not found: " rdpFile)
            }

            ; ---------- 3. 防重复启动 ----------
            ;~ if this.isRDPActive(rdpFile) {
                ;~ this.log("RDP already active → " name)
                ;~ this.activateRDPWindow()
                ;~ return
            ;~ }

            ;~ ; ---------- 4. 启动 ----------
            ;~ Run '"' rdpFile '"'

			this.ToggleWindow("mstsc.exe",'"' rdpFile '"')


            this.log("RDP launched → " name)

		} catch Error as e {
            this.log("ERROR: " e.Message)
            MsgBox "RDP Error:`n" e.Message
        }
    }

    ; 判断是否已有 RDP 窗口
    static isRDPActive(rdpFile) {
        ; 模糊匹配窗口标题（不同系统语言会不同）
        return WinExist("ahk_exe mstsc.exe")
    }

	static ToggleWindow(ahk_exe, APP_PATH) {
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


    ; 激活已有窗口
    static activateRDPWindow() {
        hwnd := WinExist("ahk_exe mstsc.exe")
        if hwnd {
            WinActivate hwnd
        }
    }

    ; 日志记录
    static log(msg) {
        logFile := A_ScriptDir "\rdp.log"
        time := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        FileAppend "[" time "] " msg "`n", logFile, "UTF-8"
    }
}


;~ ToggleWindow(ahk_exe, APP_PATH) {
	;~ if WinExist("ahk_exe " ahk_exe) {
		;~ ; 检查窗口是否已激活
		;~ if WinActive("ahk_exe " ahk_exe) {
			;~ WinMinimize
		;~ } else {
			;~ WinActivate
		;~ }
	;~ } else {
		;~ Run APP_PATH
	;~ }
;~ }
; ============================================
; 热键绑定
; ============================================

; Win+\：快速直连（最快，不做前置探测）
#\::
{
    ToggleOrConnectRDP("fast", "X1")
}

; Ctrl+Win+\：安全探测（DNS + 3389 检测后再连接）
#^\::
{
    ToggleOrConnectRDP("safe", "X1")
}

; Ctrl+Alt+M：若当前是远程桌面窗口，则最小化该窗口
^!m::
{
    MinimizeCurrentRDPDesktop()
}

; Ctrl+Alt+Shift+M：临时调试当前窗口/根窗口信息
^!+m::
{
    ShowRDPDebugInfo()
}

MinimizeCurrentRDPDesktop() {
    hwnd := WinGetID("A")
    if !hwnd {
        return
    }

    if MinimizeMstscRootWindow(hwnd) {
        return
    }

    if IsWindowsRemoteSession() {
        MsgBox(
            "当前脚本运行在远程会话中，但本地 mstsc 客户端窗口不在这个会话里，无法从这里最小化本机 RDP 窗口。`n`n请把脚本运行在本地客户端后再按这个热键。",
            "RDP 提示"
        )
    } else {
        ToolTip("未找到可最小化的 mstsc 窗口")
        SetTimer(() => ToolTip(), -1200)
    }
}

MinimizeMstscRootWindow(hwnd := 0) {
    if !hwnd {
        hwnd := WinGetID("A")
    }

    ; 优先：当前活动窗口的根窗口若属于 mstsc，直接最小化
    if hwnd {
        rootHwnd := GetRootWindow(hwnd)
        rootProc := WinGetProcessName("ahk_id " rootHwnd)
        if (rootProc = "mstsc.exe") {
            WinMinimize("ahk_id " rootHwnd)
            return true
        }
    }

    ; 回退：遍历所有 mstsc 顶层窗口并最小化第一个可见窗口
    ids := WinGetList("ahk_exe mstsc.exe")
    for id in ids {
        style := WinGetStyle("ahk_id " id)
        if (style & 0x10000000) { ; WS_VISIBLE
            WinMinimize("ahk_id " id)
            return true
        }
    }

    return false
}

ShowRDPDebugInfo() {
    hwnd := WinGetID("A")
    if !hwnd {
        MsgBox("未获取到活动窗口。")
        return
    }

    rootHwnd := GetRootWindow(hwnd)
    winClass := WinGetClass("ahk_id " hwnd)
    winProc := WinGetProcessName("ahk_id " hwnd)
    rootClass := WinGetClass("ahk_id " rootHwnd)
    rootProc := WinGetProcessName("ahk_id " rootHwnd)
    isRemoteSession := IsWindowsRemoteSession() ? "true" : "false"
    isRdpEnv := IsRDPEnvironment(hwnd) ? "true" : "false"

    info := "Active hwnd: " hwnd "`n"
        . "class: " winClass "`n"
        . "process: " winProc "`n`n"
        . "Root hwnd: " rootHwnd "`n"
        . "root class: " rootClass "`n"
        . "root process: " rootProc "`n`n"
        . "IsWindowsRemoteSession: " isRemoteSession "`n"
        . "IsRDPEnvironment: " isRdpEnv

    MsgBox(info, "RDP Debug")
}

IsRDPEnvironment(hwnd := 0) {
    if !hwnd {
        hwnd := WinGetID("A")
    }
    return IsRDPWindow(hwnd)
}

IsWindowsRemoteSession() {
    ; SM_REMOTESESSION = 0x1000，非 0 表示当前会话为远程桌面会话
    return DllCall("user32\GetSystemMetrics", "int", 0x1000, "int") != 0
}

IsRDPWindow(hwnd) {
    if !hwnd {
        return false
    }

    rootHwnd := GetRootWindow(hwnd)
    winClass := WinGetClass("ahk_id " rootHwnd)
    winProc := WinGetProcessName("ahk_id " rootHwnd)

    ; 全屏/嵌套场景下优先识别根窗口，兼容常见远程桌面窗口类
    return (winProc = "mstsc.exe"
        || winClass = "TscShellContainerClass"
        || winClass = "TscShellWndClass")
}

GetRootWindow(hwnd) {
    ; GA_ROOT = 2，返回顶级祖先窗口句柄
    rootHwnd := DllCall("user32\GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
    return rootHwnd ? rootHwnd : hwnd
}

ToggleOrConnectRDP(mode := "fast", targetHost := "X1") {
    ahk_exe := "mstsc.exe"

    if WinExist("ahk_exe " ahk_exe) {
        if WinActive("ahk_exe " ahk_exe) {
            WinMinimize
        } else {
            WinActivate
        }
        return
    }

    if (mode = "safe") {
        ConnectRDPByProbe(targetHost)
    } else {
        ConnectRDPFast(targetHost)
    }
}

ConnectRDPFast(targetHost := "X1") {
    targetScript := A_ScriptDir "\rdp-connect.ps1"
    if !FileExist(targetScript) {
        MsgBox("错误: 脚本文件路径不存在 - " . targetScript)
        return
    }

    psExe := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    cmd := '"' psExe '" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' . targetScript . '" "' . targetHost . '" -Mode "fast" -SkipProbe'
    try {
        Run(cmd, , "Hide", &psPid)
    } catch Error as e {
        WriteRDPLog("mode=fast host=" . targetHost . " launch_failed=" . e.Message)
        MsgBox("RDP 启动失败: " . e.Message)
        return
    }
    ToolTip("快速直连(仅解析): " . targetHost)
    SetTimer(() => ToolTip(), -1000)
}

ConnectRDPByProbe(targetHost := "X1") {
    targetScript := A_ScriptDir "\rdp-connect.ps1"
    if !FileExist(targetScript) {
        MsgBox("错误: 脚本文件路径不存在 - " . targetScript)
        return
    }

    psExe := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    cmd := '"' psExe '" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' . targetScript . '" "' . targetHost . '" -Mode "safe"'
    try {
        Run(cmd, , "Hide", &psPid)
    } catch Error as e {
        WriteRDPLog("mode=safe host=" . targetHost . " launch_failed=" . e.Message)
        MsgBox("RDP 启动失败: " . e.Message)
        return
    }
    ToolTip("安全探测连接: " . targetHost)
    SetTimer(() => ToolTip(), -1000)
}

WriteRDPLog(msg) {
    logFile := A_ScriptDir "\rdp.log"
    time := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    FileAppend("[" . time . "] " . msg . "`n", logFile, "UTF-8")
}

;~ powershell -ExecutionPolicy Bypass -File "E:\AutoHotKey\hotkey\rdp-connect.ps1"


; Ctrl + Alt + P → prod
;~ ^!p::RDPManager.connect("prod")


