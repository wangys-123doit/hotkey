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

; Win+\：快速直连（先尝试唤醒，再快速连接）
#\::
{
    ToggleOrConnectRDP("fast", "X1")
}

; Ctrl+Win+\：安全探测（先尝试唤醒，再做解析和 3389 检测）
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
    ToolTip("快速直连(含唤醒): " . targetHost)
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
    ToolTip("安全探测连接(含唤醒): " . targetHost)
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


/* 最稳的方法是到目标主机 X1 上直接查，步骤如下。

1. 先把 X1 手动开机并登录。
2. 在 X1 上打开 PowerShell，执行：
Get-NetAdapter -Physical | Where-Object {$_.Status -eq "Up"} | Select-Object Name, MacAddress, Status
3. 选你实际在用的网卡（通常是有线 Ethernet），记下 MacAddress。

备选方法：
1. 在路由器后台看 DHCP 客户端列表，按主机名 X1 找到 MAC。
2. 如果你知道 X1 当前 IP，也可以在 X1 上用 ipconfig /all 看 物理地址。

拿到后填到 config.ini：
1. 找到 [WakeOnLan] 段。
2. 把 X1= 后面的值填成 MAC，例如 00-11-22-33-44-55。
3. 保存后再测试热键或运行脚本。

注意：
1. 优先填有线网卡 MAC，WoL 对无线网卡通常不稳定或不支持。
2. 你的脚本支持带 - 或 : 的格式。 */