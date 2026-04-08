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


